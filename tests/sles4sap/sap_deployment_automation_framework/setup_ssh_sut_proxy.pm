# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test module that generates .ssh/config entries from SDAF inventory file to allow ssh proxy connection from
#   worker VM directly into SUT.

# Required OpenQA variables:
#     'SDAF_ENV_CODE'  Code for SDAF deployment env.
#     'SDAF_WORKLOAD_VNET_CODE' Virtual network code for workload zone.
#     'PUBLIC_CLOUD_REGION' SDAF internal code for azure region.
#     'SAP_SID' SAP system ID.
#     'SDAF_DEPLOYER_RESOURCE_GROUP' Existing deployer resource group - part of the permanent cloud infrastructure.

use parent 'sles4sap::sap_deployment_automation_framework::basetest';
use strict;
use warnings;
use sles4sap::sap_deployment_automation_framework::deployment
  qw(serial_console_diag_banner load_os_env_variables sdaf_prepare_private_key read_uploaded_inventory);
use sles4sap::sap_deployment_automation_framework::deployment_connector
  qw(prepare_ssh_config get_deployer_vm find_deployment_id get_deployer_ip verify_ssh_proxy_connection);
use sles4sap::sap_deployment_automation_framework::naming_conventions
  qw(convert_region_to_short generate_resource_group_name upload_inventory_filename);
use sles4sap::console_redirection qw(connect_target_to_serial disconnect_target_from_serial);
use sles4sap::azure_cli qw(az_keyvault_list);
use serial_terminal qw(select_serial_terminal);
use testapi;

sub test_flags {
    return {fatal => 1};
}

sub run {
    my $deployer_resource_group = get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP');

    select_serial_terminal();
    serial_console_diag_banner('Module setup_ssh_sut_proxy.pm : start');

    # Retrieve private key for SUTs from workload zone.
    my @workload_zone_vault = @{az_keyvault_list(resource_group => generate_resource_group_name(deployment_type => 'workload_zone'))};
    die "Workload zone needs to have exactly one vault. Found:\n" . join(', ', @workload_zone_vault)
      unless @workload_zone_vault == 1;
    sdaf_prepare_private_key(key_vault => $workload_zone_vault[0], ssh_key_filename => 'id_rsa_sut');

    # Get deployer data
    my $deployment_id = find_deployment_id(deployer_resource_group => $deployer_resource_group);
    my $deployer_name = get_deployer_vm(deployer_resource_group => $deployer_resource_group, deployment_id => $deployment_id);
    my $deployer_ip = get_deployer_ip(deployer_resource_group => $deployer_resource_group, deployer_vm_name => $deployer_name);
    my $inventory_data = read_uploaded_inventory($deployment_id);

    # Create SUT entries for ~/.ssh/config
    prepare_ssh_config(
        inventory_data => $inventory_data, jump_host => $deployer_ip, identity_file => '~/.ssh/id_rsa_sut');

    record_info('PROXY check', 'Checking SSH proxy connection to all defined hosts');
    verify_ssh_proxy_connection(inventory_data=>$inventory_data);

    record_info('SSH Proxy OK', 'SSH proxy to SUT is ready');
    serial_console_diag_banner('Module setup_ssh_sut_proxy.pm : stop');
}

1;
