# SUSE's openQA tests
#
# Copyright 2017-2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::database_hana;
use strict;
use warnings;
use testapi;
use Carp qw(croak);
use Exporter qw(import);
use saputils qw(check_crm_output get_primary_node get_failover_node calculate_hana_topology);
use sles4sap::sapcontrol;

our @EXPORT = qw(
  hdb_stop
  wait_for_failed_resources
  wait_for_takeover
  register_replica
  get_node_roles
  find_hana_resource_name
);


=head1 SYNOPSIS

Package contains functions for interacting with hana database and related actions.

=cut

=head2 hdb_stop

    hdb_stop(instance_id=>'00', [switch_user=>'sidadm', command=>'kill']);

Stop hana database using C<HDB stop> command. Function expects to be executed as sidadm, however you can use B<switch_user>
to execute command using C<sudo su -> as a different user. The user needs to have correct permissions for performing
requested action.
Function waits till all DB processes are stopped.

=over

=item * B<instance_id>: Database instance ID. Mandatory.

=item * B<switch_user>: Execute command as specified user with help of C<sudo su ->. Default: undef

=item * B<command>: HDB command to trigger. Default: stop

=back

=cut

sub hdb_stop {
    my (%args) = @_;
    my $stop_timeout = 600;
    $args{command} //= 'stop';
    croak("Command '$args{command}' is not supported.") unless grep(/$args{command}/, ('kill', 'stop'));

    $args{command} = 'kill -x' if ($args{command} eq 'kill');
    my $sudo_su = $args{switch_user} ? "sudo su - $args{switch_user} -c" : '';
    my $cmd = join(' ', $sudo_su, '"', 'HDB', $args{command}, '"');
    record_info('HDB stop', "Executing '$cmd' on " . script_output('hostname'));
    assert_script_run($cmd, timeout => $stop_timeout);

    # Wait Hana processes to stop
    sapcontrol_process_check(instance_id => $args{instance_id}, expected_state => 'stopped', wait_for_state => 'yes', timeout => $stop_timeout);
    record_info('DB stopped');
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
        $takeover_ok = 1 if (get_primary_node(topology_data => $topology) eq $args{target_node});
        sleep 30;
    }
}

=head2 register_replica

    register_replica(target_hostname=>'Dumbledore', instance_id=>'00' [, switch_user=>'hdbadm']);

Executes replica node registration after failover using 'hdbnsutil' command. Node must be stopped, otherwise command fails.

=over

=item * B<target_hostname>: Hostname of the node that should be registered as replica

=item * B<instance_id>: Instance ID

=item * B<switch_user>: Execute command as specified user with help of C<sudo su ->. Default: undef


=back

=cut

sub register_replica {
    my (%args) = @_;
    croak('Argument "$replica_hostname" missing') unless $args{target_hostname};
    my $topology = calculate_hana_topology(input => script_output('SAPHanaSR-showAttr --format=script'));
    my $primary_hostname = get_primary_node(topology_data => $topology);
    croak("Primary node '$primary_hostname' not found in 'SAPHanaSR-showAttr' output") unless $primary_hostname;
    croak("Replica node '$args{target_hostname}' not found in 'SAPHanaSR-showAttr' output") unless
      $topology->{$args{target_hostname}};

    my $cmd = join(' ',
        'hdbnsutil',
        '-sr_register',
        "--remoteHost=$primary_hostname",
        "--remoteInstance=$args{instance_id}",
        "--replicationMode=$topology->{$args{target_hostname}}{srmode}",
        "--operationMode=$topology->{$args{target_hostname}}{op_mode}",
        "--name=$topology->{$args{target_hostname}}{site}",
        '--online');
    $cmd = join(' ', 'sudo', 'su', '-', $args{switch_user}, '-c', '"', $cmd, '"') if $args{switch_user};
    assert_script_run($cmd);
    record_info('HANA REG', "Site '$topology->{$args{target_hostname}}{site}' registered as replica");
}

=head2 get_node_roles

    get_node_roles();

Returns B<HASHREF> containing current status of Hana cluster node roles by parsing 'SAPHanaSR-showAttr' output.
Example:
    {primary_node=>'Harry', failover_node='Potter'}

=cut

sub get_node_roles {
    my $topology = calculate_hana_topology(input => script_output('SAPHanaSR-showAttr --format=script'));
    my %result = (
        primary_node => get_primary_node(topology_data => $topology),
        failover_node => get_failover_node(topology_data => $topology));
    return (\%result);
}

=head2 find_hana_resource_name

    find_hana_resource_name();

Finds SAP Hana primitive resource name by listing primitives with type 'ocf:suse:SAPHana'.

=cut

sub find_hana_resource_name {
    my $primitive;
    foreach (split("\n", script_output('crm configure show related:ocf:suse:SAPHana | grep primitive'))) {
        my @aux = split(/\s+/, $_);
        $primitive = $aux[1] if $aux[2] and $aux[2] eq 'ocf:suse:SAPHana';
        last if $primitive;
    }
    # additional check if returned HANA resource exists
    assert_script_run("crm resource status $primitive");
    return $primitive;
}

1;