#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use FindBin '$Bin';
use lib "$Bin/lib","$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

use constant TEST_COUNT => 7;
use Test::More tests => TEST_COUNT;

# this script tests credentials file parsing

use_ok('VM::EC2',':standard');

# defaults
my $ec2 = VM::EC2->new(-print_error=>1,
                       -credentials_file=>'./t/credentials_file') or BAIL_OUT("Can't load VM::EC2 module");

is($ec2->access_key,'DEFAULT_KEY');
is($ec2->secret,'DEFAULT_SECRET');

# foo profile (shorthand)
$ec2 = VM::EC2->new(-print_error=>1,
                    -credentials_file=>'./t/credentials_file',
                    -credentials_profile=>'foo') or BAIL_OUT("Can't load VM::EC2 module");

is($ec2->access_key,'FOO_KEY');
is($ec2->secret,'FOO_SECRET');

# foo profile (longhand)
$ec2 = VM::EC2->new(-print_error=>1,
                    -credentials_file=>'./t/credentials_file',
                    -credentials_profile=>'profile foo') or BAIL_OUT("Can't load VM::EC2 module");

is($ec2->access_key,'FOO_KEY');
is($ec2->secret,'FOO_SECRET');

exit 0;
