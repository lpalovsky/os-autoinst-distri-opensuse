# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Triggers cleanup of the workload zone and SUT using SDAF automation

use parent 'sles4sap::microsoft_sdaf_basetest';
use strict;
use testapi;
use warnings FATAL => 'all';
use sles4sap::microsoft_sdaf;

sub test_flags {
    return {fatal => 1};
}

sub run {
    serial_console_diag_banner('SDAF Cleanup');
    # Setting up cleanup flag will trigger post run cleanup
    set_var('SDAF_DO_CLEANUP', 'YES! Please, do it.');
}

# post fail override to avoid running failed cleanup 2x
sub post_fail_hook {
    record_os_variables();
}

1;
