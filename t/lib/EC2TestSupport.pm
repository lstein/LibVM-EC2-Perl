package EC2TestSupport;
use base 'Exporter';
our @EXPORT_OK = qw(setup_environment TEST_IMAGE);
our @EXPORT    = @EXPORT_OK;

use constant TEST_IMAGE  => 'ami-4a936a23'; # Nano natty - only 1 GB in size!

sub setup_environment {
    unless ($ENV{EC2_ACCESS_KEY} && $ENV{EC2_SECRET_KEY}) {
	print STDERR <<END;
To run this test script, you must have an Amazon EC2 Access and
Secret key pair. Please define the environment variables:

  EC2_ACCESS_KEY
  EC2_SECRET_KEY

If these variables are not defined, you will be prompted for them.

Press <enter> to continue, or ^C to abort.
END
;
	scalar <>;
    }
    $ENV{EC2_ACCESS_KEY} ||= msg('Enter your EC2 access key: ');
    $ENV{EC2_SECRET_KEY} ||= msg('Enter your EC2 secret key: ');
}

sub msg {
    my $msg = shift;
    print STDERR $msg;
    chomp (my $result = <>);
    die "aborted" unless $result;
    $result;
}

1;
