package hana_sr_dummy;
use base 'sles4sap_publiccloud_basetest';
use main_common 'loadtest';
use strict;
use warnings FATAL => 'all';
use testapi;

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;
    $self->{instances} = $run_args->{instances};
    $self->{my_instance} = $run_args->{site_a};
    $self->select_serial_terminal;
    record_info("Dummy", "module for farts and giggles.");
    $self->setup_sbd_delay("30s");
}

1;
