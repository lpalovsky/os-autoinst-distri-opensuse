# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
#
# Library contains various tools to connect a running test to an existing deployment.

package sles4sap::sap_deployment_automation_framework::deployment_connector;

use strict;
use warnings;
use testapi;
use Exporter qw(import);
use YAML::PP;
use Mojo::JSON qw(decode_json);
use publiccloud::instance;
use Scalar::Util qw(looks_like_number);
use utils qw(write_sut_file);
use Carp qw(croak);
use mmapi qw(get_parents get_job_autoinst_vars get_children get_job_info get_current_job_id);
use sles4sap::azure_cli;
use sles4sap::sap_deployment_automation_framework::deployment;
use sles4sap::sap_deployment_automation_framework::naming_conventions;
use Data::Dumper;

our @EXPORT = qw(
  get_deployment_vm
  get_deployer_ip
  check_deployer_ssh
  instance_data_from_inventory
  find_deployment_dir
  find_deployment_id
  ssh_config_add_instances
  read_inventory_file
  get_sap_inventory_path
  ssh_config_entry_add
);

=head2 get_deployer_ip

    get_deployer_ip(deployer_resource_group=>$deployer_resource_group, deployer_vm_name=>$deployer_vm_name);

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployer_vm_name>: Deployer VM resource name

Returns first public IP of deployer VM that is reachable and can be used for SDAF deployment connection.

=cut

sub get_deployer_ip {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    croak 'Missing "deployer_vm_name" argument' unless $args{deployer_vm_name};

    my $az_query_cmd = join(' ', 'az', 'vm', 'list-ip-addresses', '--resource-group', $args{deployer_resource_group},
        '--name', $args{deployer_vm_name}, '--query', '"[].virtualMachine.network.publicIpAddresses[].ipAddress"', '-o', 'json');

    my $ip_addr = decode_json(script_output($az_query_cmd));
    # Find first IP connection working
    for my $ip (@{ $ip_addr }) {
        return $ip if check_deployer_ssh($ip, wait_started=>'yes');
    }
    return undef;
}


=head2 check_deployer_ssh

    check_deployer_ssh($deployer_ip_addr [, $wait_started=>'true']);

B<deployer_ip_addr>: Deployer VM IP address

B<wait_started>: Wait until SSH available or timeout.

B<ssh_port>: Specify custom SSH port number. Default: 22

B<wait_timeout>: Time in sec to stop waiting after if ssh is still unavailable

Checks if deployer VM is running and ssh is available. Returns found state.
Optionally function can wait till VM reaches requested state until timeout.
Function dies only with internal errors, VM status should be evaluated and handled by caller.

=cut

sub check_deployer_ssh {
    my ($deployer_ip_addr, %args) = @_;
    croak 'Deployer IP not specified.' unless $deployer_ip_addr;
    $args{wait_timeout} //= 180;
    $args{ssh_port} //= 22;
    my $ssh_available = 0;

    my $nc_cmd = 'nc -zv';
    $nc_cmd .= ' -w 10' if $args{wait_started}; # This option lets wait 10s for server response
    $nc_cmd .= " $deployer_ip_addr $args{ssh_port}";

    my $start_time = time();
    until ($ssh_available) {
        $ssh_available = 1 if !script_run($nc_cmd, quiet=>1);
        last unless $args{wait_started};
        last if (time() - $start_time) >= $args{wait_timeout};
        diag('SSH unavailable, retrying...');
        sleep 5; # just a separation between loops, to avoid bombarding the server constantly
    }
    my $availability_message = $ssh_available ? 'available' : 'unavailable';
    record_info('SSH check', "SSH connection to '$deployer_ip_addr -p $args{ssh_port}': $availability_message");
    return $ssh_available;
}

=head2 get_parent_ids

    get_parent_ids();

Returns B<ARRAYREF> of all parent job IDs acquired from current job data.
Each SDAF deployment carries unique ID which is the deployment job ID. With multi-machine approach, actual test is
running as a dependency after deployment and carries different job ID. In order to access deployment related data,
it needs to access parent job ID.

=cut

sub get_parent_ids {
    my $job_info = get_job_info(get_current_job_id());
    # This will loop through all parent job types (chained, parallel, etc...) and creates a list of IDs
    my @parent_ids = map {@{$job_info->{'parents'}{$_}}} keys(%{ $job_info->{'parents'} });

    foreach (@parent_ids) { die "Returned parent ID must be a number: '$_'" unless looks_like_number($_);}
    return \@parent_ids;
}

=head2 get_deployment_vm

    get_deployment_vm(deployer_resource_group=>$deployer_resource_group, deployment_id=>'123456');

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployment_id>: Deployment ID

Returns deployer VM name which is tagged with deployment_id specified in parameter. This means that the VM was used
to deploy the infrastructure under this ID and contains whole SDAF setup.
Function returns VM name or undef if no VM was found.
Function dies if there is more than one VM found, because two VM's must not have same ID.

=cut

sub get_deployment_vm {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    croak 'Missing mandatory argument $args{deployment_id}' unless $args{deployment_id};

    # Following query lists VMs within a resource group that were tagged with specified deployment id.
    my $az_cmd = join(' ',
        'az vm list',
        "--resource-group $args{deployer_resource_group}",
        "--query \"\[?tags.deployment_id == '$args{deployment_id}'].name\"",
        '--output json'
    );

    my @vm_list = @{ decode_json(script_output($az_cmd)) };
    die "Multiple VMs with same IDs found. Each VM must have unique ID!\n
    Following VMs found tagged with: deployment_id=$args{deployment_id}"
        if @vm_list > 1;

    return $vm_list[0];
}

=head2 find_deployment_id

    find_deployment_id(deployer_resource_group=>$deployer_resource_group);

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

Finds deployment ID for current test. Function collects current test ID, all parent test IDs and checks for which
a deployer VM exists. Parent test IDs are checked in case of MM test.
Dies if multiple deployments found.

=cut

sub find_deployment_id {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    my @check_list = (get_current_job_id(), get_parents());
    my @vms_found;
    for my $deployment_id (@check_list) {
        my $vm_name =
            get_deployment_vm(deployer_resource_group=>$args{deployer_resource_group}, deployment_id=>$deployment_id);
        push(@vms_found, $vm_name) if $vm_name;
    }
    die "More than one deployment found.\nJobs IDs: " .
        join(', ', @check_list) . "\nVMs found: " . join(', ', @vms_found) if @vms_found > 1;

    return($vms_found[0]);
}

=head2 find_deployment_dir

    find_deployment_dir();

Retrieves all parent job test IDs and checks if there is an existing deployment associated with that ID.
Dies if none or multiple deployments are found.

=cut

sub find_deployment_dir {
    return(get_var('SDAF_DEPLOYMENT_ID')) if get_var('SDAF_DEPLOYMENT_ID');
    # Create list of job IDs for which an existing deployment directory exists
    my @deployment_ids = grep { !script_run('test -d ' . deployment_dir(job_id=>$_)) } @{ get_parent_ids() };
    # Create list of directories matching to ID
    my @deployment_directories = map  { deployment_dir(job_id=>$_) } @deployment_ids;
    # There must be only one directory found
    die("None or multiple directories found: \n" . join("\n", @deployment_directories))
       if @deployment_directories ne 1;

    return $deployment_directories[0];
}

=head2 get_sap_inventory_path

    get_sap_inventory_path(
        [ env_code=>$env_code,
        sdaf_region_code=>$sdaf_region_code,
        sap_sid=>$sap_sid,
        vnet_code=>$vnet_code ]
    );

B<env_code>:  SDAF parameter for environment code (for our purpose we can use 'LAB')

B<sdaf_region_code>: SDAF parameter to choose PC region. Note SDAF is using internal abbreviations (SECE = swedencentral)

B<sap_sid> SAP SID of the existing deployment. Default: get_var('SAP_SID')

B<vnet_code>: SDAF parameter for virtual network code. Library and deployer use different vnet than SUT env

Returns full path to an existing ansible inventory file

=cut

sub get_sap_inventory_path {
    my (%args) = @_;
    $args{sap_sid} //= get_required_var('SAP_SID');
    $args{env_code} //= get_required_var('SDAF_ENV_CODE');
    $args{vnet_code} //= get_required_var('SDAF_WORKLOAD_VNET_CODE');
    $args{sdaf_region_code} //= get_required_var('PUBLIC_CLOUD_REGION');

    foreach ('env_code', 'sdaf_region_code', 'sap_sid', 'vnet_code') {
        croak "Missing mandatory argument: $_" unless $args{$_};
    };

    my $config_root_path = get_sdaf_config_path(
        deployment_type     => 'sap_system',
        sap_sid             => $args{sap_sid},
        env_code            => $args{env_code},
        vnet_code           => $args{vnet_code},
        sdaf_region_code    => convert_region_to_short($args{sdaf_region_code}), # converts full region name to SDAF abbreviation
        job_id              => find_deployment_id()
    );

    return "$config_root_path/$args{sap_sid}_hosts.yaml";
}

=head2 read_inventory_file

    read_inventory_file($sap_inventory_file_path);

B<inventory_file_path> SAP SID of the existing deployment. Default: get_var('SAP_SID')

Returns full path to an existing ansible inventory file

=cut

sub read_inventory_file {
    my ($inventory_file_path) = @_;
    my $ypp = YAML::PP->new;
    my $raw_file = script_output("cat $inventory_file_path");
    my $yaml_data = $ypp->load_string($raw_file);
    return $yaml_data;
}

=head2 instance_data_from_inventory

    instance_data_from_inventory();


B<region_code>: SDAF parameter to choose PC region. Note SDAF is using internal abbreviations (SECE = swedencentral)

B<provider_data>: Provider data obtained from calling B<provider_factory()>

B<sut_ssh_key_path>: Full path to private key for accessing SUT.

B<inventory_content> Referenced content of the inventory yaml file

Creates and returns  B<$instances> class which is a main component of F<lib/sles4sap_publiccloud.pm> and
general public cloud libraries F</lib/publiccloud/*>.

=cut

sub instance_data_from_inventory {
    my (%args) = @_;
    croak('Missing mandatory argument "$args{provider_data}" ') unless $args{provider_data};
    croak('Missing mandatory argument "$args{sut_ssh_key_path}" ') unless $args{sut_ssh_key_path};
    $args{region_code} //= get_required_var('PUBLIC_CLOUD_REGION');

    my @instances = ();

    for my $instance_type (keys(%{ $args{inventory_content} })) {
        my $hosts = $args{inventory_content}->{$instance_type}{hosts};
        for my $physical_host (keys %$hosts){
            my $instance = publiccloud::instance->new(
                public_ip   => $hosts->{$physical_host}->{ansible_host},
                instance_id => $physical_host,
                username    => $hosts->{$physical_host}->{ansible_user},
                ssh_key     => $args{sut_ssh_key_path},
                provider    => $args{provider_data},
                region      => $args{region_code}
            );
            push(@instances, $instance);
            record_info('Instance', Dumper($instance));
        }
    }
    publiccloud::instances::set_instances(@instances);
    return \@instances;
}

=head2 ssh_config_entry_add

    ssh_config_entry_add(entry_name=$entry_name, hostname=>$hostname
        [, identity_file=>$identity_file, identities_only=><bool>, proxy_jump=$proxy_jump, batch_mode=>bool]);

B<entry_name> Config entry name. This name can be used instead of host/IP in ssh command. Example: ssh root@<entry_name>

B<user> Define ssh username

B<hostname> Target hostname or IP addr

B<identity_file> Full path to SSH private key

B<identities_only> If true, SSH will only attempt passwordless login

B<batch_mode> If true, all SSH interactive features will be disabled. Test won't have to wait for timeouts.

B<proxy_jump> Jump host hostname, IP addr or point to another entry in config file

Add host entry into ~/.ssh/config

=cut

sub ssh_config_entry_add {
    my (%args) = @_;
    my $config_path = '~/.ssh/config';
    my @mandatory_args = qw(entry_name hostname);
    foreach (@mandatory_args) {
        croak "Missing mandatory argument: $_" unless $args{$_};
    }

    # passwordless, non-interactive ssh by default
    $args{batch_mode} //= 'yes';
    $args{identities_only} //= 'yes';

    my @file_contents = (
        "Host $args{entry_name}",
        "  HostName $args{hostname}",
        "  IdentitiesOnly $args{identities_only}",
        "  BatchMode $args{batch_mode}"
    );
    push(@file_contents, "  User $args{user}") if $args{user};
    push(@file_contents, "  IdentityFile $args{identity_file}") if $args{identity_file};
    push(@file_contents, "  ProxyJump $args{proxy_jump}") if $args{proxy_jump};
    assert_script_run("echo \"$_\" >> $config_path") foreach @file_contents;
}

=head2 ssh_config_add_instances

    ssh_config_entry_add(entry_name=$entry_name, hostname=>$hostname
        [, identity_file=>$identity_file, identities_only=><bool>, proxy_jump=$proxy_jump]);

B<inventory_content> Referenced content of the inventory yaml file

B<jump_host> hostname, IP address or F<~/.ssh/config> entry pointing to jumphost

B<identity_file> Full path to SSH private key

Reads data located in B<$instances> class and composes F<~/.ssh/config> entry for each host. This is meant specifically
for hosts that need to be accessed using jumphost and allows them to be accessed with ssh command .
The B<$instances> class is main component of F<lib/sles4sap_publiccloud.pm> and
general public cloud libraries F</lib/publiccloud/*>.

=cut

sub ssh_config_add_instances {
    my (%args) = @_;
    foreach ('inventory_content', 'jump_host', 'identity_file') {
        croak "Missing mandatory argument '\$args{$_}'" unless $args{$_};
    }
    for my $instance_type ( keys(%{ $args{inventory_content} }) ) {
        my $hosts = $args{inventory_content}->{$instance_type}{hosts};
        for my $hostname (keys %$hosts) {
            my $host_data = $hosts->{$hostname};
            ssh_config_entry_add(
                entry_name      => "$hostname $host_data->{ansible_host}", # This allows both hostname and IP login
                user            => $host_data->{ansible_user},
                hostname        => $host_data->{ansible_host},
                identity_file   => $host_data->{identity_file},
                identities_only => 'yes',
                proxy_jump      => $args{jump_host}
            );
        }
    };
}