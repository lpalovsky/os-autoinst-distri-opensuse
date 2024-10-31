# SUSE's openQA tests
#
# Copyright SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

use parent 'opensusebasetest';
use strict;
use warnings;
use testapi;
use utils;
use YAML::PP qw(Load);
use Mojo::URL;
use Mojo::File qw(path);
use sles4sap::console_redirection;
use serial_terminal qw(select_serial_terminal);

sub run {

    set_var('REDIRECT_DESTINATION_IP', get_required_var('TARGET_SUT_IP'));
    set_var('REDIRECT_DESTINATION_USER', get_required_var('SUT_USER'));

    select_serial_terminal();
    connect_target_to_serial();



    disconnect_target_from_serial();
}
