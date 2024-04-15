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
use sles4sap::sdaf_sles4sap_publiccloud_bridge;

subtest '[find_deployment_id] Test expected failures' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sdaf_sles4sap_publiccloud_bridge', no_auto => 1);
    $ms_sdaf->redefine( script_run => sub { return 0; });

    $ms_sdaf->redefine( get_parent_ids => sub { return []; });
    dies_ok { find_deployment_id() } 'Die with no deployment being found';

    $ms_sdaf->redefine( get_parent_ids => sub { return ['/some/path/', '/that/other/path', '/oh_no/this_is_bad']; });
    dies_ok { find_deployment_id() } 'Die with multiple deployments being found';
};


subtest '[find_deployment_id]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sdaf_sles4sap_publiccloud_bridge', no_auto => 1);
    $ms_sdaf->redefine( get_parent_ids => sub { return ['42']; });
    $ms_sdaf->redefine( script_run => sub { return 0; });
    is find_deployment_id(), '/tmp/Azure_SAP_Automated_Deployment_42', 'Pass with finding exactly one deployment.'
};

subtest '[instance_data_from_inventory] ' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sdaf_sles4sap_publiccloud_bridge', no_auto => 1);
    $ms_sdaf->redefine( find_deployment_id => sub { return '42'; });
    $ms_sdaf->redefine( get_config_root_path => sub { return '/the/path/towards/happiness/and'; });
    $ms_sdaf->redefine( record_info => sub { return ; });
    $ms_sdaf->redefine( script_output => sub {return
        "QES_DB:
  hosts:
    qesdhdb01l013:
      ansible_host        : 192.168.1.2
      ansible_user        : azureadm
      ansible_connection  : ssh
      connection_type     : key
      virtual_host        : virtualhostname01
      become_user         : root
      os_type             : linux
      vm_name             : LAB-SECE-SAP04-QES_virtualhostname01
  vars:
    node_tier             : hana
    supported_tiers       : [hana, scs, pas]
"
    });
    my $expected_result = {
           'ssh_key' => '/the/path/towards/happiness/and/sshkey',
           'username' => 'azureadm',
           'public_ip' => '192.168.1.2',
           'instance_id' => 'qesdhdb01l013',
           'region' => 'swedencentral',
           'provider' => 'AZURE'
    };

    set_var('SAP_SID', 'QES');
    set_var('SDAF_ENV_CODE', 'LAB');
    set_var('SDAF_WORKLOAD_VNET_CODE', 'DEP05');
    set_var('PUBLIC_CLOUD_REGION', 'swedencentral');
    my $result = instance_data_from_inventory();

    is_deeply($result->[0], $expected_result, 'Check SUT instance data structure');
};

subtest '[get_parent_ids]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::sdaf_sles4sap_publiccloud_bridge', no_auto => 1);
    my $parent_job_data = {
        parents  => {
            'Chained'          => [ '123' ],
            'Parallel'         => [ '123456', '123455' ],
            'Directly chained' => [ '1234' ]
        },
        priority => '50'
    };

    my $number_of_parent_jobs = 0;
    $ms_sdaf->redefine( record_info => sub { return; });
    $ms_sdaf->redefine( get_current_job_id => sub { return '42'; });
    $ms_sdaf->redefine(script_run => sub { $number_of_parent_jobs ++; return 0 if  grep /\/123$/, @_; return 1 });
    $ms_sdaf->redefine(get_job_info => sub { return $parent_job_data });
    $ms_sdaf->redefine(deployment_dir => sub { return "/path_to/the_ultimate_answer/$_[1]"; });

    find_deployment_id();
    is $number_of_parent_jobs, '4', 'Function must find all 4 parents';
};

# subtest '[get_parent_ids] Test expected failures' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::sdaf_sles4sap_publiccloud_bridge', no_auto => 1);
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

done_testing;