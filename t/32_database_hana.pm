use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use sles4sap::database_hana;

subtest '[is_registration_automatic] ' => sub {
    my $db_hana = Test::MockModule->new('sles4sap::database_hana', no_auto => 1);
    $db_hana->redefine(script_run => sub { return 0; });

    is is_registration_automatic(), 1, 'Detect parameter being active';
    $db_hana->redefine(script_run => sub { return 1; });
    is is_registration_automatic(), 0, 'Detect parameter being inactive';
};

subtest '[hdb_stop] HDB command compilation' => sub {
    my $db_hana = Test::MockModule->new('sles4sap::database_hana', no_auto => 1);
    my @calls;
    $db_hana->redefine(assert_script_run => sub { @calls = $_[0]; return 0; });
    $db_hana->redefine(script_output => sub { return 'Dumbledore'; });
    $db_hana->redefine(sapcontrol_process_check => sub { return 0; });
    $db_hana->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    hdb_stop(instance_id => '00', switch_user => 'Albus');
    ok((grep /HDB/, @calls), 'Execute HDB command');
    ok((grep /stop/, @calls), 'Use "stop" function');
    ok((grep /sudo su \- Albus/, @calls), 'Run as another user');
};

subtest '[hdb_stop] Sapcontrol arguments' => sub {
    my $db_hana = Test::MockModule->new('sles4sap::database_hana', no_auto => 1);
    my @sapcontrol_args;
    $db_hana->redefine(assert_script_run => sub { return 0; });
    $db_hana->redefine(script_output => sub { return 'Dumbledore'; });
    $db_hana->redefine(sapcontrol_process_check => sub { @sapcontrol_args = @_; return 0; });
    $db_hana->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    hdb_stop(instance_id => 'Albus');
    ok((grep /instance_id/, @sapcontrol_args), 'Madatory arg "instance_id"');
    ok((grep /expected_state/, @sapcontrol_args), 'Define expected state');
    ok((grep /wait_for_state/, @sapcontrol_args), 'Wait until processes are in correct state');
};

subtest '[wait_for_takeover]' => sub {
    my $db_hana = Test::MockModule->new('sles4sap::database_hana', no_auto => 1);

};

done_testing;
