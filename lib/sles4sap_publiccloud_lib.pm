# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Functions for SAP tests

use base 'publiccloud::basetest';
package sles4sap_publiccloud_lib;
use strict;
use warnings FATAL => 'all';
use testapi;
use Exporter 'import';
use Carp qw(croak);

our @EXPORT = qw(
  run_cmd
  get_promoted_hostname
);

=head2 run_cmd
    run_cmd(cmd => 'command', [runas => 'user', timeout => 60]);

Runs a command C<cmd> via ssh in the given VM and log the output.
All commands are executed through C<sudo>.
If 'runas' defined, command will be executed as specified user,
otherwise it will be executed as root.

=cut
sub run_cmd {
    my ($self, %args) = @_;
    croak('Argument <cmd> missing') unless ($args{cmd});
    my $timeout = bmwqemu::scale_timeout($args{timeout} // 60);
    my $title = $args{title} // $args{cmd};
    $title =~ s/[[:blank:]].+// unless defined $args{title};
    my $cmd = defined($args{runas}) ? "su - $args{runas} -c '$args{cmd}'" : "$args{cmd}";

    # Without cleaning up variables SSH commands get executed under wrong user
    delete($args{cmd});
    delete($args{title});
    delete($args{timeout});
    delete($args{runas});

    my $out = $self->{my_instance}->run_ssh_command(cmd => "sudo $cmd", timeout => $timeout, %args);
    record_info("$title output - $self->{my_instance}->{instance_id}", $out) unless ($timeout == 0 or $args{quiet} or $args{rc_only});
    return $out;
}

=head2 get_promoted_hostname()
    get_promoted_hostname();

Checks and returns hostname of HANA promoted node.
=cut
sub get_promoted_hostname {
    my ($self) = @_;
    my $resource_output = $self->run_cmd(cmd => "crm resource status msl_SAPHana_HDB_HDB00", quiet => 1);
    record_info("crm out", $resource_output);
    my @master = $resource_output =~ /:\s(\S+)\sMaster/g;
    if (scalar @master != 1) {
        diag("Master database not found or command returned abnormal output.\n
        Check 'crm resource status' command output below:\n");
        diag($resource_output);
        die("Master database was not found, check autoinst.log");
    }

    return join("", @master);
}

1;