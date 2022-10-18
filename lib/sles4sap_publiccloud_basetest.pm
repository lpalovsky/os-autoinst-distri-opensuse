package sles4sap_publiccloud_basetest;

use base 'publiccloud::basetest';
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use testapi;
use qesapdeployment;

our @EXPORT = qw(cleanup);

sub cleanup {
    my ($self) = @_;
    # Do not run destroy if already executed
    return if ($self->{cleanup_called});
    $self->{cleanup_called} = 1;
    my $inventory_check_cmd = join(" ", ("test", "-f", qesap_get_inventory()));
    if (script_run($inventory_check_cmd) == 0) {
        record_info("Ansible cleanup");
        my $ansible_cleanup_rc = qesap_execute(verbose => "--verbose", cmd => "ansible", cmd_options => "-d", timeout => 1200);
        record_soft_failure("Ansible destroy failed.") if $ansible_cleanup_rc != 0;
    }

    record_info("Cleaning up terraform infrastructure");
    my $terraform_cleanup_rc = qesap_execute(verbose => "--verbose", cmd => "terraform", cmd_options => "-d", timeout => 1200);
    record_soft_failure("Terraform destroy failed.") if $terraform_cleanup_rc != 0;
    record_info("Cleanup finished");
}

sub post_fail_hook {
    my ($self,) = @_;
    if (get_var("PUBLIC_CLOUD_NO_CLEANUP_ON_FAILURE")) {
        diag("Skip post fail", "Variable 'PUBLIC_CLOUD_NO_CLEANUP_ON_FAILURE' defined.");
        return;
    }
    $self->cleanup();
}

sub post_run_hook {
    my ($self) = @_;
    if ($self->test_flags()->{publiccloud_multi_module} or get_var("PUBLIC_CLOUD_NO_CLEANUP")) {
        diag("Skip post run", "Skipping post run hook. \n Variable 'PUBLIC_CLOUD_NO_CLEANUP' defined or test_flag 'publiccloud_multi_module' active");
        return;
    }
    $self->cleanup();
}

1;
