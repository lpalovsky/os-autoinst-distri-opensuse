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
use sles4sap_publiccloud_lib;
use Data::Dumper;
use Storable;


sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}


sub run {
    my ($self, $run_args) = @_;
    my $instances = $run_args->{instances};
    $self->select_serial_terminal;

    # Identify Site A (Master) and Site B
    foreach my $instance (@$instances) {
        $self->{my_instance} = $instance;
        my $instance_id = $instance->{'instance_id'};

        # Skip instances without HANA db
        next if ($instance_id !~ m/vmhana/);

        # Define initial state for both sites
        # Site A is always PROMOTED after deployment
        my $master_node = $self->get_promoted_hostname();
        $run_args->{site_a} = $instance if ($instance_id eq $master_node);
        $run_args->{site_b} = $instance if ($instance_id ne $master_node);
    }

    if ($run_args->{site_a}->{instance_id} eq "undef" || $run_args->{site_b}->{instance_id} eq "undef") {
        die("Failed to identify Hana nodes");
    }

    # Todo: improve naming for more than two nodes
    record_info("Instances:", "Detected HANA instances:
        Site A: $self->{site_a}->{instance_id}
        Site B: $self->{site_b}->{instance_id}");

    record_info("Deployment OK",);
    return 1;
}

1;
