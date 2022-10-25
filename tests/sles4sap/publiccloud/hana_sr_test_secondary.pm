# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary:

use base 'sles4sap_publiccloud_basetest';
use strict;
use warnings FATAL => 'all';
use sles4sap_publiccloud;
use testapi;
use Data::Dumper;

sub run {
    my ($self, $run_args) = @_;
    $self->{instances} = $run_args->{instances};
    my $hana_start_timeout = bmwqemu::scale_timeout(600);
    my $site_b = $run_args->{site_b};
    $self->select_serial_terminal;

    # Switch to control Site B (currently replica mode)
    $self->{my_instance} = $site_b;
    my $cluster_status = $self->run_cmd(cmd => "crm status");
    record_info("Cluster status", $cluster_status);
    # Check initial state: 'site B' = replica mode
    die("Site B '$site_b->{instance_id}' is NOT in replication mode.") if
      $self->get_promoted_hostname() eq $site_b->{instance_id};

    # Stop DB
    # check variable DB_ACTION in case of separate usage of the test.
    my $db_action = get_var("DB_ACTION", $run_args->{hana_test_definitions}{$self->{name}});
    if ($db_action eq "stop") {
        record_info("Stop DB", "Stopping Site B ('$site_b->{instance_id}')");
    }
    elsif ($db_action eq "kill") {
        record_info("Kill DB", "Killing Site B ('$site_b->{instance_id}')");
    }
    elsif ($db_action eq "crash") {
        record_info("Crash DB", "Crashing OS on Site B ('$site_b->{instance_id}')");
    }
    else {
        croak("Database action unknown or not defined.");
    }
    # Setup sbd delay in case of crash OS to prevent cluster starting too quickly after reboot
    $self->setup_sbd_delay("30s") if $db_action eq "crash";
    $self->stop_hana(method => $db_action);

    if ($db_action eq "crash") {
        $self->{my_instance}->wait_for_ssh(username => 'cloudadmin');
        sleep 10;
        $self->wait_for_pacemaker();
    }

    # wait for DB to start with resources
    $self->is_hana_online(wait_for_start => 'true');
    my $hana_started = time;
    while (time - $hana_started > $hana_start_timeout) {
        last if $self->is_hana_resource_running();
        sleep 30;
    }

    # Check if DB started as primary
    die("Site B '$site_b->{instance_id}' did NOT start in replication mode.")
      if $self->get_promoted_hostname() eq $site_b->{instance_id};

    record_info("Done", "Test finished");
}

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

1;
