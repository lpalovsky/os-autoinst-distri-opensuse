# SUSE's openQA tests
#
# Copyright 2017-2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Functions for SAP tests
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::database_hana;
use strict;
use warnings;
use testapi;
use Carp qw(croak);
use Exporter qw(import);
use saputils qw(check_crm_output get_primary_node calculate_hana_topology);
use sles4sap::sapcontrol;

our @EXPORT = qw(
  hdb_stop
  is_registration_automatic
  wait_for_failed_resources
  wait_for_takeover
);


=head1 SYNOPSIS

Package contains functions for interacting with hana database and related actions.

=cut

=head2 sudo

    sudo($activate);

Return string 'sudo ' (space included) if there is any 'true' equivalent passed as an argument, otherwise return empty string.
This is to be used to prepend 'sudo' to any command under a condition.
Example: script_run(sudo($args{as_root}) . 'whoami');

=over

=item * B<$activate>: Any value which is an equivalent to 'true' makes functkion return 'sudo'. Default: false

=back

=cut

sub sudo {
    return ('sudo ') if @_;
}

=head2 hdb_stop

    hdb_stop(instance_id=>'00', [switch_user=>'sidadm']);

Stop hana database using C<HDB stop> command. Function expects to be executed as sidadm, however you can use B<switch_user>
to execute command using C<sudo su -> as a different user. The user needs to have correct permissions for performing
requested action.
Function waits till all DB processes are stopped.

=over

=item * B<instance_id>: Database instance ID. Mandatory.

=item * B<switch_user>: Execute command as specified user with help of C<sudo su ->. Default: undef

=back

=cut

sub hdb_stop {
    my (%args) = @_;
    my $stop_timeout = 600;
    my $sudo_su = $args{switch_user} ? "sudo su - $args{switch_user} -c" : '';
    my $cmd = join(' ', $sudo_su, '"', 'HDB', 'stop', '"');
    record_info('HDB stop', "Executing '$cmd' on " . script_output('hostname'));
    assert_script_run($cmd, timeout => $stop_timeout);
    sapcontrol_process_check(instance_id => $args{instance_id}, expected_state => 'stopped', wait_for_state => 'yes', timeout => $stop_timeout);
    record_info('DB stopped');
}

=head2 is_registration_automatic

    is_registration_automatic([as_root=>1]);

Returns 1 if crm cluster 'AUTOMATED_REGISTER' parameter is set for SAP HANA DB.

=over

=item * B<as_root>: Optional. Runs command using sudo. Default: current user.

=back

=cut

sub is_registration_automatic {
    my (%args) = @_;
    my $cmd = sudo($args{as_root}) . 'crm configure show related:ocf:suse:SAPHana | grep AUTOMATED_REGISTER=true';
    return 1 if !script_run($cmd, quiet => 1);
    return 0;
}

=head2 wait_for_failed_resources

    wait_for_failed_resources();

Wait until 'crm_mon' starts showing failed resources. This can be used as first indicator of a started failover.

=cut

sub wait_for_failed_resources {
    my $timeout = 300;
    my $start_time = time;
    while (check_crm_output(input => script_output('crm_mon -R -r -n -N -1', quiet => 1))) {
        sleep 30;
        die("Cluster did not register any failed resource within $timeout sec") if (time - $timeout > $start_time);
    }
    record_info('CRM info', "Cluster registered failed resources\n" . script_output('crm_mon -R -r -n -N -1', quiet => 1));
}

=head2 wait_for_takeover

    wait_for_takeover(target_node=>'expeliarmus');

Waits until B<target_node> performs takeover and reaches 'PRIM' state.

=over

=item * B<target_node>: Node hostname which is expected to take over.

=back

=cut

sub wait_for_takeover {
    my (%args) = @_;
    my $timeout = 300;
    my $start_time = time;
    my $topology;
    my $takeover_ok;
    until ($takeover_ok) {
        die("Node '$args{target_node}' did not take over within $timeout sec") if (time - $timeout > $start_time);
        $topology = calculate_hana_topology(input => script_output('SAPHanaSR-showAttr --format=script'));
        $takeover_ok = 1 if (get_primary_node(input => $topology) eq $args{target_node});
        sleep 30;
    }
}
