# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Libraries interacting with 'govc' CLI used for vmware vSphere server.


package qeaas::vmware_govc;

use base Exporter;
use strict;
use warnings;
use Exporter;
use testapi;
use version_utils 'is_sle';
use Mojo::Util 'trim';
use Carp 'croak';

our @EXPORT = qw(
  govc_cmd
  govc_vm_create
  govc_vm_destroy
  govc_vm_exists
  delimit_string_into_hash
);

=head1 SYNOPSIS

Library used around 'govc' CLI tool used for managing vmware vSphere server.
All about the project and usage can be found below:

https://github.com/vmware/govmomi/tree/main/govc
https://github.com/vmware/govmomi/blob/main/govc/USAGE.md
=cut

=head2 govc_cmd

 govc_cmd($subcommand, [govc_arguments => $govc_arguments], [quiet => $quiet]);

Executes govc command with subcommand and opktional argumens specified.
Returns RC in case of $quiet being true, otherwise command output is returned.
=cut

sub govc_cmd {
    my ($subcommand, %args) = @_;
    my $govc_arguments = $args{govc_arguments} // '';
    my $quiet = $args{quiet} // 0;
    croak unless $subcommand;

    my $govc_command = trim(join(' ', 'govc', $subcommand, $govc_arguments));
    my $rc = script_run($govc_command, quiet => $quiet);
    # Flipping bash RC to perl true/false
    my $result = $rc ? 0 : 1;

    record_info("govc exec", "executing:\n $govc_command");
    return $result;
}

=head2 govc_vm_create

 govc_vm_create();

Creates VM on vSphere server. For options and their descriptions check official documentation:
https://github.com/vmware/govmomi/blob/main/govc/USAGE.md#vmcreate

=cut

sub govc_vm_create {
    my (%args) = @_;
    my $quiet = $args{quiet} // 0;
    my $datastore_cluster = $args{datastore_cluster};
    my $datastore = $args{datastore};
    my $memsize_mb = $args{memsize_mb};
    my $cpu_num = $args{cpu_num};
    my $mac_addr = $args{mac_addr};
    my $vm_network = $args{vm_network};
    my $os_disk_size_gb = $args{os_disk_size_gb};
    my $vm_name = $args{vm_name};
    my $deployment_name = $args{deployment_name};
    my $guest_os_id = $args{guest_os_id};
    my $do_not_start = $args{do_not_start};
    my $iso_filename = $args{iso_filename};
    my $iso_datastore = $args{iso_datastore};
    my $firmware = $args{firmware};

    my @mandatory_args = ($datastore_cluster, $datastore, $memsize_mb, $cpu_num, $vm_network, $vm_name, $deployment_name, $os_disk_size_gb, $firmware, $guest_os_id);
    foreach (@mandatory_args) { croak('Missing mandatory argument') unless defined($_) }

    my @govc_arguments = (
        "-annotation='$deployment_name'",
        "-net='$vm_network'",
        "-g='$guest_os_id'",
        "-net.adapter='e1000'",
        "-c='$cpu_num'",
        "-m='$memsize_mb'",
        "-dc='$datastore_cluster'",
        "-ds='$datastore'",
        join('', "-disk='", $os_disk_size_gb, "G'"),
        "-firmware='$firmware'");

    $do_not_start ? push(@govc_arguments, '-on=false') : push(@govc_arguments, '-on=true');
    push(@govc_arguments, "-net.address='$mac_addr'") if $mac_addr;
    push(@govc_arguments, "-iso='$iso_filename'") if $iso_filename;
    push(@govc_arguments, "-iso-datastore='$iso_datastore'") if $iso_datastore;
    push(@govc_arguments, "-verbose='true'") unless $quiet;
    push(@govc_arguments, $vm_name);

    my $govc_result = govc_cmd("vm.create", govc_arguments => join(' ', @govc_arguments));
    return $govc_result;
}

=head2 collect_vm_deployment_data

 collect_vm_deployment_data($string_data);

Creates a hash by delimiting data from a string. This way one can store hash in an openQA variable.
Delimiters:
    "=" delimits key from value
    " ," separaters key/value pairs from each other
    OpenQA variable example:  [QEAAS_VM_1: "vm_name='vm_hana1', network=some_network_name, mac=0c:fd:37:96:8c:15, cpu=8, memory=2048, os_disk_size=60"]

=cut

sub delimit_string_into_hash {
    my ($string_data) = @_;
    croak "Mandatory argument '$string_data' was not specified." unless $string_data;
    my %result = split(/[,=]/, $string_data);

    return \%result;
}

=head2 govc_vm_destroy

 collect_vm_deployment_data($string_data);

Destroys all infrastructure related to the specified VM.
If VM is not found on the vSphere server, action is skipped.

=cut

sub govc_vm_destroy {
    my ($vm_name, %args) = @_;
    croak "Mandatory argument 'vm_name' was not specified." unless $vm_name;
    unless (govc_vm_exists($vm_name)) {
        record_info('VM missing', "VM '$vm_name' not found on the server, skipping cleanup");
        return 1;
    }
    my $destroy_cmd = "vm.destroy $vm_name";
    my $quiet = $args{quiet};
    govc_cmd($destroy_cmd, quiet => $quiet);
    return 1;
}


=head2 govc_vm_exists

 govc_vm_exists($vm_name);

Returns 1 if vm exists on vSphere server, otherwise 0.

=cut

sub govc_vm_exists {
    my ($vm_name) = @_;
    croak "Mandatory argument 'vm_name' was not specified." unless $vm_name;
    # grep here is required since vm.info returns 0 even if VM does not exist
    my $result = govc_cmd("vm.info $vm_name| grep $vm_name");
    $result;
}
