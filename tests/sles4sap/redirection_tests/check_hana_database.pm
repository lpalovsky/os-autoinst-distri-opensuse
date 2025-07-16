# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Post deployment screens and checks

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

package check_hana_database;
use strict;
use warnings FATAL => 'all';
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;
use sles4sap::console_redirection::redirection_data_tools;
use hacluster qw(wait_for_idle_cluster check_cluster_state);
use sles4sap::database_hana qw(hdb_info);
use sles4sap::sap_host_agent qw(saphostctrl_list_instances);
use hacluster qw($crm_mon_cmd);

=head1 SYNOPSIS

Module executes checks and status screens for HANA database cluster.

=cut

sub run {
    my ($self, $run_args) = @_;
    my $redirection_data = sles4sap::console_redirection::redirection_data_tools->new($run_args->{redirection_data});
    my %database_hosts = %{$redirection_data->get_databases};
    if (!%database_hosts) {
        record_info('N/A', 'Database deployment not detected, skipping.');
        return;
    }
    my %results;

    # DB cluster result collection
    for my $host (keys(%database_hosts)) {
        # Everything is now executed on SUT, not worker VM
        my $ip_addr = $database_hosts{$host}{ip_address};
        my $user = $database_hosts{$host}{ssh_user};
        my %instance_results;
        die "Redirection data missing. Got:\nIP: $ip_addr\nUSER: $user\n" unless $ip_addr and $user;

        connect_target_to_serial(destination_ip => $ip_addr, ssh_user => $user, switch_root => 'yes');
        wait_for_idle_cluster();

        my $instance_data = saphostctrl_list_instances(as_root => 'yes', running => 'yes');

        # Collected results will be displayed at the end of the module
        $instance_results{Release} = script_output('cat /etc/os-release', quiet => 1);
        $instance_results{'System Replication'} = script_output('SAPHanaSR-showAttr', quiet => 1);
        $instance_results{'CRM status'} = script_output($crm_mon_cmd, quiet => 1);
        $instance_results{'HDB info'} = hdb_info(switch_user => $instance_data->[0]{sidadm}, quiet => 'true');
        $results{$host} = \%instance_results;

        check_cluster_state();
        disconnect_target_from_serial();
    }
    record_info('RESULTS');
    for my $host (keys(%results)) {
        record_info("Host: $host");
        my $host_results = $results{$host};
        # Loop over result title and command output
        record_info($_, $host_results->{$_}) foreach keys(%{$host_results});
    }
}

1;
