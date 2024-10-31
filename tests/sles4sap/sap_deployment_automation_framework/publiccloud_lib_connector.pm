# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:  Executes setup of HanaSR scenario using SDAF ansible playbooks according to:
#           https://learn.microsoft.com/en-us/azure/sap/automation/tutorial#sap-application-installation

use base 'sles4sap_publiccloud_basetest';
use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection qw(connect_target_to_serial disconnect_target_from_serial);
use sles4sap_publiccloud;
use sles4sap::sap_deployment_automation_framework::inventory_tools;
use sles4sap::sap_deployment_automation_framework::naming_conventions
    qw(get_sdaf_inventory_path convert_region_to_short get_workload_vnet_code);

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;
    select_serial_terminal;
    connect_target_to_serial();

    set_var('_SECRET_PUBLIC_CLOUD_CREDENTIALS_USER', 'azureadm');
    set_var('_SECRET_PUBLIC_CLOUD_CREDENTIALS_PWD', 'pass');

    my $provider = publiccloud::azure->new();
    use Data::Dumper;
    record_info('Provider', Dumper($provider));

    my $inventory_path = get_sdaf_inventory_path(
        env_code => get_required_var('SDAF_ENV_CODE'),
        sdaf_region_code => convert_region_to_short(get_required_var('PUBLIC_CLOUD_REGION')),
        vnet_code => get_workload_vnet_code(),
        sap_sid => get_required_var('SAP_SID')
    );
    my $inventory_data = read_inventory_file($inventory_path);
    # Share inventory data between all tests
    $self->{sdaf_inventory} = $inventory_data;
    record_info('Provider', Dumper($inventory_data));

    my $instances = instance_data_from_inventory(
        provider_data => $provider,
        sut_ssh_key_path => '/something',
        inventory_content => $inventory_data
    );
    record_info('Instances', Dumper($instances));

    for my $instance (@$instances) {
        record_info 'Instance', join(' ', 'IP: ', $instance->public_ip, 'Name: ', $instance->instance_id);
        $self->{my_instance} = $instance;
        $instance->wait_for_ssh();
    }

}

1;
