# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Test initializes console redirection to cloud Deployer VM.

# Required OpenQA variables:
#     'SDAF_ENV_CODE'  Code for SDAF deployment env.
#     'SDAF_WORKLOAD_VNET_CODE' Virtual network code for workload zone.
#     'PUBLIC_CLOUD_REGION' SDAF internal code for azure region.
#     'SAP_SID' SAP system ID.

use parent 'sles4sap_publiccloud_basetest';
use strict;
use warnings;
use testapi;
use serial_terminal qw(select_serial_terminal);
use sles4sap::sdaf_deployment_library;
use sles4sap::sdaf_sles4sap_publiccloud_bridge;
use sles4sap::console_redirection;
use sles4sap_publiccloud;
use Data::Dumper;

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

# Test uses OpenQA variables as default values for various library functions.
# Fail asap if those variables are missing.
sub check_required_vars {
    my @variables = qw(
      SDAF_ENV_CODE
      SDAF_WORKLOAD_VNET_CODE
      PUBLIC_CLOUD_REGION
      SAP_SID
    );
    get_required_var($_) foreach @variables;
}

sub run {
    my ($self, $run_args) = @_;
    # QESAP cleanup must not run!
    set_var('QESAP_NO_CLEANUP', '1');
    set_var('QESAP_NO_CLEANUP_ON_FAILURE', '1');
    select_serial_terminal();

    my $deployment_id = find_deployment_id();
    my $env_variables = env_variable_file(job_id=>$deployment_id);

    connect_target_to_serial();
    load_os_env_variables(env_variable_file=>$env_variables);

    my $provider = $self->provider_factory();
    my $instances = instance_data_from_inventory(provider=>$provider);

    record_info('$self', Dumper($self));
    record_info('$run_args', Dumper($run_args));

    my $site_letter = 'a';
    for my $instance (@$instances) {
        $self->{my_instance} = $instance;
        $self->run_cmd(cmd=>'hostname', runas=>'azureadm', quiet=>1);
        $run_args->{"site_$site_letter"} = $instance;
        record_info('SITE', "site_$site_letter");
        $site_letter ++;
    }

    $self->{instances} = $run_args->{instances} = $instances;
    $self->{provider} = $run_args->{my_provider} = $provider;

    disconnect_target_from_serial();

    # Get ssh keys from SUT and setup SSH proxy jump
    # This will allow direct ssh login from worker WM to SUT via jumphost
    ssh_config_add_instances(instances=>$instances, jump_host=>sdaf_get_deployer_ip());
    record_info('ssh conf', script_output("cat ~/.ssh/config"));
}

1;