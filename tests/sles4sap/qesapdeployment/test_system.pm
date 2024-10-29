# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use qesapdeployment;
use hacluster qw($crm_mon_cmd cluster_status_matches_regex);

sub run {
    my ($self) = @_;
    my $provider_setting = get_required_var('PUBLIC_CLOUD_PROVIDER');

    # Ignore return, just test the mechanism to find the inventory
    qesap_get_inventory(provider => $provider_setting);

    my $chdir = qesap_get_terraform_dir(provider => $provider_setting);
    assert_script_run("terraform -chdir=$chdir output");
    my @remote_cmd = (
        'pwd', 'uname -a',
        'cat /etc/os-release',
        'sudo SUSEConnect --status-text',
        'zypper ref', 'zypper lr',
        'zypper in -f -y vim',
        'zypper -n in ClusterTools2'
    );
    qesap_ansible_cmd(cmd => $_, provider => $provider_setting, timeout => 300) for @remote_cmd;
}

sub post_fail_hook {
    my ($self) = shift;
    # This test module does not have both
    # fatal flag and qesap_test_postfail, so that in case of failure
    # the next test_ module is executed too.
    # Deployment destroy is delegated to the destroy test module
    $self->SUPER::post_fail_hook;
}

1;