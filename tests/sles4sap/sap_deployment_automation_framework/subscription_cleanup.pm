# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test which does general preparation on jumphost by:

=head1 SYNOPSIS

This is not a test module but part of teardown for instances running SDAF
deployment based tests.
Module scans subscription defined by OpenQA settings and destroys resources
left after failed deployment and jobs. This module is supposed to be scheduled
independently from any test scenarios.


=cut

use Mojo::Base 'sles4sap::sap_deployment_automation_framework::basetest';
use strict;
use warnings FATAL => 'all';
use serial_terminal qw(select_serial_terminal);
use testapi;
use sles4sap::sap_deployment_automation_framework::deployment
    qw(az_login check_credentials);
use sles4sap::sap_deployment_automation_framework::subscription_cleanup;


sub run {
    select_serial_terminal();
    az_login();
    assert_script_run('az extension add --name resource-graph --upgrade');
    my $cleanup_result = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();
    $cleanup_result->get_orphaned_resource_groups();

    use Data::Dumper;
    record_info('Cleanup', Dumper($cleanup_result));

}

sub test_flags {
    return {fatal => 1};
}

1;