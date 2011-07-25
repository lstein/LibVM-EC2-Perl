#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use File::Temp qw(tempfile);
use FindBin '$Bin';
use lib "$Bin/lib","$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

use constant TEST_COUNT => 19;
use Test::More tests => TEST_COUNT;
use EC2TestSupport;

$SIG{TERM} = $SIG{INT} = sub { exit 0 };  # run the termination

# this script exercises instances and volumes
my($ec2, $instance,$key,$address,$deallocate_address,$volume);

SKIP: {

skip "instance tests declined",TEST_COUNT unless confirm_payment();
setup_environment();

print STDERR "Spinning up an instance (that'll be \$0.02 please)...\n";

require_ok('VM::EC2');
$ec2 = VM::EC2->new() or BAIL_OUT("Can't load VM::EC2 module");

my $natty = $ec2->describe_images(TEST_IMAGE);  # defined in t/EC2TestSupport
BAIL_OUT($ec2->error_str) unless $natty;			

$key     = $ec2->create_key_pair("MyTestKey$$");
$key or BAIL_OUT("could not create test key");

my $finger  = $key->fingerprint;

$instance = $natty->run_instances(-max_count     => 1,
				  -user_data     => 'xyzzy',
				  -key_name      => $key,
				  -instance_type => 't1.micro');
sleep 1;
ok($instance,'run_instances()');
$instance->add_tags(Name=>'test instance created by VM::EC2');
$ec2->wait_for_instances($instance);
is($instance->current_status,'running','instance is running');
is($instance->userData,'xyzzy','user data is available to instance');

# allocate or reuse an elastic IP address to test association
my @addresses = grep {!$_->instanceId} $ec2->describe_addresses();
if (@addresses) {
    $address = $addresses[0];
} else {
    $address = $ec2->allocate_address;
    $deallocate_address++;
}
SKIP: {
    skip "no elastic addresses available for testing",2 unless $address;
    ok($instance->associate_address($address),'elastic address association');
    sleep 2;
    $instance->refresh;
    ok($instance->disassociate_address($address),'address disassociation');
}

# volume management
my $zone   = $instance->placement;
$volume = $ec2->create_volume(-size=>1,-availability_zone=>$zone);
ok($volume,'volume creation');

my $cnt = 0;
while ($cnt++ < 10 && $volume->current_status eq 'creating') { sleep 2 }
SKIP: {
    skip "could not create a new volume, status was ".$volume->current_status,6
	unless $volume->current_status eq 'available';
    my $a = $instance->attach_volume($volume => '/dev/sdg1');
    ok($a,'attach()');
    $cnt = 0;
    while ($cnt++ < 10 && $a->current_status ne 'attached') { sleep 2 }
    is($a->current_status,'attached','attach volume to instance');
    is($volume->current_status,'in-use','volume reports correct attachment');
    ok($volume->detach,'detach volume from instance');
    $cnt = 0;
    while ($cnt++ < 20 && $volume->current_status ne 'available') { sleep 2 }
    is($volume->current_status,'available','detached volume becomes available');
    ok($ec2->delete_volume($volume),'delete volume');
    undef $volume;
}

ok(!$instance->userData('abcdefg'),"don't change user data on running instance");
ok($instance->stop('wait'),'stop running instance');
is($instance->current_status,'stopped','stopped instance reports correct state');
ok($instance->userData('abcdefg'),"can change user data on stopped instance");
is($instance->userData,'abcdefg','user data set ok');

# after stopping instance, should be console output
ok($instance->console_output,'console output available');

}  # SKIP


exit 0;

END {
    if ($instance) {
	print STDERR "Terminating $instance...\n";
	$instance->terminate();
    }
    if ($key) {
	print STDERR "Removing test key...\n";
	$ec2->delete_key_pair($key);
    }
    if ($address && $deallocate_address) {
	print STDERR "Deallocating $address...\n";
	$ec2->release_address($address);
    }
    if ($volume) {
	print STDERR "Deleting volume...\n";
	$volume->disassociate();
	$ec2->delete_volume($volume);
    }
}

sub confirm_payment {
    print STDERR <<END;
This test will launch one "micro" instance under your Amazon account
and then terminate it, incurring a one hour runtime charge. This will
incur a charge of \$0.02 (as of July 2011), which may be covered under 
the AWS free tier.
END
;
    print STDERR "Do you want to proceed? [Y/n] ";
    chomp(my $input = <>);
    $input ||= 'y';
    return $input =~ /^[yY]/;
}
