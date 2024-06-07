# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:

# Required OpenQA variables:


use parent 'sles4sap::microsoft_sdaf_basetest';
use strict;
use warnings;
use sles4sap::sdaf_deployment_library;
use sles4sap::azure_cli;
use serial_terminal qw(select_serial_terminal);
use mmapi qw(get_current_job_id);
use testapi;

sub test_flags {
    return {fatal => 1};
}

sub run {
    select_serial_terminal();
    serial_console_diag_banner('Module sdaf_clone_deployer.pm : start');
    my $deployer_resource_group = get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');
    my $snapshot_source_disk = get_var('SDAF_DEPLOYER_SNAPSHOT', 'deployer_snapshot_latest');
    my $deployer_vm_size = get_var('SDAF_DEPLOYER_MACHINE', 'Standard_B2als_v2'); # Small VM to control costs
    my $new_deployer_vm_name = sdaf_get_deployer_name();
    my $deployer_disk_name = "$new_deployer_vm_name\_Os";

    az_login();

    # Create OS disk from snapshot
    az_disk_create(resource_group=>$deployer_resource_group, name=>$deployer_disk_name, source=>$snapshot_source_disk);

    # Create new VM clone
    my $vm_create_cmd = join(' ', 'az vm create',
        "--resource-group $deployer_resource_group",
        "--name $new_deployer_vm_name",
        "--attach-os-disk $deployer_disk_name",
        "--size $deployer_vm_size",
        "--os-type Linux"
    );
    assert_script_run($vm_create_cmd, timeout=>600);

    my $deployer_public_ip = sdaf_get_deployer_ip(deployer_resource_group=>$deployer_resource_group);
    sdaf_check_deployer_ssh($deployer_public_ip, wait_started=>'yeeeees');

    serial_console_diag_banner('Module sdaf_clone_deployer.pm : stop');
}

1;