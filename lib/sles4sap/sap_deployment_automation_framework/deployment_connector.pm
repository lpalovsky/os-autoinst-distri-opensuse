# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

=head1 SYNOPSIS

This library contains various functions that help finding and connecting openQA job to the correct deployment VM.
Deployment VM is recognized from other VMs by being tagged with B<deployment_id> tag. Deployment ID is an unique
identifier which is an OpenQA job ID of a job that created this VM.
In single machine test Deployment ID equals test ID. This is not always true in case of multi-machine jobs.
Deployment ID might be an ID of the parent job which executed the deployment itself.

B<Example>:
Job: 123456 - deployment module - created deployer VM tagged with "deployment_id=123456",
Job: 123457 (child of 123456) - some test module
Deployment ID returned from both jobs: 123456 - because it matches with existing VM tagged with "deployment_id=123456"

=cut

package sles4sap::sap_deployment_automation_framework::deployment_connector;

use strict;
use warnings;
use testapi;
use Exporter qw(import);
use Mojo::JSON qw(decode_json);
use Scalar::Util qw(looks_like_number);
use Carp qw(croak);
use mmapi qw(get_parents get_job_autoinst_vars get_children get_job_info get_current_job_id);
use Data::Dumper;

our @EXPORT = qw(
  get_deployer_vm
  get_deployer_ip
  check_deployer_ssh
  find_deployment_id
  find_deployer_resources
);

=head2 check_deployer_ssh

    check_deployer_ssh($deployer_ip_addr [, ssh_port=>42 ,$wait_started=>'true', wait_timeout=>'42']);

B<deployer_ip_addr>: Deployer VM IP address

B<wait_started>: Probe SSH port in loop untill it is available or B<wait_timeoout> is reached.

B<wait_timeout>: Time in sec to stop probing SSH port.

B<ssh_port>: Specify custom SSH port number. Default: 22

Checks if deployer VM is running and listening on ssh port. Returns found state.
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
    # With `-w 10` netcat keeps waiting 10s for server response instead of returning immediately
    $nc_cmd .= ' -w 10' if $args{wait_started};
    $nc_cmd .= " $deployer_ip_addr $args{ssh_port}";

    my $start_time = time();
    until ($ssh_available) {
        $ssh_available = 1 if !script_run($nc_cmd, quiet => 1);
        last unless $args{wait_started};
        last if (time() - $start_time) >= $args{wait_timeout};
        record_info('SSH N/A', 'SSH unavailable, retrying in 10s');
        sleep 10;    # just a separation between loops, to avoid bombarding the server constantly
    }
    my $status = $ssh_available ? 'available' : 'unavailable';
    record_info('SSH check', "SSH connection to '$deployer_ip_addr -p $args{ssh_port}': $status");
    return $ssh_available;
}

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
    for my $ip (@{$ip_addr}) {
        return $ip if check_deployer_ssh($ip, wait_started => 'yes');
    }
    return undef;
}

=head2 get_deployer_vm

    get_deployer_vm(deployer_resource_group=>$deployer_resource_group, deployment_id=>'123456');

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployment_id>: Deployment ID

Returns deployer VM name which is tagged with B<deployment_id> specified in parameter. This means that the VM was used
to deploy the infrastructure under this ID and contains whole SDAF setup.
Function returns VM name or undef if no VM was found.
Function dies if there is more than one VM found, because two VM's must not have same ID.

=cut

sub get_deployer_vm {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    $args{deployment_id} //= find_deployment_id();
    croak 'Missing mandatory argument $args{deployment_id}' unless $args{deployment_id};

    # Following query lists VMs within a resource group that were tagged with specified deployment id.
    my $az_cmd = join(' ',
        'az vm list',
        "--resource-group $args{deployer_resource_group}",
        "--query \"\[?tags.deployment_id == '$args{deployment_id}'].name\"",
        '--output json'
    );

    my @vm_list = @{decode_json(script_output($az_cmd))};
    diag((caller(0))[3] . " - VMs found: " . join(', ', @vm_list));
    die "Multiple VMs with same IDs found. Each VM must have unique ID!\n
    Following VMs found tagged with: deployment_id=$args{deployment_id}"
      if @vm_list > 1;

    return $vm_list[0];
}

=head2 get_parent_ids

    get_parent_ids();

Returns B<ARRAYREF> of all parent job IDs acquired from current job data.

=cut

sub get_parent_ids {
    my $job_info = get_job_info(get_current_job_id());
    # This will loop through all parent job types (chained, parallel, etc...) and creates a list of IDs
    my @parent_ids = map { @{$job_info->{parents}{$_}} } keys(%{$job_info->{parents}});
    diag((caller(0))[3] . "Parent job data: " . Dumper($job_info->{parents}));
    foreach (@parent_ids) { die "Returned parent ID must be a number: '$_'" unless looks_like_number($_); }
    return \@parent_ids;
}

=head2 find_deployment_id

    find_deployment_id(deployer_resource_group=>$deployer_resource_group);

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

Finds deployment ID for currently running test. Deployment ID is ID of an OpenQA test which created deployer VM.
In case of multi-machine test this can be either parent test ID or current job id as well.
This function collects all OpenQA job IDs related to current test run and checks if any of them match an existing
deployer VM tagged with this ID.

B<Example>:
Job: 123456 - deployment module - created deployer VM tagged with "deployment_id=123456",
Job: 123457 (child of 123456) - some test module
Deployment ID returned from both jobs: 123456 - because it matches with existing VM tagged with "deployment_id=123456"

=cut

sub find_deployment_id {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    my @check_list = (get_current_job_id(), @{get_parent_ids()});

    diag("Job IDs found: " . Dumper(@check_list));
    my @ids_found;
    for my $deployment_id (@check_list) {
        my $vm_name =
          get_deployer_vm(deployer_resource_group => $args{deployer_resource_group}, deployment_id => $deployment_id);
        push(@ids_found, $deployment_id) if $vm_name;
    }
    die "More than one deployment found.\nJobs IDs: " .
      join(', ', @check_list) . "\nVMs found: " . join(', ', @ids_found) if @ids_found > 1;

    return ($ids_found[0]);
}

=head2 get_deployer_resources

    get_deployer_resources(deployer_resource_group=>$deployer_resource_group, deployment_id=>'123456');

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployment_id>: Deployment ID

B<return_ids>: Returns array of resource IDs instead of names

Returns ARRAYREF of all resources belonging to B<deployer_resource_group> tagged with B<deployment_id>.

=cut

sub find_deployer_resources {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    $args{deployment_id} //= find_deployment_id();
    $args{return_ids} = $args{return_ids} ? 'id' : 'name';
    my $az_cmd = join(' ',
        'az resource list',
        "--resource-group $args{deployer_resource_group}",
        "--query \"[?tags.deployment_id == '$args{deployment_id}'].$args{return_ids}\"",
        '--output json'
    );

    my @resource_list = @{decode_json(script_output($az_cmd))};

    return \@resource_list;
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