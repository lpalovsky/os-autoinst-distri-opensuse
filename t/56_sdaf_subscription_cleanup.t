use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use POSIX qw(strftime);
use List::Util qw(any none);
use Data::Dumper;
use sles4sap::sap_deployment_automation_framework::subscription_cleanup;

sub undef_variables {
    my @openqa_variables = qw( OPENQA_HOSTNAME SDAF_CLEANUP_RETENTION_SEC );
    set_var($_, undef) foreach @openqa_variables;
}

subtest '[get_orphaned_resource_groups] Check KQM composition' => sub {
    my $cleanup = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::subscription_cleanup', no_auto => 1);
    my $azcli = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $azcli->noop('assert_script_run');
    # Capture only calls from single execution
    $azcli->redefine(script_run => sub { push @calls, $_[0] if $_[0] =~ /sap_system/; return 0; });
    $azcli->redefine(script_output => sub {
        return 'out.json' if grep /az.json/, $_[0];
        return '[]' if grep /out.json/, $_[0]; }
    );
    $cleanup->redefine(get_current_job_id => sub { return '42'; });
    $cleanup->redefine(get_job_info => sub { return {t_started => '1999-01-01T00:00:00'}; });
    $cleanup->redefine(no_cleanup_tag => sub { return 'no_cleanup'; });

    set_var('OPENQA_HOSTNAME', 'Ivory');

    my $cleanup_result = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();
    $cleanup_result->get_orphaned_resource_groups();

    note("\n --> " . join("\n --> ", @calls));
    ok((any { /resourcecontainers/ } @calls), 'Query resource container');
    ok((any { /where name startswith/ } @calls), 'Query resource name');
    ok((any { /where type =\~ \'microsoft.resources\/subscriptions\/resourcegroups\'/ } @calls), 'Query resource type');
    ok((any { /where not\(bag_keys\(tags\) has/ } @calls), 'Filter out "no cleanup" tag');
    ok((any { /project name/ } @calls), 'Include resource name in output');
    ok((any { /deployment_id\=tostring\(tags.deployment_id\)/ } @calls), 'Include "deployment_id" tag in output');
    ok((any { /openqa_created_date\=tostring\(tags\.openqa_created_date\)/ } @calls), 'Include "openqa_created_date" tag in output');

    undef_variables();
};

subtest '[get_orphaned_resource_groups] Check deletion list logic' => sub {
    my $cleanup = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::subscription_cleanup', no_auto => 1);
    my $old = '1999-01-01T00:00:00+00:00';
    my $young = strftime('%Y-%m-%dT%H:%M:%S+00:00', gmtime);
    # az graph query return samples
    my @sap_systems = (
        {name => 'SDAF-OpenQA-sap_system-1', openqa_created_date => $old, deployment_id => '1'},
        {name => 'SDAF-OpenQA-sap_system-2', openqa_created_date => $young, deployment_id => '2'},
    );
    my @workload_zones = (
        {name => 'SDAF-OpenQA-workload_zone-1', openqa_created_date => $old, deployment_id => '1'},
        {name => 'SDAF-OpenQA-workload_zone-2', openqa_created_date => $old, deployment_id => '2'},
        {name => 'SDAF-OpenQA-workload_zone-3', openqa_created_date => $old, deployment_id => '3'},
        {name => 'SDAF-OpenQA-workload_zone-4', openqa_created_date => $young, deployment_id => '4'},
    );
    $cleanup->redefine(no_cleanup_tag => sub { return 'no_cleanup'; });
    $cleanup->redefine(az_graph_query => sub {
            my %args = @_;
            my $is_sap_query = grep { /SDAF-OpenQA-sap_system/ } @{$args{statements}};
            return {error => 0, rc => 0, output => $is_sap_query ? \@sap_systems : \@workload_zones};
    });
    $cleanup->redefine(get_current_job_id => sub { return '42'; });
    $cleanup->redefine(get_job_info => sub { return {t_started => '1999-01-01T00:00:00'}; });
    set_var('OPENQA_HOSTNAME', 'Ivory');

    my $cleanup_result = sles4sap::sap_deployment_automation_framework::subscription_cleanup->new();
    $cleanup_result->{results}{sap_systems}{ids} = [];
    $cleanup_result->{results}{workload_zones}{ids} = [];
    $cleanup_result->get_orphaned_resource_groups();

    my $sap_ids = $cleanup_result->{results}{sap_systems}{ids};
    my $zone_ids = $cleanup_result->{results}{workload_zones}{ids};

    note("\n SAP systems --> " . join("\n --> ", Dumper($cleanup_result->{results}{sap_systems})));
    note("\n Workload zones--> " . join("\n --> ", Dumper($cleanup_result->{results}{workload_zones})));

    ok((any { $_->{name} eq 'SDAF-OpenQA-sap_system-1' } @$sap_ids), '"sap_system" older than retention time is marked for deletion');
    ok((none { $_->{name} eq 'SDAF-OpenQA-sap_system-2' } @$sap_ids), '"sap_system" younger than retention time is not marked for deletion');
    ok((any { $_->{name} eq 'SDAF-OpenQA-workload_zone-1' } @$zone_ids), 'Old "workload_zone" is marked if its "sap_system" is marked for deletion');
    ok((none { $_->{name} eq 'SDAF-OpenQA-workload_zone-2' } @$zone_ids), 'Do not mark old workload zone for deletion without "sap_system" being marked too.');
    ok((any { $_->{name} eq 'SDAF-OpenQA-workload_zone-3' } @$zone_ids), 'Old "workload_zone" is marked if corresponding "sap_system" does not exist');
    ok((none { $_->{name} eq 'SDAF-OpenQA-workload_zone-4' } @$zone_ids), '"workload_zone" younger than retention time is not marked');

    undef_variables();
};

done_testing;
