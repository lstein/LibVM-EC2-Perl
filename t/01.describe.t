#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use File::Temp qw(tempfile);
use FindBin '$Bin';
use constant TEST_COUNT => 25;

use lib "$Bin/../lib","$Bin/../blib/lib","$Bin/../blib/arch";

use Test::More tests => TEST_COUNT;
use constant UBUNTU  => 'ami-4a936a23'; # Nano natty - only 1 GB in size!

setup_environment();

require_ok('VM::EC2');
my $ec2 = VM::EC2->new() or BAIL_OUT("Can't load VM::EC2 module");
ok($ec2,'VM::EC2->new');

my $natty = $ec2->describe_images(UBUNTU);
ok($natty,'describe image by id');

is($natty->imageLocation,'755060610258/ebs/ubuntu-images/ubuntu-natty-11.04-i386-server-20110426-nano','$image->imageLocation');
like($natty->description,'/http:\/\/nolar\.info\/nano-ami/','$image->description');
is($natty->architecture,'i386','$image->architecture');
is(($natty->blockDeviceMapping)[0],'/dev/sda1=snap-90ed13fe:1:true','$image->blockDeviceMapping');
is($natty->imageState,'available','$image->imageState');

my $owner = $natty->imageOwnerId();
my @i = $ec2->describe_images(-ownerId=>$natty->imageOwnerId,
			      -filter=>{description=>$natty->description,
					'manifest-location'=>$natty->imageLocation});
ok (@i == 1,'describe_images() with multiple filters');
is ($i[0],$natty,'describe_images() with multiple filters returns expected image');

# test tagging
ok($natty->add_tags(Name=>'MyFavoriteImage',Description=>'Test tag added by VM::EC2'),'tag addition');
$natty->refresh;
my $tags = $natty->tags;
is($tags->{Name},'MyFavoriteImage','tag retrieval');

@i = $ec2->describe_images(-filter=>{'tag:Name'        => 'MyFavoriteImage',
				     'tag:Description' => '*VM::EC2'});
is ($i[0],$natty,'retrieve by tags');

ok($natty->add_tags(Name=>'MyLeastFavoriteImage'),'tag replacement');
sleep 1; # takes a while to register
$natty->refresh;
is($natty->tags->{Name},'MyLeastFavoriteImage','tag replacement');

ok($natty->delete_tags(['Name','Description']),'tag deletion');
sleep 1; # takes a short while to register
$natty->refresh;
$tags = $natty->tags;  # should be no tags now
is(scalar keys %$tags,0,'tag deletion');

# exercise availability regions and keys
my @regions = $ec2->describe_regions;
ok(scalar @regions,'describe regions');

# make a key
my $kn      = 'VM-EC2 Test Key';
$ec2->delete_key_pair($kn);  # in case it was already there
my $key     = $ec2->create_key_pair($kn);
ok($key,'create key');
is($key->name,$kn,'create key name matches');

my @keys    = $ec2->describe_key_pairs;
ok(scalar @keys,'describe keys');

my @i = grep {$_->name eq $key} @keys;
is(scalar @i,1,'get keys');
is($i[0]->fingerprint,$key->fingerprint,'fingerprints match');
ok($ec2->delete_key_pair($key),'delete key');

@keys = $ec2->describe_key_pairs($kn);
is(scalar @keys,0,'delete key works');

exit 0;

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
