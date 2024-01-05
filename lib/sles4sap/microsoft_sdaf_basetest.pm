# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
#
# Basetest used for Microsoft SDAF deployment

package sles4sap::microsoft_sdaf_basetest;
use strict;
use warnings;
use testapi;
use parent 'opensusebasetest';
use sles4sap::microsoft_sdaf;
use sles4sap::console_redirection;

sub post_fail_hook {
    record_os_variables();
    record_info('Post fail', 'Executing post fail hook');
    connect_target_to_serial();
    sdaf_destroy();
    disconnect_target_from_serial();

}

sub post_run_hook {
    record_info('Post run', 'Executing post run hook');
    unless (get_var('SDAF_DO_CLEANUP')) {
        record_info('No cleanup', "Openqa variable 'SDAF_DO_CLEANUP' not set, skipping cleanup");
        return;
    }
    connect_target_to_serial();
    sdaf_destroy();
    disconnect_target_from_serial();
}

1;
