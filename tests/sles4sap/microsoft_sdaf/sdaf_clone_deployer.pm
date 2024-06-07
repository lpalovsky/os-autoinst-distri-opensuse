# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:  Clones existing Deployer VM which will be used for test run.
# Playbooks can be found in SDAF repo: https://github.com/Azure/sap-automation/tree/main/deploy/ansible

# Required OpenQA variables:
#     'SDAF_ENV_CODE'  Code for SDAF deployment env.
#     'SDAF_WORKLOAD_VNET_CODE' Virtual network code for workload zone.
#     'PUBLIC_CLOUD_REGION' SDAF internal code for azure region.
#     'SAP_SID' SAP system ID.
#     'SDAF_DEPLOYER_RESOURCE_GROUP' Existing deployer resource group - part of the permanent cloud infrastructure.

# Optional:
#     'SDAF_ANSIBLE_VERBOSITY_LEVEL' Override default verbosity for 'ansible-playbook'.

use parent 'sles4sap::microsoft_sdaf_basetest';
use strict;
use warnings;
use sles4sap::sdaf_deployment_library;
use sles4sap::azure_cli;
use serial_terminal qw(select_serial_terminal);
use testapi;

sub test_flags {
    return {fatal => 1};
}

sub run {
    select_serial_terminal();
    serial_console_diag_banner('Module sdaf_clone_deployer.pm : start');
    my $deployer_resource_group = get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    my $snapshot_source_disk = '';
    my $deployer_disk_name = '';
    my $new_deployer_vm_name = '';

    # Ensure that source VM is stopped.
    az_vm_deallocate(resource_group=>$deployer_resource_group, name=>$deployer_resource_group);

    # Create disk snapshot
    az_snapshot_create(resource_group=>$deployer_resource_group, name=>$deployer_resource_group, source=>$snapshot_source_disk);

    # Create OS disk from snapshot
    az_disk_create(resource_group=>$deployer_resource_group, name=>$deployer_resource_group, source=>$deployer_disk_name);

    # Create new VM clone
    my $vm_create_cmd = join(' ', 'az vm create',
        "--resource-group $deployer_resource_group",
        "--name $new_deployer_vm_name",
        "--attach-os-disk $deployer_disk_name",
        "--os-type Linux"
    );

    assert_script_run($vm_create_cmd);

    serial_console_diag_banner('Module sdaf_clone_deployer.pm : stop');
}

1;