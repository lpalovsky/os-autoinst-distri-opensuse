use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use POSIX qw(strftime);
use sles4sap::sap_deployment_automation_framework::subscription_cleanup;

subtest '[time_test] Mandatory args' => sub {
    dies_ok { time_test() } 'Croak with missing argument';
};

subtest '[time_test] Default retention (12H)' => sub {
    ok(time_test('1990-01-01T23:00:00+00:00'), 'Return "true" if time is outside of retention period');
    ok(!time_test(strftime("%Y-%m-%dT%H:%M:%S", localtime)),  'Return "true" if time is within retention period');
};

done_testing;
