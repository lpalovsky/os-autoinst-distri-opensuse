# SUSE's openQA tests
#
# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Select given PACKAGES
#    You can pass
#    PACKAGES=quota-nfs,-samba,-grub2  packages starting with - will be removed
#    some package will block installation, conflict will be resolved passing
#    INSTALLATION_BLOCKED=grub2
#
# Maintainer: Sergio Lindo Mansilla <slindomansilla@suse.com>

use base 'opensusebasetest';
use strict;
use warnings;
use base "consoletest";
use testapi;
use serial_terminal 'select_serial_terminal';

sub run {
    my ($self) = @_;
    select_serial_terminal;
    sleep 600;
    record_info "manual tests";

}

sub test_flags {
    return {milestone => 1, fatal => 1};
}