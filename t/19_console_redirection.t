use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use sles4sap::console_redirection;

our $serialdev = 'ttyS0';    # this is a global OpenQA variable

# make cleaning vars easier at the end of the unit test
sub unset_vars {
    my @variables = qw(REDIRECT_DESTINATION_IP REDIRECT_DESTINATION_USER BASE_VM_ID QEMUPORT
      AUTOINST_URL_HOSTNAME_ORIGINAL AUTOINST_URL_HOSTNAME REDIRECTION_CONFIGURED);
    set_var($_, undef) foreach @variables;
}

subtest '[connect_target_to_serial] Test exceptions' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    $redirect->redefine(enter_cmd => sub { return; });
    $redirect->redefine(handle_login_prompt => sub { return; });
    $redirect->redefine(record_info => sub { return; });
    $redirect->redefine(check_serial_redirection => sub { return 0; });

    set_var('BASE_VM_ID', '7902847fcc554911993686a1d5eca2c8');

    dies_ok { connect_target_to_serial(target_ip => '192.168.1.1') } 'Fail with missing ssh user';
    dies_ok { connect_target_to_serial(ssh_user => 'Totoro') } 'Fail with missing ip address';

    $redirect->redefine(check_serial_redirection => sub { return 1; });
    dies_ok { connect_target_to_serial(ssh_user => 'Totoro', target_ip => '192.168.1.1') }
    'Fail if function attempts redirect console second time';

    unset_vars();
    dies_ok { connect_target_to_serial(ssh_user => 'Totoro', target_ip => '192.168.1.1') }
    'Fail with "BASE_VM_ID" unset';
    dies_ok { connect_target_to_serial(ssh_user => 'Totoro', target_ip => 'Satsuki') }
    'Fail invalid IP';

    dies_ok { connect_target_to_serial(ssh_user => ' ', target_ip => '192.168.1.1') } 'Fail with user defined as empty space';
};

subtest '[connect_target_to_serial] Check command composition' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    my @ssh_cmd;
    my $redirection_status;
    $redirect->redefine(enter_cmd => sub { @ssh_cmd = @_; return 1; });
    # At this point Redirection is expected to work, therefore change $redirection_status to 1, so next check passed
    $redirect->redefine(handle_login_prompt => sub { $redirection_status = 1; return; });
    $redirect->redefine(record_info => sub { return; });
    $redirect->redefine(check_serial_redirection => sub { return $redirection_status; });
    $redirect->redefine(script_output => sub { return 'castleinthesky'; });
    set_var('BASE_VM_ID', '7902847fcc554911993686a1d5eca2c8');
    connect_target_to_serial(destination_ip => '192.168.1.1', ssh_user => 'Totoro');
    note('CMD:', join(' ', @ssh_cmd));
    ok(grep(/ssh/, @ssh_cmd), 'Execute main command');
    ok(grep(/-o StrictHostKeyChecking=no/, @ssh_cmd), 'Disable strict host key checking');
    ok(grep(/-o ServerAliveInterval=60/, @ssh_cmd), 'Set option: "ServerAliveInterval"');
    ok(grep(/-o ServerAliveCountMax=120/, @ssh_cmd), 'Set option: "ServerAliveCountMax"');
    ok(grep(/Totoro\@192.168.1.1/, @ssh_cmd), 'Host login');
    ok(grep(/2>&1 | tee -a \/dev\/ttyS0/, @ssh_cmd), 'Redirect output to serial device');
    unset_vars();
};

subtest '[connect_target_to_serial] Scenario: console already redirected' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    $redirect->redefine(enter_cmd => sub { die; });    # Unit test should not reach this part - redirection is already set
    $redirect->redefine(record_info => sub { return; });
    $redirect->redefine(check_serial_redirection => sub { return 1; });
    $redirect->redefine(script_output => sub { return 'Castle in the sky'; });
    set_var('BASE_VM_ID', '7902847fcc554911993686a1d5eca2c8');
    ok(connect_target_to_serial(destination_ip => '192.168.1.1', ssh_user => 'Totoro'), 'Skip if redirection already active');
    unset_vars();
};

subtest '[disconnect_target_from_serial]' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    my $wait_serial_done = 0;    # Flag that code entered while loop
    $redirect->redefine(record_info => sub { return 1; });
    $redirect->redefine(wait_serial => sub { $wait_serial_done = 1; return ':~'; });
    $redirect->redefine(enter_cmd => sub { return 1; });
    $redirect->redefine(check_serial_redirection => sub { return $wait_serial_done; });
    $redirect->redefine(set_serial_term_prompt => sub { return 1; });
    $redirect->redefine(script_output => sub { return ''; });

    ok disconnect_target_from_serial(base_vm_machine_id => '7902847fcc554911993686a1d5eca2c8'), 'Pass with machine ID defined by positional argument';

    set_var('BASE_VM_ID', '7902847fcc554911993686a1d5eca2c8');
    ok disconnect_target_from_serial(), 'Pass with machine ID defined by parameter BASE_VM_ID';
    unset_vars();

    dies_ok { disconnect_target_from_serial() } 'Fail without specifying machine ID and BASE_VM_ID undefined';
};

subtest '[check_serial_redirection]' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    $redirect->redefine(script_output => sub { return '7902847fcc554911993686a1d5eca2c8'; });
    $redirect->redefine(record_info => sub { return; });

    set_var('BASE_VM_ID', '7902847fcc554911993686a1d5eca2c8');
    is check_serial_redirection(), '0', 'Return 0 if machine IDs match';
    set_var('BASE_VM_ID', '999999999999999999999999');
    is check_serial_redirection(), '1', 'Return 1 if machine IDs do not match';

    unset_vars();

    is check_serial_redirection(base_vm_machine_id => '123456'), '1', 'Pass with specifying ID via positional argument';
    dies_ok { check_serial_redirection() } 'Fail with BASE_VM_ID being unset';
};

subtest '[redirection_init]' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    $redirect->redefine(assert_script_run => sub { return 1; });
    $redirect->redefine(script_run => sub { return 0; });
    $redirect->redefine(autoinst_url => sub { return 'https://codegurus.all/spicy_code/global_variables-only'; });
    $redirect->redefine(save_tmp_file => sub { return 0; });
    $redirect->redefine(connect_target_to_serial => sub { return 1; });
    $redirect->redefine(disconnect_target_from_serial => sub { return 1; });
    $redirect->redefine(remote_port_forward => sub { return 1; });
    $redirect->redefine(record_info => sub { return 1; });
    $redirect->redefine(script_output => sub { return '7902847fcc554911993686a1d5eca2c8' });
    set_var('QEMUPORT', '15685');

    ok(redirection_init(ssh_user => 'Totoro', destination_ip => '192.168.1.1'), 'Pass with correct usage');
    unset_vars();
};

subtest '[redirection_init] Test Exceptions' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    $redirect->redefine(script_run => sub { return 1; });
    $redirect->redefine(record_info => sub { return 1; });
    $redirect->redefine(script_output => sub { return '7902847fcc554911993686a1d5eca2c8' });

    dies_ok { redirection_init(ssh_user => 'Totoro') } 'Fail with destination IP undefined';
    dies_ok { redirection_init(destination_ip => '192.168.1.1') } 'Fail with SSH user undefined';
    dies_ok { redirection_init(ssh_user => 'Totoro', destination_ip => '192.168.1.1') } 'Fail with autossh package not being installed';


};

subtest '[remote_port_forward] Test via redirection_init()' => sub {
    my $redirect = Test::MockModule->new('sles4sap::console_redirection', no_auto => 1);
    my @assert_script_run;
    my $as_root;
    $redirect->redefine(assert_script_run => sub { @assert_script_run = @_ if grep /autossh/, $_[0]; return '1985'; });
    $redirect->redefine(script_run => sub { return 0; });
    $redirect->redefine(autoinst_url => sub { return 'https://codegurus.all/spicy_code/global_variables-only'; });
    $redirect->redefine(save_tmp_file => sub { return 0; });
    $redirect->redefine(connect_target_to_serial => sub { return 1; });
    $redirect->redefine(disconnect_target_from_serial => sub { return 1; });
    $redirect->redefine(record_info => sub { return 1; });
    $redirect->redefine(script_output => sub { return 'root' if grep(/whoami/, @_) and $as_root; return 'ghibli'; });

    set_var('REDIRECT_DESTINATION_IP', '192.168.1.5');
    set_var('REDIRECT_DESTINATION_USER', 'ghibli');
    set_var('QEMUPORT', '15685');

    redirection_init();
    note('CMD:', join(' ', @assert_script_run));
    ok(grep(/sudo/, @assert_script_run), 'Execute main command with sudo');
    ok(grep(/autossh/, @assert_script_run), 'Execute main command');
    ok(grep(/-f/, @assert_script_run), 'Run in background');
    ok(grep(/-N/, @assert_script_run), 'Do not execute any command');
    ok(grep(/-R 15686:10.0.2.2:15686/, @assert_script_run), 'Remote forwarding');
    ok(grep(/ghibli\@192.168.1.5/, @assert_script_run), 'Login host');

    $as_root = 1;
    redirection_init();
    note('CMD:', join(' ', @assert_script_run));
    ok(!grep(/sudo/, @assert_script_run), 'Execute command as root without sudo');
    unset_vars();
};

done_testing;
