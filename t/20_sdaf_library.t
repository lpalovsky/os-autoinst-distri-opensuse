use strict;
use warnings;
use Test::Mock::Time;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use List::MoreUtils qw(uniq);
use Data::Dumper;
use testapi;
use sles4sap::microsoft_sdaf;

sub undef_variables {
    my @openqa_variables = qw(SDAF_ENV_CODE SDAF_LOCATION RESOURCE_GROUP SDAF_VNET_CODE SAP_SID);
    set_var($_, '') foreach @openqa_variables;
}

subtest '[get_tfvars_path] Test passing scenarios - test using prepare_sdaf_repo()' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my %arguments = (
        sap_sid => 'RAY',
        deployer_vnet_code => 'KAMARIA',
        workload_vnet_code => 'AMURO',
        region_code => 'Side',
        env_code => '7'
    );
    my %expected_results = (
        workload_zone => '/tmp/Azure_SAP_Automated_Deployment_0079/WORKSPACES/LANDSCAPE/7-Side-AMURO-INFRASTRUCTURE/7-Side-AMURO-INFRASTRUCTURE-0079.tfvars',
        sap_system => '/tmp/Azure_SAP_Automated_Deployment_0079/WORKSPACES/SYSTEM/7-Side-AMURO-RAY/7-Side-AMURO-RAY-0079.tfvars',
        library => '/tmp/Azure_SAP_Automated_Deployment_0079/WORKSPACES/LIBRARY/7-Side-SAP_LIBRARY/7-Side-SAP_LIBRARY.tfvars',
        deployer => '/tmp/Azure_SAP_Automated_Deployment_0079/WORKSPACES/DEPLOYER/7-Side-KAMARIA-INFRASTRUCTURE/7-Side-KAMARIA-INFRASTRUCTURE.tfvars'
    );
    my %get_tfvars_results;

    $ms_sdaf->redefine(assert_script_run => sub { return 1; });
    $ms_sdaf->redefine(get_current_job_id => sub { return '0079'; });
    $ms_sdaf->redefine(dirname => sub {
        $get_tfvars_results{workload_zone} = $_[0] if grep(/LANDSCAPE/, @_);
        $get_tfvars_results{sap_system} = $_[0] if grep(/SYSTEM/, @_);
        $get_tfvars_results{library} = $_[0] if grep(/LIBRARY/, @_);
        $get_tfvars_results{deployer} = $_[0] if grep(/DEPLOYER/, @_);
        return @_;
    });

    prepare_sdaf_repo(%arguments);
    foreach (keys(%expected_results)) {
        is $get_tfvars_results{$_}, $expected_results{$_}, "Pass with corrct tfvars path generated for: $_";
    }

};

subtest '[get_tfvars_path] Test unsupported deployment types - test using set_common_sdaf_os_env()' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my %arguments = (
        sap_sid => 'RAY',
        deployer_vnet_code => 'KAMARIA',
        workload_vnet_code => 'AMURO',
        region_code => 'Side',
        env_code => '7',
        sdaf_tfstate_storage_account=>'white_base',
        sdaf_key_vault=>'Gundam',
        subscription_id=>'RX-78',
    );
    my @unexpected_failures;

    $ms_sdaf->redefine(assert_script_run => sub { return 1; });
    $ms_sdaf->redefine(get_current_job_id => sub { return '0079'; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/tmp/'; });
    $ms_sdaf->redefine(serial_console_diag_banner => sub { return; });
    $ms_sdaf->redefine(write_bashrc_entries => sub { return; });
    # This prevents get_required_var() to fail, creating false positive
    $ms_sdaf->redefine(get_required_var => sub { return undef});
    # Search for correct fail message, weeding out false positives
    $ms_sdaf->redefine(croak => sub {
        croak() if grep(/^Invalid/, @_);
        # record unexpected fail message
        push(@unexpected_failures, $_[0]) unless grep(/^Invalid/, @_);
    });

    my @unsupported_types = ('workload', 'sut', 'funky stuff', '');
    foreach (@unsupported_types) {
        my $orig_value = $arguments{deployment_type};
        $arguments{deployment_type} = $_;
        dies_ok { set_common_sdaf_os_env(%arguments) } "Dies with invalid deployment type: $_";
        $arguments{deployment_type} = $orig_value;
    }
    is @unexpected_failures, 0,
        "Check for unexpected failures within unit test.\n\t Unexpected messages found:" . join("\n", @unexpected_failures);
};

subtest '[prepare_sdaf_repo]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my %arguments = (
        sap_sid => 'RAY',
        region_code => 'Side',
        env_code => '7',
        deployer_vnet_code => 'AMURO',
        workload_vnet_code => 'SAYLA'
    );

    my @git_commands;
    my %vnet_checks;
    $ms_sdaf->redefine(log_dir => sub { return '/tmp/openqa_logs'; });
    $ms_sdaf->redefine(assert_script_run => sub {
        push(@git_commands, join('', $_[0])) if grep(/git/, $_[0]);
        return 1; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/root/SDAF/'; });
    # this is to check if internal logic picks correct vnet code for deployment type
    $ms_sdaf->redefine(get_tfvars_path => sub {
            my (%args) = @_;
            $vnet_checks{$args{deployment_type}} = $args{vnet_code};
            return '/some/useless/path'; });

    prepare_sdaf_repo(%arguments);


    is $git_commands[0], 'git clone https://github.com/Azure/sap-automation.git sap-automation --quiet', 'Clone SDAF automation code repo';
    is $git_commands[1], 'git clone https://github.com/Azure/sap-automation-samples.git samples --quiet', 'Clone SDAF automation samples repo';

    # Check correct vnet codes
    is $vnet_checks{library}, '', 'Return library without vnet code';
    is $vnet_checks{deployer}, $arguments{deployer_vnet_code}, 'Return correct vnet code for deployer';
    is $vnet_checks{workload_zone}, $arguments{workload_vnet_code}, 'Return correct vnet code for workload zone';
    is $vnet_checks{sap_system}, $arguments{workload_vnet_code}, 'Return correct vnet code for sap SUT';

};

subtest '[prepare_sdaf_repo] Check directory creation' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my %arguments = (
        sap_sid => 'RAY',
        region_code => 'Side',
        env_code => '7',
        deployer_vnet_code => 'AMURO',
        workload_vnet_code => 'SAYLA',
        deployment_type => 'workload_zone'
    );
    my $log_dir = '/tmp/logs';
    my $tfvars_file = 'Azure_SAP_Automated_Deployment/WORKSPACES/DEPLOYER/LAB-SECE-DEP05-INFRASTRUCTURE/LAB-SECE-DEP05-INFRASTRUCTURE.tfvars';
    my @mkdir_commands;
    $ms_sdaf->redefine(assert_script_run => sub { push(@mkdir_commands, $_[0]) if grep(/mkdir/, @_); return 1; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/tmp/SDAF'; });
    $ms_sdaf->redefine(get_tfvars_path => sub { return $tfvars_file; });
    $ms_sdaf->redefine(log_dir => sub { return '/tmp/openqa_logs'; });

    prepare_sdaf_repo(%arguments);
    is $mkdir_commands[0], 'mkdir -p /tmp/SDAF; cd $_', 'Create deployment root directory';
    is $mkdir_commands[1], 'mkdir -p /tmp/openqa_logs', 'Create logging directory';
    is $mkdir_commands[2], 'mkdir -p Azure_SAP_Automated_Deployment/WORKSPACES/DEPLOYER/LAB-SECE-DEP05-INFRASTRUCTURE',
        'Create workspace directory';
};

subtest '[prepare_tfvars_file] Test missing or incorrect args' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    $ms_sdaf->redefine(data_url => sub { return 'openqa.suse.de/data/' . join('', @_); });
    my @incorrect_deployment_types = qw(funny_library eployer sap_ workload _zone);

    dies_ok { prepare_tfvars_file(); } 'Fail without specifying "$deployment_type"';
    dies_ok { prepare_tfvars_file($_); } "Fail with incorrect deployment type: $_" foreach @incorrect_deployment_types;

};

subtest '[prepare_tfvars_file] Test curl commands' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my $curl_cmd;
    $ms_sdaf->redefine(assert_script_run => sub { $curl_cmd = $_[0] if grep(/curl/, $_[0]); return 1; });
    $ms_sdaf->redefine(upload_logs => sub { return 1; });
    $ms_sdaf->redefine(replace_tfvars_variables => sub { return 1; });
    $ms_sdaf->redefine(get_os_variable => sub { return $_[0]; });
    $ms_sdaf->redefine(data_url => sub { return 'http://openqa.suse.de/data/' . join('', @_); });

    # '-o' is only for checking if correct parameter gets picked from %tfvars_os_variable
    my %expected_results = (
        deployer => 'curl -v -fL http://openqa.suse.de/data/sles4sap/sdaf/DEPLOYER.tfvars -o deployer_parameter_file',
        sap_system => 'curl -v -fL http://openqa.suse.de/data/sles4sap/sdaf/SAP_SYSTEM.tfvars -o sap_system_parameter_file',
        workload_zone => 'curl -v -fL http://openqa.suse.de/data/sles4sap/sdaf/WORKLOAD_ZONE.tfvars -o workload_zone_parameter_file',
        library => 'curl -v -fL http://openqa.suse.de/data/sles4sap/sdaf/LIBRARY.tfvars -o library_parameter_file'
    );

    for my $type (keys %expected_results) {
        prepare_tfvars_file($type);
        is $curl_cmd, $expected_results{$type}, "Return corect url and tfvars variable";
    }
};

subtest '[set_os_variable]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    $ms_sdaf->redefine(assert_script_run => sub { return 1; });

    is set_os_variable('Bilbo', 'Baggins'), 'export Bilbo=Baggins', 'Export variable';
};

subtest '[replace_tfvars_variables] Test correct variable replacement' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    $ms_sdaf->redefine(assert_script_run => sub { return 1; });
    $ms_sdaf->redefine(script_output => sub { return '/somewhere/in/the/Shire'; });
    $ms_sdaf->redefine(upload_logs => sub { return 1; });
    $ms_sdaf->redefine(data_url => sub { return 'openqa.suse.de/data/' . join('', @_); });
    $ms_sdaf->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my %replaced_variables;
    $ms_sdaf->redefine(file_content_replace => sub { %replaced_variables = @_[1 .. $#_]; return 1; });

    my %expected_variables = (
        SDAF_ENV_CODE => 'Balbo',
        SDAF_LOCATION => 'Mungo',
        RESOURCE_GROUP => 'Bungo',
        SDAF_VNET_CODE => 'Bilbo',
        SAP_SID => 'Frodo'
    );

    for my $var_name (keys %expected_variables) {
        set_var($var_name, $expected_variables{$var_name});
    }
    prepare_tfvars_file('workload_zone');

    for my $var_name (keys(%expected_variables)) {
        is $replaced_variables{'%' . $var_name . '%'}, $expected_variables{$var_name},
          "Pass with %$var_name% replaced by '$expected_variables{$var_name}'";
    }
    undef_variables();
};

subtest '[get_resource_group]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    $ms_sdaf->redefine(get_current_job_id => sub { return '0079'; });
    my @expected_failures = ('something_funky', 'workload', 'zone', 'sut', 'lib', 'deploy');
    my %expected_pass = (
        workload_zone => 'SDAF-OpenQA-workload_zone-0079',
        sap_system => 'SDAF-OpenQA-sap_system-0079',
        deployer => 'SDAF-OpenQA-deployer-0079',
        library => 'SDAF-OpenQA-library-0079'
    );

    for my $value (@expected_failures) {
        dies_ok { get_resource_group($value); } "Fail with unsupported 'SDAF_DEPLOYMENT_TYPE' value: $value";
    }

    for my $type (keys %expected_pass) {
        my $rg = get_resource_group($type);
        is $rg, $expected_pass{$type}, "Pass with '$type' and resource group '$rg";
    }
};


subtest '[record_os_variables] ' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my $actual_result;
    $ms_sdaf->redefine(record_info => sub { $actual_result = $_[1]; });
    $ms_sdaf->redefine(get_os_variable => sub { return 'horse'; });
    $ms_sdaf->redefine(serial_console_diag_banner => sub { return 'useless output'; });
    my $expected_result = join("\n", (
            'SAP_AUTOMATION_REPO_PATH=horse',
            'CONFIG_REPO_PATH=horse',
            'parameterFile=horse',
            'deployer_tfstate_key=horse',
            'landscape_tfstate_key=horse',
            'sap_system_tfvars_file=horse',
            'workload_zone_tfvars_file=horse',
            'deployerState=horse',
            'key_vault=horse',
            'tfstate_storage_account=horse',
            'env_code=horse',
            'region_code=horse',
            'sap_env_code=horse',
            'vnet_code=horse',
            'deployer_env_code=horse',
            'deployer_vnet_code=horse'));

    record_os_variables();
    note("RESULT --> \n$actual_result");
    is $actual_result, $expected_result, 'Return correct output without additional variables';
};

subtest '[serial_console_diag_banner] ' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my $printed_output;
    $ms_sdaf->redefine(script_run => sub { $printed_output = $_[0]; return 1; });
    my $correct_output = '############################    SMOOTH CRIMINAL    ############################';

    serial_console_diag_banner('smOotH CrimInal');
    is $printed_output, $correct_output, "Print banner correctly in uppercase:\n$correct_output";
    dies_ok { serial_console_diag_banner() } 'Fail with missing test to be printed';
    dies_ok { serial_console_diag_banner('dirty diana' x 6) } 'Fail with string exceeds max number of characters';
};

subtest '[sdaf_deploy_workload_zone] Test missing arguments' => sub {
        dies_ok { sdaf_deploy_workload_zone() } 'Expected failure with missing argument: workload_tfvars_file';
};

subtest '[sdaf_deploy_workload_zone]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my $config_path_command;
    my $sdaf_command;
    $ms_sdaf->redefine(assert_script_run => sub { $config_path_command = $_[0] if grep(/^cd\s/, @_) ; return 0; });
    $ms_sdaf->redefine(script_run => sub { $sdaf_command = $_[0] if grep(/install_workloadzone.sh/, @_) ; return 0; });
    $ms_sdaf->redefine(record_info => sub { return 1; });
    $ms_sdaf->redefine(set_os_variable => sub { return 1; });
    $ms_sdaf->redefine(record_os_variables => sub { return 1; });
    $ms_sdaf->redefine(set_storage_account_permissions => sub { return 1; });
    $ms_sdaf->redefine(get_resource_group => sub { return 1; });
    $ms_sdaf->redefine(upload_logs => sub { return 1; });
    $ms_sdaf->redefine(log_dir => sub { return '/tmp/openqa_logs'; });

    my $tfvars_file = '/root/Azure_SAP_Automated_Deployment/WORKSPACES/DEPLOYER/LAB-SECE-DEP05-INFRASTRUCTURE/LAB-SECE-DEP05-INFRASTRUCTURE.tfvars';
    my $expected_command = '( $SAP_AUTOMATION_REPO_PATH/deploy/scripts/install_workloadzone.sh --parameterfile LAB-SECE-DEP05-INFRASTRUCTURE.tfvars --deployer_environment ${deployer_env_code} --deployer_tfstate_key ${deployer_env_code}-${region_code}-${deployer_vnet_code}-INFRASTRUCTURE.terraform.tfstate --keyvault ${key_vault} --storageaccountname ${tfstate_storage_account} --subscription ${ARM_SUBSCRIPTION_ID} --tenant_id ${ARM_TENANT_ID} --spn_id ${ARM_CLIENT_ID} --spn_secret ${ARM_CLIENT_SECRET} --auto-approve 2>&1 | tee /tmp/openqa_logs/deploy_workload_zone.log ; exit ${PIPESTATUS[0]})';

    sdaf_deploy_workload_zone($tfvars_file);
    is $config_path_command,
      'cd /root/Azure_SAP_Automated_Deployment/WORKSPACES/DEPLOYER/LAB-SECE-DEP05-INFRASTRUCTURE/', 'Enter correct config path';
    is $sdaf_command, $expected_command, 'Pass with executing correct command';
};

subtest '[cleanup]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    # Keep the resource group order to check if sap_system gets deleted first
    my $resource_groups = "SDAF-OpenQA-workload_zone-6445
    SDAF-OpenQA-sap_system-6445";
    my @deleted_groups;
    $ms_sdaf->redefine(qesap_az_get_resource_group => sub { return $resource_groups; });
    $ms_sdaf->redefine(delete_resource_group => sub { push @deleted_groups, $_[0]; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/tmp/Azure_SAP_Automated_Deployment_0079/'; });
    $ms_sdaf->redefine(assert_script_run => sub { return 1; });

    cleanup();
    # Order matters here - sap_system needs to be deleted before workload zone
    is $deleted_groups[0], 'SDAF-OpenQA-sap_system-6445', 'Delete sap sut group';
    is $deleted_groups[1], 'SDAF-OpenQA-workload_zone-6445', 'Delete workload zone group';
};

subtest '[cleanup] Test expected failure' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    # Keep the resource group order to check if sap_system gets deleted first
    my $resource_groups = "SDAF-OpenQA-workload_zone-6445
    SDAF-OpenQAaaa-workload_zone-6445
    SDAF-OpenQA-sap_system-6445";
    my @deleted_groups;
    $ms_sdaf->redefine(qesap_az_get_resource_group => sub { return $resource_groups; });
    $ms_sdaf->redefine(delete_resource_group => sub { push @deleted_groups, $_[0]; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/tmp/Azure_SAP_Automated_Deployment_0079/'; });
    $ms_sdaf->redefine(assert_script_run => sub { return 1; });

    dies_ok { cleanup() } 'Fail with multiple workload zones detected';
};
#
# subtest '[sdaf_execute_remover] Test expected failure' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
#     # helps to detect if test failed at the correct place
#     $ms_sdaf->redefine(get_os_variable => sub { return ''; });
#     my @expected_failures = ('sap', 'system', 'workload', 'anything_else', 'library', 'deployer');
#
#     dies_ok { sdaf_execute_remover() } 'Fail with undefined deployment_type';
#     dies_ok { sdaf_execute_remover($_) } "Fail with incorrect deployment_type: $_" foreach @expected_failures;
#     dies_ok { sdaf_execute_remover('workload_zone') } 'Fail with undefined tfvars OS variable';
# };
#
# subtest '[sdaf_execute_remover] Test functionality' => sub {
#     my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
#     my @script_run_calls;
#     $ms_sdaf->redefine(deployment_dir => sub { return '/some/path/'; });
#     $ms_sdaf->redefine(assert_script_run => sub { return 0; });
#     $ms_sdaf->redefine(record_info => sub { return 0; });
#     $ms_sdaf->redefine(script_run => sub { push @script_run_calls, $_[0] if grep /remover/, $_[0]; return 0; });
#     $ms_sdaf->redefine(get_os_variable => sub {
#             return '/some/path/LAB-SECE-SAP04-INFRASTRUCTURE-6453.tfvars' if $_[0] eq 'workload_zone_parameter_file';
#             return '/some/path/LAB-SECE-SAP04-QES-6453.tfvars' if $_[0] eq 'sap_system_parameter_file';
#     });
#
#     sdaf_execute_remover('workload_zone');
#     is $script_run_calls[0],
#       '/some/path//sap-automation/deploy/scripts/remover.sh --parameterfile LAB-SECE-SAP04-INFRASTRUCTURE-6453.tfvars --type sap_landscape --auto-approve',
#       'Return correct command for workload zone deployment';
#
#     sdaf_execute_remover('sap_system');
#     is $script_run_calls[1],
#       '/some/path//sap-automation/deploy/scripts/remover.sh --parameterfile LAB-SECE-SAP04-QES-6453.tfvars --type sap_system --auto-approve',
#       'Return correct command for SAP system deployment';
# };

subtest '[sdaf_destroy] Test expected failure' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    # Keep the resource group order to check if sap_system gets deleted first
    my $resource_groups = "SDAF-OpenQA-workload_zone-6445
    SDAF-OpenQAaaa-workload_zone-6445
    SDAF-OpenQA-sap_system-6445";
    $ms_sdaf->redefine(qesap_az_get_resource_group => sub { return $resource_groups; });
    dies_ok { sdaf_destroy() } 'Fail with multiple workload zones detected';
};

subtest '[sdaf_prepare_ssh_keys]' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my %get_ssh_commands;

    $ms_sdaf->redefine(script_run => sub { return 0; });
    $ms_sdaf->redefine(assert_script_run => sub { return 0; });
    $ms_sdaf->redefine(script_output => sub {
        $get_ssh_commands{privkey_cmd} = $_[0] if grep /sshkey\$/, @_;
        $get_ssh_commands{pubkey_cmd} = $_[0] if grep /-pub\$/, @_;
        return 0; });
    $ms_sdaf->redefine(az_get_ssh_key => sub { return 0; });

    sdaf_prepare_ssh_keys('WhitePony');
    is $get_ssh_commands{privkey_cmd}, 'az keyvault secret list --vault-name WhitePony --query [].name --output tsv | grep sshkey$', 'Return correct command for retrieving private key';
    is $get_ssh_commands{pubkey_cmd}, 'az keyvault secret list --vault-name WhitePony --query [].name --output tsv | grep sshkey-pub$', 'Return correct command for retrieving public key';

    dies_ok {sdaf_prepare_ssh_keys()} 'Fail with missing deployer key vault argument';
};

subtest '[sdaf_get_deployer_ip] Test passing behavior' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my @script_output_commands;
    $ms_sdaf->redefine( script_output => sub {
        push @script_output_commands, $_[0];
        return 'Passenger' if grep /vm\slist\s/, @_;
        return '192.168.0.1';});

    my $ip_addr = sdaf_get_deployer_ip('DigitalBath');
    is $script_output_commands[0], 'az vm list --resource-group DigitalBath --query [].name --output tsv',
        'Pass using correct command for retrieving vm list';
    is $script_output_commands[1],
        'az vm list-ip-addresses --resource-group DigitalBath --name Passenger --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv',
        'Pass using correct command for retrieving public IP addr';
    is $ip_addr, '192.168.0.1', 'Pass returing correct IP addr';

    dies_ok {sdaf_get_deployer_ip()} 'Fail with missing deployer resource group argument';
    $ms_sdaf->redefine( script_output => sub { return '192.168.0.1';});
};

subtest '[sdaf_get_deployer_ip] Test expected failures' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my @incorrect_ip_addresses =(
        '192.168.0.500',
        'Back.to.sch.ool',
        '192.168.0.',
        '2001:db8:85a3::8a2e:370:7334'
    );

    dies_ok {sdaf_get_deployer_ip()} 'Fail with missing deployer resource group argument';
    for my $ip_input (@incorrect_ip_addresses) {
        $ms_sdaf->redefine( script_output => sub { return $ip_input;});
        dies_ok {sdaf_get_deployer_ip('Change')} "Detect incorrect IP addr pattern: $ip_input";
    }
};

subtest '[sdaf_execute_playbook] Fail with missing mandatory arguments' => sub {
    dies_ok {sdaf_execute_playbook()} 'Croak with missing mandatory argument "playbook_filename"';
};

subtest '[sdaf_execute_playbook] Command execution' => sub {
    my $ms_sdaf = Test::MockModule->new('sles4sap::microsoft_sdaf', no_auto => 1);
    my $ansible_playbook_cmd;

    $ms_sdaf->redefine(log_dir => sub { return '/tmp/openqa_logs'; });
    $ms_sdaf->redefine(assert_script_run => sub { return 0; });
    $ms_sdaf->redefine(deployment_dir => sub { return '/tmp/SDAF'; });
    $ms_sdaf->redefine(dirname => sub { return '/tmp/SDAF/WORKSPACES/LANDSCAPE/LAB-SECE-SAP04-INFRASTRUCTURE'; });
    $ms_sdaf->redefine(get_os_variable => sub { return; });
    $ms_sdaf->redefine(script_run => sub {
        $ansible_playbook_cmd = $_[0] if grep(/ansible-playbook/, $_[0]);
        return 0;
    });

    $ms_sdaf->redefine(upload_logs => sub { return ; });
    set_var('SAP_SID', 'QAS');

    my $expected_result = join(' ', '(', 'ansible-playbook',
        '--inventory-file="QAS_hosts.yaml"',
        '--private-key=/tmp/SDAF/WORKSPACES/LANDSCAPE/LAB-SECE-SAP04-INFRASTRUCTURE/sshkey',
        '--extra-vars="_workspace_directory=`pwd`"',
        '--extra-vars="@sap-parameters.yaml"',
        '--ssh-common-args="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=120"',
        '/tmp/SDAF/sap-automation/deploy/ansible/playbook_01_os_base_config.yaml 2>&1',
        '| tee /tmp/openqa_logs/playbook_01_os_base_config.log',
        '; exit ${PIPESTATUS[0]})'
    );

    sdaf_execute_playbook(playbook_filename=>'playbook_01_os_base_config.yaml');
    is $ansible_playbook_cmd, $expected_result, 'Execute correct ansible command';
    undef_variables();
};

done_testing;
