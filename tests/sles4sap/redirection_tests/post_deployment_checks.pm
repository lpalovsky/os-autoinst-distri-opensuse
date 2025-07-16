# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Post deployment screens and checks

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

package post_deployment_checks;
use strict;
use warnings FATAL => 'all';
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::console_redirection;
use Data::Dumper;

=head1 SYNOPSIS

Module executes post deployment checks and status screens about deployed infrastructure and application.

=cut

sub run {
    my ($self, $run_args) = @_;
    my %redirection_data = %{$run_args->{redirection_data}};
    record_info('full data', Dumper(\%redirection_data));

    my @all_hosts = map { $_ => $redirection_data{$_} } keys(%redirection_data);
    record_info('all hosts', Dumper(\@all_hosts));
    my %database_hosts = %{ $redirection_data{db_hana} };

    my @execution_plan = [
        {hosts => @all_hosts, commands => [{description => 'OS info', command => 'cat /etc/os-release'}]},
        {hosts => %database_hosts, commands => [
            {description => 'DB processes', command => 'ps -ef | grep hdb'},
            {description => 'HDB info', command => 'sudo -u hdbadm /hana/shared/HDB/HDB00/HDB info'}
        ]
        },
        {hosts => %database_hosts, commands => [
            {description => 'DB cluster', command => 'sudo crm status full'},
            {description => 'HanaSR status', command => 'sudo SAPHanaSR-showAttr'}
        ]
        }
    ];

    record_info('DATA', \@execution_plan);

    # OS info


    # Show database related info

    # HA DB info

    # HA ENSA2 info

    #

}

1;
