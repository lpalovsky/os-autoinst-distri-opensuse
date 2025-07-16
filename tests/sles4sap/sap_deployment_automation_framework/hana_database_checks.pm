# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Post deployment screens and checks

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

package hana_database_checks;
use strict;
use warnings FATAL => 'all';
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;
use sles4sap::console_redirection::redirection_data_tools;
use hacluster qw(wait_for_idle_cluster check_cluster_state);
use sles4sap::database_hana qw(hdb_info);
use sles4sap::sap_host_agent qw(saphostctrl_list_instances);
use Data::Dumper;

=head1 SYNOPSIS

Module executes post deployment checks and status screens for HANA database cluster.

=cut

sub run {
    my ($self, $run_args) = @_;
    my $redirection = sles4sap::console_redirection::redirection_data_tools->new($run_args->{redirection_data});
    my %database_hosts = %{ $redirection->get_databases };
    my $instance_data;

    # DB cluster
    for my $host (keys(%database_hosts)) {
        # Everything is now executed on SUT, not worker VM
        my $ip_addr = $database_hosts{$host}{ip_address};
        my $user = $database_hosts{$host}{ssh_user};
        die "Redirection data missing. Got:\nIP: $ip_addr\nUSER: $user\n" unless $ip_addr and $user;

        connect_target_to_serial(destination_ip => $ip_addr, ssh_user => $user, switch_root => 'yes');
        wait_for_idle_cluster();

        # Only collect the data once
        $instance_data //= saphostctrl_list_instances(as_root => 'yes');

        # loop commands
        record_info("STATUS $host", "Status screens for '$host'.\nConnecting: $user\@$ip_addr");
        record_info('OS release', script_output('cat /etc/os-release', quiet => 1));
        record_info('Show attr', script_output('SAPHanaSR-showAttr', quiet => 1));
        record_info('CRM status', script_output('crm status full', quiet => 1));
        hdb_info(switch_user => $instance_data->[0]{sidadm}, quiet => 'true');

        # display record info
        check_cluster_state();
        disconnect_target_from_serial();
        record_info('STATUS OK');
    }
}

1;
