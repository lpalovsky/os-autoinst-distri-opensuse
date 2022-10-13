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



sub run {
    my ($self) = @_;

    $self->select_serial_terminal;

    # Allows to use previous ha-sap-terraform-deployment
    if (!get_var("HA_SAP_TERRAFORM_DEPLOYMENT")) {
        die if qesap_execute(cmd => 'ansible', timeout => 3600) != 0;
    }

    record_info("Deployment OK",);
    return 1;
}

1;
