# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Deploys a vmware based VM using 'govc' CLI tool.

use strict;
use warnings;
use testapi;
use base "qeaas::qeaas_vmware_basetest";
use serial_terminal 'select_serial_terminal';
use qeaas::vmware_govc;


sub deploy_single_vm {
    my ($vm_index) = @_;
    my $vm_definition = delimit_string_into_hash(get_required_var('QEAAS_VM' . $vm_index));
    my %vm_definition = %$vm_definition;

    record_info('VM Deploy', "'Deploying VM: $vm_definition{'vm_name'}'");

    govc_vm_create('datastore_cluster' => get_required_var('QEAAS_DATASTORE_CLUSTER'),
        'datastore' => get_required_var('QEAAS_DATASTORE'),
        'vm_network' => get_required_var('QEAAS_VM_NETWORK'),
        'deployment_name' => get_required_var('QEAAS_DEPLOYMENT_NAME'),
        'firmware' => get_var('QEAAS_VM_FIRMWARE', 'efi'),
        'guest_os_id' => get_required_var('QEAAS_GUEST_OS_ID'),
        'iso_filename' => get_var('QEAAS_ISO_FILENAME'),
        'iso_datastore' => get_var('QEAAS_ISO_DATASTORE'),
        'vm_name' => $vm_definition{'vm_name'},
        'memsize_mb' => $vm_definition{'memory'},
        'cpu_num' => $vm_definition{'cpu'},
        'mac_addr' => $vm_definition{'mac'},
        'os_disk_size_gb' => $vm_definition{'os_disk_size'},
        'quiet' => '1'
    );
}

sub run {
    my ($self, $run_args) = @_;
    my $node_count = get_required_var('QEAAS_VM_COUNT');

    for my $vm_index (1 .. $node_count) {
        die "VM deployment failed, check logs for details." unless deploy_single_vm($vm_index);
    }
}

1;
