# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Registration SUT
# Maintainer: QE-SAP <qe-sap@suse.de>

=head1 NAME

ipaddr2/registration.pm - Perform SUT registration for the ipaddr2 test

=head1 DESCRIPTION

This module handles the registration of the SUT (System Under Test) VMs
for the ipaddr2 test.
Its behavior depends on whether cloud-init was used for the initial setup.

If cloud-init is disabled (B<IPADDR2_CLOUDINIT> is 0), this module will:
- Check the registration status
- If the image is Not Registered: register the two SUT VMs
  with the SUSE Customer Center (SCC) using the provided registration code.
- Register any specified add-on products.

After registration (or if cloud-init was enabled), it refreshes the software repositories
for both SUT VMs and lists them for logging purposes.

=head1 VARIABLES

=over 4

=item B<IPADDR2_CLOUDINIT>

Controls whether this module performs the registration. Defaults to enabled (1) in the overall test flow.
If set to 0, this module handles the full registration process.
If enabled (not 0), this module skips the registration steps and only refreshes the repositories,
assuming registration was handled by cloud-init during deployment.

=item B<SCC_REGCODE_SLES4SAP>

SUSE Customer Center registration code for SLES for SAP.
Required if B<IPADDR2_CLOUDINIT> is set to 0 and the OS image is a BYOS (Bring Your Own Subscription) type.

=item B<SCC_ADDONS>

A comma-separated list of SUSE Customer Center addons to register.
Each selected addon will require its own registration code in a dedicated variable.
This is used only when B<IPADDR2_CLOUDINIT> is set to 0.

=back

=head1 MAINTAINER

QE-SAP <qe-sap@suse.de>

=cut

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use serial_terminal qw( select_serial_terminal );
use publiccloud::utils;
use sles4sap::ipaddr2 qw(
  ipaddr2_deployment_logs
  ipaddr2_cloudinit_logs
  ipaddr2_infra_destroy
  ipaddr2_scc_addons
  ipaddr2_scc_check
  ipaddr2_scc_register
  ipaddr2_refresh_repo
  ipaddr2_ssh_internal
  ipaddr2_bastion_pubip
);

sub run {
    my ($self) = @_;

    select_serial_terminal;

    my $bastion_ip = ipaddr2_bastion_pubip();

    # Check if cloudinit is active or not. In case it is,
    # registration was eventually performed by the cloudinit script
    # and no need to be performed here.
    if (check_var('IPADDR2_CLOUDINIT', 0)) {
        # Check if reg code is provided or not, PAYG does not need it
        if (get_var('SCC_REGCODE_SLES4SAP')) {
            foreach (1 .. 2) {
                # Check if somehow the image is already registered or not
                my $is_registered = ipaddr2_scc_check(
                    bastion_ip => $bastion_ip,
                    id => $_);
                record_info('is_registered', "$is_registered");
                # Conditionally register the SLES for SAP instance.
                # Registration is attempted only if the instance is not currently registered and a
                # registration code ('SCC_REGCODE_SLES4SAP') is available.
                ipaddr2_scc_register(
                    bastion_ip => $bastion_ip,
                    id => $_,
                    scc_code => get_required_var('SCC_REGCODE_SLES4SAP')) if ($is_registered ne 1);
            }
        }
        # Optionally register addons
        ipaddr2_scc_addons(
            bastion_ip => $bastion_ip,
            scc_addons => get_required_var('SCC_ADDONS')
        ) if (get_var('SCC_ADDONS'));
    }

    foreach my $id (1 .. 2) {
        # refresh repo
        ipaddr2_refresh_repo(id => $id, bastion_ip => $bastion_ip);

        # record repo lr
        ipaddr2_ssh_internal(id => $id,
            cmd => "sudo zypper lr",
            bastion_ip => $bastion_ip);
        # record repo ls
        ipaddr2_ssh_internal(id => $id,
            cmd => "sudo zypper ls",
            bastion_ip => $bastion_ip);
    }
}

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub post_fail_hook {
    my ($self) = shift;
    ipaddr2_deployment_logs() if check_var('IPADDR2_DIAGNOSTIC', 1);
    ipaddr2_cloudinit_logs() unless check_var('IPADDR2_CLOUDINIT', 0);
    ipaddr2_infra_destroy();
    $self->SUPER::post_fail_hook;
}

1;
