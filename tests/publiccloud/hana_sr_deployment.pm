# SUSE's openQA tests
#
# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: pacemaker-cli crmsh csync2
# Summary: Test public cloud SLES4SAP images
#
# Maintainer: Loic Devulder <ldevulder@suse.de>

use Mojo::Base 'publiccloud::basetest';
use testapi;
use Mojo::File 'path';
use Mojo::JSON;
use version_utils 'is_sle';
use publiccloud::utils;

=head2 upload_ha_sap_logs

    upload_ha_sap_logs($instance):

Upload the HA/SAP logs from instance C<$instance> on the Webui.
=cut
sub upload_ha_sap_logs {
    my ($self, $instance) = @_;
    my @logfiles = qw(salt-deployment.log salt-os-setup.log salt-pre-deployment.log salt-result.log);

    # Upload logs from public cloud VM
    $instance->run_ssh_command(cmd => 'sudo chmod o+r /var/log/salt-*');
    foreach my $file (@logfiles) {
        $instance->upload_log("/var/log/$file", log_name => "$instance->{instance_id}-$file");
    }
}

sub run{
    my ($self) = @_;
    my $timeout = 120;
    my @cluster_types = split(',', get_required_var('CLUSTER_TYPES'));

    $self->select_serial_terminal;

    my $provider = $self->provider_factory();
    record_info("provider = $provider");
    record_info("RG = "get_var("RESOURCE_GROUP"));
}

1;