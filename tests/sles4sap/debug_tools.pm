package debug_tools;
use parent haclusterbasetest;
use strict;
use warnings FATAL => 'all';
use testapi;
use serial_terminal qw(select_serial_terminal);
use Data::Dumper;

sub run {
    my ($self) = @_;
    select_serial_terminal;
    my $script_path = '/root/upload.sh';
    my $curl_cmd = join(' ',
        'curl --form upload=@$1 ',
        autoinst_url('/uploadlog/$2'));
    record_info('curl command', $curl_cmd);
    assert_script_run( "echo '$curl_cmd' > $script_path");
    assert_script_run("chmod +x $script_path");
}

1;