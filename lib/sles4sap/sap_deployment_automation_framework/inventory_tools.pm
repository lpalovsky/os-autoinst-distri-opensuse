# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::sap_deployment_automation_framework::inventory_tools;

use warnings;
use strict;
use YAML::PP;
use testapi;
use Exporter qw(import);
use Carp qw(croak);
use sles4sap::sap_deployment_automation_framework::naming_conventions qw(convert_region_to_short);
use publiccloud::instance;


=head1 SYNOPSIS

Library contains functions that handle SDAF inventory file.

=cut

our @EXPORT = qw(
  instance_data_from_inventory
  read_inventory_file
);

=head2 read_inventory_file

    read_inventory_file($sap_inventory_file_path);

Returns full path to an existing ansible inventory file

=over

=item * B<inventory_file_path> Full file path pointing to SDAF inventory file

=back
=cut

sub read_inventory_file {
    my ($inventory_file_path) = @_;
    my $ypp = YAML::PP->new;
    my $raw_file = script_output("cat $inventory_file_path");
    my $yaml_data = $ypp->load_string($raw_file);
    return $yaml_data;
}

=head2 instance_data_from_inventory

    instance_data_from_inventory(convert_region_to_short=>'SECE', provider_data=>'',
    sut_ssh_key_path=>'/home/.ssh/id_rsa' [, inventory_content=>'']);

Creates and returns  B<$instances> class which is a main component of F<lib/sles4sap_publiccloud.pm> and
general public cloud libraries F</lib/publiccloud/*>.

=over

=item * B<region_code>: Public cloud region code

=item * B<provider_data>: Provider data obtained from calling B<provider_factory()>

=item * B<sut_ssh_key_path>: Full path to private key for accessing SUT.

=item * B<inventory_content> Referenced content of the inventory yaml file

=back
=cut

sub instance_data_from_inventory {
    my (%args) = @_;
    croak('Missing mandatory argument "$args{provider_data}" ') unless $args{provider_data};
    croak('Missing mandatory argument "$args{sut_ssh_key_path}" ') unless $args{sut_ssh_key_path};
    $args{region_code} //= get_required_var('PUBLIC_CLOUD_REGION');

    my @instances = ();

    for my $instance_type (keys(%{$args{inventory_content}})) {
        my $hosts = $args{inventory_content}->{$instance_type}{hosts};
        for my $physical_host (keys %$hosts) {
            my $instance = publiccloud::instance->new(
                public_ip => $hosts->{$physical_host}->{ansible_host},
                instance_id => $physical_host,
                username => $hosts->{$physical_host}->{ansible_user},
                ssh_key => $args{sut_ssh_key_path},
                provider => $args{provider_data},
                region => $args{region_code}
            );
            push(@instances, $instance);
            #record_info('Instance', Dumper($instance));
        }
    }
    publiccloud::instances::set_instances(@instances);
    return \@instances;
}
