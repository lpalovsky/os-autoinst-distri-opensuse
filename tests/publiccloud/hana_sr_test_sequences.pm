package hanasr_fencing;
use strict;
use warnings FATAL => 'all';
use Mojo::Base 'publiccloud::basetest';
use testapi;


sub run {
    my ($self) = @_;
    my $timeout = 120;
    my @cluster_types = split(',', get_required_var('CLUSTER_TYPES'));

    $self->select_serial_terminal;

    record_info('Dummy module')

}

1;