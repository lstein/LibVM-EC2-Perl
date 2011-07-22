#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use File::Temp qw(tempfile);
use FindBin '$Bin';
use lib "$Bin/lib","$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

use constant TEST_COUNT => 11;
use Test::More tests => TEST_COUNT;
use EC2TestSupport;

$SIG{TERM} = $SIG{INT} = sub { exit 0 };  # run the termination

# this script tests the keypairs functions

setup_environment();

require_ok('VM::EC2');
my $ec2 = VM::EC2->new() or BAIL_OUT("Can't load VM::EC2 module");

my $natty = $ec2->describe_images(TEST_IMAGE);  # defined in t/EC2TestSupport
BAIL_OUT($ec2->error_str) unless $natty;			

my $key     = $ec2->create_key_pair("MyTestKey$$");
$key or BAIL_OUT("could not create test key");

my $finger  = $key->fingerprint;

print STDERR "Spinning up an instance (that'll be \$0.02 please)...\n";

my $i = $natty->run_instances(-max_count     => 1,
			      -user_data     => 'xyzzy',
			      -key_name      => $key,
			      -instance_type => 't1.micro');
sleep 1;
ok($i,'run_instances()');
$i->add_tags(Name=>'test instance created by VM::EC2');
$ec2->wait_for_instances($i);
is($i->current_status,'running','instance is running');
is($i->userData,'xyzzy','user data is available to instance');

# allocate or reuse an elastic IP address to test association
my @addresses = grep {!$_->instanceId} $ec2->describe_addresses();
my ($address,$deallocate_address);
if (@addresses) {
    $address = $addresses[0];
} else {
    $address = $ec2->allocate_address;
    $deallocate_address++;
}
SKIP: {
    skip "no elastic addresses available for testing",2 unless $address;
    ok($i->associate_address($address),'elastic address association');
    sleep 2;
    $i->refresh;
    ok($i->disassociate_address($address),'address disassociation');
}

# volume management
my $zone   = $i->placement;
my $volume = $ec2->create_volume(-size=>1,-availability_zone=>$zone);
ok($volume,'volume creation');

my $cnt = 0;
while ($cnt++ < 10 && $volume->current_status eq 'creating') { sleep 2 }
SKIP: {
    skip "could not create a new volume, status was ".$volume->current_status,6
	unless $volume->current_status eq 'available';
    my $a = $i->attach_volume($volume => '/dev/sdg1');
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

ok(!$i->userData('abcdefg'),"can't change user data on running instance");
ok($i->stop('wait'),'stop running instance');
is($i->current_status,'stopped','stopped instance reports correct state');
ok($i->userData('abcdefg'),"can change user data on stopped instance");
is($i->userData,'abcdefg','user data set ok');

# after stopping instance, should be console output
ok($i->console_output,'console output available');
ok($i->console_output =~ /$finger/,'Console output contains ssh key fingerprint');

exit 0;

END {
    if ($i) {
	print STDERR "Terminating $i...\n";
	$i->terminate();
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
