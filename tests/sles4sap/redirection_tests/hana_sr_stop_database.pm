# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;
use saputils qw(calculate_hana_topology get_primary_node);
use hacluster qw(wait_for_idle_cluster);
use Data::Dumper;

sub run {
    my ($self, $run_args) = @_;
    my %databases = %{ $run_args->{redirection_data}{db_hana} };

    # Command node is a DB cluster node (does not matter which) which will issue various commands to check cluster state, etc...
    my $command_node = (keys %databases)[0];
    my %command_node_data = %{ $databases{$command_node} };

    # Connect to command node to get topology data
    connect_target_to_serial(
        destination_ip => $command_node_data{ip_address}, ssh_user => $command_node_data{ssh_user}, switch_root => '1');
    my $topology = calculate_hana_topology(input => script_output('SAPHanaSR-showAttr --format=script'));
    my $primary_db = get_primary_node(input => $topology);

    # We need to switch to the primary node if it is not already connected
    unless ($primary_db eq $command_node) {
        disconnect_target_from_serial();
        connect_target_to_serial(
            destination_ip => $databases{$primary_db}{ip_address},
            ssh_user => $databases{$primary_db}{ssh_user},
            switch_root => '1');
    }
    assert_script_run('zypper -n in ClusterTools2', timeout=>600);
    wait_for_idle_cluster();

    disconnect_target_from_serial();
}

1;