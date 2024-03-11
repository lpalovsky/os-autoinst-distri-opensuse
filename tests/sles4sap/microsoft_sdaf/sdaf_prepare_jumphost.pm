# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test for redirecting console to deployer VM

use parent sles4sap::microsoft_sdaf_basetest;
use strict;
use warnings;
use testapi;
use sles4sap::microsoft_sdaf;
use sles4sap::console_redirection;
use serial_terminal qw(select_serial_terminal);

sub test_flags {
    return {fatal => 1};
}
sub run {

    select_serial_terminal();
    my $subscription_id = az_login();
    my $deployer_ip = sdaf_get_deployer_ip(deployer_resource_group => get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP'));
    my $ssh_user = get_var('REDIRECT_TARGET_USER', 'azureadm');

    set_var('REDIRECT_TARGET_USER', $ssh_user);
    set_var('REDIRECT_TARGET_IP', $deployer_ip);    # IP addr to redirect console to
    sdaf_prepare_ssh_keys(deployer_key_vault => get_required_var('SDAF_KEY_VAULT'));
    assert_script_run('zypper in -y autossh');

    redirection_init();

    # From now on everything is executed on Deployer VM (residing on cloud).
    connect_target_to_serial();
    data_url('sles4sap/script_output.yaml');
    my $retrieve_cmd = join(' ', 'curl', '-v', '-fL', data_url('sles4sap/script_output.yaml'), '-o', '/tmp/script_output.yaml');

    assert_script_run($retrieve_cmd);
    upload_logs('/tmp/script_output.yaml');

    disconnect_target_from_serial();

}

1;
