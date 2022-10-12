# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Deploy public cloud infrastructure using terraform.

use base 'sles4sap_publiccloud_basetest';
use strict;
use warnings;
use testapi;
use Mojo::File 'path';
use publiccloud::utils;
use qesapdeployment;
use Data::Dumper;

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

=head2 set_default_values

    Check certain openQA variables and set default values if not existing.
    Detects HANA/HA scenario, sets values accordingly and checks for possible conflicts.

=cut
sub set_default_values {
    set_var("QESAP_HANA_HA_ENABLED", get_var('QESAP_HANA_HA_ENABLED', "false"));
    set_var("NODE_COUNT", get_var('NODE_COUNT', 1));
    set_var("QESAP_VM_SIZE", get_var('QESAP_VM_SIZE', "Standard_E4s_v3"));
    set_var("USE_SAPCONF", get_var("USE_SAPCONF", "true"));
    set_var("HANA_OS_MAJOR_VERSION",get_var("HANA_OS_MAJOR_VERSION", (split("-", get_var("VERSION")))[0]));

    # Cluster related setup
    my $ha_enabled = get_var("QESAP_HANA_HA_ENABLED") =~ /False|false|0/ ? 0 : 1;
    if ($ha_enabled eq 1 && get_var("NODE_COUNT") > 1){
        # set fencing to native if no ha cluster is set to avoid deploying ISCSI server
        record_info("HA scenario", "Parameters are set for HA/HANA scenario.");
        set_var("FENCING_MECHANISM", "native");
    }

    # Cluster needs at least 2 nodes
    die("HA cluster needs at least 2 nodes. Check 'NODE_COUNT' parameter.") if $ha_enabled eq 1 && get_var("NODE_COUNT") <= 1;
}

=head2 create_ansible_playbook_list

    Detects HANA/HA scenario from openQA variables and creates "ansible: create:" section in config.yaml file.

=cut
sub create_playbook_section {
    # Cluster related setup
    my $ha_enabled = get_var("QESAP_HANA_HA_ENABLED") =~ /False|false|0/ ? 0 : 1;
    my @playbook_list;
    my @hana_playbook_list = (
        "pre-cluster.yaml",
        "sap-hana-preconfigure.yaml -e use_sapconf=" . get_var("USE_SAPCONF"),
        "cluster_sbd_prep.yaml",
        "sap-hana-storage.yaml",
        "sap-hana-download-media.yaml",
        "sap-hana-install.yaml",
        "sap-hana-system-replication.yaml",
        "sap-hana-system-replication-hooks.yaml",
        "sap-hana-cluster.yaml"
    );
    my $registration = "registration.yaml -e reg_code=" . get_var("SCC_REGCODE_SLES4SAP") . " -e email_address=''";

    # Add registration module (later it can be controlled by variable in case registration happens earlier)
    push(@playbook_list, $registration);
    if ( $ha_enabled == 1 ){
        push(@playbook_list, @hana_playbook_list);
    }
    return(\@playbook_list);
}

=head2 create_ansible_playbook_list

    Detects HANA/HA scenario from openQA variables and creates "ansible: create:" section in config.yaml file.

=cut
sub create_hana_vars_section {
    # Cluster related setup
    my $ha_enabled = get_var("QESAP_HANA_HA_ENABLED") =~ /False|false|0/ ? 0 : 1;
    my %hana_vars;
    if ($ha_enabled == 1) {
        $hana_vars{sap_hana_install_software_directory} = get_var("HANA_MEDIA", "/hana/shared/install");
        $hana_vars{sap_hana_install_master_password} = get_required_var("_HANA_MASTER_PW");
        $hana_vars{sap_hana_install_sid} = get_var("INSTANCE_SID", "HA1");
        $hana_vars{sap_hana_install_instance_number} = get_var("INSTANCE_ID", "00");
        $hana_vars{sap_domain} = get_var("SAP_DOMAIN", "qesap.example.com");
        $hana_vars{primary_site} = get_var("", "Site_A");
        $hana_vars{secondary_site} = get_var("", "Site_B");
    }
    return(\%hana_vars);
}

sub run {
    my ($self, $run_args) = @_;
    $self->select_serial_terminal;
    my $provider = $self->provider_factory();

    # Collect OpenQA variables and default values
    set_var("SLE_IMAGE" ,$provider->get_image_id());
    set_default_values();
    my $ansible_playbooks = create_playbook_section();
    my $ansible_hana_vars = create_hana_vars_section();
    if ($ansible_hana_vars){record_info("HANA vars ok")};
    return;
    # Prepare QESAP deplyoment
    qesap_prepare_env(openqa_variables=>qesap_get_variables(), provider => lc(get_required_var('PUBLIC_CLOUD_PROVIDER')));
    qesap_create_ansible_section(ansible_section=>'create', section_content=>$ansible_playbooks) if @$ansible_playbooks;
    qesap_create_ansible_section(ansible_section=>'hana_vars', section_content=>$ansible_hana_vars) if %$ansible_hana_vars;

    # Regenerate config files (This workaround will be replaced with full yaml generator)
    qesap_prepare_env(openqa_variables=>qesap_get_variables(), provider => lc(get_required_var('PUBLIC_CLOUD_PROVIDER')), only_configure=>1);
    # This tells "create_instances" to skip the deployment setup related to old ha-sap-terraform-deployment project
    $provider->{terraform_env_prepared} = 1;
    my @instances = $provider->create_instances(check_connectivity => 0);
    my @instances_export;
    # Upload inventory file for debug
    #my $inventory_file = qesap_get_inventory(provider=>get_required_var('PUBLIC_CLOUD_PROVIDER'));
    #upload_logs($inventory_file, log_name=>"ansible_inventory.txt");

    foreach my $instance (@instances) {
        $self->{my_instance} = $instance;
        push(@instances_export, $instance);
        $instance->wait_for_ssh();
        # Does not fail for some reason.
        #$instance->ssh_script_run(cmd=>'hostnamectl hostname');
    }

    $self->{instances} = $run_args->{instances} = \@instances_export;
    record_info("Deployment OK",);
    return 1;
}

1;
