# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Boots into jumphost qcow and installs 'govc' CLI tool.

use strict;
use warnings;
use testapi;
use base "qeaas::qeaas_vmware_basetest";
use utils;
use serial_terminal 'select_serial_terminal';
use qeaas::vmware_govc;

sub test_flags {
    return {fatal => 1, multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;
    my $govc_filename = 'govc_Linux_' . get_var('ARCH') . '.tar.gz';
    my $govc_url = 'https://github.com/vmware/govmomi/releases/latest/download/' . $govc_filename;
    my %env_vars = (
        'GOVC_URL' => get_required_var('VSPHERE_URL'),
        'GOVC_USERNAME' => get_required_var('VSPHERE_USERNAME') . '@' . get_required_var('VSPHERE_DOMAIN'),
        'GOVC_PASSWORD' => get_required_var('VSPHERE_PASSWORD'),
        'GOVC_INSECURE' => get_var('VSPHERE_INSECURE', '0')
    );

    select_serial_terminal();
    foreach my $var_name (keys %env_vars) {
        assert_script_run("export $var_name=\"$env_vars{$var_name}\"");
    }

    assert_script_run(join(' ', 'curl', '-L', $govc_url, '-o', "/tmp/$govc_filename"));
    assert_script_run("tar -xvzf /tmp/$govc_filename -C /usr/local/bin/");
    govc_cmd('about');

    record_info('GOVC tool', "Tool 'govc' installed.");
}

1;
