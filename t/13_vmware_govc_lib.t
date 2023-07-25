use strict;
use warnings;
use Test::MockModule;
use Test::Exception;
use Test::More;
use qeaas::vmware_govc;

subtest '[govc_cmd] Die without cmd' => sub {
    dies_ok { govc_cmd() } 'Test should die without cmd argument';
};

subtest '[govc_cmd] Check command RC' => sub {
    my $vmware_govc = Test::MockModule->new('qeaas::vmware_govc', no_auto => 1);
    $vmware_govc->redefine(script_run => sub { return 1; });
    $vmware_govc->redefine(record_info => sub { note(join(' # ', 'RECORD_INFO -->', @_)); });

    # Check return values after RC to true/false conversion
    is govc_cmd('carrot.cook'), 0, 'Return 0 in case of command fails';
    $vmware_govc->redefine(script_run => sub { return 0; });
    is govc_cmd('carrot.cook'), 1, 'Return 1 in case of command pass';
};

subtest '[govc_vm_create] Check mandatory args' => sub {
    my $vmware_govc = Test::MockModule->new('qeaas::vmware_govc', no_auto => 1);
    # Return command as PASS
    $vmware_govc->redefine(script_run => sub { return 0; });
    $vmware_govc->redefine(record_info => sub { note(join(' # ', 'RECORD_INFO -->', @_)); });

    dies_ok { govc_vm_create(datastore_cluster => 'potato') } 'Fail with missing mandatory args';
    my $govc_result = govc_vm_create(datastore_cluster => 'potato',
        datastore => 'brambor',
        memsize_mb => 'zemiak',
        cpu_num => 'kartoffel',
        guest_os_id => 'patata',
        vm_network => 'papa',
        deployment_name => 'ziemniak',
        firmware => 'peruna',
        os_disk_size_gb => 'burgonya',
        vm_name => 'bandurka');
    is $govc_result, 1, 'Return 1 if all mandatory arguments are defined.';
};

subtest '[delimit_string_into_hash] Return hash' => sub {
    my $vmware_govc = Test::MockModule->new('qeaas::vmware_govc', no_auto => 1);
    $vmware_govc->redefine(record_info => sub { note(join(' # ', 'RECORD_INFO -->', @_)); });
    my $result = delimit_string_into_hash("vm_name=vm_hana1,network=some_network_name,mac=0c:fd:37:96:8c:15,cpu=8,memory=2048,os_disk_size=60");
    my %result = %$result;
    is ref($result), 'HASH', 'Result reftype should be hash';
    is $result{'vm_name'}, 'vm_hana1', "Check 'vm_name' value";
};

subtest '[govc_vm_exists] logic checks' => sub {
    my $vmware_govc = Test::MockModule->new('qeaas::vmware_govc', no_auto => 1);
    $vmware_govc->redefine(govc_cmd => sub { return 1; });
    dies_ok { govc_vm_exists() } 'Fail with missing vm name';
    is govc_vm_exists('pimiento'), 1, 'Return 1 if all mandatory arguments are defined.';

};

subtest '[govc_vm_destroy] logic checks' => sub {
    my $vmware_govc = Test::MockModule->new('qeaas::vmware_govc', no_auto => 1);
    $vmware_govc->redefine(record_info => sub { note(join(' # ', 'RECORD_INFO -->', @_)); });
    $vmware_govc->redefine(govc_vm_exists => sub { return 1; });
    $vmware_govc->redefine(script_run => sub { return 1; });
    dies_ok { govc_vm_destroy() } 'Fail with missing vm name';
    ok govc_vm_destroy('paprika'), 'Pass if vm name is defined';
};

done_testing;
