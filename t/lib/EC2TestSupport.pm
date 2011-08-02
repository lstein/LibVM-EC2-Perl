package EC2TestSupport;
use base 'Exporter';
use POSIX 'setsid','setpgid','tcsetpgrp';
our @EXPORT_OK = qw(setup_environment reset_declined reset_cache TEST_IMAGE);
our @EXPORT    = @EXPORT_OK;

use constant TEST_IMAGE  => 'ami-4a936a23'; # Nano natty - only 1 GB in size!

sub reset_declined { unlink '.declined' }
sub reset_cache    { unlink '.credentials' }

sub setup_environment {
    return if -e '.declined';
    unless ($ENV{EC2_ACCESS_KEY} && $ENV{EC2_SECRET_KEY}) {
	read_from_cache() && return 1;
	eval {
	    local $SIG{INT}  = sub {warn "Interrupted!\n";die "interrupted" };
	    local $SIG{ALRM} = sub {warn "Timeout!\n"    ;die "timeout"};
	    print STDERR <<END;
# To run this test script, you must have an Amazon EC2 Access and
# Secret key pair. Please define the environment variables:
#
#   EC2_ACCESS_KEY
#   EC2_SECRET_KEY
#
# If these variables are not defined, you will be prompted for them.
# Hit return without entering any values to skip tests.
# (These prompts will timeout automatically in 10s.)
END
;
	    $ENV{EC2_ACCESS_KEY} ||= msg('Enter your EC2 access key: ') or die "aborted";
	    $ENV{EC2_SECRET_KEY} ||= msg('Enter your EC2 secret key: ') or die "aborted";
	};
	alarm(0);
	if ($@ =~ /interrupted|timeout|aborted/) {
	    open my $f,'>.declined';
	    close $f;
	    return;
	}
	write_to_cache();
    }
    1;
}

sub write_to_cache {
    open my $f,'>.credentials';
    print $f "EC2_ACCESS_KEY=$ENV{EC2_ACCESS_KEY}\n";
    print $f "EC2_SECRET_KEY=$ENV{EC2_SECRET_KEY}\n";
    close $f;
}
sub read_from_cache {
    open my $f,'.credentials' or return;
    chmod 0600,'.credentials';
    while (<$f>) {
	chomp;
	my($key,$value) = split '=';
	$ENV{$key}||=$value;
    }
    return 1 if $ENV{EC2_ACCESS_KEY} && $ENV{EC2_SECRET_KEY};
}

sub msg {
    my $msg = shift;
    print STDERR $msg;
    alarm(10);
    chomp (my $result = <>);
    $result;
}

1;
