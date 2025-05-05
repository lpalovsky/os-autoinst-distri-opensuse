# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test module for azure stonith based fencing agent


use strict;
use warnings FATAL => 'all';

use base 'sles4sap_publiccloud_basetest';
use serial_terminal 'select_serial_terminal';
use testapi;
use sles4sap_publiccloud;
use sles4sap::qesap::qesapdeployment;
use Data::Dumper;

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;

    # Needed to have peering and ansible state propagated in post_fail_hook
    $self->import_context($run_args);
    use Data::Dumper;
    record_info('Inst DATA', Dumper($run_args->{instances}));
    my %redirection_data;
    for my $host_data (@{ $run_args->{instances} }) {
        record_info('Host DATA', Dumper($host_data));
        next unless $host_data->{instance_id} =~ /vmhana/;
        $redirection_data{db_hana}{$host_data->{instance_id}} = {
            ip_address => $host_data->{public_ip},
            ssh_user => $host_data->{username}
        };
    }
    record_info('Redir DATA', Dumper(\%redirection_data));
    $run_args->{redirection_data} = \%redirection_data;
}

1;