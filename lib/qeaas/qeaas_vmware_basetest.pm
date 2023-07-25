# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Basetest for 'govc' tool based deployment on vmware.

package qeaas::qeaas_vmware_basetest;
use Mojo::Base 'consoletest';

use strict;
use warnings;
use testapi;
use qeaas::vmware_govc;

sub cleanup_infrastructure {
    my $node_count = get_required_var('QEAAS_VM_COUNT');

    for my $vm_index (1 .. $node_count) {
        my $vm_params = get_required_var("QEAAS_VM$vm_index");
        my $vm_name = delimit_string_into_hash($vm_params)->{'vm_name'};
        record_info('VM destroy', "'Destroying VM: $vm_name'");
        govc_vm_destroy($vm_name, quiet => '1');
    }
}

sub post_fail_hook {
    record_info('CLEANUP', 'Post fail cleanup.');
    cleanup_infrastructure();
    return;
}

sub post_run_hook {
    my ($self) = @_;
    record_info('CLEANUP', 'Post run cleanup.') unless $self->test_flags()->{multi_module};
    cleanup_infrastructure() unless $self->test_flags()->{multi_module};
    return;
}

1;
