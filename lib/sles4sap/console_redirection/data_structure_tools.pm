# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::data_structure_tools;
use strict;
use warnings;
use testapi;
use Carp qw(croak);
use Exporter qw(import);
use serial_terminal qw(select_serial_terminal);

=head1 SYNOPSIS

This library provides functions for manipulating data structures used in `tests/sles4sap/redirection_tests`. Usually to
make easier pulling out frequently used data sets like lists of databases, nw instances,...

=cut
