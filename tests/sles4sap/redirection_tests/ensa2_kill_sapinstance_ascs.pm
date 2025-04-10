# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test module tests ENSA2 Central Services with HANA DB - Use sapcontrol to move ASCS.
#   It runs sapcontrol related commands on remote host using console redirection.
#   For more information read 'README.md'

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;

sub run {
    my ($self, $run_args) = @_;
    my %redirection_data = %{$run_args->{redirection_data}};

    # Check if cluster is being healthy
    # Check resource fail count - must be 0

    # Kill ENQ process

    # Check if ENQ process was killed

    # Wait for ENQ process to come up again on the same node


}

1;
