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
use sles4sap_publiccloud;
use publiccloud::utils;
use qesapdeployment;
use Data::Dumper;
use Storable;


sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

=head3 qesap_get_variables

    Create a hash of variables and a list of required vars to replace in yaml config.
    Values are taken either from ones defined in openqa ("value") or ("default") values within this function.
    Openqa value takes precedence.
=cut
sub qesap_get_variables {
    my %variables;
    $variables{HANA_SAR} = get_required_var("HANA_SAR");
    $variables{REGION} = get_required_var("PUBLIC_CLOUD_REGION");
    $variables{HANA_CLIENT_SAR} = get_required_var("HANA_CLIENT_SAR");
    $variables{HANA_SAPCAR} = get_required_var("HANA_SAPCAR");
    $variables{SCC_REGCODE_SLES4SAP} = get_required_var("SCC_REGCODE_SLES4SAP");
    $variables{STORAGE_ACCOUNT_NAME} = get_var("STORAGE_ACCOUNT_NAME");
    $variables{STORAGE_ACCOUNT_KEY} = get_var("STORAGE_ACCOUNT_KEY");
    $variables{PUBLIC_CLOUD_OS_IMAGE} = get_var("PUBLIC_CLOUD_OS_IMAGE");
    $variables{PUBLIC_CLOUD_RESOURCE_NAME} = get_var("PUBLIC_CLOUD_RESOURCE_NAME");
    $variables{FENCING_MECHANISM} = get_var("FENCING_MECHANISM", "sbd");
    $variables{HANA_OS_MAJOR_VER} = (split("-", get_var("VERSION")))[0];

    return (%variables);
}

sub run {
    my ($self, $run_args) = @_;
    my %variables = qesap_get_variables();

    $self->select_serial_terminal;


    my $provider = $self->provider_factory();

    if (!get_var("HA_SAP_TERRAFORM_DEPLOYMENT")) {
        qesap_prepare_env(openqa_variables => \%variables, provider => lc(get_required_var('PUBLIC_CLOUD_PROVIDER')));
        # This tells "create_instances" to skip the deployment setup related to old ha-sap-terraform-deployment project
        $provider->{terraform_env_prepared} = 1;
    }

    my @instances = $provider->create_instances(check_connectivity => 0);
    my @instances_export;

    record_info("Teraform Instances:", Dumper(\@instances));

    foreach my $instance (@instances) {
        $self->{my_instance} = $instance;
        push(@instances_export, $instance);

    }

    $self->{instances} = $run_args->{instances} = \@instances_export;
    record_info("Deployment OK",);
    return 1;
}

1;
