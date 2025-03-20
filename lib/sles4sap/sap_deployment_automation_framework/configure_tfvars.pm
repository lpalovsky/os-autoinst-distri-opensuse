# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>

package sles4sap::sap_deployment_automation_framework::configure_tfvars;

use strict;
use warnings;
use testapi;
use Exporter qw(import);
use Carp qw(croak);
use utils qw(file_content_replace write_sut_file);
use sles4sap::sap_deployment_automation_framework::deployment qw(get_os_variable);
use sles4sap::sap_deployment_automation_framework::naming_conventions qw(convert_region_to_short);
use sles4sap::sap_deployment_automation_framework::deployment_connector qw(find_deployment_id);

=head1 SYNOPSIS

Library with common functions for Microsoft SDAF deployment automation that help with preparation of tfvars file.

=cut

our @EXPORT = qw(
  create_workload_tfvars
  prepare_tfvars_file
  validate_components
);

=head2 prepare_tfvars_file

    prepare_tfvars_file(deployment_type=>$deployment_type);

Downloads tfvars template files from openQA data dir and places them into correct place within SDAF repo structure.
Returns full path of the tfvars file.

=over

=item * B<$deployment_type>: Type of the deployment (workload_zone, sap_system, library... etc)

=item * B<components>: B<ARRAYREF> of components that should be installed. Check function B<validate_components> for available options.

=item * B<os_image>: It support both Azure catalog image name (':' separated string) or
                     image uri (as provided by PC get_image_id() and PUBLIC_CLOUD_IMAGE_LOCATION).
                     it is only used and mandatory when deployment_type is sap_system.

=back
=cut

sub prepare_tfvars_file {
    my (%args) = @_;
    croak 'Deployment type not specified' unless $args{deployment_type};
    croak "'os_image' argument is mandatory when deployment_type is sap_system" if (($args{deployment_type} eq 'sap_system') && !$args{os_image});
    croak "'components' argument is mandatory when deployment_type is sap_system" if (($args{deployment_type} eq 'sap_system') && !$args{components});
    my %tfvars_os_variable = (
        deployer => 'deployer_parameter_file',
        sap_system => 'sap_system_parameter_file',
        workload_zone => 'workload_zone_parameter_file',
        library => 'library_parameter_file'
    );
    croak "Unknown deployment type: $args{deployment_type}" unless $tfvars_os_variable{$args{deployment_type}};

    my %tfvars_template_url = (
        deployer => data_url('sles4sap/sap_deployment_automation_framework/DEPLOYER.tfvars'),
        sap_system => data_url('sles4sap/sap_deployment_automation_framework/SAP_SYSTEM.tfvars'),
        workload_zone => data_url('sles4sap/sap_deployment_automation_framework/WORKLOAD_ZONE.tfvars'),
        library => data_url('sles4sap/sap_deployment_automation_framework/LIBRARY.tfvars')
    );

    # fencing parameters are set up for both sap_system and workload_zone
    set_fencing_parameters();

    # Only SAP systems deployment need those parametrs to be defined
    if ($args{deployment_type} eq 'sap_system') {
        validate_components(components => $args{components});
        # Parameters required for defining DB VM image for SAP systems deployment
        set_image_parameters(os_image => $args{os_image});
        # Parameters required for Hana DB HA scenario
        set_hana_db_parameters(components => $args{components});
        # Netweaver related parameters
        set_netweaver_parameters(components => $args{components});
    }

    # replace default vnet name with shorter one to avoid naming restrictions
    set_workload_vnet_name();

    my $tfvars_file = get_os_variable($tfvars_os_variable{$args{deployment_type}});

    assert_script_run join(' ', 'curl', '-v', '-fL', $tfvars_template_url{$args{deployment_type}}, '-o', $tfvars_file);
    assert_script_run("test -f $tfvars_file");
    replace_tfvars_variables($tfvars_file);
    upload_logs($tfvars_file, log_name => "$args{deployment_type}.tfvars.txt");
    return $tfvars_file;
}

=head2 replace_tfvars_variables

    replace_tfvars_variables('/path/to/file.tfvars');

Replaces placeholder pattern B<%OPENQA_VARIABLE%> with corresponding OpenQA variable value.
If OpenQA variable is not set, placeholder is replaced with empty value.

=over

=item * B<$tfvars_file>: Full path to the tfvars file

=back
=cut

sub replace_tfvars_variables {
    my ($tfvars_file) = @_;
    croak 'Variable "$tfvars_file" undefined' unless defined($tfvars_file);
    # Regex searches for placeholders in tfvars file templates in format `%OPENQA_VARIABLE%`
    # Those will be replaced by OpenQA parameter value with the same name
    my @variables = split("\n", script_output("grep -oP \'(\?<=%)[0-9A-Z_]+(?=%)\' $tfvars_file"));
    my %to_replace = map { '%' . $_ . '%' => get_var($_, '') } @variables;
    file_content_replace($tfvars_file, %to_replace);
}

=head2 set_workload_vnet_name

    set_workload_vnet_name([job_id=>'123456']);

Returns VNET name used for workload zone and sap systems resources. VNET name must be unique for each landscape,
therefore it contains test ID as an identifier.

=over

=item * B<$job_id>: Specify job id to be used. Default: current deployment job ID

=back
=cut

sub set_workload_vnet_name {
    my (%args) = @_;
    $args{job_id} //= find_deployment_id();
    die('no deployment ID found') unless $args{job_id};
    # Try to keep vnet name as short as possible. Later this is used in the name for the peering in a format:
    # deployer-vnet_to_workload-vnet
    # if it is too long you might hit name length limit and test ID gets clipped.
    set_var('SDAF_SUT_VNET_NAME', 'OpenQA-' . $args{job_id});
}

=head2 set_image_parameters

    set_image_parameters(image_id => 'aaa:bbb:ccc:ddd');

Sets OpenQA parameters required for replacing tfvars template variables for database VM image.

=over

=item * B<os_image>: It support both Azure catalog image name (':' separated string) or
                     image uri (as provided by PC get_image_id() and PUBLIC_CLOUD_IMAGE_LOCATION).
                     it is only used and mandatory when deployment_type is sap_system.

=back
=cut

sub set_image_parameters {
    my (%args) = @_;

    my %params;

    # This regex targets the general Azure Gallery image naming patterns,
    # excluding part of the name that are related to PC library.
    if ($args{os_image} =~ /^\/subscriptions\/.*\/galleries\/.*/) {
        $params{SDAF_SOURCE_IMAGE_ID} = $args{os_image};
        $params{SDAF_IMAGE_TYPE} = 'custom';
    }
    else {
        # Parse image ID supplied by OpenQA parameter 'PUBLIC_CLOUD_IMAGE_ID'
        my @variable_names = qw(SDAF_IMAGE_PUBLISHER SDAF_IMAGE_OFFER SDAF_IMAGE_SKU SDAF_IMAGE_VERSION);

        # This maps a variable name from array @variable names to value from delimited 'PUBLIC_CLOUD_IMAGE_ID' parameter
        # Order is important here
        @params{@variable_names} = split(':', $args{os_image});
        $params{SDAF_IMAGE_TYPE} = 'marketplace';
    }

    # Add all remaining parameters with static values
    $params{SDAF_IMAGE_OS_TYPE} = 'LINUX';    # this can be modified in case of non linux images

    foreach (keys(%params)) {
        set_var($_, $params{$_});
    }
}

=head2 set_hana_db_parameters

    set_hana_db_parameters(components=>['db_install', 'db_ha']);

Sets tfvars Database HA parameters according to scenario defined by B<$args{components}>.

=over

=item * B<components>: B<ARRAYREF> of components that should be installed. Check function B<validate_components> for available options.

=back

=cut

sub set_hana_db_parameters {
    my (%args) = @_;
    # Enable HA cluster
    set_var('SDAF_HANA_HA_SETUP', grep(/ha/, @{$args{components}}) ? 'true' : 'false');
}

=head2 set_fencing_parameters

    set_fencing_parameters();

Sets tfvars HA fencing related parameters according to scenario defined OpenQA settings.

=cut

sub set_fencing_parameters {
    # Fencing mechanism AFA (Azure fencing agent - MSI), ASD (Azure shared disk - SBD), ISCSI (iSCSI based SBD fencing)
    # Default value: 'msi' - AFA - Azure fencing agent (MSI)
    my $fencing_type = get_var('SDAF_FENCING_MECHANISM', 'msi');
    record_info("FENCING: $fencing_type", "Fencing mechanism set to '$fencing_type'");

    # Ensures consistent OpenQA setting names across all types deployment solutions.
    # msi = MSI based fencing
    # sbd = iSCSI based SBD devices
    # asd = Azure shared disk as SBD device
    my %supported_fencing_values = (msi => 'AFA', sbd => 'ISCSI', asd => 'ASD');
    die "Fencing type '$fencing_type' is not supported" unless grep /^$fencing_type$/, keys(%supported_fencing_values);

    # This is dumb and will be improved in TEAM-10145
    set_var('SDAF_FENCING_TYPE', $supported_fencing_values{$fencing_type});
    # Setup ISCSI deployment
    if (get_var('SDAF_FENCING_TYPE') =~ /ISCSI/) {
        # Set default value for iSCSI device count
        set_var('SDAF_ISCSI_DEVICE_COUNT', get_var('SDAF_ISCSI_DEVICE_COUNT', '1'));
    }
    else {
        # Disable iSCSI deployment if not needed
        set_var('SDAF_ISCSI_DEVICE_COUNT', '0');
    }
}

=head2 set_netweaver_parameters

    set_netweaver_parameters(components=>['db_install', 'db_ha']);

Sets tfvars parameters related to SAP Netweaver according to scenario defined by B<$args{components}>.

=over

=item * B<components>: B<ARRAYREF> of components that should be installed. Check function B<validate_components> for available options.

=back

=cut

sub set_netweaver_parameters {
    my (%args) = @_;
    # Default values - everything turned off
    my %parameters = (
        # All nw_* scenarios require ASCS deployment
        SDAF_ASCS_SERVER => grep(/nw/, @{$args{components}}) ? 1 : 0,
        # So far 1x PAS and 1x AAS should be enough for coverage
        SDAF_APP_SERVER_COUNT => grep(/pas/, @{$args{components}}) + grep(/aas/, @{$args{components}}),
        SDAF_ERS_SERVER => grep(/ensa/, @{$args{components}}) ? 'true' : 'false'
    );

    for my $parameter (keys(%parameters)) {
        set_var($parameter, $parameters{$parameter});
    }
}

=head2 validate_components

    validate_components(components=>['db_install', 'db_ha']);

Checks if components list is valid and supported by code. Croaks if not.
Currently supported components are:

=over

=item * B<components>: B<ARRAYREF> of components that should be installed.
    Supported values:
        db_install : Basic DB installation
        db_ha : Database HA setup
        nw_pas : Installs primary application server (PAS)
        nw_aas : Installs additional application server (AAS)
        nw_ensa : Installs enqueue replication server (ERS)

=back

=cut

sub validate_components {
    my (%args) = @_;
    croak '$args{components} must be an ARRAYREF' unless ref($args{components}) eq 'ARRAY';

    my %valid_components = ('db_install' => 'Basic DB installation.',
        db_ha => 'db_ha : Database HA setup',
        nw_pas => 'db_pas : Installs primary application server (PAS)',
        nw_aas => 'nw_aas : Installs additional application server (AAS)',
        nw_ensa => 'nw_ensa : Installs enqueue replication server (ERS)');

    for my $component (@{$args{components}}) {
        croak "Unsupported component: '$component'\nSupported values:\n" . join("\n", values(%valid_components))
          unless grep /^$component$/, keys(%valid_components);
    }
    # need to return positive value for unit test to work properly
    return 1;
}

=head2 create_workload_tfvars

    create_workload_tfvars(components=>['db_install', 'db_ha']);



=over

=item * B<environment>: SDAF environment. Can be supplied using OpenQA setting 'SDAF_ENV_CODE'

=item * B<location>: Public cloud location. Can be supplied using OpenQA setting 'PUBLIC_CLOUD_REGION'

=item * B<components>: B<ARRAYREF> of components that should be installed.
    Supported values:
        db_install : Basic DB installation
        db_ha : Database HA setup
        nw_pas : Installs primary application server (PAS)
        nw_aas : Installs additional application server (AAS)
        nw_ensa : Installs enqueue replication server (ERS)

=back

=cut

sub create_workload_tfvars {
    my (%args) = @_;
    $args{environment} //= get_required_var('SDAF_ENV_CODE');
    $args{location} //= get_required_var('PUBLIC_CLOUD_REGION');
    $args{resource_group} //= get_required_var('SDAF_RESOURCE_GROUP');
    $args{job_id} //= find_deployment_id();

    for my $arg ('job_id', 'network_data', 'workload_vnet_code') {
        croak("Missing mandatory argument \$args{$arg}") unless $args{$arg};
    }

    my %tfvars_data;
    $tfvars_data{file_header} = "### File was generated by OpenQA automation according to template:\n### https://github.com/Azure/SAP-automation-samples/blob/main/Terraform/WORKSPACES/SYSTEM/LAB-SECE-SAP04-L00/LAB-SECE-SAP04-L00.tfvars\n";
    $tfvars_data{env_definitions} = env_definitions(
        environment => $args{environment}, location => $args{location}, resource_group=>$args{resource_group});
    $tfvars_data{workload_networking} = workload_networking(
        environment => $args{environment},
        location => $args{location},
        job_id => $args{job_id}
    );
    $tfvars_data{subnet_definition} = subnet_definition(network_data => $args{network_data});
    $tfvars_data{nat_configuration} = nat_configuration(
        environment => $args{environment},
        sdaf_region => convert_region_to_short($args{location}),
        workload_vnet_code => $args{workload_vnet_code});
    my $tfvars_file = get_os_variable('workload_zone_parameter_file');

    write_tfvars_file(tfvars_data => \%tfvars_data, tfvars_file => $tfvars_file);
    upload_logs($tfvars_file, log_name => 'workload_zone.tfvars.txt');
}

=head2 write_tfvars_file

    write_tfvars_file();

Writes $args{tfvars_data} into target tfvars file located on SUT.
$args{tfvars_data} is a HASHREF containg individual sections that should be included in final tfvars content.
Example:
{
file_header => "Comment placed on top of the tfvars file",
env_definitions => {header => 'Comment placed on top of a section',
    tfvars_variable = 'value', tfvars_variable_2 = 'value2'},
workload_networking => {header => 'Comment placed on top of a section',
    tfvars_variable_3 = 'value3', tfvars_variable_4 = 'value4'},
}

=over

=item * B<tfvars_file>: Target tfvars file location

=item * B<tfvars_data>: Target tfvars file data - Must be a HASHREF

=back

=cut

sub write_tfvars_file {
    my (%args) = @_;
    for my $arg ('tfvars_data', 'tfvars_file') {
        croak "Missing mandatory argument \$args{$arg}" unless $args{$arg};
    }
    croak 'Argument \$args{tfvars_data} must be a HASHREF' unless ref($args{tfvars_data});

    my $file_contents = $args{tfvars_data}->{file_header};
    $file_contents .= compile_tfvars_section($args{tfvars_data}->{env_definitions});
    $file_contents .= compile_tfvars_section($args{tfvars_data}->{workload_networking});
    $file_contents .= compile_tfvars_section($args{tfvars_data}->{subnet_definition});
    $file_contents .= compile_tfvars_section($args{tfvars_data}->{nat_configuration});
    $file_contents .= compile_tfvars_section($args{tfvars_data}->{iscsi_devices});
    write_sut_file($args{tfvars_file}, $file_contents);
}

=head2 compile_tfvars_section

    compile_tfvars_section($section_data);

=over

=item * B<$section_data>:

=back

=cut

sub compile_tfvars_section {
    my ($section_data) = @_;
    my $header = $section_data->{header};
    delete $section_data->{header};
    return (join("\n", "\n\n$header", map { "$_ = $section_data->{$_}" } keys(%{$section_data})));
}

=head2 env_definitions

    env_definitions();

Returns tfvars environment definitions section in hash format.
Example: {environment : 'LAB', location : 'swedencentral'}

=over

=item * B<environment>: SDAF environment

=item * B<location>: Public cloud location

=back

=cut

sub env_definitions {
    my (%args) = @_;
    for my $arg ('environment', 'location') {
        croak "Missing mandatory argument \$args{$arg}" unless $args{$arg};
    }
    my %result = (
        header              => '### Environment definitions ###',
        resource_group      => "\"$args{resource_group}\"",
        evnironment         => "\"$args{environment}\"",
        location            => "\"$args{location}\"",
        automation_username => '"azureadm"',
        # enable_purge_control_for_keyvaults is an optional parameter that czan be used to disable the purge protection fro Azure keyvaults
        enable_purge_control_for_keyvaults => 'false',
        # enable_rbac_authorization_for_keyvault Controls the access policy model for the workload zone keyvault.
        enable_rbac_authorization_for_keyvault => 'false'
    );

    return (\%result);
}

=head2 workload_networking

    workload_networking();

Returns tfvars environment definitions section in hash format.
Example: {environment : 'LAB', location : 'swedencentral'}

=over

=item * B<environment>: SDAF environment

=item * B<location>: Public cloud location

=item * B<job_id>: OpenQA job ID which the deployment belongs to

=item * B<network_address_space>: Network address space reserved for all subnets

=back

=cut

sub workload_networking {
    my (%args) = @_;
    for my $arg ('environment', 'location', 'job_id') {
        croak "Missing mandatory argument \$args{$arg}" unless $args{$arg};
    }
    my %result = (
        header => '### Networking ###',
        evnironment => "\"$args{environment}\"",
        location => "\"$args{location}\"",
        # Workload VNET name - keep as short as possible as resource naming has limitations
        network_name => "\"OpenQA-$args{job_id}\"",
        # disable private endpoints for key vaults and storage accounts
        use_private_endpoint => 'false',
        # disable service endpoints for key vaults and storage accounts
        use_service_endpoint => 'false',
        # Peering between control plane and workload zone (enable connection from deployer VM to SUT network)
        peer_with_control_plane_vnet => 'true',
        # Enables firewall for keyvaults and storage - only SUT subnets will be able to access it
        enable_firewall_for_keyvaults_and_storage => 'true',
        public_network_access_enabled => 'true',
        # Disable resource delete lock for cleanup to work properly
        place_delete_lock_on_resources => 'false',
        # Defines if a custom dns solution is used
        use_custom_dns_a_registration => 'false',
        # Defines if the Virtual network for the Virtual machines is registered with DNS
        # This also controls the creation of DNS entries for the load balancers
        register_virtual_network_to_dns => 'true',
        # If defined provides the DNS label for the Virtual Network
        dns_label=>'"openqa.net"',
        # Boolean value indicating if storage accounts and key vaults should be registered to the corresponding dns zones
        register_storage_accounts_keyvaults_with_dns => 'false'
    );
    return \%result;
}

=head2 nat_configuration

    nat_configuration();

Returns tfvars environment definitions section in hash format.
Example: {environment : 'LAB', location : 'swedencentral'}

=over

=item * B<environment>: SDAF environment

=item * B<sdaf_region>: Public cloud location

=item * B<deployer_vnet_code>: Public cloud location

=back

=cut

sub nat_configuration {
    my (%args) = @_;
    for my $arg ('environment', 'sdaf_region', 'workload_vnet_code') {
        croak "Missing mandatory argument \$args{$arg}" unless $args{$arg};
    }
    my %result = (
        header => '###  NAT Configuration ###',
        deploy_nat_gateway => 'true',
        nat_gateway_name => "\"$args{environment}-$args{sdaf_region}-$args{workload_vnet_code}-NG_0001\"",
        nat_gateway_public_ip_tags => '{"ipTagType": "OpenQA-SDAF-automation", "tag": "OpenQA-SDAF-automation"}'
    );

    return (\%result);
}

=head2 subnet_definition

    subnet_definition();

Returns tfvars environment definitions section in hash format.
Example: {environment : 'LAB', location : 'swedencentral'}

=over

=item * B<environment>: SDAF environment

=item * B<location>: Public cloud location

=back

=cut

sub subnet_definition {
    my (%args) = @_;
    croak 'Missing mandatory argument $args{network_data}' unless $args{network_data};
    my %result = (
        header => '###  Subnet definitions ###',
        network_address_space => $args{network_data}->{network_address_space},
        iscsi_subnet_address_prefix => $args{network_data}->{iscsi_subnet_address_prefix},
        web_subnet_address_prefix => $args{network_data}->{web_subnet_address_prefix},
        admin_subnet_address_prefix => $args{network_data}->{admin_subnet_address_prefix},
        db_subnet_address_prefix => $args{network_data}->{db_subnet_address_prefix},
        app_subnet_address_prefix => $args{network_data}->{app_subnet_address_prefix}
    );

    return (\%result);
}

=head2 iscsi_devices

    iscsi_devices();

Returns tfvars environment definitions section in hash format.
Example: {environment : 'LAB', location : 'swedencentral'}

=over

=item * B<environment>: SDAF environment

=item * B<location>: Public cloud location

=back

=cut

sub iscsi_devices {
    # Fencing mechanism AFA (Azure fencing agent - MSI), ASD (Azure shared disk - SBD), ISCSI (iSCSI based SBD fencing)
    # Default value: 'msi' - AFA - Azure fencing agent (MSI)
    my $fencing_type = get_var('SDAF_FENCING_MECHANISM', 'msi');

    # Ensures consistent OpenQA setting names across all types deployment solutions.
    # msi = MSI based fencing
    # sbd = iSCSI based SBD devices
    # asd = Azure shared disk as SBD device
    my %supported_fencing_values = (msi => 'AFA', sbd => 'ISCSI', asd => 'ASD');
    die "Fencing type '$fencing_type' is not supported" unless grep /^$fencing_type$/, keys(%supported_fencing_values);

    my %result = (header => '###  ISCSI Devices ###');
    if ($fencing_type eq 'sbd') {
        # Number of iSCSI devices to be created
        $result{iscsi_count} = '"' . get_var('SDAF_ISCSI_DEVICE_COUNT', 3) . '"';
        # Size of iSCSI Virtual Machines to be created
        $result{iscsi_size} = '"Standard_D2s_v3"';
        # Defines if the iSCSI devices use DHCP
        $result{iscsi_useDHCP} = 'true';
        # Defines the Virtual Machine authentication type for the iSCSI device
        $result{iscsi_authentication_type} = '"key"';
        # Defines the username for the iSCSI devices
        $result{iscsi_authentication_username} = '"azureadm"';
        # Defines the Availability zones for the iSCSI devices
        $result{iscsi_vm_zones} = '["1", "2", "3"]';
    }
    else {
        # Do not deploy ISCSI if not needed
        $result{iscsi_count} = '"0"';
    }
    return (\%result);
}