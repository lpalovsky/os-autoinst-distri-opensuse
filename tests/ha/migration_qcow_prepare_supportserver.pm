# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Additional task to release IP addresses from supportserver
# Maintainer: QE-SAP <qe-sap@suse.de>

use strict;
use warnings;
use base 'basetest';
use lockapi;
use testapi;

sub run {
    my @config_paths = ("/var/lib/dhcp/dhcpd.leases", "/var/lib/dhcp/db/dhcpd.leases");
    for (@config_paths) {
        my $file_exists = script_run("test $_");
        # Beware that value of "$file_exists" is RC, eg. RC1 = file does not exist
        record_info("File check", "File $_ exists and will be deleted.") unless $file_exists;
        script_run("rm $_") unless $file_exists;
    }
}

1;
