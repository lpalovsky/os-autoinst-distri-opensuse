
# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Deployment of the SAP systems zone using SDAF automation

# Required OpenQA variables:
#     'SDAF_WORKLOAD_VNET_CODE' Virtual network code for workload zone.

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use strict;
use warnings;
use serial_terminal qw(select_serial_terminal);
use testapi;
use sles4sap::sap_deployment_automation_framework::deployment
    qw(serial_console_diag_banner
        prepare_tfvars_file
        az_login
        set_common_sdaf_os_env
        prepare_sdaf_project
        sdaf_execute_deployment
    );
use sles4sap::sap_deployment_automation_framework::naming_conventions qw(generate_resource_group_name);


sub test_flags {
    return {fatal => 1};
}

sub run {
    wait_still_screen();
    select_serial_terminal();
    serial_console_diag_banner('Module sdaf_deploy_sap_systems.pm : start');
    my $subscription_id = az_login();
    set_var('SDAF_RESOURCE_GROUP', generate_resource_group_name(deployment_type => 'deployer'));
    set_var('SDAF_VNET_CODE', get_required_var('SDAF_DEPLOYER_VNET_CODE'));

    set_common_sdaf_os_env(subscription_id => $subscription_id);
    prepare_sdaf_project();

    prepare_tfvars_file(deployment_type => 'deployer');

    set_var('SDAF_RESOURCE_GROUP', generate_resource_group_name(deployment_type => 'library'));
    prepare_tfvars_file(deployment_type => 'library');

    sdaf_execute_deployment(deployment_type=>'deployer');

    serial_console_diag_banner('Module sdaf_deploy_sap_systems.pm : end');
}

1;