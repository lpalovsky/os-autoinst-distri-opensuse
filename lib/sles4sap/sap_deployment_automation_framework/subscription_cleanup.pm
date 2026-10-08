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
use sles4sap::sap_deployment_automation_framework::deployment_connector qw(no_cleanup_tag);

our @EXPORT = qw(
  get_orphaned_workload_zones
  get_orphaned_sap_systems
);

=head2 new

    my $cleanup_state = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();

Class is used to hold data structure containing all information regarding orphaned resources cleanup.

=cut

sub new ($class) {
    # `state` initializes variables only once and keeps values across all class instances
    my $job_id = get_current_job_id();

    state $self = {
        test_id     => get_current_job_id(),
        instance_id => get_required_var('OPENQA_HOSTNAME'),
        start_time  => get_job_info($job_id)->{t_started},
        end_time    => undef,
        test_result => undef,
        cleanup_result => undef,
        results     => {
            sap_systems    => {
                ids => [],
                result => undef
            },
            workload_zones => {
                ids    => [],
                result => undef
            },
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

Checks B<$input_time> against 'SDAF_CLEANUP_RETENTION_SEC' (Default 12H) openQA setting.
Returns 'true' if time is older/greater that retention period, otherwise 0.

=over

=item * B<input_time>: Time to check against retention period

=back

=cut

sub time_test ($input_time) {
    croak 'Missing mandatory argument: $input_time' unless $input_time;
    my $retention_age = get_var('SDAF_CLEANUP_RETENTION_SEC', '43200');
    # Couple of notes to time formats:
    # - for format explanation check 'man strftime' - az cli returns date in ISO 8601 format
    # - Time::Piece does not recognize microseconds, they need to be neutered using regex
    $input_time =~ s/\.\d+(?=\+\d\d)//;

    # - Time::Piece does not recognize az cli timezone format `+02:00`, only `+0200`
    #   - therefore we have to do some colonoscopy and remove `:` from az cli output
    $input_time =~ s/(?<=\+\d\d):(?=\d\d$)//;
    my $time = Time::Piece->strptime($input_time, '%Y-%m-%dT%H:%M:%S%z')->epoch();
    my $resource_orphaned = $time < time() -  $retention_age ? 1 : 0;
    diag("\n[CLEANUP]Retention test:
        Resource age: $time
        Retention age: $retention_age
        Resource orphaned: $resource_orphaned"
    );
    return $resource_orphaned;
}

=head2 _orphaned_group_kql

    _orphaned_group_kql(name_pattern => 'SDAF-OpenQA-sap_system');

Returns string with a KQL to query sap_systems or workload_zone groups.

=over

=item B<name_pattern> Resource group name pattern.

=back
=cut

sub _orphaned_group_kql (%args) {
    my $kql_return_structure = join(', ',
        'name',
        'deployment_id=tostring(tags.deployment_id)',
        'openqa_created_date=tostring(tags.openqa_created_date)'
    );
    my @kql_body = (
        'resourcecontainers',
        "where type =~ 'microsoft.resources/subscriptions/resourcegroups'",
        "where name startswith '$args{name_pattern}'",
        "where not(bag_keys(tags) has '" . no_cleanup_tag() . "')",
        "project $kql_return_structure"
    );

    return @kql_body;
}

=head2 get_orphaned_resource_groups

    my $cleanup_result = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();
    $cleanup_result->get_orphaned_resource_groups();

Queries for all orphaned SDAF resource groups older than retention
period and updates main class data. A workload zone is added only if a 'sap_system'
resource group with the same B<deployment_id> is already in the deletion list
C<< $self->{results}{sap_systems}{ids} >>. Or does not exist at all.

=cut

sub get_orphaned_resource_groups ($self) {
    my @sap_kql = _orphaned_group_kql(name_pattern => 'SDAF-OpenQA-sap_system');
    my @workload_kql = _orphaned_group_kql(name_pattern => 'SDAF-OpenQA-workload_zone');
    my $sap_groups = az_graph_query(statements => \@sap_kql, query => 'data', timeout=>'360')->{output};
    my $workload_groups = az_graph_query(statements => \@workload_kql, query => 'data', timeout => '360')->{output};

    # Mark all 'sap_systems' RG for deletion
    $self->{results}{sap_systems}{ids} = [map { time_test($_->{openqa_created_date}) ? $_ : () } @{$sap_groups}];

    for my $group (@{$workload_groups}) {
        my $deployment_id = $group->{deployment_id};
        next unless time_test($group->{openqa_created_date});
        # Add workload zone if its 'sap_systems' RG is marked for deletion or does not exist at all
        next unless (grep { $_->{deployment_id} eq $deployment_id } @{$self->{results}{sap_systems}{ids}})
          or not(grep { $_->{deployment_id} eq $deployment_id } @{$sap_groups});
        push @{$self->{results}{workload_zones}{ids}}, $group;
    }
}

=head2 destroy_orphaned_groups

    my $cleanup_result = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();
    $cleanup_result->destroy_orphaned_groups();

Destroys all 'sap_systems' and 'workload_zone' resource groups which were marked as orphaned
by `get_orphaned_resource_groups()`

=cut

sub destroy_orphaned_groups ($self) {
    # define new array with group names - sap systems first, append workload zones
    # for loop through array
        # delete groiup one by one using az_group_delete()
        # if group is deleted
}

1;