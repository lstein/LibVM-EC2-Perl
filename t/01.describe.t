#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use File::Temp qw(tempfile);
use FindBin '$Bin';
use constant TEST_COUNT => 1;

use lib "$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

unless ($ENV{EC2_ACCESS_KEY} && $ENV{EC2_SECRET_KEY}) {
       print STDERR <<END;
To run this test script, you must have an Amazon EC2 Access and
Secret key pair. Please define the environment variables:

  EC2_ACCESS_KEY
  EC2_SECRET_KEY

If these variables are not defined, you will be prompted for them.

Press <enter> to continue, or ^C to abort.
END
scalar <>;
}

BEGIN {
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  use Test;
  plan test => TEST_COUNT;
}

$ENV{EC2_ACCESS_KEY} ||= msg('Enter your EC2 access key: ');
$ENV{EC2_SECRET_KEY} ||= msg('Enter your EC2 secret key: ');

use MyAWS;

{
  my $aws = MyAWS->new();
  ok($aws);
}

exit 0;

sub msg {
    my $msg = shift;
    print STDERR $msg;
    chomp (my $result = <>);
    die "aborted" unless $result;
    $result;
}