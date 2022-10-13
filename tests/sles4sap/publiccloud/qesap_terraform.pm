# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Deploy SAP Hana cluster with system replication and verify working cluster.

use base 'sles4sap_publiccloud_basetest';
use strict;
use warnings;
use testapi;
use Mojo::File 'path';
use publiccloud::utils;
use qesapdeployment;
use Data::Dumper;
use Storable;


sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;
    $self->select_serial_terminal;
    my $provider = $self->provider_factory();

    set_var("SLE_IMAGE" ,$provider->get_image_id());
    qesap_prepare_env(openqa_variables=>qesap_get_variables(), provider => lc(get_required_var('PUBLIC_CLOUD_PROVIDER')));

    # This tells "create_instances" to skip the deployment setup related to old ha-sap-terraform-deployment project
    $provider->{terraform_env_prepared} = 1;
    my @instances = $provider->create_instances(check_connectivity => 0);
    my @instances_export;

    foreach my $instance (@instances) {
        $self->{my_instance} = $instance;
        push(@instances_export, $instance);
        $instance->wait_for_ssh();
        $instance->ssh_script_run('hostnamectl hostname');
    }

    $self->{instances} = $run_args->{instances} = \@instances_export;
    record_info("Deployment OK",);
    return 1;
}

1;
