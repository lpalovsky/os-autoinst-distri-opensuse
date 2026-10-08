# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
#
# Library used for cleaning up orphaned SDAF resources

package sles4sap::sap_deployment_automation_framework::subscription_cleanup;
use strict;
use warnings;
use testapi;
use Mojo::Base -signatures;
use Exporter qw(import);
use Time::Piece;
use Carp qw(croak);
use mmapi qw(get_parents get_job_autoinst_vars get_children get_job_info get_current_job_id);
use sles4sap::sap_deployment_automation_framework::deployment_connector qw(no_cleanup_tag);
use sles4sap::azure_cli;

our @EXPORT = qw(
  time_test
);

=head2 new

    my $cleanup_state = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();

Class is used to hold data structure containing all information regarding orphaned resources cleanup.

=cut

sub new {
    my ($class) = @_;
    # `state` initializes variables only once and keeps values across all class instances
    state $self = {
        test_id     => get_current_job_id(),
        instance_id => undef,
        start_time  => undef,
        end_time    => undef,
        test_result => undef,
        cleanup_result => undef,
        results     => {
            sap_systems    => undef,
            workload_zones => undef,
            secrets        => undef,
            tfstate_files  => undef,
            deployer_vms   => undef,
            ibsm_peerings  => undef
        }
    };
    return bless $self, $class;
}

=head2 time_test

    time_test($input_time);

Checks B<$input_time> against 'SDAF_DEPLOYER_VM_RETENTION_SEC' (Default 12H) openQA setting.
Returns 'true' if time is older/greater that retention period, otherwise undef.

=over

=item * B<input_time>: Time to check against retention period

=back

=cut

sub time_test ($input_time) {
    croak 'Missing mandatory argument: $input_time' unless $input_time;
    # Couple of notes to time formats:
    # - for format explanation check 'man strftime' - az cli returns date in ISO 8601 format
    # - Time::Piece does not recognize microseconds, they need to be neutered using regex
    $input_time =~ s/\.\d+(?=\+\d\d)//;

    # - Time::Piece does not recognize az cli timezone format `+02:00`, only `+0200`
    #   - therefore we have to do some colonoscopy and remove `:` from az cli output
    $input_time =~ s/(?<=\+\d\d):(?=\d\d$)//;
    my $time = Time::Piece->strptime($input_time, '%Y-%m-%dT%H:%M:%S%z')->epoch();

    return $time < time() - get_var('SDAF_DEPLOYER_VM_RETENTION_SEC', '43200') ? 1 : undef;
}

=head2 get_orphaned_groups

    get_orphaned_groups();

Returns list of resource groups outside of retention criteria.

=cut

sub get_orphaned_groups () {
    my @sap_groups = az_group_name_get(query=>''); # ^SDAF-OpenQA-sap_system-[0-9]+$

}

1;