# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:
#   - Test collects data about current cluster setup
#   - Failover is performed on primary database and
#   -

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;
use saputils qw(calculate_hana_topology get_primary_node get_failover_node);
use hacluster qw(wait_for_idle_cluster wait_until_resources_started);
use sles4sap::sap_host_agent qw(saphostctrl_list_databases parse_instance_name);
use sles4sap::database_hana;
use sles4sap::sapcontrol qw(sapcontrol_process_check);
use Data::Dumper;

sub run {
    my ($self, $run_args) = @_;
    #my $failover_type = get_required_var('DB_FAILOVER_TYPE');
    #record_info('Test INFO', "Performing primary DB failover scenario: $failover_type");
    my %databases = %{$run_args->{redirection_data}{db_hana}};

    # Command node is a DB cluster node (does not matter which) which will issue various commands to check cluster state, etc...
    my $target_node = (keys %databases)[0];
    my %target_node_data = %{$databases{$target_node}};

    # Connect to command node to get topology data
    connect_target_to_serial(
        destination_ip => $target_node_data{ip_address}, ssh_user => $target_node_data{ssh_user}, switch_root => '1');

    # Install ClusterTools2 if not yet present
    assert_script_run('zypper -n in ClusterTools2', timeout => 600) if script_run('rpm -q ClusterTools2');

    # Wait for cluster to settle before doing anything
    wait_until_resources_started();
    wait_for_idle_cluster();

    my $topology = calculate_hana_topology(input => script_output('SAPHanaSR-showAttr --format=script'));
    my $primary_db = get_primary_node(input => $topology);
    my $replica_db = get_failover_node(input => $topology);
    my $automatic_register = is_registration_automatic();
    record_info('Primary DB', "Primary DB node found: $primary_db");

    # We need to switch to the primary node if it is not already connected
    unless ($primary_db eq $target_node) {
        record_info('Console switch', "Reconnecting console to primary DB node: $primary_db");
        disconnect_target_from_serial();
        connect_target_to_serial(
            destination_ip => $databases{$primary_db}{ip_address},
            ssh_user => $databases{$primary_db}{ssh_user},
            switch_root => '1');
    }

    # Retrieve database information: DB SID and instance ID
    my @db_data = @{(saphostctrl_list_databases())};
    record_info('DB data', Dumper(@db_data));
    die('Multiple databases on one host not supported') if @db_data > 1;
    my ($db_sid, $db_id) = @{parse_instance_name($db_data[0]->{'instance_name'})};

    # Perform failover on primary
    hdb_stop(instance_id => $db_id, switch_user => lc($db_sid) . 'adm');

    # Wait for takeover
    record_info('Takeover', "Waiting for node '$replica_db' to become primary");
    wait_for_failed_resources();
    wait_for_takeover(target_node => $replica_db);

    # Register and start replication
    if ($automatic_register) {
        record_info('REG: Auto', "Parameter: AUTOMATED_REGISTER=true\nNo action to be done");
    }
    else {
        record_info('REG: Manual', "Parameter: AUTOMATED_REGISTER=false\nRegistration will be done manually");
    }

    # Wait for database processes to start
    record_info('DB wait', "Waiting for database node '$primary_db' to start");
    sapcontrol_process_check(
        instance_id => $db_id, expected_state => 'started', wait_for_state => 'yes', timeout => 600);
    record_info('DB started', "All database node '$primary_db' processes are 'GREEN'");

    # Wait for cluster co come up
    record_info('Cluster wait', 'Waiting for cluster to come up');
    wait_until_resources_started();
    wait_for_idle_cluster();
    record_info('Cluster OK', 'Cluster resources up and running');

    assert_script_run('crm resource refresh');
    disconnect_target_from_serial();
}

1;
