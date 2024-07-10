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
use YAML::PP;
use mmapi qw(get_parents get_job_autoinst_vars get_children get_job_info get_current_job_id);
use Data::Dumper;

our @EXPORT = qw(
  get_deployer_vm
  get_deployer_ip
  check_ssh_availability
  find_deployment_id
  find_deployer_resources
  ssh_config_entry_add
  prepare_ssh_config
  verify_ssh_proxy_connection
);

=head2 check_ssh_availability

    check_ssh_availability($deployer_ip_addr [, ssh_port=>42 ,$wait_started=>'true', wait_timeout=>'42']);

Checks if deployer VM is running and listening on ssh port. Returns found state.
Optionally function can wait till VM reaches requested state until timeout.
Function dies only with internal errors, VM status should be evaluated and handled by caller.

B<deployer_ip_addr>: Deployer VM IP address

B<wait_started>: Probe SSH port in loop untill it is available or B<wait_timeoout> is reached.

B<wait_timeout>: Time in sec to stop probing SSH port.

B<ssh_port>: Specify custom SSH port number. Default: 22

=cut

sub check_ssh_availability {
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

Returns first public IP of deployer VM that is reachable and can be used for SDAF deployment connection.

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployer_vm_name>: Deployer VM resource name

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
        return $ip if check_ssh_availability($ip, wait_started => 'yes');
    }
    return undef;
}

=head2 get_deployer_vm

    get_deployer_vm(deployer_resource_group=>$deployer_resource_group, deployment_id=>'123456');

Returns deployer VM name which is tagged with B<deployment_id> specified in parameter. This means that the VM was used
to deploy the infrastructure under this ID and contains whole SDAF setup.
Function returns VM name or undef if no VM was found.
Function dies if there is more than one VM found, because two VM's must not have same ID.

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployment_id>: Deployment ID

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

Finds deployment ID for currently running test. Deployment ID is ID of an OpenQA test which created deployer VM.
In case of multi-machine test this can be either parent test ID or current job id as well.
This function collects all OpenQA job IDs related to current test run and checks if any of them match an existing
deployer VM tagged with this ID.

B<Example>:
Job: 123456 - deployment module - created deployer VM tagged with "deployment_id=123456",
Job: 123457 (child of 123456) - some test module
Deployment ID returned from both jobs: 123456 - because it matches with existing VM tagged with "deployment_id=123456"

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

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

    get_deployer_resources(deployer_resource_group=>$deployer_resource_group [, deployment_id=>'123456', return_ids=1]);

Returns ARRAYREF of all resources belonging to B<deployer_resource_group> tagged with B<deployment_id>.

B<deployer_resource_group>: Deployer resource group. Default: get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP')

B<deployment_id>: Deployment ID

B<return_value>: Control the content of the returned array. It can either return array of resource IDs or resource names.
    Values allowed: id, name
    Default: name

=cut

sub find_deployer_resources {
    my (%args) = @_;
    $args{deployer_resource_group} //= get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    $args{deployment_id} //= find_deployment_id();
    $args{return_value} //= 'name';
    croak "Argument 'return_value' accepts only 'id' or 'name'" unless grep(/$args{return_value}/, ('id', 'name'));

    my $az_cmd = join(' ',
        'az resource list',
        "--resource-group $args{deployer_resource_group}",
        "--query \"[?tags.deployment_id == '$args{deployment_id}'].$args{return_value}\"",
        '--output json'
    );

    my @resource_list = @{decode_json(script_output($az_cmd))};

    return \@resource_list;
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

B<strict_host_key_checking> Turn off host key check

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
    push(@file_contents, "  StrictHostKeyChecking $args{strict_host_key_checking}") if $args{strict_host_key_checking};
    assert_script_run("echo \"$_\" >> $config_path", quiet=>1) foreach @file_contents;
}

=head2 prepare_ssh_config

    prepare_ssh_config(inventory_data=>HASHREF, jump_host=>10.10.10.10, identity_file=>'/home/tux/id_rsa');

Reads parsed and referenced SDAF inventory data and composes F<~/.ssh/config> entry for each host.
In case of SDAF you need to specify B<jump_host> if you want to set this up on worker VM and access SUT via SSH proxy.
For parsing inventory data check function B<read_inventory_content> inside:
I<lib/sles4sap/sap_deployment_automation_framework/deployment.pm>

B<inventory_data> SDAF inventory content in referenced perl data structure.

B<jump_host> hostname, IP address or F<~/.ssh/config> entry pointing to jumphost. Keyless SSH must be working.

B<identity_file> Full path to SSH private key

=cut

sub prepare_ssh_config {
    my (%args) = @_;
    foreach ('inventory_data', 'jump_host', 'identity_file') {
        croak "Missing mandatory argument '\$args{$_}'" unless $args{$_};
    }

    # Add Jumphost first
    ssh_config_entry_add(
        entry_name    => 'deployer_jump',
        user          => 'azureadm',
        hostname      => $args{jump_host},
        identities_only => 'yes',
        identity_file => '~/.ssh/id_rsa'
    );

    # Add all SUT systems defined in inventory file
    for my $instance_type (keys(%{$args{inventory_data}})) {
        my $hosts = $args{inventory_data}->{$instance_type}{hosts};
        for my $hostname (keys %$hosts) {
            my $host_data = $hosts->{$hostname};
            ssh_config_entry_add(
                entry_name               => "$hostname", # This allows both hostname and IP login
                user                     => $host_data->{ansible_user},
                hostname                 => $host_data->{ansible_host},
                identity_file            => $args{identity_file},
                identities_only          => 'yes',
                proxy_jump               => 'deployer_jump',
                strict_host_key_checking => 'no'
            );
        }
    }
    record_info('SSH config', "SSH proxy setup added into '~/.ssh/config':\n" . script_output('cat ~/.ssh/config'));
}

sub verify_ssh_proxy_connection {
    my (%args) = @_;
    for my $instance_type (keys(%{$args{inventory_data}})) {
        my $hosts = $args{inventory_data}->{$instance_type}{hosts};
        for my $hostname (keys %$hosts){
            # run simple 'hostname' command on each host
            assert_script_run("ssh $hostname hostname", quiet=>1);
            record_info('SSH check', "SSH proxy connection to $hostname: OK");
        }
    }
}