# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test module executes cloud custodian to clean up SDAF orphaned resources
#

use Mojo::Base 'sles4sap::sap_deployment_automation_framework::basetest';
use sles4sap::sap_deployment_automation_framework::deployment qw(az_login);
use sles4sap::azure_cli;
use serial_terminal qw(select_serial_terminal);
use testapi;

sub test_flags {
    return {fatal => 1};
}

sub run {
    select_serial_terminal();
    az_login();
    my $custodian_dir = '~/custodian';
    my $custodian_filename = 'custodian_cleanup.yaml';
    my @commands = (
        'python3 -m venv custodian',
        'source custodian/bin/activate',
        'pip install --upgrade pip',
        'pip install c7n',
        'pip install c7n_azure',
        "mkdir -p $custodian_dir/outputs/",
        "cd $custodian_dir"
    );

    for my $cmd (@commands){
        assert_script_run($cmd, quiet=>'1');
    }

    my $retrieve_custodian = join(' ', 'curl', '-v', '-fL',
        data_url("sles4sap/sap_deployment_automation_framework/$custodian_filename"),
        '-o', "$custodian_dir/$custodian_filename");
    assert_script_run($retrieve_custodian, quiet=>'1');

    my @custodian_policies = (
        'SDAF-delete-deployer-vms',
        'SDAF-delete-deployer-nic',
        'SDAF-delete-deployer-disk',
        'SDAF-delete-deployer-pip',
        'SDAF-delete-deployer-nsg',
        'SDAF-delete-old-sap_systems',
        'SDAF-delete-old-workload_zones',
        'SDAF-mark-for-cleanup-workload_zones'
    );
    my @policy_report;
    my $dry_run = get_var('SDAF_CUSTODIAN_EXECUTE') ? undef : '-d';
    record_info('DRY RUN', 'Dry run mode. No policy is executed. Define OpenQA setting "SDAF_CUSTODIAN_EXECUTE" to execute policies.') if $dry_run;
    for my $policy (@custodian_policies) {
        my $custodian_run = join(' ',
            'custodian run', $dry_run, '-v',
            "-s $custodian_dir/outputs/",
            "-p $policy",
            "$custodian_dir/$custodian_filename"
        );
        my $custodian_report = join(' ',
            'custodian report',
            '--format grid',
            "-s $custodian_dir/outputs/",
            "-p $policy",
            "$custodian_dir/$custodian_filename"
        );
        record_info("Policy: $policy",
            "Executing policy '$policy':\n$custodian_run\n" .
                script_output($custodian_run, quiet=>'1'));
        push @policy_report, "\n====================== Report: $custodian_report ======================\n";
        push @policy_report, script_output($custodian_report, quiet=>'1');
    }
    record_info('Report', join("\n", @policy_report));
}

sub post_fail_hook {
    record_info('No postfail');
}

1;
