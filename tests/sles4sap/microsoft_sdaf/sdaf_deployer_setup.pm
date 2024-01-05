# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test which does general preparation on jumphost by:
#   - setting up OS env variables
#   - preparing directory structure and cloning repositories

# Required OpenQA variables:
#     'SDAF_ENV_CODE'  Code for SDAF deployment env.
#     'SDAF_DEPLOYER_VNET_CODE' Deployer virtual network code.
#     'SDAF_WORKLOAD_VNET_CODE' Virtual network code for workload zone.
#     'SDAF_REGION_CODE' SDAF internal code for azure region.
#     'SAP_SID' SAP system ID.
#     'SDAF_DEPLOYER_RESOURCE_GROUP' Existing deployer resource group - part of the permanent cloud infrastructure.

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
    my @required_packages = qw(terraform terraform-provider-azurerm git jq );

    select_serial_terminal();
    # From now on everything is executed on Deployer VM (residing on cloud).
    connect_target_to_serial();
    serial_console_diag_banner('Prepare jumphost');
    my $subscription_id = az_login();
    my $deployer_ip =sdaf_get_deployer_ip(get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP'));
    set_var('TARGET_SUT_IP', $deployer_ip); # This is not SUT IP but jumphost VM. Just parameter naming convention.
    set_var('SUT_USER', 'azureadm');

    set_common_sdaf_os_env(subscription_id => $subscription_id);
    prepare_sdaf_repo();
    disconnect_target_from_serial();

    record_info('Jumphost ready');
    serial_console_diag_banner('jumphost ready');
}

1;
