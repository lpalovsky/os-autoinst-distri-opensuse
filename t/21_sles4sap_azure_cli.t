use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::Mock::Time;

use List::Util qw(any none);
use sles4sap::azure_cli;

subtest '[az_group_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_group_create(name => 'Arlecchino', region => 'Pulcinella');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az group create/ } @calls), 'Correct composition of the main command');
    ok((any { /--location Pulcinella/ } @calls), '--location');
    ok((any { /--name Arlecchino/ } @calls), '--name');
};


subtest '[az_group_create] missing args' => sub {
    dies_ok { az_group_create(region => 'Pulcinella') } 'Die for missing argument name';
    dies_ok { az_group_create(name => 'Arlecchino') } 'Die for missing argument region';
    ok 1;
};


subtest '[az_network_vnet_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_vnet_create(
        resource_group => 'Arlecchino',
        region => 'Pulcinella',
        vnet => 'Pantalone',
        snet => 'Colombina');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network vnet create/ } @calls), 'Correct composition of the main command');
};


subtest '[az_network_nsg_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_nsg_create(
        resource_group => 'Arlecchino',
        name => 'Brighella');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network nsg create/ } @calls), 'Correct composition of the main command');
};


subtest '[az_network_nsg_rule_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_nsg_rule_create(
        resource_group => 'Arlecchino',
        nsg => 'Brighella',
        name => 'Pantalone',
        port => 22);
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network nsg rule create/ } @calls), 'Correct composition of the main command');
};


subtest '[az_network_publicip_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_publicip_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network public-ip create/ } @calls), 'Correct composition of the main command');
    ok((none { /allocation-method/ } @calls), 'No argument --allocation-method');
    ok((none { /zone/ } @calls), 'No argument --zone');
};


subtest '[az_network_publicip_create] with optional arguments' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_publicip_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        allocation_method => 'Static',
        zone => 'Venezia Mestre');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /--allocation-method Static/ } @calls), 'Argument --allocation-method');
    ok((any { /--zone Venezia Mestre/ } @calls), 'Argument --zone');
};


subtest '[az_network_lb_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_network_lb_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        vnet => 'Pantalone',
        snet => 'Colombina',
        backend => 'Smeraldina',
        frontend_ip => 'Momolo');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network lb create/ } @calls), 'Correct composition of the main command');
};


subtest '[az_vm_as_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_vm_as_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        region => 'Pulcinella');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm availability-set create/ } @calls), 'Correct composition of the main command');
};


subtest '[az_vm_create]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_vm_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        image => 'Mirandolina');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm create/ } @calls), 'Correct composition of the main command');
};

subtest '[az_vm_create] with public IP' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_vm_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        image => 'Mirandolina',
        public_ip => 'Fulgenzio');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /--public-ip-address Fulgenzio/ } @calls), 'custom Public IP address');
};

subtest '[az_vm_create] with no public IP' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_vm_create(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        image => 'Mirandolina',
        public_ip => '""');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /--public-ip-address ""/ } @calls), 'empty Public IP address');
};

subtest '[az_vm_openport]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    az_vm_openport(
        resource_group => 'Arlecchino',
        name => 'Truffaldino',
        port => 80);
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm open-port/ } @calls), 'Correct composition of the main command');
    ok((any { /--port 80/ } @calls), 'Correct port argument');
};

subtest '[az_nic_id_get]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(script_output => sub { push @calls, $_[0]; return 'Eugenia'; });
    my $res = az_nic_id_get(
        resource_group => 'Arlecchino',
        name => 'Truffaldino');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm show/ } @calls), 'Correct composition of the main command');
    ok(($res eq 'Eugenia'), 'Correct return');
};

subtest '[az_nic_name_get]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(script_output => sub { push @calls, $_[0]; return 'Eugenia'; });
    my $res = az_nic_name_get(
        nic_id => 'Fabrizio');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network nic show/ } @calls), 'Correct composition of the main command');
    ok((any { /--query.*name/ } @calls), 'Correct filter');
    ok(($res eq 'Eugenia'), 'Correct return');
};

subtest '[az_ipconfig_name_get]' => sub {
    my $qesap = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my @calls;
    $qesap->redefine(script_output => sub { push @calls, $_[0]; return 'Eugenia'; });
    my $res = az_ipconfig_name_get(
        nic_id => 'Fabrizio');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az network nic show/ } @calls), 'Correct composition of the main command');
    ok((any { /--query.*ipConfigurations.*name/ } @calls), 'Correct filter');
    ok(($res eq 'Eugenia'), 'Correct return');
};

subtest '[az_network_vnet_list]' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    my $cmd_out='LAB-SECE-SAP04_vnet_a
LAB-SECE-SAP04_vnet_b
LAB-SECE-SAP04_vnet_c';
    my @expected_result = ('LAB-SECE-SAP04_vnet_a', 'LAB-SECE-SAP04_vnet_b', 'LAB-SECE-SAP04_vnet_c');
    $mock->redefine(script_output => sub { $cmd = $_[0]; return $cmd_out; });

    dies_ok {az_network_vnet_list()} "Fail with missing argument: 'resource_group'";

    my $result = az_network_vnet_list(resource_group=>'Eugenia');
    is ref($result), 'ARRAY', 'Returned value must be ARRAY';
    is $cmd, "az network vnet list --resource-group Eugenia --query \"[].name\" -o tsv",
        "Pass with executed command: \n$cmd";
    is_deeply($result, \@expected_result, 'Return correct result');

    print('VNETS: ' . @{ az_network_vnet_list(resource_group => 'Eugenia') }[0]);
};

subtest '[az_network_vnet_subnet_list] Test exceptions' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    $mock->redefine(script_output => sub { return; });

    dies_ok {az_network_vnet_subnet_list(vnet_name=>'Eugenia')} "Fail with missing argument: 'resource_group'";
    dies_ok {az_network_vnet_subnet_list(resource_group=>'Elisa')} "Fail with missing argument: 'vnet_name'";
};

subtest '[az_network_vnet_subnet_list]' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    my $cmd_out='LAB-SECE-SAP04_admin-subnet
LAB-SECE-SAP04_app-subnet
LAB-SECE-SAP04_db-subnet';
    my @expected_result = (
        'LAB-SECE-SAP04_admin-subnet',
        'LAB-SECE-SAP04_app-subnet',
        'LAB-SECE-SAP04_db-subnet'
    );
    $mock->redefine(script_output => sub { $cmd = $_[0]; return $cmd_out; });

    my $result = az_network_vnet_subnet_list(vnet_name=>'Eugenia', resource_group=>'Elisa');
    is ref($result), 'ARRAY', 'Returned value must be ARRAY';
    is $cmd, "az network vnet subnet list --resource-group Elisa --vnet-name Eugenia --query \"[].name\" -o tsv",
        "Pass with executed command: \n$cmd";
    is_deeply($result, \@expected_result, 'Return correct result');
};

subtest '[az_network_nat_gateway_create] Test exceptions' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    $mock->redefine(assert_script_run => sub { $cmd = $_[0]; return 1; });
    my %mandatory_args = (
        resource_group => 'Elisa',
        gateway_name   => 'Eugenia',
        public_ip      => 'Fabrizio'
    );

    foreach (keys(%mandatory_args)) {
        my $original_value = $mandatory_args{$_};
        $mandatory_args{$_} = undef;
        dies_ok {az_network_nat_gateway_create(%mandatory_args)} "Fail with missing argument: '$_'";
        $mandatory_args{$_} = $original_value;
    }
};

subtest '[az_network_nat_gateway_create]' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    my $expected_cmd = 'az network nat gateway create --resource-group Elisa --name Eugenia --public-ip-addresses Fabrizio';
    $mock->redefine(assert_script_run => sub { $cmd = $_[0]; return 1; });
    my %mandatory_args = (
        resource_group => 'Elisa',
        gateway_name   => 'Eugenia',
        public_ip      => 'Fabrizio'
    );

    az_network_nat_gateway_create(%mandatory_args);
    is $cmd, $expected_cmd, "Execute correct command: '$cmd'";
};

subtest '[az_network_vnet_subnet_update] Test exceptions' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    $mock->redefine(assert_script_run => sub { $cmd = $_[0]; return 1; });
    my %mandatory_args = (
        resource_group => 'Elisa',
        gateway_name   => 'Eugenia',
        vnet_name      => 'Fabrizio',
        subnet_name    => 'Truffaldino'
    );

    foreach (keys(%mandatory_args)) {
        my $original_value = $mandatory_args{$_};
        $mandatory_args{$_} = undef;
        dies_ok {az_network_vnet_subnet_update(%mandatory_args)} "Fail with missing argument: '$_'";
        $mandatory_args{$_} = $original_value;
    }
};

subtest '[az_network_vnet_subnet_update]' => sub {
    my $mock = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    my $cmd;
    my $expected_cmd = 'az network vnet subnet update --resource-group Elisa --name Truffaldino --vnet-name Fabrizio --nat-gateway Eugenia';
    $mock->redefine(assert_script_run => sub { $cmd = $_[0]; return 1; });
    my %mandatory_args = (
        resource_group => 'Elisa',
        gateway_name   => 'Eugenia',
        vnet_name      => 'Fabrizio',
        subnet_name    => 'Truffaldino'
    );

    az_network_vnet_subnet_update(%mandatory_args);
    is $cmd, $expected_cmd, "Execute correct command: '$cmd'";
};

done_testing;
