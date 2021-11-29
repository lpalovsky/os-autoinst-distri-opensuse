package hana_sr_cleanup;
use strict;
use warnings FATAL => 'all';
use Mojo::Base 'publiccloud::basetest';
use testapi;

sub run {
    my ($self) = @_;
    my $provider = get_required_var('PROVIDER');
    my $instances = get_required_var('INSTANCES');
    record_info("Provider = $provider");
    record_info("Instances = $instances");
}

1;