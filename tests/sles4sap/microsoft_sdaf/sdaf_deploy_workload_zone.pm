# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Deployment of the workload zone and SUT using SDAF automation

use parent 'sles4sap::microsoft_sdaf_basetest';

use strict;
use warnings;
use sles4sap::microsoft_sdaf;
use sles4sap::console_redirection;
use serial_terminal qw(select_serial_terminal);
use testapi;

sub test_flags {
    return {fatal => 1};
}

sub run {
    serial_console_diag_banner('workload zone deployment: start');

    # From now on everything is executed on Deployer VM (residing on cloud).
    connect_target_to_serial();

    # Setup Workload zone openQA variables - used for tfvars template
    my %openqa_variables = (
        SDAF_VNET_CODE => get_required_var('SDAF_WORKLOAD_VNET_CODE'),
        RESOURCE_GROUP => get_resource_group('workload_zone'),
    );
    foreach (keys %openqa_variables) { set_var($_, $openqa_variables{$_}); }
    set_os_variable('vnet_code', get_required_var('SDAF_WORKLOAD_VNET_CODE'));
    my $workload_tfvars_file = prepare_tfvars_file('workload_zone');
    az_login();
    sdaf_deploy_workload_zone($workload_tfvars_file);
    disconnect_target_from_serial();
    serial_console_diag_banner('workload zone deployment: end');
}

1;
