# SUSE's openQA tests
#
# Copyright 2016-2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: crmsh
# Summary: Create filesystem and check content


package redirected_node;
use parent 'opensusebasetest';
use strict;
use warnings FATAL => 'all';
use serial_terminal qw(select_serial_terminal);
use testapi;
use lockapi;

sub run {
    my ($self) = @_;
    select_serial_terminal;
    

}

1;
