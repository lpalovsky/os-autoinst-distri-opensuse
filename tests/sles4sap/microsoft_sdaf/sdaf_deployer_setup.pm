# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test which does general preparation on jumphost by:
#   - preparing file with OS env variables that are required by SDAF
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
use sles4sap::sdaf_library;
use sles4sap::console_redirection;
use serial_terminal qw(select_serial_terminal);
use testapi;

sub test_flags {
    return {fatal => 1};
}

# Test uses OpenQA variables as default values for various library functions.
# Fail asap if those variables are missing.
sub check_required_vars {
    my @variables = qw(
      SDAF_ENV_CODE
      SDAF_DEPLOYER_VNET_CODE
      SDAF_WORKLOAD_VNET_CODE
      SDAF_REGION_CODE
      SAP_SID
      SDAF_DEPLOYER_RESOURCE_GROUP
    );
    get_required_var($_) foreach @variables;
}

sub run {
    select_serial_terminal();
    # Mark module start in serial console
    message_to_serial('START: sdaf_deployer_setup.pm');

    # From now on everything is executed on Deployer VM (residing on cloud).
    connect_target_to_serial();
    my $subscription_id = az_login();
    set_common_sdaf_os_env(subscription_id => $subscription_id);
    prepare_sdaf_repo();
    record_info('Jumphost ready');
    # Do not leave open connection between modules.
    disconnect_target_from_serial();
    # Mark module end in serial console
    message_to_serial('END: sdaf_deployer_setup.pm');
}

1;
