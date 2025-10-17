# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Setup peering between SUT VNET and IBSm VNET

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::azure_cli;
use sles4sap::sap_deployment_automation_framework::deployment_connector qw(find_deployment_id);
use sles4sap::sap_deployment_automation_framework::basetest qw(ibsm_data_collect);
use sles4sap::sap_deployment_automation_framework::naming_conventions;
use sles4sap::sap_deployment_automation_framework::deployment;
use sles4sap::console_redirection;

=head1 NAME

sles4sap/sap_deployment_automation_framework/ibsm_configure.pm - Setup connection between ISBM and Workload zone VNETs.

=head1 MAINTAINER

QE-SAP <qe-sap@suse.de>

=head1 DESCRIPTION

Test module sets up network peering between tests workload zone and IBSm VNET.

B<The key tasks performed by this module include:>

=over

=item * Verifies if test module was executed with 'IS_MAINTENANCE' OpenQA setting and returns if IBSm connection is not required.

=item * Collects data required for creating network peerings

=item * Creates resources for two way peering between two VNETs

=item * Creates DNS zone and record for all SUTs to access ISBM host using FQDN defined by OpenQA setting B<'REPO_MIRROR_HOST'>

=item * Verifies if peering resources were created

=back

=head1 OPENQA SETTINGS

=over

=item * B<IBSM_RG> : IBSm resource group name

=item * B<IS_MAINTENANCE> : Define if test scenario includes applying maintenance updates

=item * B<REPO_MIRROR_HOST> : IBSm repository hostname

=back
=cut

sub test_flags {
    return {fatal => 1};
}

sub run {
    unless (get_var('IS_MAINTENANCE')) {
        # Just a safeguard for case the module is in schedule without 'IS_MAINTENANCE' OpenQA setting being set
        record_info('MAINTENANCE OFF', 'OpenQA setting "IS_MAINTENANCE" is disabled, skipping IBSm setup');
        return;
    }

    # add repo

    # update

    # reboot

    # check
}

1;