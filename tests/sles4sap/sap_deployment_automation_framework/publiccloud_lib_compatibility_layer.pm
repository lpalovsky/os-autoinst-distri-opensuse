# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Prepares compatibility layer for using `lib/publiccloud/` library with SDAF deployment

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection qw(connect_target_to_serial disconnect_target_from_serial);
use sles4sap::sap_deployment_automation_framework::inventory_tools qw(read_inventory_file sdaf_create_instances);
use sles4sap::sap_deployment_automation_framework::naming_conventions
  qw(get_sdaf_inventory_path convert_region_to_short get_sdaf_config_path get_workload_vnet_code);
sub run {
    my ($self, $run_args) = @_;
    select_serial_terminal;

    my $inventory_path = get_sdaf_inventory_path(
        env_code => get_required_var('SDAF_ENV_CODE'),
        sdaf_region_code => convert_region_to_short(get_required_var('PUBLIC_CLOUD_REGION')),
        vnet_code => get_workload_vnet_code(),
        sap_sid => get_required_var('SAP_SID')
    );

    my $sut_ssh_private_key = get_sdaf_config_path(
        deployment_type => 'sap_system',
        env_code => get_required_var('SDAF_ENV_CODE'),
        sdaf_region_code => convert_region_to_short(get_required_var('PUBLIC_CLOUD_REGION')),
        vnet_code => get_workload_vnet_code(),
        sap_sid => get_required_var('SAP_SID')
    ) . '/sshkey';

    # Connect serial to Deployer VM to get inventory file
    connect_target_to_serial();
    my $inventory_data = read_inventory_file($inventory_path);
    # From now on all commands will be executed on worker VM

    my $instances = $self->{instances} = sdaf_create_instances(
        inventory_content=>$inventory_data, sut_ssh_key_path=>$sut_ssh_private_key);
    use Data::Dumper;
    record_info('Instances', Dumper($instances));


    for my $instance (@$instances) {
        $self->{my_instance} = $instance;
        $instance->wait_for_ssh();
    }

    disconnect_target_from_serial();
}

1;