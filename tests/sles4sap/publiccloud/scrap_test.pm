use strict;
use warnings;
use testapi;
use utils;
use hacluster;
use serial_terminal 'prepare_serial_console';
use bootloader_setup qw(change_grub_config grub_mkconfig);
use Data::Dumper;

use base 'consoletest';

sub script_output_retry_check {
    my %args = @_;
    my $cmd = $args{cmd} // die('No command specified.');
    my $regex = $args{regex_string} // die('Regex input missing');
    my $retry = $args{retry} // 5;
    my $sleep = $args{sleep} // 10;
    my $ignore_failure = $args{ignore_failure} // "0";
    my $result;

    foreach (1..$retry){
        $result = script_output($cmd);
        return $result if $result =~ /$regex/;
        sleep $sleep;
        next;
    }
    record_info('Script out', "Script output did not match pattern '$regex' after $retry retries.\nOutput: $result");
    die('Pattern did not match') unless $ignore_failure;
    return $result;
}

sub run{
    my ($self) = @_;
    select_console 'root-console';
    ensure_serialdev_permissions;
    prepare_serial_console;

    assert_script_run('dmesg -E');
    assert_script_run('dmesg -n debug');
    my $msg = "echo 'Random kernel message' >> /dev/kmsg;";

    
    my %params = (
        #'corosync_token' => validate_script_output_retry($corosync_token),
        #'corosync_consensus' => validate_script_output_retry($corosync_consensus),
        'sbd_watchdog_timeout' => validate_script_output_retry($sbd_watchdog_timeout, sub {m/^\d+$/}, delay=>1, retry=>2),
        'sbd_delay_start' => validate_script_output_retry($sbd_delay_start, sub { m/^\d+$|yes|no/ }, delay=>1, retry=>2)
        #'pcmk_delay_max' => get_var('USE_DISKLESS_SBD') ? 30 :
        #  validate_script_output_retry($pcmk_delay_max)
    );
    upload_logs('/etc/sysconfig/sbd');
    record_info('SBD Params', Dumper(\%params));
}

1;