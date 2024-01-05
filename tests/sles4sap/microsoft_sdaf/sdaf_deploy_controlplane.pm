# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

use parent 'sles4sap::microsoft_sdaf_basetest';
use strict;
use warnings;
use serial_terminal qw(select_serial_terminal);
use testapi;
use utils qw(zypper_call);
use Utils::Systemd qw(systemctl);
use sles4sap::microsoft_sdaf;

sub test_flags {
    return {fatal => 1};
}

sub run {
    my @required_packages = qw(terraform terraform-provider-azurerm ansible git jq);
    my $env_code = get_required_var('SDAF_ENV_CODE_CODE');
    my $deployer_vnet_code = get_required_var('SDAF_DEPLOYER_VNET_CODE');
    my $workload_vnet_code = get_required_var('SDAF_WORKLOAD_VNET_CODE');
    my $region_code = get_required_var('SDAF_REGION_CODE');
    my $deployment_dir_root = get_var('DEPLOYMENT_ROOT_DIR', '/root');
    my $deployment_dir = "$deployment_dir_root/Azure_SAP_Automated_Deployment";

    # reset deployment setup flag
    set_var('SDAF_DEPLOYMENT_SET', '0');

    select_serial_terminal();
    assert_script_run("zypper in -y @required_packages");

    my $subscription_id = az_login();
    set_os_env(env_code => $env_code,
        vnet_code => $vnet_code,
        region_code => $region_code,
        deployment_dir => $deployment_dir,
        subscription_id => $subscription_id);
    prepare_sdaf_repo(env_code => $env_code,
        vnet_code => $vnet_code,
        region_code => $region_code,
        deployment_dir => $deployment_dir,
        subscription_id => $subscription_id);

    sdaf_deploy_controlplane();

}

1;
