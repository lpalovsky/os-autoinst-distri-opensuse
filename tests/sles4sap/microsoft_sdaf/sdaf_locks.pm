use parent 'opensusebasetest';
use strict;
use warnings;
use testapi;
use lockapi;
use mmapi;

sub run {
    barrier_create('SDAF_DEPLOYMENT')
}

1;