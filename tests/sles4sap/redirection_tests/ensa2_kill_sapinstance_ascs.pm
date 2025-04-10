# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test module tests ENSA2 Central Services with HANA DB - Use sapcontrol to move ASCS.
#   It runs sapcontrol related commands on remote host using console redirection.
#   For more information read 'README.md'

use parent 'sles4sap::sap_deployment_automation_framework::basetest';

use warnings;
use strict;
use testapi;
use serial_terminal qw(select_serial_terminal);
use hacluster;
use sles4sap::console_redirection;

sub run {
    my ($self, $run_args) = @_;
    my %redirection_data = %{$run_args->{redirection_data}};
    my $ascs_hostname = (keys($redirection_data{'nw_ascs'}))[0];
    my %ascs_data = $redirection_data{'nw_ascs'}{$ascs_hostname};

    # Connect to scs VM
    connect_target_to_serial(
        destination_ip => $ascs_data{ip_address}, ssh_user => $ascs_data{ssh_user}, switch_root => 1);

    # Check if cluster is being healthy
    my $fail_count;
    record_info('Cluster wait', 'Waiting for resources to start');
    wait_until_resources_started();
    wait_for_idle_cluster();
    record_info('Cluster check', 'Checking state of cluster resources');
    check_cluster_state();

    my @instance_resources = @{ crm_resources_by_class(primitive_class => 'ocf::heartbeat:SAPInstance') };
    my $ascs_instance = grep /SCS/, @instance_resources;
    # Check resource fail count - must be 0
    $fail_count = get_crm_failcount(resource=>$ascs_instance, assert_result=>'yes');
    record_info("Fail count: $fail_count", "Fail count is $fail_count");

    # Kill ENQ process
    record_info('PROC list', script_output('ps -ef | grep sap')); # Show SAP processes running
    my $enq_pid = script_output('pgrep en.sap');
    die 'ENQ process ID not found' unless $enq_pid;
    assert_script_run("kill -9 $enq_pid");

    # Check if ENQ process was killed
    record_info('PROC list', script_output('ps -ef | grep sap')); # Show SAP processes running
    die 'ENQ process still running after being killed.' unless script_run('pgrep en.sap'); # pgrep returns 1 if process was not found

    # Wait for ENQ process to come up again on the same node
    record_info('Cluster wait', 'Waiting for resources to start');
    wait_until_resources_started();
    wait_for_idle_cluster();
    record_info('Cluster check', 'Checking state of cluster resources');
    check_cluster_state();

    # Check if fail count is 1
    $fail_count = get_crm_failcount(resource=>$ascs_instance);
    die "Fail count must be larger than 0 after failure. got: '$fail_count'" unless $fail_count;
    record_info("Fail count: $fail_count", "Fail count is $fail_count");

}

1;
