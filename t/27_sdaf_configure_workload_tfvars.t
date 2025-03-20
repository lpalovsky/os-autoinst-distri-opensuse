use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use sles4sap::sap_deployment_automation_framework::configure_workload_tfvars;

subtest '[validate_components]' => sub {
    ok validate_components(components => ['db_install']), "Pass with 'db_install' argument";
    ok validate_components(components => ['db_ha']), "Pass with 'db_ha' argument";
    ok validate_components(components => ['nw_pas']), "Pass with 'nw_pas' argument";
    ok validate_components(components => ['nw_aas']), "Pass with 'nw_aas' argument";
    ok validate_components(components => ['nw_ensa']), "Pass with 'nw_ensa' argument";
};

subtest '[validate_components] Exceptions' => sub {
    my @incorrect_values = ('db', 'pas', 'nw', 'ensa', 'aas', 'ha');

    foreach (@incorrect_values) {
        dies_ok { validate_components(components => [$_]) } "Fail with unsupported value: '$_'";
    }
};

subtest '[create_workload_tfvars] Test exceptions' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::configure_workload_tfvars', no_auto => 1);
    $ms_sdaf->redefine(get_os_variable => sub { return 'espresso'; });
    $ms_sdaf->redefine(find_deployment_id => sub { return 'lungo'; });
    my %arguments = (environment => 'LAB',
        location => 'swedencentral',
        job_id => '42',
        network_data => 'americano',
        workload_vnet_code => 'jelly_bean'
    );

    for my $arg (keys(%arguments)) {
        my $original = $arguments{$arg};
        $arguments{$arg} = undef;
        $ms_sdaf->redefine(find_deployment_id => sub { return undef; }) if $arg eq 'job_id';
        dies_ok { create_workload_tfvars(%arguments); } "Croak with missing mandatory argument '$arg'";
        $ms_sdaf->redefine(find_deployment_id => sub { return 'lungo'; });
        $arguments{$arg} = $original;
    }
};

subtest '[env_definitions]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::configure_workload_tfvars', no_auto => 1);
    my $tfvars_file;
    $ms_sdaf->redefine(get_os_variable => sub { return 'espresso'; });
    $ms_sdaf->redefine(find_deployment_id => sub { return 'lungo'; });
    $ms_sdaf->redefine(write_sut_file => sub { $tfvars_file = $_[1]; return; });
    my %network_data = (
        network_address_space => '192.168.1.0/26',
        db_subnet_address_prefix => '192.168.1.0/28',
        web_subnet_address_prefix => '192.168.1.56/29',
        admin_subnet_address_prefix => '192.168.1.48/29',
        iscsi_subnet_address_prefix => '192.168.1.32/28',
        app_subnet_address_prefix => '192.168.1.16/28'
    );
    my %arguments = (environment => 'LAB',
        location => 'swedencentral',
        job_id => '42',
        workload_vnet_code => 'jelly_bean',
        network_data => \%network_data);

    create_workload_tfvars(%arguments);
    note("\nTfvars file:\n$tfvars_file");
};

done_testing;

