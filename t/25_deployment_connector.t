use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use testapi;
use Data::Dumper;
use Scalar::Util qw(reftype);
use sles4sap::sap_deployment_automation_framework::deployment_connector;

sub undef_variables {
    my @openqa_variables = qw(
        SAP_SID
        SDAF_ENV_CODE
        SDAF_WORKLOAD_VNET_CODE
        PUBLIC_CLOUD_REGION
    );
    set_var($_, '') foreach @openqa_variables;
}

subtest '[get_deployment_vm] Test expected failures' => sub {
    my $mock_func = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
    $mock_func->redefine( script_output => sub { return '
[
  "0079-Zaku_II",
  "0079-MSM-07"
]
'; });

    dies_ok { get_deployment_vm(deployer_resource_group=>'Char') } 'Croak with missing mandatory arg: deployment_id';
    dies_ok {get_deployment_vm(deployer_resource_group=>'Char', deployment_id=>'0079')} 'Die with multiple VMs tagged with same ID';
};

subtest '[get_deployment_vm] Check command composition' => sub {
    my $mock_func = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
    my @calls;
    $mock_func->redefine( script_output => sub { push(@calls, @_); return '[
  "0079-Zaku_II"
]'
    });

    my $result = get_deployment_vm(deployer_resource_group=>'Char', deployment_id=>'0079');
    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((grep /az vm list/, @calls), 'Check main az command');
    ok((grep /--resource-group Char/, @calls), 'Check --resource-group argument');
    ok((grep /--query "\[\?tags.deployment_id == '0079'].name"/, @calls), 'Check --query argument');
    ok((grep /--output json/, @calls), 'Output must be in json format');
    is $result, '0079-Zaku_II', 'Return VM name';

    $mock_func->redefine( script_output => sub { push(@calls, @_); return '[]'});
    is get_deployment_vm(deployer_resource_group=>'Char', deployment_id=>'0079'), undef, 'Return empty string if no VM found';
};

subtest '[find_deployment_id] Test expected failures' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
    $ms_sdaf->redefine( get_current_job_id => sub { return '0079'; });
    $ms_sdaf->redefine( get_parents => sub { return '0083'; });
    $ms_sdaf->redefine( get_deployment_vm => sub { return '0079'; });

    dies_ok { find_deployment_id(deployer_resource_group=>'Char') } 'Die with multiple deployments being found';
};

subtest '[find_deployment_id]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
    $ms_sdaf->redefine( get_current_job_id => sub { return '0079'; });
    $ms_sdaf->redefine( get_parents => sub { return '0083'; });
    $ms_sdaf->redefine( get_deployment_vm => sub { return '0079' if grep(/0079/, @_); });

    is find_deployment_id(deployer_resource_group=>'Char'), '0079', 'Return only one ID';

    $ms_sdaf->redefine( get_current_job_id => sub { return; });
    is find_deployment_id(deployer_resource_group=>'Char'), undef, 'Return undef if no ID found';
};

# subtest '[get_parent_ids]' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     my $parent_job_data = {
#         parents  => {
#             'Chained'          => [ '123' ],
#             'Parallel'         => [ '123456', '123455' ],
#             'Directly chained' => [ '1234' ]
#         },
#         priority => '50'
#     };
#
#     $ms_sdaf->redefine(get_current_job_id => sub { return '42'; });
#     $ms_sdaf->redefine(get_job_info => sub { return $parent_job_data });
#
#     is get_pare, '4', 'Function must find all 4 parents';
# };

# subtest '[get_parent_ids] Test expected failures' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     my $parent_job_data = {
#         parents  => {
#             'Chained'          => ['lol'],
#             'Parallel'         => ['101'],
#             'Directly chained' => [ ]
#         },
#         priority => '50'
#     };
#     $ms_sdaf->redefine( record_info => sub { return; });
#     $ms_sdaf->redefine( get_current_job_id => sub { return '42'; });
#     $ms_sdaf->redefine(get_job_info => sub { return $parent_job_data });
#     dies_ok { get_parent_ids() } 'Die with ID not being a number';
# };
#
# subtest '[get_sap_inventory_path] Test exceptions' => sub {
#     my @variables = qw( SAP_SID SDAF_ENV_CODE SDAF_WORKLOAD_VNET_CODE PUBLIC_CLOUD_REGION );
#
#     set_var('SAP_SID', 'QES');
#     set_var('SDAF_ENV_CODE', 'LAB');
#     set_var('SDAF_WORKLOAD_VNET_CODE', 'DEP04');
#     set_var('PUBLIC_CLOUD_REGION', 'SECE');
#
#     foreach (@variables) {
#         my $original_value = get_var($_);
#         set_var($_, undef);
#         dies_ok { get_sap_inventory_path() } "Fail with missing parameter: '$_'";
#         set_var($_, $original_value);
#     }
#
#     undef_variables();
# };
#
# subtest '[get_sap_inventory_path]' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     set_var('SAP_SID', 'QES');
#     set_var('SDAF_ENV_CODE', 'LAB');
#     set_var('SDAF_WORKLOAD_VNET_CODE', 'DEP04');
#     set_var('PUBLIC_CLOUD_REGION', 'swedencentral');
#
#     $ms_sdaf->redefine( find_deployment_id => sub { return '42'; });
#     $ms_sdaf->redefine( convert_region_to_short => sub { return 'SECE'; });
#     $ms_sdaf->redefine( get_sdaf_config_path => sub {
#         return '/tmp/Azure_SAP_Automated_Deployment_42/WORKSPACES/SYSTEM/LAB-SECE-DEP04-QES'; });
#     is get_sap_inventory_path(),
#         '/tmp/Azure_SAP_Automated_Deployment_42/WORKSPACES/SYSTEM/LAB-SECE-DEP04-QES/QES_hosts.yaml',
#         'Pass with returning correct deployment path.';
#
#     undef_variables();
# };
#
#
# subtest '[instance_data_from_inventory] ' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     $ms_sdaf->redefine( record_info => sub { return ; });
#     my $expected_result = [
#         {
#             'public_ip' => '10.10.10.3',
#             'provider' => 'provider data',
#             'username' => 'azureadm',
#             'instance_id' => 'qesdhdb02l107',
#             'region' => 'swedencentral',
#             'ssh_key' => '/the/path/towards/happiness/and/sshkey'
#         },
#     ];
#
#     my $inventory_data = {
#         'QES_DB' => {
#             'vars'  => undef,
#             'hosts' => {
#                 'qesdhdb02l107' => {
#                     'ansible_connection' => 'ssh',
#                     'connection_type'    => 'key',
#                     'virtual_host'       => 'qesdhdb02l107',
#                     'ansible_user'       => 'azureadm',
#                     'vm_name'            => 'LAB-SECE-SAP04-QES_qesdhdb02l1073',
#                     'become_user'        => 'root',
#                     'ansible_host'       => '10.10.10.3',
#                     'os_type'            => 'linux'
#                 }
#             }
#         }
#     };
#
#     set_var('PUBLIC_CLOUD_REGION', 'swedencentral');
#
#     my $result = instance_data_from_inventory(
#         provider_data=>'provider data',
#         sut_ssh_key_path=>'/the/path/towards/happiness/and/sshkey',
#         inventory_content=>$inventory_data
#     );
#
#     is_deeply($result, $expected_result, 'Check SUT instance data structure');
#     undef_variables();
# };
#
#
# subtest '[ssh_config_entry_add] Test exceptions' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     $ms_sdaf->redefine( write_sut_file => sub { return $_[1]; });
#
#     dies_ok {ssh_config_entry_add(hostname=>'silly_goose')} 'Fail with missing mandatory argument: entry_name';
#     dies_ok {ssh_config_entry_add(entry_name=>'serious_goose')} 'Fail with missing mandatory argument: hostname';
#
# };
#
# subtest '[ssh_config_entry_add]' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#     my $result;
#     my $expected;
#     $ms_sdaf->redefine( write_sut_file => sub { $result = $_[1]; return; });
#
#     ssh_config_entry_add(hostname=>'silly_goose', entry_name=>'serious_goose');
#     $expected = join("\n\t", 'Host serious_goose', 'HostName silly_goose', "\n");
#     is $result, $expected, 'Check file contents using mandatory args only';
#
#     ssh_config_entry_add(
#         entry_name      => 'serious_goose',
#         hostname        => 'silly_goose',
#         user            => 'betty_the_farmer',
#         identities_only => 'yes',
#         identity_file   => '~/goose/nest',
#         proxy_jump      => 'migrating_goose'
#     );
#     $expected = join("\n\t",
#         'Host serious_goose',
#         'HostName silly_goose',
#         'User betty_the_farmer',
#         'IdentitiesOnly yes',
#         'IdentityFile ~/goose/nest',
#         'ProxyJump migrating_goose',
#         "\n");
#     is $result, $expected, 'Check file contents using supported arguments';
# };
#
# subtest '[ssh_config_add_instances]' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sap_deployment_automation_framework::deployment_connector', no_auto => 1);
#
#     my $mock_inventory_data = {
#         'QES_PAS' => {
#             'hosts' => {
#                 'qespas01l107' => {
#                     'ansible_connection' => 'ssh',
#                     'connection_type'    => 'key',
#                     'virtual_host'       => 'qespas01l107',
#                     'ansible_user'       => 'azureadm',
#                     'vm_name'            => 'LAB-SECE-SAP04-QES_qespas01l107',
#                     'become_user'        => 'root',
#                     'ansible_host'       => '10.10.10.2',
#                     'os_type'            => 'linux'
#                 }
#             },
#             'vars'         => undef
#         },
#         'QES_DB' => {
#             'vars'  => undef,
#             'hosts' => {
#                 'qesdhdb02l107' => {
#                     'ansible_connection' => 'ssh',
#                     'connection_type'    => 'key',
#                     'virtual_host'       => 'qesdhdb02l107',
#                     'ansible_user'       => 'azureadm',
#                     'vm_name'            => 'LAB-SECE-SAP04-QES_qesdhdb02l1073',
#                     'become_user'        => 'root',
#                     'ansible_host'       => '10.10.10.3',
#                     'os_type'            => 'linux'
#                 },
#                 'qesdhdb01l007' => {
#                     'vm_name'            => 'LAB-SECE-SAP04-QES_qesdhdb01l0073',
#                     'become_user'        => 'root',
#                     'ansible_host'       => '10.10.10.4',
#                     'os_type'            => 'linux',
#                     'ansible_user'       => 'azureadm',
#                     'virtual_host'       => 'qesdhdb01l007',
#                     'connection_type'    => 'key',
#                     'ansible_connection' => 'ssh'
#                 }
#             }
#         }
#     };
#     my @entries;
#     $ms_sdaf->redefine( write_sut_file => sub { $result = $_[1]; return; });
#
#
# };

done_testing;