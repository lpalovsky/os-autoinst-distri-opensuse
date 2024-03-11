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
  sdaf_prepare_ssh_keys
  sdaf_get_deployer_ip
);

=head2 az_login

 az_login();

Azure login using SPN credentials defined by secret OpenQA parameters:

B<_SECRET_AZURE_SPN_APPLICATION_ID>

B<_SECRET_AZURE_SPN_APP_PASSWORD>

B<_SECRET_AZURE_ARM_TENANT_ID>

Returns 'subscription ID' on success.

=cut

sub az_login {
    # Note: For login I cannot use standard PC library, because it gives credentials which are missing permissions
    my $app_id = get_required_var('_SECRET_AZURE_SDAF_APP_ID');
    my $app_secret = get_required_var('_SECRET_AZURE_SDAF_APP_PASSWORD');
    my $tenant_id = get_required_var('_SECRET_AZURE_SDAF_TENANT_ID');
    my @secret_variables = (
        "export ARM_CLIENT_ID=$app_id",
        "export ARM_CLIENT_SECRET=$app_secret",
        "export ARM_TENANT_ID=$tenant_id"
    );

    write_bashrc_variables(@secret_variables);

    my $login_cmd = 'while ! az login --service-principal -u ${ARM_CLIENT_ID} -p ${ARM_CLIENT_SECRET} -t ${ARM_TENANT_ID}; do sleep 10; done';
    assert_script_run($login_cmd, timeout => 120);

    my $subscription_id = script_output('az account show -o tsv --query id');
    return ($subscription_id);
}

=head2 write_bashrc_variables

    write_bashrc_variables(@variable list);

=cut

sub write_bashrc_variables {
    my (@variables) = @_;

    write_sut_file('/root/az_variables', join("\n", "\n", @variables));
    assert_script_run('cat /root/az_variables >> /root/.bashrc', quiet => 1);
    assert_script_run('source /root/.bashrc', quiet => 1);
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
    my $cmd = join(' ',
        'az', 'keyvault', 'secret', 'show',
        '--vault-name', $args{deployer_key_vault},
        '--name', $args{ssh_key_name},
        '--query', 'value',
        '--output', 'tsv', '>', "/root/.ssh/$args{ssh_key_filename}");

    my $rc = 1;
    my $retry = 3;
    while ($rc) {
        $rc = script_run($cmd);
        last if $rc;
        croak 'Failed to retrieve ssh key from keyvault' unless $retry;
        $retry--;
        sleep 5;
    }
}

=head2 sdaf_prepare_ssh_keys

    sdaf_prepare_ssh_keys(deployer_key_vault=$deployer_key_vault, ssh_key_name=$key_name);

B<deployer_key_vault> Deployer key vault name

B<ssh_key_name> SSH key name residing on keyvault

Retrieves public and private ssh key from DEPLOYER keyvault and sets up permissions.

=cut

sub sdaf_prepare_ssh_keys {
    my (%args) = @_;
    croak 'Missing mandatory argument $args{deployer_key_vault}' unless $args{deployer_key_vault};

    my $az_cmd = "az keyvault secret list --vault-name $args{deployer_key_vault} --query [].name --output tsv";
    my %ssh_keys = (
        id_rsa => script_output("$az_cmd | grep sshkey\$"),
        'id_rsa.pub' => script_output("$az_cmd | grep sshkey-pub\$")
    );

    assert_script_run('mkdir -p /root/.ssh');
    assert_script_run('chmod 700 /root/.ssh');
    for my $key_file (keys %ssh_keys) {
        az_get_ssh_key(
            deployer_key_vault => $args{deployer_key_vault},
            ssh_key_name => $ssh_keys{$key_file},
            ssh_key_filename => $key_file
        );
    }
    assert_script_run("chmod 600 /root/.ssh/id_rsa");
    assert_script_run("chmod 644 /root/.ssh/id_rsa.pub");
}

=head2 sdaf_get_deployer_ip

    sdaf_get_deployer_ip(deployer_resource_group=>$deployer_resource_group);

B<deployer_resource_group> Deployer key vault name

Retrieves public IP of the deployer VM.

=cut

sub sdaf_get_deployer_ip {
    my (%args) = @_;
    croak 'Missing "deployer_resource_group" argument' unless $args{deployer_resource_group};

    my $vm_name = script_output("az vm list --resource-group $args{deployer_resource_group} --query [].name --output tsv");
    my $az_query_cmd = join(' ', 'az', 'vm', 'list-ip-addresses', '--resource-group', $args{deployer_resource_group},
        '--name', $vm_name, '--query', '"[].virtualMachine.network.publicIpAddresses[0].ipAddress"', '-o', 'tsv');

    my $ip_addr = script_output($az_query_cmd);
    croak "Not a valid ip addr: $ip_addr" unless grep /^$RE{net}{IPv4}$/, $ip_addr;
    return $ip_addr;
}

1;