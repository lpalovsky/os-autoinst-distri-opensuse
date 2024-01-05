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
    serial_console_diag_banner('sap infrastructure deploy: start');
    # Setup SUT deployment openQA variables
    my %openqa_variables = (
        SDAF_VNET_CODE => get_required_var('SDAF_WORKLOAD_VNET_CODE'),
        RESOURCE_GROUP => get_resource_group('sap_system'),
    );
    foreach (keys %openqa_variables) { set_var($_, $openqa_variables{$_}); }
    set_os_variable('vnet_code', get_required_var('SDAF_WORKLOAD_VNET_CODE'));
    connect_target_to_serial();

    my $tfvars_file = prepare_tfvars_file('sap_system');
    az_login();
    sdaf_deploy_sap_system($tfvars_file);
    disconnect_target_from_serial();
    serial_console_diag_banner('sap infrastructure deploy: end');
}

1;
