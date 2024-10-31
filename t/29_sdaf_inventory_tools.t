use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use sles4sap::sap_deployment_automation_framework::inventory_tools;
use Data::Dumper;


subtest '[instance_data_from_inventory] ' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::inventory_tools', no_auto => 1);
    $ms_sdaf->redefine(record_info => sub { return; });
    my $expected_result = [
        {
            'public_ip' => '10.10.10.3',
            'provider' => 'provider data',
            'username' => 'azureadm',
            'instance_id' => 'qesdhdb02l107',
            'region' => 'swedencentral',
            'ssh_key' => '/the/path/towards/happiness/and/sshkey'
        },
    ];

    my $inventory_data = {
        'QES_DB' => {
            'vars' => undef,
            'hosts' => {
                'qesdhdb02l107' => {
                    'ansible_connection' => 'ssh',
                    'connection_type' => 'key',
                    'virtual_host' => 'qesdhdb02l107',
                    'ansible_user' => 'azureadm',
                    'vm_name' => 'LAB-SECE-SAP04-QES_qesdhdb02l1073',
                    'become_user' => 'root',
                    'ansible_host' => '10.10.10.3',
                    'os_type' => 'linux'
                }
            }
        }
    };

    set_var('PUBLIC_CLOUD_REGION', 'swedencentral');

    my $result = instance_data_from_inventory(
        provider_data => 'provider data',
        sut_ssh_key_path => '/the/path/towards/happiness/and/sshkey',
        inventory_content => $inventory_data
    );

    print(Dumper($result));
};


done_testing;
