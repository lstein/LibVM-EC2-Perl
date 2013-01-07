#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use File::Temp qw(tempfile);
use FindBin '$Bin';
use lib "$Bin/lib","$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

use constant TEST_COUNT => 9;
use Test::More tests => TEST_COUNT;
use EC2TestSupport;

$SIG{TERM} = $SIG{INT} = sub { exit 0 };  # run the termination

use constant LC_NAME  => 'VM-EC2-Launch-test';
use constant ASG_NAME => 'VM-EC2-ASG-test';

# this script tests the autoscaling groups
my ($ec2);

require_ok('VM::EC2');
SKIP: {

skip "account information unavailable",TEST_COUNT-1 unless setup_environment();

$ec2 = VM::EC2->new(-region=>'eu-west-1') or BAIL_OUT("Can't load VM::EC2 module");

# in case it was here from a previous invocation
$ec2->delete_launch_configuration(-name => LC_NAME);
$ec2->delete_autoscaling_group(-name => ASG_NAME);

$ec2->print_error(1);

my $s = $ec2->create_launch_configuration(
    -name => LC_NAME,
    -image_id => 'ami-3a0f034e', # ubuntu 12.04 in eu-west-1
    -instance_type => 't1.micro',
    -security_groups => ['default'],
    -instance_monitoring => 0,
);
ok($s, 'create_launch_configuration');

my @l = $ec2->describe_launch_configurations();
ok(scalar @l, 'describe_launch_configurations');
is($l[0]->launch_configuration_name, LC_NAME, 'created name is correct');

$s = $ec2->create_autoscaling_group(
    -name => ASG_NAME,
    -min_size => 0,
    -max_size => 0,
    -launch_config => LC_NAME,
    -desired_capacity => 0,
    -availability_zones => [qw/eu-west-1a/],
);
ok($s, 'create_autoscaling_group');

my @a = $ec2->describe_autoscaling_groups();
ok(scalar @a, 'describe_autoscaling_group');
is($a[0]->max_size, 0, 'correct max size');

$s = $ec2->update_autoscaling_group(
    -name => ASG_NAME,
    -max_size => 1,
);
ok($s, 'update_autoscaling_group');

@a = $ec2->describe_autoscaling_groups();
is($a[0]->max_size, 1, 'correctly updated max size');
}

exit 0;

END {
    print STDERR "# cleaning up...\n";
	if ($ec2) {
        $ec2->print_error(0);
        $ec2->delete_launch_configuration(-name => LC_NAME);
        $ec2->delete_autoscaling_group(-name => ASG_NAME);
    }
};

