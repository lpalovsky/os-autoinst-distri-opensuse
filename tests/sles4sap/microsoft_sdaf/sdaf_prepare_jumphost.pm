# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test for redirecting console to deployer VM

use parent sles4sap::microsoft_sdaf_basetest;
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

    select_serial_terminal();
    my $subscription_id = az_login();
    my $deployer_ip = sdaf_get_deployer_ip(deployer_resource_group => get_required_var('SDAF_DEPLOYER_RESOURCE_GROUP'));
    my $ssh_user = get_var('REDIRECT_TARGET_USER', 'azureadm');

    set_var('REDIRECT_TARGET_USER', $ssh_user);
    set_var('REDIRECT_TARGET_IP', $deployer_ip);    # IP addr to redirect console to
    sdaf_prepare_ssh_keys(deployer_key_vault => get_required_var('SDAF_KEY_VAULT'));

    redirection_init();

    # From now on everything is executed on Deployer VM (residing on cloud).
    connect_target_to_serial(ssh_user => $ssh_user, target_ip => $deployer_ip);
    record_info("TEST conn", "This is a 'hostname' command executed on target host: " . script_output('hostname'));
    assert_script_run('hostname');

    select_console 'log-console';
    assert_script_run('hostname');

    select_serial_terminal;
    disconnect_target_from_serial();
    record_info("TEST noconn", "This is a 'hostname' command executed on worker VM after disconnection: " . script_output('hostname'));
    assert_script_run('hostname');
}

1;