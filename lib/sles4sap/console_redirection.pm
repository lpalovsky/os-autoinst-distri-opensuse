# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::console_redirection;
use strict;
use warnings;
use testapi;
use Carp qw(croak);
use Exporter qw(import);
use serial_terminal qw(select_serial_terminal);
use Regexp::Common qw(net);

=head1 SYNOPSIS

Library that enables console redirection and file transfers from worker based VM to another host.
Can be used for cases where worker VM is not the target host for API calls and command execution, but serves only as a jumphost.

=cut

our @EXPORT = qw(
  connect_target_to_serial
  disconnect_target_from_serial
  redirection_init
  check_serial_redirection
);

my $ssh_opt = '-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=120';

=head2 handle_login_prompt

    handle_login_prompt();

B<ssh_user> Login user
Detects if login prompt appears and types the password.
In case of ssh keys being in place and command prompt appears, the fucntion does not type anything.

=cut

sub handle_login_prompt {
    my $pwd = get_var('_SECRET_SUT_PASSWORD', $testapi::password);
    set_serial_term_prompt();
    my $serial_response = wait_serial(qr/Password:\s*$|:~/i);    # look for either password prompt or command prompt to appear

    if (grep /Password:\s*$/, $serial_response) {    # Handle password prompt if it appears
        type_password $pwd;
        send_key 'ret';
    }

    wait_serial((qr/:~|#|>/i), timeout=>20);
}

=head2 redirection_init

    redirection_init();

Do preparation before redirecting console. Gets base VM id and initial setup.
This is required to be done only once at the beginning of the whole test.
If you have a multiumachine setup, execute this on each worker VM.

=cut

sub redirection_init {
    # This should get worker VM id before any redirection happening
    # ID serves as identification of the 'base' VM to return to.
    set_var('WORKER_VM_ID', script_output 'cat /etc/machine-id');
}

=head2 set_serial_term_prompt

    set_serial_term_prompt();

Detects if login prompt appears and types the password.

=cut

sub set_serial_term_prompt {
    $testapi::distri->{serial_term_prompt} = '';    # reset previous prompt first
    my $current_user = script_output('whoami');
    croak 'SSH user not defined and/or "whoami" script failed.' unless defined($current_user);
    $testapi::distri->{serial_term_prompt} = ($current_user eq 'root' ? '# ' : '> ');
}

=head2 connect_target_to_serial

    connect_target_to_serial([ssh_user=>ssh_user, target_ip=>$target_ip]);

B<ssh_user> Login user - default value is defined by OpenQA parameter REDIRECT_TARGET_USER
B<target_ip> Target host IP - default value is defined by OpenQA parameter REDIRECT_TARGET_IP

Establishes ssh connection to target and redirects serial output to serial concole on worker VM.
This allows OpenQA access to command return codes and output for evaulation by standard API call.

=cut

sub connect_target_to_serial {
    my (%args) = @_;
    my $redirect_ip = $args{'target_ip'} // get_required_var('REDIRECT_TARGET_IP');
    my $ssh_user = $args{'ssh_user'} // get_required_var('REDIRECT_TARGET_USER');

    croak 'Missing "ssh_user" argument' unless $ssh_user;
    croak 'Missing "redirect_ip" argument' unless $redirect_ip;
    croak "OpenQA variable WORKER_VM_ID undefined. Run 'redirection_init()' first" unless get_var('WORKER_VM_ID');
    croak "IP address '$redirect_ip' is not valid." unless grep(/^$RE{net}{IPv4}$/, $redirect_ip);
    croak 'Global variable "$searialdev" undefined' unless $serialdev;
    croak "Console is already redirected to:" . script_output('hostname') if check_serial_redirection();

    enter_cmd "ssh $ssh_opt $ssh_user\@$redirect_ip 2>&1 | tee -a /dev/$serialdev";
    handle_login_prompt($ssh_user);
    record_info('Redirect ON', "Serial redirection established to: $redirect_ip");
}

=head2 disconnect_target_from_serial

    disconnect_target_from_serial([worker_machine_id=$worker_machine_id]);

B<worker_machine_id> Target host IP - default value is defined by OpenQA parameter WORKER_VM_ID from redirect_init()

Disconnects target from serial console by typing 'exit' command until host machine ID matches ID of the worker VM.

=cut

sub disconnect_target_from_serial {
    my (%args) = @_;
    my $worker_machine_id = $args{worker_machine_id} // get_required_var('WORKER_VM_ID');
    set_serial_term_prompt();
    my $serial_redirection_status = check_serial_redirection(worker_machine_id => $worker_machine_id);
    while ($serial_redirection_status ne 0) {
        enter_cmd('exit');    # Enter command and wait for screen start changing
        $testapi::distri->{serial_term_prompt} = '';    # reset console prompt
        wait_serial(qr/Connection.*closed./, timeout => 10);    # Wait for connection to close
        wait_serial(qr/# |> /, timeout => 10);    # Wait for console prompt to appear
        set_serial_term_prompt();    # after logout user might change and prompt with it.
        $serial_redirection_status = check_serial_redirection($worker_machine_id);
    }
    record_info('Redirect OFF', "Serial redirection closed. Console set to: " . script_output('hostname'));
}

=head2 check_serial_redirection

    check_serial_redirection([worker_machine_id=$worker_machine_id]);

B<worker_machine_id> Target host IP - default value is defined by OpenQA parameter WORKER_VM_ID from redirect_init()

Compares current machine-id to the worker VM ID either defined by WORKER_VM_ID variable or positional argument.
Machine ID is used instead of IP addr since cloud VM IP might not be visible from the inside (for example via 'ip a')

=cut

sub check_serial_redirection {
    my (%args) = @_;
    my $expected_machine_id = $args{worker_machine_id} // get_required_var('WORKER_VM_ID');
    my $current_id = script_output 'cat /etc/machine-id';

    my $redirection_status = $current_id eq $expected_machine_id ? 0 : 1;
    record_info('Redir check', 'Console redirection is not active') unless $redirection_status;
    record_info('Redir check', "Console is redirected to: " . script_output('hostname')) if $redirection_status;
    return $redirection_status;
}

1;
