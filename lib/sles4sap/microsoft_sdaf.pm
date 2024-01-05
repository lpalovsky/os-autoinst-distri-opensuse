# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
#
# Library used for Microsoft SDAF deployment

package sles4sap::microsoft_sdaf;

use strict;
use warnings;
use testapi;
use Exporter qw(import);
use Carp qw(croak);
use mmapi qw(get_current_job_id);
use utils qw(write_sut_file file_content_replace);
use qesapdeployment qw(qesap_az_get_resource_group);
use File::Basename;
use Regexp::Common qw(net);

=head1 SYNOPSIS

Library with common functions for Microsoft SDAF deployment automation:
https://learn.microsoft.com/en-us/azure/sap/automation/get-started

=cut

our @EXPORT = qw(
  az_login
  set_common_sdaf_os_env
  prepare_sdaf_repo
  prepare_tfvars_file
  sdaf_deploy_workload_zone
  sdaf_deploy_sap_system
  sdaf_destroy
  sdaf_prepare_ssh_keys
  sdaf_get_deployer_ip
  sdaf_execute_playbook
  set_os_variable
  get_resource_group
  record_os_variables
  serial_console_diag_banner
  cleanup
);

=head2 deployment_dir

    deployment_dir();

Returns deployment directory path with job ID appended as unique identifier.

=cut
sub deployment_dir {
    my $deployment_dir_root = get_var('DEPLOYMENT_ROOT_DIR', '/tmp');
    return "$deployment_dir_root/Azure_SAP_Automated_Deployment_" . get_current_job_id();
}

=head2 log_dir

    log_dir();

Returns logging directory path with job ID appended as unique identifier.

=cut
sub log_dir {
    return '/tmp/openqa_logs_' . get_current_job_id();
}

=head2 command_output_into_log

    command_output_into_log(command=>$command, log_file=>$log_file);

B<command>: Command which output should be logged into file.
B<log_file>: Full log file path and filename to pipe command output into.

Transforms given command so it displays output in shell but also in a log file.
It also takes care of reporting exit code of the command itself instead of the one from 'tee' command.
Returns string with transformed command.

Command structure: (command_to_execute 2>$1 | tee /log/file.log; exit ${PIPESTATUS[0]})
    'exit ${PIPESTATUS[0]}' - returns 'command_to_execute' return code instead of one from 'tee'
    (...) - puts everything into subshell to prevent 'exit' logging out of current shell
    tee - writes output also into the log file


=cut
sub command_output_into_log {
    my (%args) = @_;
    foreach ('command', 'log_file') {
        croak "Missing mandatory argument: $_" unless $args{$_};
    }

    my $result = join(' ', '(', $args{command}, '2>&1', '|', 'tee', $args{log_file}, ';', 'exit', '${PIPESTATUS[0]})' );
    return $result;
}

=head2 az_login

 az_login();

Azure login using SPN credentials defined by secret OpenQA parameters:
B<_SECRET_AZURE_SDAF_APP_ID>
B<_SECRET_AZURE_SDAF_APP_PASSWORD>
B<_SECRET_AZURE_SDAF_TENANT_ID>

Returns 'subscription ID' on success.
SDAF needs SPN credentials with special permissions. Check link below for details.
https://learn.microsoft.com/en-us/azure/sap/automation/deploy-control-plane?tabs=linux#prepare-the-deployment-credentials

=cut

sub az_login {

    my @variables = (
        'export ARM_CLIENT_ID=' . get_required_var('_SECRET_AZURE_SDAF_APP_ID'),
        'export ARM_CLIENT_SECRET=' . get_required_var('_SECRET_AZURE_SDAF_APP_PASSWORD'),
        'export ARM_TENANT_ID=' . get_required_var('_SECRET_AZURE_SDAF_TENANT_ID'),
    );

    # This writes .bashrc variables using a special file without exposing them in serial console.
    write_bashrc_entries(@variables);

    my $login_cmd = 'while ! az login --service-principal -u ${ARM_CLIENT_ID} -p ${ARM_CLIENT_SECRET} -t ${ARM_TENANT_ID}; do sleep 10; done';
    assert_script_run($login_cmd, timeout => 5 * 60);

    my $subscription_id = script_output('az account show -o tsv --query id');
    return ($subscription_id);
}

=head2 set_common_sdaf_os_env

    set_os_env(
        subscription_id=>$subscription_id
        [, env_code=>$env_code]
        [, deployer_vnet_code=>$deployer_vnet_code]
        [, workload_vnet_code=>$workload_vnet_code]
        [, region_code=>$region_code]
        [, sap_sid=>$sap_sid]
        [, sdaf_tfstate_storage_account=$sdaf_tfstate_storage_account]
        [, sdaf_key_vault=>$sdaf_key_vault]
    );

B<subscription_id>: Azure subscription ID
B<env_code>: Code for SDAF deployment env. Default: 'SDAF_ENV_CODE'
B<deployer_vnet_code>: Deployer virtual network code. Default 'SDAF_DEPLOYER_VNET_CODE'
B<workload_vnet_code>: Virtual network code for workload zone. Default: 'SDAF_WORKLOAD_VNET_CODE'
B<region_code>: SDAF internal code for azure region. Default: 'SDAF_REGION_CODE'
B<sap_sid>: SAP system ID. Default 'SAP_SID'
B<sdaf_tfstate_storage_account>: Storage account residing in library resource group. Location for stored tfstate files. Default 'SDAF_TFSTATE_STORAGE_ACCOUNT'
B<sdaf_key_vault>: Key vault name inside Deployer resource group. Default 'SDAF_KEY_VAULT'

Sets up common OS env variables required by SDAF in .bashrc and loads them.
OS env variables are core of how to execute SDAF and many are used even internally by SDAF code.
For detailed variable description check : https://learn.microsoft.com/en-us/azure/sap/automation/naming

=cut

sub set_common_sdaf_os_env {
    my (%args) = @_;
    my $deployment_dir = deployment_dir();

    $args{env_code} //= get_required_var('SDAF_ENV_CODE');
    $args{deployer_vnet_code} //= get_required_var('SDAF_DEPLOYER_VNET_CODE');
    $args{workload_vnet_code} //= get_required_var('SDAF_WORKLOAD_VNET_CODE');
    $args{region_code} //= get_required_var('SDAF_REGION_CODE');
    $args{sap_sid} //= get_required_var('SAP_SID');
    $args{sdaf_tfstate_storage_account} //= get_required_var('SDAF_TFSTATE_STORAGE_ACCOUNT');
    $args{sdaf_key_vault} //= get_required_var('SDAF_KEY_VAULT');

    my @variables = (
        "export env_code=$args{env_code}",
        "export deployer_vnet_code=$args{deployer_vnet_code}",
        "export workload_vnet_code=$args{workload_vnet_code}",
        "export sap_env_code=$args{env_code}",
        "export deployer_env_code=$args{env_code}",
        "export region_code=$args{region_code}",
        "export SID=$args{sap_sid}",
        "export ARM_SUBSCRIPTION_ID=$args{subscription_id}",
        "export SAP_AUTOMATION_REPO_PATH=$deployment_dir/sap-automation/",
        'export DEPLOYMENT_REPO_PATH=${SAP_AUTOMATION_REPO_PATH}',
        "export CONFIG_REPO_PATH=$deployment_dir/WORKSPACES",
        'export deployer_parameter_file=' . get_tfvars_path(deployment_type=>'deployer', vnet_code=>$args{deployer_vnet_code}, %args),
        'export library_parameter_file=' . get_tfvars_path(deployment_type=>'library', %args),
        'export sap_system_parameter_file=' . get_tfvars_path(deployment_type=>'sap_system', vnet_code=>$args{workload_vnet_code}, %args),
        'export workload_zone_parameter_file=' . get_tfvars_path(deployment_type=>'workload_zone', vnet_code=>$args{workload_vnet_code}, %args),
        "export tfstate_storage_account=$args{sdaf_tfstate_storage_account}",
        "export key_vault=$args{sdaf_key_vault}"
    );
    # Mark function start end end as it produces a lot of garbage serial output
    serial_console_diag_banner('Set OS variables: start');
    write_bashrc_entries(@variables);
    serial_console_diag_banner('Set OS variables: end');
}

=head2 get_tfvars_path

    get_tfvars_path(
        deployment_type=>$deployment_type,
        env_code=>$env_code,
        region_code=>$region_code,
        [vnet_code=>$vnet_code,
        sap_sid=>$sap_sid]);

Returns full tfvars filepath respective to deployment type.

B<deployment_type> Type of the deployment (workload_zone, sap_system, library... etc)
B<env_code>  SDAF parameter for environment code (for our purpose we can use 'LAB')
B<region_code> SDAF parameter to choose PC region. Note SDAF is using internal abbreviations (SECE = swedencentral)
B<vnet_code> SDAF parameter for virtual network code. Library and deployer use different vnet than SUT env
B<sap_sid> SDAF parameter for sap system ID

=cut

sub get_tfvars_path {
    my (%args) = @_;
    my @supported_types = ('workload_zone', 'sap_system', 'library', 'deployer');
    # common mandatory args

    my @mandatory_args = qw(deployment_type env_code region_code);
    # library does not require 'vnet_code'
    push @mandatory_args, 'vnet_code' unless $args{deployment_type} eq 'library';
    # only sap_system requires 'sap_sid'
    push @mandatory_args, 'sap_sid' if $args{deployment_type} eq 'sap_system';

    # Only workload and sap SUT needs unique ID
    my $job_id = get_current_job_id();

    foreach (@mandatory_args) { croak "Missing mandatory argument: '$_'" unless defined($args{$_}); }

    croak "Invalid deployment type: $args{deployment_type}\nCurrently supported ones are: @supported_types" unless
      grep(/^$args{deployment_type}$/, @supported_types);


    my $file_path;
    if ($args{deployment_type} eq 'workload_zone') {
        my $env_reg_vnet = join('-', $args{env_code}, $args{region_code}, $args{vnet_code});
        $file_path = "LANDSCAPE/$env_reg_vnet-INFRASTRUCTURE/$env_reg_vnet-INFRASTRUCTURE-$job_id.tfvars";
    }
    if ($args{deployment_type} eq 'deployer') {
        my $env_reg_vnet = join('-', $args{env_code}, $args{region_code}, $args{vnet_code});
        $file_path = "DEPLOYER/$env_reg_vnet-INFRASTRUCTURE/$env_reg_vnet-INFRASTRUCTURE.tfvars";
    }
    if ($args{deployment_type} eq 'library') {
        my $env_reg = join('-', $args{env_code}, $args{region_code});
        $file_path = "LIBRARY/$env_reg-SAP_LIBRARY/$env_reg-SAP_LIBRARY.tfvars";
    }
    if ($args{deployment_type} eq 'sap_system') {
        my $env_reg_vnet_sid = join('-', $args{env_code}, $args{region_code}, $args{vnet_code}, $args{sap_sid});
        $file_path = "SYSTEM/$env_reg_vnet_sid/$env_reg_vnet_sid-$job_id.tfvars";
    }

    my $result = join('/', deployment_dir(), 'WORKSPACES', $file_path);
    return $result;
}

=head2 homedir

    homedir();

Returns home directory path.

=cut

sub homedir {
    return(script_output('echo $HOME'));
}

=head2 write_bashrc_entries

    write_bashrc_entries(@entry_list);

B<entry_list> list of entries to be appended to .bashrc file

Writes .bashrc entries using special file to prevent sensitive entry values being exposed in serial terminal.

=cut

sub write_bashrc_entries {
    my (@entry_list) = @_;
    my $home = homedir();
    write_sut_file("$home/az_variables", join("\n", "\n", @entry_list));
    assert_script_run("cat $home/az_variables >> $home/.bashrc", quiet => 1);
    assert_script_run("source $home/.bashrc", quiet => 1);
}

=head2 set_os_variable

    set_os_variable($variable_name, $variable_value);

B<$variable_name> Variable name
B<$variable_value> Variable value

Exports temporary OS env variable.
WARNING: This is executed via 'assert_script_run' therefore output will be visible in logs
Returns executed command.

=cut

sub set_os_variable {
    my ($variable_name, $variable_value) = @_;
    my $env_cmd = "export $variable_name=$variable_value";
    assert_script_run($env_cmd);
    return ($env_cmd);
}

=head2 get_os_variable

    get_os_variable($variable_name);

B<$variable_name> Variable name

Returns value of requested OS env variable name.
Variable is acquired using 'echo' command and is visible in serial terminal output.

=cut

sub get_os_variable {
    my ($variable_name) = @_;
    croak 'Positional argument $variable_name not defined' unless $variable_name;
    $variable_name =~ s/[\$}{]//g;

    return script_output("echo \${$variable_name}", quiet => 1);
}

=head2 prepare_sdaf_repo

   prepare_sdaf_repo(
        [, env_code=>$env_code]
        [, region_code=>$region_code]
        [, workload_vnet_code=>$workload_vnet_code]
        [, deployervnet_code=>$workload_vnet_code]
        [, sap_sid=>$sap_sid]);

Prepares directory structure and Clones git repository for SDAF samples and automation code.

B<env_code>: Code for SDAF deployment env. Default: 'SDAF_ENV_CODE'
B<deployer_vnet_code>: Deployer virtual network code. Default 'SDAF_DEPLOYER_VNET_CODE'
B<workload_vnet_code>: Virtual network code for workload zone. Default: 'SDAF_WORKLOAD_VNET_CODE'
B<region_code>: SDAF internal code for azure region. Default: 'SDAF_REGION_CODE'
B<sap_sid>: SAP system ID. Default 'SAP_SID'

=cut

sub prepare_sdaf_repo {
    my (%args) = @_;
    $args{env_code} //= get_required_var('SDAF_ENV_CODE');
    $args{deployer_vnet_code} //= get_required_var('SDAF_DEPLOYER_VNET_CODE');
    $args{workload_vnet_code} //= get_required_var('SDAF_WORKLOAD_VNET_CODE');
    $args{region_code} //= get_required_var('SDAF_REGION_CODE');
    $args{sap_sid} //= get_required_var('SAP_SID');

    my $deployment_dir = deployment_dir();
    my @git_repos = ("https://github.com/Azure/sap-automation.git sap-automation",
        "https://github.com/Azure/sap-automation-samples.git samples");

    assert_script_run("mkdir -p $deployment_dir; cd \$_");
    assert_script_run('mkdir -p ' .  log_dir());
    foreach (@git_repos) {
        assert_script_run("git clone $_ --quiet");
    }
    assert_script_run("cp -Rp samples/Terraform/WORKSPACES $deployment_dir/WORKSPACES");
    # Ensure correct directories are in place
    my %vnet_codes = (
        workload_zone => $args{workload_vnet_code},
        sap_system => $args{workload_vnet_code},
        library => '',
        deployer => $args{deployer_vnet_code}
    );

    my @create_workspace_dirs;
    for my $deployment_type ('workload_zone', 'sap_system', 'library', 'deployer') {
        my $tfvars_file = get_tfvars_path(
            vnet_code => $vnet_codes{$deployment_type},
            sap_sid => $args{sap_sid},
            region_code => $args{region_code},
            env_code => $args{env_code},
            deployment_type => $deployment_type
        );

        push(@create_workspace_dirs, dirname($tfvars_file));
    }

    assert_script_run("mkdir -p $_") foreach @create_workspace_dirs;
}

=head2 prepare_tfvars_file

    prepare_tfvars_file($deployment_type);

B<$deployment_type> Type of the deployment (workload_zone, sap_system, library... etc)

Downloads tfvars template files from openQA data dir and places them into correct place within SDAF repo structure.
Returns full path of the tfvars file.

=cut

sub prepare_tfvars_file {
    my ($deployment_type) = @_;
    my %tfvars_os_variable = (
        deployer => 'deployer_parameter_file',
        sap_system => 'sap_system_parameter_file',
        workload_zone => 'workload_zone_parameter_file',
        library => 'library_parameter_file'
    );
    my %tfvars_template_url = (
        deployer => data_url('sles4sap/sdaf/DEPLOYER.tfvars'),
        sap_system => data_url('sles4sap/sdaf/SAP_SYSTEM.tfvars'),
        workload_zone => data_url('sles4sap/sdaf/WORKLOAD_ZONE.tfvars'),
        library => data_url('sles4sap/sdaf/LIBRARY.tfvars')
    );
    croak 'Deplyoment type not specified' unless $deployment_type;
    croak "Unknown deployment type: $deployment_type" unless $tfvars_os_variable{$deployment_type};

    my $tfvars_file = get_os_variable($tfvars_os_variable{$deployment_type});
    my $retrieve_tfvars_cmd = join(' ', 'curl', '-v', '-fL', $tfvars_template_url{$deployment_type}, '-o', $tfvars_file);

    assert_script_run($retrieve_tfvars_cmd);
    assert_script_run("test -f $tfvars_file");
    replace_tfvars_variables($tfvars_file);
    upload_logs($tfvars_file, log_name => "$deployment_type.tfvars");
    return $tfvars_file;
}

=head2 replace_tfvars_variables

    replace_tfvars_variables();

B<$deployment_type> Type of the deployment (workload_zone, sap_system, library... etc)

Replaces variables

=cut

sub replace_tfvars_variables {
    my ($tfvars_file) = @_;
    croak 'Variable "$tfvars_file" undefined' unless defined($tfvars_file);
    my @variables = qw(SDAF_ENV_CODE SDAF_LOCATION RESOURCE_GROUP SDAF_VNET_CODE SAP_SID);
    my %to_replace = map { '%' . $_ . '%' => get_var($_, '') } @variables;
    file_content_replace($tfvars_file, %to_replace);
}

=head2 sdaf_deploy_workload_zone

    sdaf_deploy_workload_zone( $workload_tfvars_file );

B<workload_tfvars_file>: Full path to workload zone deployment tfvars file

Executes SDAF workload zone deployment using tfvars file specified.
https://learn.microsoft.com/en-us/azure/sap/automation/deploy-workload-zone?tabs=linux#deploy-the-sap-workload-zone

=cut

sub sdaf_deploy_workload_zone {
    my ($workload_tfvars_file) = @_;
    croak 'Missing mandatory argument: workload_tfvars_file' unless defined($workload_tfvars_file);

    # SDAF has to be executed from the profile directory
    my ($tfvars_filename, $tfvars_path) = fileparse($workload_tfvars_file);

    assert_script_run("cd $tfvars_path");
    my $deployer_state_file = get_var('SDAF_DEPLOYER_TFSTATE',
        '${deployer_env_code}-${region_code}-${deployer_vnet_code}-INFRASTRUCTURE.terraform.tfstate');

    set_os_variable('parameterFile', $tfvars_filename);
    set_os_variable('deployerState', $deployer_state_file);
    record_os_variables();

    my $deploy_command = join(' ', '$SAP_AUTOMATION_REPO_PATH/deploy/scripts/install_workloadzone.sh', '--parameterfile',
        $tfvars_filename, '--deployer_environment', '${deployer_env_code}', '--deployer_tfstate_key',
        $deployer_state_file, '--keyvault', '${key_vault}', '--storageaccountname', '${tfstate_storage_account}',
        '--subscription', '${ARM_SUBSCRIPTION_ID}', '--tenant_id', '${ARM_TENANT_ID}', '--spn_id',
        '${ARM_CLIENT_ID}', '--spn_secret', '${ARM_CLIENT_SECRET}', '--auto-approve');
    my $output_log_file = log_dir() . "/deploy_workload_zone.log";

    my $rc = script_run(command_output_into_log(command=>$deploy_command, log_file=>$output_log_file), timeout => 1800);
    upload_logs($output_log_file, log_name=>'deploy_workload_zone.log');
    die "Workload zone deployment failed with RC: $rc" if $rc;
    record_info('Deploy done');
}

=head2 sdaf_deploy_sap_system

    sdaf_deploy_sap_system($sap_system_tfvars_file);

Executes SDAF workload zone deployment.

=cut

sub sdaf_deploy_sap_system {
    my ($sap_system_tfvars_file) = @_;

    my ($tfvars_filename, $tfvars_path) = fileparse($sap_system_tfvars_file);

    my $deploy_command = join(' ', '${DEPLOYMENT_REPO_PATH}/deploy/scripts/installer.sh', '--parameterfile',
        $tfvars_filename, '--type', 'sap_system', '--storageaccountname',
        '${tfstate_storage_account}', '--state_subscription', '${ARM_SUBSCRIPTION_ID}', '--auto-approve');
     my $output_log_file = log_dir() . "/deploy_sap_system.log";

    # SDAF has to be run from tfvars path.
    assert_script_run("cd $tfvars_path");
    my $rc = script_run(command_output_into_log(command=>$deploy_command, log_file=>$output_log_file), timeout => 1800);
    upload_logs($output_log_file, log_name=>'deploy_sap_system.log');
    die "Workload zone deployment failed with RC: $rc" if $rc;
    record_info('Deploy OK');
}

=head2 get_resource_group

    get_resource_group($deployment_type);

B<$deployment_type> Type of the deployment (workload_zone, sap_system, library... etc)

Returns name of the resource group according to the deployment type specified by OpenQA variable: 'SDAF_DEPLOYMENT_TYPE'.
Resource group pattern I<SDAF-OpenQA-[deployment type]-[deployment id]>

=cut

sub get_resource_group {
    my ($deployment_type) = @_;
    my @supported_types = ('workload_zone', 'sap_system', 'library', 'deployer');
    croak "Unsupported deployment type: $deployment_type\nCurrently supported ones are: @supported_types" unless
      grep(/^$deployment_type$/, @supported_types);
    my $job_id = get_current_job_id();
    my $resource_group = join('-', 'SDAF', 'OpenQA', $deployment_type, $job_id);

    return $resource_group;
}

=head2 record_os_variables

    record_os_variables([$additional_variables]);

B<additional_variables> string with additional variables delimited by space

Shows all listed OS variables using 'record_info' API call. Mostly good for troubleshooting and post fail hook.
Be sure not to expose credentials!

=cut

sub record_os_variables {
    my ($additional_variables) = @_;
    my @variables = qw(
      SAP_AUTOMATION_REPO_PATH
      CONFIG_REPO_PATH
      parameterFile
      deployer_tfstate_key
      landscape_tfstate_key
      sap_system_tfvars_file
      workload_zone_tfvars_file
      deployerState
      key_vault
      tfstate_storage_account
      env_code
      region_code
      sap_env_code
      vnet_code
      deployer_env_code
      deployer_vnet_code );
    serial_console_diag_banner('Record OS variables: start');
    @variables = (@variables, split(' ', $additional_variables)) if defined($additional_variables);
    @variables = map { "$_=" . get_os_variable($_) } @variables;
    my $output = join("\n", @variables);
    serial_console_diag_banner('Record OS variables: end');
    record_info('OS variables', $output);
}

=head2 serial_console_diag_banner

    serial_console_diag_banner($input_text);

B<input_text> string that will be printed in uppercase surrounded by '#' to make it more visible in output

Prints a simple line in serial console that marks a point in output to make it more readable. Can be used for example to
mark start and end of a function or a point in test so it is easier to find while debugging.

=cut

sub serial_console_diag_banner {
    my ($input_text) = @_;
    # make all lines equal length and fill
    my $max_length = 80;
    # leave some space for '#' symbol and dividing spaces
    my $max_string_length = $max_length - 16;
    croak 'No input text specified' unless $input_text;
    croak "Input text is longer than" . $max_string_length . "characters. Make it shorter." unless length($input_text) < $max_string_length;

    # max_length - length of the text - 4x2 dividing spaces
    my $symbol_fill = ($max_length - length($input_text) - 8) / 2;
    $input_text = '#' x $symbol_fill . uc(' ' x 4 . $input_text . ' ' x 4) . '#' x $symbol_fill;

    # do not fail on imteout, set timeout to lowest possible, do not output in main result page
    # TODO: ! testapi::script_run: DEPRECATED call of script_run() in lib/sles4sap/microsoft_sdaf.pm:565 requested by `die_on_timeout => 0` or set
    # $distri->{script_run_die_on_timeout}. Adapt the test code to work
    script_run($input_text, quiet => 1, die_on_timeout => 0, timeout => 1);
}

=head2 set_storage_account_permissions

    set_storage_account_permissions($resource_group);

B<input_text>

=cut

sub set_storage_account_permissions {
    my ($resource_group) = @_;
    my $list_accounts = script_output(join(' ', 'az', 'storage', 'account', 'list', '--resource-group',
            $resource_group, '--query="[].{name:name}"', '-o', 'tsv'));
    my @storage_accounts = split(/\s/, $list_accounts);
    my $worker_public_ip_addr = script_output('curl -s ipinfo.io/ip');
    foreach (@storage_accounts) {
        my $cmd = join(' ', 'az', 'storage', 'account', 'network-rule', 'add', '--resource-group', $resource_group,
            '--account-name', $_, '--ip-address', $worker_public_ip_addr);
        assert_script_run($cmd);
    }
}

=head2 resource_group_exists

    resource_group_exists($resource_group);

B<$resource_group> Resource group name to check

Checks if resource group exists. Function accepts only full resource name.
Croaks if command does not return true/false value.

=cut

sub resource_group_exists {
    my ($resource_group) = @_;
    croak 'Resource group not defined' unless $resource_group;

    my $cmd_out = script_output("az group exists -n $resource_group");
    die "Command 'az group exists -n $resource_group' failed:\n$cmd_out" unless grep /false|true/, $cmd_out;

    return $cmd_out;
}

=head2 delete_resource_group

    delete_resource_group($resource_group);

B<$resource_group> Resource group name to delete
Deletes resource group

=cut

sub delete_resource_group {
    my ($resource_group) = @_;
    croak 'Resource group not defined' unless $resource_group;
    my $rg_exists = resource_group_exists($resource_group);
    if ($rg_exists eq 'false') {
        record_info('WARN', "Resource group '$resource_group' does not exist, skipping cleanup");
        return;
    }
    record_info('Clean RG', "Deleting resource group: $resource_group");
    assert_script_run("az group delete -y -n $resource_group", timeout => 3600);
}

=head2 cleanup

    cleanup();

Finds all resource groups, tfvars and tfstate files related to test and deletes them.
Resource groups must be deleted in correct order (sap_system, workload...)
All deleted files are identified by job ID

=cut

sub cleanup {
    my @resource_groups = map { s/\s//gr } split("\n", qesap_az_get_resource_group(substring => 'SDAF'));
    my @rg_delete_order = ('sap_system', 'workload_zone');
    for my $group_type (@rg_delete_order) {
        my @resource_group = grep /$group_type/, @resource_groups;
        die "Multiple resource group found which match type: $group_type\nGroups" . join(', ', @resource_group) if
          (scalar @resource_group > 1);
        delete_resource_group($resource_group[0]);
    }
    assert_script_run('rm -Rf ' . deployment_dir());
}

=head2 sdaf_execute_remover

    sdaf_execute_remover($deployment_type, [retry=>$retry]);

B<$deployment_type> Type of the deployment (workload_zone, sap_system, library... etc)

Uses remover.sr script which is part of the SDAF project. This script can be used only on workload zone or sap system.
Control plane and library have separate removal script.
https://learn.microsoft.com/en-us/azure/sap/automation/bash/remover

=cut

sub sdaf_execute_remover {
    my ($deployment_type) = @_;
    my $retry_times = 3;
    croak 'Missing mandatory argument "deployment_type"' unless $deployment_type;
    # this script is used only for sap system and workload zone removal
    croak 'This function can be used only on sap system and workload zone removal' unless
      grep /^$deployment_type$/, ('sap_system', 'workload_zone');

    # SDAF uses multiple names here. sometimes it's workload zone, in this case it is sap landscape
    my $type_parameter = $deployment_type eq 'workload_zone' ? 'sap_landscape' : $deployment_type;
    my $deployment_dir = deployment_dir();
    my $remover_script = "$deployment_dir/sap-automation/deploy/scripts/remover.sh";
    my $tfvars_file;

    # I am using OS variables here since getting filename would need too many arguments to fill
    $tfvars_file = get_os_variable('sap_system_parameter_file') if $deployment_type eq 'sap_system';
    $tfvars_file = get_os_variable('workload_zone_parameter_file') if $deployment_type eq 'workload_zone';
    die 'Function failed to retrieve tfvars file via OS variable.' unless $tfvars_file;

    my ($tfvars_filename, $tfvars_path, $tfvars_suffix) = fileparse($tfvars_file);

    my $remover_cmd = join(' ', $remover_script,
        '--parameterfile', $tfvars_filename,
        '--type', $type_parameter,
        '--auto-approve');

    # SDAF has to be executed from the profile directory
    assert_script_run("cd " . $tfvars_path);

    my $rc;
    while ($retry_times) {
        record_info('SDAF destroy', "Executing SDAF remover:\n$remover_cmd");
        $rc = script_run($remover_cmd, timeout => 3600);
        last unless $rc;
        sleep 10 if $retry_times > 1;
        $retry_times --;
    }
    die 'SDAF remover script failed' if $rc;
    record_info('Destroy OK');
}

=head2 sdaf_destroy

    sdaf_destroy();

Uses remover.sr script which is part of the SDAF project. This script can be used only on workload zone or sap system.
Control plane and library have separate removal script.
https://learn.microsoft.com/en-us/azure/sap/automation/bash/remover

=cut

sub sdaf_destroy {
    my @resource_groups = map { s/\s//gr } split("\n", qesap_az_get_resource_group(substring => 'SDAF'));
    my @rg_delete_order = ('sap_system', 'workload_zone');
    for my $group_type (@rg_delete_order) {
        my @resource_group = grep /$group_type/, @resource_groups;
        die "Multiple resource group found which match type: $group_type\nGroups" . join(', ', @resource_group) if
          (scalar @resource_group > 1);
        sdaf_execute_remover($group_type);
    }
    return;
}

=head2 create_sap_parameters_file

    create_sap_parameters_file(bom_base_name=>$bom_base_name, deployer_key_vault=>$deployer_key_vault);

B<bom_base_name> Bill of materials base name. Check url in the description for details
B<deployer_key_vault> Deployer key vault. Key vault located in 'deployer' resource group that contains various credentials or ssh keys.

Creates sap-parameters.yaml file as described in :
https://learn.microsoft.com/en-us/azure/sap/automation/tutorial#get-sap-software-by-using-the-bill-of-materials
All playbooks are located in: /Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/

=cut

sub create_sap_parameters_file {
    my (%args) = @_;
    my %content = (
        bom_base_name    => $args{bom_base_name},
        deployer_kv_name => $args{deployer_key_vault},
        BOM_directory    => join('/', deployment_dir(), 'samples', 'SAP')
    );
    # File is located in the same directory as tfvars file
    my ($tfvars_filename, $workspace_path, $tfvars_suffix) = fileparse(get_os_variable('sap_system_parameter_file'));
    my $target_file = "$workspace_path/sap-parameters.yaml";
    # remove existing file if exists.
    assert_script_run("rm -Rf $target_file");

    for my $parameter (keys(%content)) {
        assert_script_run("echo '$parameter: $content{$parameter}' >> $target_file");
    }
}

=head2 az_get_ssh_key

    az_get_ssh_key(deployer_key_vault=$deployer_key_vault, ssh_key_name=$key_name, ssh_key_filename=$ssh_key_filename);

B<deployer_key_vault> Deployer key vault name
B<ssh_key_name> SSH key name residing on keyvault
B<ssh_key_filename> Target filename for SSH key

Retrieves SSH key from DEPLOYER keyvault.

=cut

sub az_get_ssh_key {
    my (%args) = @_;
    my $home = homedir();
    my $cmd = join( ' ',
        'az', 'keyvault', 'secret', 'show',
        '--vault-name', $args{deployer_key_vault},
        '--name', $args{ssh_key_name},
        '--query', 'value',
        '--output', 'tsv',  '>', "$home/.ssh/$args{ssh_key_filename}");

    my $rc = 1;
    my $retry = 3;
    while ($rc) {
        $rc = script_run($cmd);
        last if $rc;
        die 'Failed to retrieve ssh key from keyvault' unless $retry;
        $retry --;
        sleep 5;
    }
}

=head2 sdaf_prepare_ssh_keys

    sdaf_prepare_ssh_keys($deployer_key_vault);

B<deployer_key_vault> Deployer key vault name

Retrieves public and private ssh key from DEPLOYER keyvault and sets up permissions.

=cut

sub sdaf_prepare_ssh_keys {
    my ($deployer_key_vault) = @_;
    croak 'Missing mandatory argument $args{deployer_key_vault}' unless $deployer_key_vault;
    my $home = homedir();
    my $az_cmd = "az keyvault secret list --vault-name $deployer_key_vault --query [].name --output tsv";
    my %ssh_keys = (
        id_rsa       => script_output("$az_cmd | grep sshkey\$"),
        'id_rsa.pub' => script_output("$az_cmd | grep sshkey-pub\$")
    );

    assert_script_run("mkdir -p $home/.ssh");
    assert_script_run("chmod 700 $home/.ssh");
    for my $key_file (keys %ssh_keys) {
        az_get_ssh_key(
            deployer_key_vault=>$deployer_key_vault,
            ssh_key_name=>$ssh_keys{$key_file},
            ssh_key_filename=>$key_file
        );
    }
    assert_script_run("chmod 600 $home/.ssh/id_rsa");
    assert_script_run("chmod 644 $home/.ssh/id_rsa.pub");
}

=head2 sdaf_get_deployer_ip

    sdaf_get_deployer_ip($deployer_resource_group);

B<deployer_resource_group> Deployer key vault name

Retrieves public IP of the deployer VM.

=cut

sub sdaf_get_deployer_ip {
    my ($deployer_resource_group) = @_;
    croak 'Missing "deployer_resource_group" argument' unless $deployer_resource_group;

    my $vm_name = script_output("az vm list --resource-group $deployer_resource_group --query [].name --output tsv");
    my $az_query_cmd = join(' ', 'az', 'vm', 'list-ip-addresses', '--resource-group', $deployer_resource_group,
        '--name', $vm_name, '--query', '"[].virtualMachine.network.publicIpAddresses[0].ipAddress"', '-o', 'tsv');

    my $ip_addr = script_output($az_query_cmd);
    croak "Not a valid ip addr: $ip_addr" unless grep /^$RE{net}{IPv4}$/, $ip_addr;
    return $ip_addr;
}

=head2 sdaf_execute_playbook

    sdaf_execute_playbook(playbook_filename=$playbook_filename, sap_sid=>$sap_sid);

B<playbook_filename> yaml filename of the playbook to be executed
B<sap_sid> SAP system ID
B<timeout> timeout for executing playbook. Passed into asset_script_run.
B<verbosity> execute with verbosity level 0-4.

Execute playbook specified by B<playbook_filename> and record command output in separate log file.

=cut

sub sdaf_execute_playbook {
    my (%args) = @_;
    $args{sap_sid} //= get_required_var('SAP_SID');

    croak 'Missing mandatory argument "playbook_filename".' unless $args{playbook_filename};
    my $inventory_file_dir = dirname(get_os_variable('sap_system_parameter_file'));
    my $playbook_options = join(' ',
        "--inventory-file=\"$args{sap_sid}_hosts.yaml\"",
        "--private-key=$inventory_file_dir/sshkey",
        '--extra-vars="_workspace_directory=`pwd`"',
        '--extra-vars="@sap-parameters.yaml"',
        '--ssh-common-args="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=120"');
    $playbook_options = $playbook_options . '-vvvv' if $args{verbose};

    script_run("cd $inventory_file_dir");
    script_run("chmod 600 $inventory_file_dir/sshkey");

    my $output_log_file = log_dir() . "/$args{playbook_filename}" =~ s/.yaml|.yml/.log/r;
    my $playbook_file = join('/', deployment_dir(), 'sap-automation', 'deploy', 'ansible', $args{playbook_filename});
    my $playbook_cmd = join(' ', 'ansible-playbook', $playbook_options, $playbook_file);

    my $rc = script_run(command_output_into_log(command=>$playbook_cmd, log_file=>$output_log_file),
        timeout=>$args{timeout}, output=>"Executing playbook: $args{playbook_filename}");

    upload_logs($output_log_file);
    die "Execution of playbook failed with RC: $rc" if $rc;
}

1;
