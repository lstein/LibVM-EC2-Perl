package VM::EC2;

=head1 NAME

VM::EC2 - Control the Amazon EC2 and Eucalyptus Clouds

=head1 SYNOPSIS

 # set environment variables EC2_ACCESS_KEY, EC2_SECRET_KEY and/or EC2_URL
 # to fill in arguments automatically

 ## IMAGE AND INSTANCE MANAGEMENT
 # get new EC2 object
 my $ec2 = VM::EC2->new(-access_key => 'access key id',
                        -secret_key => 'aws_secret_key',
                        -endpoint   => 'http://ec2.amazonaws.com');

 # fetch an image by its ID
 my $image = $ec2->describe_images('ami-12345');

 # get some information about the image
 my $architecture = $image->architecture;
 my $description  = $image->description;
 my @devices      = $image->blockDeviceMapping;
 for my $d (@devices) {
    print $d->deviceName,"\n";
    print $d->snapshotId,"\n";
    print $d->volumeSize,"\n";
 }

 # run two instances
 my @instances = $image->run_instances(-key_name      =>'My_key',
                                       -security_group=>'default',
                                       -min_count     =>2,
                                       -instance_type => 't1.micro')
           or die $ec2->error_str;

 # wait for both instances to reach "running" or other terminal state
 $ec2->wait_for_instances(@instances);

 # print out both instance's current state and DNS name
 for my $i (@instances) {
    my $status = $i->current_status;
    my $dns    = $i->dnsName;
    print "$i: [$status] $dns\n";
 }

 # tag both instances with Role "server"
 foreach (@instances) {$_->add_tag(Role=>'server');

 # stop both instances
 foreach (@instances) {$_->stop}
 
 # find instances tagged with Role=Server that are
 # stopped, change the user data and restart.
 @instances = $ec2->describe_instances({'tag:Role'       => 'Server',
                                        'instance-state-name' => 'stopped'});
 for my $i (@instances) {
    $i->userData('Secure-mode: off');
    $i->start or warn "Couldn't start $i: ",$i->error_str;
 }

 # create an image from both instance, tag them, and make
 # them public
 for my $i (@instances) {
     my $img = $i->create_image("Autoimage from $i","Test image");
     $img->add_tags(Name  => "Autoimage from $i",
                    Role  => 'Server',
                    Status=> 'Production');
     $img->make_public(1);
 }

 ## KEY MANAGEMENT

 # retrieve the name and fingerprint of the first instance's 
 # key pair
 my $kp = $instances[0]->keyPair;
 print $instances[0], ": keypair $kp=",$kp->fingerprint,"\n";

 # create a new key pair
 $kp = $ec2->create_key_pair('My Key');
 
 # get the private key from this key pair and write it to a disk file
 # in ssh-compatible format
 my $private_key = $kp->private_key;
 open (my $f,'>MyKeypair.rsa') or die $!;
 print $f $private_key;
 close $f;

 # Import a preexisting SSH key
 my $public_key = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8o...';
 $key = $ec2->import_key_pair('NewKey',$public_key);

 ## SECURITY GROUPS AND FIREWALL RULES
 # Create a new security group
 my $group = $ec2->create_security_group(-name        => 'NewGroup',
                                         -description => 'example');

 # Add a firewall rule 
 $group->authorize_incoming(-protocol  => 'tcp',
                            -port      => 80,
                            -source_ip => ['192.168.2.0/24','192.168.2.1/24'});

 # Write rules back to Amazon
 $group->update;

 # Print current firewall rules
 print join ("\n",$group->ipPermissions),"\n";

 ## VOLUME && SNAPSHOT MANAGEMENT

 # find existing volumes that are available
 my @volumes = $ec2->describe_volumes({status=>'available'});

 # back 'em all up to snapshots
 foreach (@volumes) {$_->snapshot('Backup on '.localtime)}

 # find a stopped instance in first volume's availability zone and 
 # attach the volume to the instance using /dev/sdg
 my $vol  = $volumes[0];
 my $zone = $vol->availabilityZone;
 @instances = $ec2->describe_instances({'availability-zone'=> $zone,
                                        'run-state-name'   => $stopped);
 $instances[0]->attach_volume($vol=>'/dev/sdg') if @instances;

 # create a new 20 gig volume
 $vol = $ec2->create_volume(-availability_zone=> 'us-east-1a',
                            -size             =>  20);
 $ec2->wait_for_volumes($vol);
 print "Volume $vol is ready!\n" if $vol->current_status eq 'available';

 # create a new elastic address and associate it with an instance
 my $address = $ec2->allocate_address();
 $instances[0]->associate_address($address);

=head1 DESCRIPTION

This is an interface to the 2012-12-01 version of the Amazon AWS API
(http://aws.amazon.com/ec2). It was written provide access to the new
tag and metadata interface that is not currently supported by
Net::Amazon::EC2, as well as to provide developers with an extension
mechanism for the API. This library will also support the Eucalyptus
open source cloud (http://open.eucalyptus.com).

The main interface is the VM::EC2 object, which provides methods for
interrogating the Amazon EC2, launching instances, and managing
instance lifecycle. These methods return the following major object
classes which act as specialized interfaces to AWS:

 VM::EC2::BlockDevice               -- A block device
 VM::EC2::BlockDevice::Attachment   -- Attachment of a block device to an EC2 instance
 VM::EC2::BlockDevice::EBS          -- An elastic block device
 VM::EC2::BlockDevice::Mapping      -- Mapping of a virtual storage device to a block device
 VM::EC2::BlockDevice::Mapping::EBS -- Mapping of a virtual storage device to an EBS block device
 VM::EC2::Group                     -- Security groups
 VM::EC2::Image                     -- Amazon Machine Images (AMIs)
 VM::EC2::Instance                  -- Virtual machine instances
 VM::EC2::Instance::Metadata        -- Access to runtime metadata from running instances
 VM::EC2::Region                    -- Availability regions
 VM::EC2::Snapshot                  -- EBS snapshots
 VM::EC2::Tag                       -- Metadata tags

In addition, there is a high level interface for interacting with EC2
servers and volumes, including file transfer and remote shell facilities:

  VM::EC2::Staging::Manager         -- Manage a set of servers and volumes.
  VM::EC2::Staging::Server          -- A staging server, with remote shell and file transfer
                                        facilities.
  VM::EC2::Staging::Volume          -- A staging volume with the ability to copy itself between
                                        availability zones and regions.

and a few specialty classes:

  VM::EC2::Security::Token          -- Temporary security tokens for granting EC2 access to
                                        non-AWS account holders.
  VM::EC2::Security::Credentials    -- Credentials for use by temporary account holders.
  VM::EC2::Security::Policy         -- Policies that restrict what temporary account holders
                                        can do with EC2 resources.
  VM::EC2::Security::FederatedUser  -- Account name information for temporary account holders.

Lastly, there are several utility classes:

 VM::EC2::Generic                   -- Base class for all AWS objects
 VM::EC2::Error                     -- Error messages
 VM::EC2::Dispatch                  -- Maps AWS XML responses onto perl object classes
 VM::EC2::ReservationSet            -- Hidden class used for describe_instances() request;
                                        The reservation Ids are copied into the Instance
                                         object.

There is also a high-level API called "VM::EC2::Staging::Manager" for
managing groups of staging servers and volumes which greatly
simplifies the task of creating and updating instances that mount
multiple volumes. The API also provides a one-line command for
migrating EBS-backed AMIs from one zone to another. See
L<VM::EC2::Staging::Manager>.

The interface provided by these modules is based on that described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/. The
following caveats apply:

 1) Not all of the Amazon API is currently implemented. Specifically,
    a handful calls dealing with cluster management and VM importing
    are missing.  See L</MISSING METHODS> for a list of all the
    unimplemented API calls. Volunteers to fill in these gaps are
    most welcome!

 2) For consistency with common Perl coding practices, method calls
    are lowercase and words in long method names are separated by
    underscores. The Amazon API prefers mixed case.  So in the Amazon
    API the call to fetch instance information is "DescribeInstances",
    while in VM::EC2, the method is "describe_instances". To avoid
    annoyance, if you use the mixed case form for a method name, the
    Perl autoloader will automatically translate it to underscores for
    you, and vice-versa; this means you can call either
    $ec2->describe_instances() or $ec2->DescribeInstances().

 3) Named arguments passed to methods are all lowercase, use
    underscores to separate words and start with hyphens.
    In other words, if the AWS API calls for an argument named
    "InstanceId" to be passed to the "DescribeInstances" call, then
    the corresponding Perl function will look like:

         $instance = $ec2->describe_instances(-instance_id=>'i-12345')

    In most cases automatic case translation will be performed for you
    on arguments. So in the previous example, you could use
    -InstanceId as well as -instance_id. The exception
    is when an absurdly long argument name was replaced with an 
    abbreviated one as described below. In this case, you must use
    the documented argument name.

    In a small number of cases, when the parameter name was absurdly
    long, it has been abbreviated. For example, the
    "Placement.AvailabilityZone" parameter has been represented as
    -placement_zone and not -placement_availability_zone. See the
    documentation for these cases.

 4) For each of the describe_foo() methods (where "foo" is a type of
    resource such as "instance"), you can fetch the resource by using
    their IDs either with the long form:

          $ec2->describe_foo(-foo_id=>['a','b','c']),

    or a shortcut form: 

          $ec2->describe_foo('a','b','c');

    Both forms are listed in the headings in the documentation.

 5) When the API calls for a list of arguments named Arg.1, Arg.2,
    then the Perl interface allows you to use an anonymous array for
    the consecutive values. For example to call describe_instances()
    with multiple instance IDs, use:

       @i = $ec2->describe_instances(-instance_id=>['i-12345','i-87654'])

 6) All Filter arguments are represented as a -filter argument whose value is
    an anonymous hash:

       @i = $ec2->describe_instances(-filter=>{architecture=>'i386',
                                               'tag:Name'  =>'WebServer'})

    If there are no other arguments you wish to pass, you can omit the
    -filter argument and just pass a hashref:

       @i = $ec2->describe_instances({architecture=>'i386',
                                      'tag:Name'  =>'WebServer'})

    For any filter, you may represent multiple OR arguments as an arrayref:

      @i = $ec2->describe-instances({'instance-state-name'=>['stopped','terminated']})

    When adding or removing tags, the -tag argument uses the same syntax.

 7) The tagnames of each XML object returned from AWS are converted into methods
    with the same name and typography. So the <privateIpAddress> tag in a
    DescribeInstancesResponse, becomes:

           $instance->privateIpAddress

    You can also use the more Perlish form -- this is equivalent:

          $instance->private_ip_address

    Methods that correspond to complex objects in the XML hierarchy
    return the appropriate Perl object. For example, an instance's
    blockDeviceMapping() method returns an object of type
    VM::EC2::BlockDevice::Mapping.

    All objects have a fields() method that will return the XML
    tagnames listed in the AWS specifications.

      @fields = sort $instance->fields;
      # 'amiLaunchIndex', 'architecture', 'blockDeviceMapping', ...

 8) Whenever an object has a unique ID, string overloading is used so that 
    the object interpolates the ID into the string. For example, when you
    print a VM::EC2::Volume object, or use it in another string context,
    then it will appear as the string "vol-123456". Nevertheless, it will
    continue to be usable for method calls.

         ($v) = $ec2->describe_volumes();
         print $v,"\n";                 # prints as "vol-123456"
         $zone = $v->availabilityZone;  # acts like an object

 9) Many objects have convenience methods that invoke the AWS API on your
    behalf. For example, instance objects have a current_status() method that returns
    the run status of the object, as well as start(), stop() and terminate()
    methods that control the instance's lifecycle.

         if ($instance->current_status eq 'running') {
             $instance->stop;
         }

 10) Calls to AWS that have failed for one reason or another (invalid
    arguments, communications problems, service interruptions) will
    return undef and set the VM::EC2->is_error() method to true. The
    error message and its code can then be recovered by calling
    VM::EC2->error.

      $i = $ec2->describe_instance('i-123456');
      unless ($i) {
          warn 'Got no instance. Message was: ',$ec2->error;
      }

    You may also elect to raise an exception when an error occurs.
    See the new() method for details.

=head1 EXAMPLE SCRIPT

The script sync_to_snapshot.pl, distributed with this module,
illustrates a relatively complex set of steps on EC2 that does
something useful. Given a list of directories or files on the local
filesystem it copies the files into an EBS snapshot with the desired
name by executing the following steps:

1. Provisions a new EBS volume on EC2 large enough to hold the data.

2. Spins up a staging instance to manage the network transfer of data
from the local machine to the staging volume.

3. Creates a temporary ssh keypair and a security group that allows an
rsync-over-ssh.

4. Formats and mounts the volume if necessary.

5. Initiates an rsync-over-ssh for the designated files and
directories.

6. Unmounts and snapshots the volume.

7. Cleans up.

If a snapshot of the same name already exists, then it is used to
create the staging volume, enabling network-efficient synchronization
of the files. A snapshot tag named "Version" is incremented each time
you synchronize.

=head1 CORE METHODS

This section describes the VM::EC2 constructor, accessor methods, and
methods relevant to error handling.

=cut

use strict;

use VM::EC2::Dispatch;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(hmac_sha256 sha1_hex);
use POSIX 'strftime';
use URI;
use URI::Escape;
use VM::EC2::Error;
use Carp 'croak','carp';

our $VERSION = '1.23';
our $AUTOLOAD;
our @CARP_NOT = qw(VM::EC2::Image    VM::EC2::Volume
                   VM::EC2::Snapshot VM::EC2::Instance
                   VM::EC2::ReservedInstance);

# hard-coded timeout for several wait_for_terminal_state() calls.
use constant WAIT_FOR_TIMEOUT => 600;

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my $proper = VM::EC2->canonicalize($func_name);
    $proper =~ s/^-//;
    if ($self->can($proper)) {
	eval "sub $pack\:\:$func_name {shift->$proper(\@_)}";
	$self->$func_name(@_);
    } else {
	croak "Can't locate object method \"$func_name\" via package \"$pack\"";
    }
}

use constant import_tags => {
    ':default'  => ['instance','elastic_ip','ebs','ami','keys','zone','general','tag','security_group',],
    ':vpn'      => ['customer_gateway','dhcp','eni','private_ip','internet_gateway','network_acl','route_table','subnet','vpc','vpn','vpg',],
    ':standard' => [':default'],
};

# e.g. use VM::EC2 ':default','!ami';
sub import {
    my $self = shift;
    my @args = @_;
    @args    = ':default' unless @args;
    while (1) {
	my @processed = map {/^:/ && import_tags->{$_} ? @{import_tags->{$_}} : $_ } @args;
	last if @processed == @args;  # no more expansion needed
	@args = @processed;
    }
    my %exclude;
    foreach (@args) {
	$exclude{$1}++ if /^!(\S+)/;
    }
    foreach (@args) {
	next unless /^\S/;
	next if $exclude{$_};
	my $class = "VM::EC2::REST::$_";
	eval "require $class; 1" or die $@;
    }
}

=head2 $ec2 = VM::EC2->new(-access_key=>$id,-secret_key=>$key,-endpoint=>$url)

Create a new Amazon access object. Required arguments are:

 -access_key   Access ID for an authorized user

 -secret_key   Secret key corresponding to the Access ID

 -security_token Temporary security token obtained through a call to the
               AWS Security Token Service

 -endpoint     The URL for making API requests

 -region       The region to receive the API requests

 -raise_error  If true, throw an exception.

 -print_error  If true, print errors to STDERR.

One or more of -access_key or -secret_key can be omitted if the
environment variables EC2_ACCESS_KEY and EC2_SECRET_KEY are
defined. If no endpoint is specified, then the environment variable
EC2_URL is consulted; otherwise the generic endpoint
http://ec2.amazonaws.com/ is used. You can also select the endpoint by
specifying one of the Amazon regions, such as "us-west-2", with the
-region argument. The endpoint specified by -region will override
-endpoint.

-security_token is used in conjunction with temporary security tokens
returned by $ec2->get_federation_token() and $ec2->get_session_token()
to grant restricted, time-limited access to some or all your EC2
resources to users who do not have access to your account. If you pass
either a VM::EC2::Security::Token object, or the
VM::EC2::Security::Credentials object contained within the token
object, then new() does not need the -access_key or -secret_key
arguments. You may also pass a session token string scalar to
-security_token, in which case you must also pass the access key ID
and secret keys generated at the same time the session token was
created. See
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/UsingIAM.html
and L</AWS SECURITY TOKENS>.

To use a Eucalyptus cloud, please provide the appropriate endpoint
URL.

By default, when the Amazon API reports an error, such as attempting
to perform an invalid operation on an instance, the corresponding
method will return empty and the error message can be recovered from
$ec2->error(). However, if you pass -raise_error=>1 to new(), the module
will instead raise a fatal error, which you can trap with eval{} and
report with $@:

  eval {
     $ec2->some_dangerous_operation();
     $ec2->another_dangerous_operation();
  };
  print STDERR "something bad happened: $@" if $@;

The error object can be retrieved with $ec2->error() as before.

=cut

sub new {
    my $self = shift;
    my %args = @_;

    my ($id,$secret,$token);
    if (ref $args{-security_token} && $args{-security_token}->can('access_key_id')) {
	$id     = $args{-security_token}->accessKeyId;
	$secret = $args{-security_token}->secretAccessKey;
	$token  = $args{-security_token}->sessionToken;
    }

    $id           ||= $args{-access_key} || $ENV{EC2_ACCESS_KEY}
                      or croak "Please provide -access_key parameter or define environment variable EC2_ACCESS_KEY";
    $secret       ||= $args{-secret_key} || $ENV{EC2_SECRET_KEY}
                      or croak "Please provide -secret_key or define environment variable EC2_SECRET_KEY";
    $token        ||= $args{-security_token};

    my $endpoint_url = $args{-endpoint}   || $ENV{EC2_URL} || 'http://ec2.amazonaws.com/';
    $endpoint_url   .= '/'                     unless $endpoint_url =~ m!/$!;
    $endpoint_url    = "http://".$endpoint_url unless $endpoint_url =~ m!https?://!;

    my $raise_error  = $args{-raise_error};
    my $print_error  = $args{-print_error};
    my $obj = bless {
	id              => $id,
	secret          => $secret,
	security_token  => $token,
	endpoint        => $endpoint_url,
	idempotent_seed => sha1_hex(rand()),
	raise_error     => $raise_error,
	print_error     => $print_error,
    },ref $self || $self;

    if ($args{-region}) {
	$self->import('zone');
	my $region   = eval{$obj->describe_regions($args{-region})};
	my $endpoint = $region ? $region->regionEndpoint :"ec2.$args{-region}.amazonaws.com";
	$obj->endpoint($endpoint);
    }

    return $obj;
}

=head2 $access_key = $ec2->access_key([$new_access_key])

Get or set the ACCESS KEY. In this and all similar get/set methods,
call the method with no arguments to get the current value, and with a
single argument to change the value:

 $current_key = $ec2->access_key;
 $ec2->access_key('XYZZY');

In the case of setting the value, these methods will return the old
value as their result:

 $old_key = $ec2->access_key($new_key);

=cut

sub access_key {shift->id(@_)}

sub id       { 
    my $self = shift;
    my $d    = $self->{id};
    $self->{id} = shift if @_;
    $d;
}

=head2 $secret = $ec2->secret([$new_secret])

Get or set the SECRET KEY

=cut

sub secret   {
    my $self = shift;
    my $d    = $self->{secret};
    $self->{secret} = shift if @_;
    $d;
}

=head2 $secret = $ec2->security_token([$new_token])

Get or set the temporary security token. See L</AWS SECURITY TOKENS>.

=cut

sub security_token   {
    my $self = shift;
    my $d    = $self->{security_token};
    $self->{security_token} = shift if @_;
    $d;
}

=head2 $endpoint = $ec2->endpoint([$new_endpoint])

Get or set the ENDPOINT URL.

=cut

sub endpoint { 
    my $self = shift;
    my $d    = $self->{endpoint};
    if (@_) {
	my $new_endpoint = shift;
	$new_endpoint    = 'http://'.$new_endpoint
	    unless $new_endpoint =~ /^https?:/;
	$self->{endpoint} = $new_endpoint;
    }
    $d;
 }

=head2 $region = $ec2->region([$new_region])

Get or set the EC2 region manipulated by this module. This has the side effect
of changing the endpoint.

=cut

sub region { 
    my $self = shift;

    my $d    = $self->{endpoint};
    $d       =~ s!^https?://!!;
    $d       =~ s!/$!!;

    $self->import('zone');
    my @regions = $self->describe_regions;
    my ($current_region) = grep {$_->regionEndpoint eq $d} @regions;

    if (@_) {
	my $new_region = shift;
	my ($region) = grep {/$new_region/} @regions;
	$region or croak "unknown region $new_region";
	$self->endpoint($region->regionEndpoint);
    }
    return $current_region;
}
VM::EC2::Dispatch->register(DescribeRegions   => 'fetch_items,regionInfo,VM::EC2::Region');

=head2 $ec2->raise_error($boolean)

Change the handling of error conditions. Pass a true value to cause
Amazon API errors to raise a fatal error. Pass false to make methods
return undef. In either case, you can detect the error condition
by calling is_error() and fetch the error message using error(). This
method will also return the current state of the raise error flag.

=cut

sub raise_error {
    my $self = shift;
    my $d    = $self->{raise_error};
    $self->{raise_error} = shift if @_;
    $d;
}

=head2 $ec2->print_error($boolean)

Change the handling of error conditions. Pass a true value to cause
Amazon API errors to print error messages to STDERR. Pass false to
cancel this behavior.

=cut

sub print_error {
    my $self = shift;
    my $d    = $self->{print_error};
    $self->{print_error} = shift if @_;
    $d;
}

=head2 $boolean = $ec2->is_error

If a method fails, it will return undef. However, some methods, such
as describe_images(), will also return undef if no resources matches
your search criteria. Call is_error() to distinguish the two
eventualities:

  @images = $ec2->describe_images(-owner=>'29731912785');
  unless (@images) {
      die "Error: ",$ec2->error if $ec2->is_error;
      print "No appropriate images found\n";
  }

=cut

sub is_error {
    defined shift->error();
}

=head2 $err = $ec2->error

If the most recently-executed method failed, $ec2->error() will return
the error code and other descriptive information. This method will
return undef if the most recently executed method was successful.

The returned object is actually an AWS::Error object, which
has two methods named code() and message(). If used in a string
context, its operator overloading returns the composite string
"$message [$code]".

=cut

sub error {
    my $self = shift;
    my $d    = $self->{error};
    $self->{error} = shift if @_;
    $d;
}

=head2 $err = $ec2->error_str

Same as error() except it returns the string representation, not the
object. This works better in debuggers and exception handlers.

=cut

sub error_str { 
    my $e = shift->{error};
    $e ||= '';
    return "$e";
}

=head2 $account_id = $ec2->account_id

Looks up the account ID corresponding to the credentials provided when
the VM::EC2 instance was created. The way this is done is to fetch the
"default" security group, which is guaranteed to exist, and then
return its groupId field. The result is cached so that subsequent
accesses are fast.

=head2 $account_id = $ec2->userId

Same as above, for convenience.

=cut

sub account_id {
    my $self = shift;
    return $self->{account_id} if exists $self->{account_id};
    my $sg   = $self->describe_security_groups(-group_name=>'default') or return;
    return $self->{account_id} ||= $sg->ownerId;
}

sub userId { shift->account_id }

=head2 $new_ec2 = $ec2->clone

This method creates an identical copy of the EC2 object. It is used
occasionally internally for creating an EC2 object in a different AWS
region:

 $singapore = $ec2->clone;
 $singapore->region('ap-souteast-1');

=cut

sub clone {
    my $self = shift;
    my %contents = %$self;
    return bless \%contents,ref $self;
}

=head1 Waiting for State Changes

The methods in this section allow your script to wait in an efficient
manner for desired state changes in instances, volumes and other
objects.

=head2 $ec2->wait_for_instances(@instances)

Wait for all members of the provided list of instances to reach some
terminal state ("running", "stopped" or "terminated"), and then return
a hash reference that maps each instance ID to its final state.

Typical usage:

 my @instances = $image->run_instances(-key_name      =>'My_key',
                                       -security_group=>'default',
                                       -min_count     =>2,
                                       -instance_type => 't1.micro')
           or die $ec2->error_str;
 my $status = $ec2->wait_for_instances(@instances);
 my @failed = grep {$status->{$_} ne 'running'} @instances;
 print "The following failed: @failed\n";

If no terminal state is reached within a set timeout, then this method
returns undef and sets $ec2->error_str() to a suitable message. The
timeout, which defaults to 10 minutes (600 seconds), can be get or set
with $ec2->wait_for_timeout().

=cut

sub wait_for_instances {
    my $self = shift;
    $self->wait_for_terminal_state(\@_,
				   ['running','stopped','terminated'],
				   $self->wait_for_timeout);
}

=head2 $ec2->wait_for_snapshots(@snapshots)

Wait for all members of the provided list of snapshots to reach some
terminal state ("completed", "error"), and then return a hash
reference that maps each snapshot ID to its final state.

This method may potentially wait forever. It has no set timeout. Wrap
it in an eval{} and set alarm() if you wish to timeout.

=cut

sub wait_for_snapshots {
    my $self = shift;
    $self->wait_for_terminal_state(\@_,
				   ['completed','error'],
				   0);  # no timeout on snapshots -- they may take days
}

=head2 $ec2->wait_for_volumes(@volumes)

Wait for all members of the provided list of volumes to reach some
terminal state ("available", "in-use", "deleted" or "error"), and then
return a hash reference that maps each volume ID to its final state.

If no terminal state is reached within a set timeout, then this method
returns undef and sets $ec2->error_str() to a suitable message. The
timeout, which defaults to 10 minutes (600 seconds), can be get or set
with $ec2->wait_for_timeout().

=cut

sub wait_for_volumes {
    my $self = shift;
    $self->wait_for_terminal_state(\@_,
				   ['available','in-use','deleted','error'],
				   $self->wait_for_timeout);
}

=head2 $ec2->wait_for_attachments(@attachment)

Wait for all members of the provided list of
VM::EC2::BlockDevice::Attachment objects to reach some terminal state
("attached" or "detached"), and then return a hash reference that maps
each attachment to its final state.

Typical usage:

    my $i = 0;
    my $instance = 'i-12345';
    my @attach;
    foreach (@volume) {
	push @attach,$_->attach($instance,'/dev/sdf'.$i++;
    }
    my $s = $ec2->wait_for_attachments(@attach);
    my @failed = grep($s->{$_} ne 'attached'} @attach;
    warn "did not attach: ",join ', ',@failed;

If no terminal state is reached within a set timeout, then this method
returns undef and sets $ec2->error_str() to a suitable message. The
timeout, which defaults to 10 minutes (600 seconds), can be get or set
with $ec2->wait_for_timeout().

=cut

sub wait_for_attachments {
    my $self = shift;
    $self->wait_for_terminal_state(\@_,
				   ['attached','detached'],
				   $self->wait_for_timeout);
}

=head2 $ec2->wait_for_terminal_state(\@objects,['list','of','states'] [,$timeout])

Generic version of the last four methods. Wait for all members of the provided list of Amazon objects 
instances to reach some terminal state listed in the second argument, and then return
a hash reference that maps each object ID to its final state.

If a timeout is provided, in seconds, then the method will abort after
waiting the indicated time and return undef.

=cut

sub wait_for_terminal_state {
    my $self = shift;
    my ($objects,$terminal_states,$timeout) = @_;
    my %terminal_state = map {$_=>1} @$terminal_states;
    my %status = ();
    my @pending = grep {defined $_} @$objects; # in case we're passed an undef
    my $status = eval {
	local $SIG{ALRM};
	if ($timeout && $timeout > 0) {
	    $SIG{ALRM} = sub {die "timeout"};
	    alarm($timeout);
	}
	while (@pending) {
	    sleep 3;
	    $status{$_} = $_->current_status foreach @pending;
	    @pending    = grep { !$terminal_state{$status{$_}} } @pending;
	}
	alarm(0);
	\%status;
    };
    if ($@ =~ /timeout/) {
	$self->error('timeout waiting for terminal state');
	return;
    }
    return $status;
}

=head2 $timeout = $ec2->wait_for_timeout([$new_timeout]);

Get or change the timeout for wait_for_instances(), wait_for_attachments(),
and wait_for_volumes(). The timeout is given in seconds, and defaults to
600 (10 minutes). You can set this to 0 to wait forever.

=cut

sub wait_for_timeout {
    my $self = shift;
    $self->{wait_for_timeout} = WAIT_FOR_TIMEOUT
	unless defined $self->{wait_for_timeout};
    my $d = $self->{wait_for_timeout};
    $self->{wait_for_timeout} = shift if @_;
    return $d;
}

=head1 EC2 AMAZON MACHINE IMAGES

The methods in this section allow you to query and manipulate Amazon
machine images (AMIs). See L<VM::EC2::Image>.

=head2 @i = $ec2->describe_images(@image_ids)

=head2 @i = $ec2->describe_images(-image_id=>\@id,-executable_by=>$id,
                                  -owner=>$id, -filter=>\%filters)

Return a series of VM::EC2::Image objects, each describing an
AMI. Optional arguments:

 -image_id        The id of the image, either a string scalar or an
                  arrayref.

 -executable_by   Filter by images executable by the indicated user account, or
                    one of the aliases "self" or "all".

 -owner           Filter by owner account number or one of the aliases "self",
                    "aws-marketplace", "amazon" or "all".

 -filter          Tags and other filters to apply

If there are no other arguments, you may omit the -filter argument
name and call describe_images() with a single hashref consisting of
the search filters you wish to apply.

The full list of image filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeImages.html

=cut

sub describe_images {
    my $self = shift;
    my %args = $self->args(-image_id=>@_);
    my @params;
    push @params,$self->list_parm($_,\%args) foreach qw(ExecutableBy ImageId Owner);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeImages',@params);
}

=head2 $image = $ec2->create_image(-instance_id=>$id,-name=>$name,%other_args)

Create an image from an EBS-backed instance and return a
VM::EC2::Image object. The instance must be in the "stopped" or
"running" state. In the latter case, Amazon will stop the instance,
create the image, and then restart it unless the -no_reboot argument
is provided.

Arguments:

 -instance_id    ID of the instance to create an image from. (required)
 -name           Name for the image that will be created. (required)
 -description    Description of the new image.
 -no_reboot      If true, don't reboot the instance.
 -block_device_mapping
                 Block device mapping as a scalar or array ref. See 
                  run_instances() for the syntax.
 -block_devices  Alias of the above

=cut

sub create_image {
    my $self = shift;
    my %args = @_;
    $args{-instance_id} && $args{-name}
      or croak "Usage: create_image(-instance_id=>\$id,-name=>\$name)";
    $args{-block_device_mapping} ||= $args{-block_devices};
    my @param = $self->single_parm('InstanceId',\%args);
    push @param,$self->single_parm('Name',\%args);
    push @param,$self->single_parm('Description',\%args);
    push @param,$self->boolean_parm('NoReboot',\%args);
    push @param,$self->block_device_parm($args{-block_device_mapping});
    return $self->call('CreateImage',@param);
}

=head2 $image = $ec2->register_image(-name=>$name,%other_args)

Register an image, creating an AMI. This can be used to create an AMI
from a S3-backed instance-store bundle, or to create an AMI from a
snapshot of an EBS-backed root volume.

Required arguments:

 -name                 Name for the image that will be created.

Arguments required for an EBS-backed image:

 -root_device_name     The root device name, e.g. /dev/sda1
 -block_device_mapping The block device mapping strings, including the
                       snapshot ID for the root volume. This can
                       be either a scalar string or an arrayref.
                       See run_instances() for a description of the
                       syntax.
 -block_devices        Alias of the above.

Arguments required for an instance-store image:

 -image_location      Full path to the AMI manifest in Amazon S3 storage.

Common optional arguments:

 -description         Description of the AMI
 -architecture        Architecture of the image ("i386" or "x86_64")
 -kernel_id           ID of the kernel to use
 -ramdisk_id          ID of the RAM disk to use
 
While you do not have to specify the kernel ID, it is strongly
recommended that you do so. Otherwise the kernel will have to be
specified for run_instances().

Note: Immediately after registering the image you can add tags to it
and use modify_image_attribute to change launch permissions, etc.

=cut

sub register_image {
    my $self = shift;
    my %args = @_;

    $args{-name} or croak "register_image(): -name argument required";
    $args{-block_device_mapping} ||= $args{-block_devices};
    if (!$args{-image_location}) {
	$args{-root_device_name} && $args{-block_device_mapping}
	or croak "register_image(): either provide -image_location to create an instance-store AMI\nor both the -root_device_name && -block_device_mapping arguments to create an EBS-backed AMI.";
    }

    my @param;
    for my $a (qw(Name RootDeviceName ImageLocation Description
                  Architecture KernelId RamdiskId)) {
	push @param,$self->single_parm($a,\%args);
    }
    push @param,$self->block_device_parm($args{-block_devices} || $args{-block_device_mapping});

    return $self->call('RegisterImage',@param);
}

=head2 $result = $ec2->deregister_image($image_id)

Deletes the registered image and returns true if successful.

=cut

sub deregister_image {
    my $self = shift;
    my %args  = $self->args(-image_id => @_);
    my @param = $self->single_parm(ImageId=>\%args);
    return $self->call('DeregisterImage',@param);
}

=head2 @data = $ec2->describe_image_attribute($image_id,$attribute)

This method returns image attributes. Only one attribute can be
retrieved at a time. The following is the list of attributes that can be
retrieved:

 description            -- scalar
 kernel                 -- scalar
 ramdisk                -- scalar
 launchPermission       -- list of scalar
 productCodes           -- array
 blockDeviceMapping     -- list of hashref

All of these values can be retrieved more conveniently from the
L<VM::EC2::Image> object returned from describe_images(), so there is
no attempt to parse the results of this call into Perl objects. In
particular, 'blockDeviceMapping' is returned as a raw hashrefs (there
also seems to be an AWS bug that causes fetching this attribute to return an
AuthFailure error).

Please see the VM::EC2::Image launchPermissions() and
blockDeviceMapping() methods for more convenient ways to get this
data.

=cut

sub describe_image_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_image_attribute(\$instance_id,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my @param  = (ImageId=>$instance_id,Attribute=>$attribute);
    my $result = $self->call('DescribeImageAttribute',@param);
    return $result && $result->attribute($attribute);
}

=head2 $boolean = $ec2->modify_image_attribute($image_id,-$attribute_name=>$value)

This method changes image attributes. The first argument is the image
ID, and this is followed by the attribute name and the value to change
it to.

The following is the list of attributes that can be set:

 -launch_add_user         -- scalar or arrayref of UserIds to grant launch permissions to
 -launch_add_group        -- scalar or arrayref of Groups to remove launch permissions from
                               (only currently valid value is "all")
 -launch_remove_user      -- scalar or arrayref of UserIds to remove from launch permissions
 -launch_remove_group     -- scalar or arrayref of Groups to remove from launch permissions
 -product_code            -- scalar or array of product codes to add
 -description             -- scalar new description

You can abbreviate the launch permission arguments to -add_user,
-add_group, -remove_user, -remove_group, etc.

Only one attribute can be changed in a single request.

For example:

  $ec2->modify_image_attribute('i-12345',-product_code=>['abcde','ghijk']);

The result code is true if the attribute was successfully modified,
false otherwise. In the latter case, $ec2->error() will provide the
error message.

To make an image public, specify -launch_add_group=>'all':

  $ec2->modify_image_attribute('i-12345',-launch_add_group=>'all');

Also see L<VM::EC2::Image> for shortcut methods. For example:

 $image->add_authorized_users(1234567,999991);

=cut

sub modify_image_attribute {
    my $self = shift;
    my $image_id = shift or croak "Usage: modify_image_attribute(\$imageId,%param)";
    my %args   = @_;

    # shortcuts
    foreach (qw(add_user remove_user add_group remove_group)) {
	$args{"-launch_$_"} ||= $args{"-$_"};
    }

    my @param  = (ImageId=>$image_id);
    push @param,$self->value_parm('Description',\%args);
    push @param,$self->list_parm('ProductCode',\%args);
    push @param,$self->launch_perm_parm('Add','UserId',   $args{-launch_add_user});
    push @param,$self->launch_perm_parm('Remove','UserId',$args{-launch_remove_user});
    push @param,$self->launch_perm_parm('Add','Group',    $args{-launch_add_group});
    push @param,$self->launch_perm_parm('Remove','Group', $args{-launch_remove_group});
    return $self->call('ModifyImageAttribute',@param);
}

=head2 $boolean = $ec2->reset_image_attribute($image_id,$attribute_name)

This method resets an attribute of the given snapshot to its default
value. The valid attributes are:

 launchPermission


=cut

sub reset_image_attribute {
    my $self = shift;
    @_      == 2 or 
	croak "Usage: reset_image_attribute(\$imageId,\$attribute_name)";
    my ($image_id,$attribute) = @_;
    my %valid = map {$_=>1} qw(launchPermission);
    $valid{$attribute} or croak "attribute to reset must be one of ",join(' ',map{"'$_'"} keys %valid);
    return $self->call('ResetImageAttribute',
		       ImageId    => $image_id,
		       Attribute  => $attribute);
}

=head1 EC2 VOLUMES AND SNAPSHOTS

The methods in this section allow you to query and manipulate EC2 EBS
volumes and snapshots. See L<VM::EC2::Volume> and L<VM::EC2::Snapshot>
for additional functionality provided through the object interface.

=head2 @v = $ec2->describe_volumes(-volume_id=>\@ids,-filter=>\%filters)

=head2 @v = $ec2->describe_volumes(@volume_ids)

Return a series of VM::EC2::Volume objects. Optional arguments:

 -volume_id    The id of the volume to fetch, either a string
               scalar or an arrayref.

 -filter       One or more filters to apply to the search

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of volume filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVolumes.html

=cut

sub describe_volumes {
    my $self = shift;
    my %args = $self->args(-volume_id=>@_);
    my @params;
    push @params,$self->list_parm('VolumeId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeVolumes',@params);
}

=head2 $v = $ec2->create_volume(-availability_zone=>$zone,-snapshot_id=>$snapshotId,-size=>$size,-volume_type=>$type,-iops=>$iops)

Create a volume in the specified availability zone and return
information about it.

Arguments:

 -availability_zone    -- An availability zone from
                          describe_availability_zones (required)

 -snapshot_id          -- ID of a snapshot to use to build volume from.

 -size                 -- Size of the volume, in GB (between 1 and 1024).

One or both of -snapshot_id or -size are required. For convenience,
you may abbreviate -availability_zone as -zone, and -snapshot_id as
-snapshot.

Optional Arguments:

 -volume_type          -- The volume type.  standard or io1, default is
                          standard

 -iops                 -- The number of I/O operations per second (IOPS) that
                          the volume supports.  Range is 100 to 2000.  Required
                          when volume type is io1.

The returned object is a VM::EC2::Volume object.

=cut

sub create_volume {
    my $self = shift;
    my %args = @_;
    my $zone = $args{-availability_zone} || $args{-zone} or croak "-availability_zone argument is required";
    my $snap = $args{-snapshot_id}       || $args{-snapshot};
    my $size = $args{-size};
    $snap || $size or croak "One or both of -snapshot_id or -size are required";
    if (exists $args{-volume_type} && $args{-volume_type} eq 'io1') {
        $args{-iops} or croak "Argument -iops required when -volume_type is 'io1'";
    }
    elsif ($args{-iops}) {
        croak "Argument -iops cannot be used when volume type is 'standard'";
    }
    my @params = (AvailabilityZone => $zone);
    push @params,(SnapshotId   => $snap) if $snap;
    push @params,(Size => $size)         if $size;
    push @params,$self->single_parm('VolumeType',\%args);
    push @params,$self->single_parm('Iops',\%args);
    return $self->call('CreateVolume',@params);
}

=head2 $result = $ec2->delete_volume($volume_id);

Deletes the specified volume. Returns a boolean indicating success of
the delete operation. Note that a volume will remain in the "deleting"
state for some time after this call completes.

=cut

sub delete_volume {
    my $self = shift;
    my %args  = $self->args(-volume_id => @_);
    my @param = $self->single_parm(VolumeId=>\%args);
    return $self->call('DeleteVolume',@param);
}

=head2 $attachment = $ec2->attach_volume($volume_id,$instance_id,$device);

=head2 $attachment = $ec2->attach_volume(-volume_id=>$volume_id,-instance_id=>$instance_id,-device=>$device);

Attaches the specified volume to the instance using the indicated
device. All arguments are required:

 -volume_id      -- ID of the volume to attach. The volume must be in
                    "available" state.
 -instance_id    -- ID of the instance to attach to. Both instance and
                    attachment must be in the same availability zone.
 -device         -- How the device is exposed to the instance, e.g.
                    '/dev/sdg'.

The result is a VM::EC2::BlockDevice::Attachment object which
you can monitor by calling current_status():

    my $a = $ec2->attach_volume('vol-12345','i-12345','/dev/sdg');
    while ($a->current_status ne 'attached') {
       sleep 2;
    }
    print "volume is ready to go\n";

or more simply

    my $a = $ec2->attach_volume('vol-12345','i-12345','/dev/sdg');
    $ec2->wait_for_attachments($a);

=cut

sub attach_volume {
    my $self = shift;
    my %args; 
    if ($_[0] !~ /^-/ && @_ == 3) { 
	@args{qw(-volume_id -instance_id -device)} = @_; 
    } else { 
	%args = @_; 
    }
    $args{-volume_id} && $args{-instance_id} && $args{-device} or
	croak "-volume_id, -instance_id and -device arguments must all be specified";
    my @param = $self->single_parm(VolumeId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(Device=>\%args);
    return $self->call('AttachVolume',@param);
}

=head2 $attachment = $ec2->detach_volume($volume_id)

=head2 $attachment = $ec2->detach_volume(-volume_id=>$volume_id,-instance_id=>$instance_id,
                                         -device=>$device,      -force=>$force);

Detaches the specified volume from an instance.

 -volume_id      -- ID of the volume to detach. (required)
 -instance_id    -- ID of the instance to detach from. (optional)
 -device         -- How the device is exposed to the instance. (optional)
 -force          -- Force detachment, even if previous attempts were
                    unsuccessful. (optional)


The result is a VM::EC2::BlockDevice::Attachment object which
you can monitor by calling current_status():

    my $a = $ec2->detach_volume('vol-12345');
    while ($a->current_status ne 'detached') {
       sleep 2;
    }
    print "volume is ready to go\n";

Or more simply:

    my $a = $ec2->detach_volume('vol-12345');
    $ec2->wait_for_attachments($a);
    print "volume is ready to go\n" if $a->current_status eq 'detached';


=cut

sub detach_volume {
    my $self = shift;
    my %args = $self->args(-volume_id => @_);
    my @param = $self->single_parm(VolumeId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(Device=>\%args);
    push @param,$self->single_parm(Force=>\%args);
    return $self->call('DetachVolume',@param);
}

=head2 @v = $ec2->describe_volume_status(@volume_ids)

=head2 @v = $ec2->describe_volume_status(\%filters)

=head2 @v = $ec2->describe_volume_status(-volume_id=>\@ids,-filter=>\%filters)

Return a series of VM::EC2::Volume::StatusItem objects. Optional arguments:

 -volume_id    The id of the volume to fetch, either a string
               scalar or an arrayref.

 -filter       One or more filters to apply to the search

 -max_results  Maximum number of items to return (must be more than
                5).

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of volume filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVolumeStatus.html

If -max_results is specified, then the call will return at most the
number of volume status items you requested. You may see whether there
are additional results by calling more_volume_status(), and then
retrieve the next set of results with additional call(s) to
describe_volume_status():

 my @results = $ec2->describe_volume_status(-max_results => 10);
 do_something(\@results);
 while ($ec2->more_volume_status) {
    @results = $ec2->describe_volume_status;
    do_something(\@results);
 }

=cut

sub more_volume_status {
    my $self = shift;
    return $self->{volume_status_token} &&
           !$self->{volume_status_stop};
}

sub describe_volume_status {
    my $self = shift;
    my @parms;

    if (!@_ && $self->{volume_status_token} && $self->{volume_status_args}) {
	@parms = (@{$self->{volume_status_args}},NextToken=>$self->{volume_status_token});
    }
    
    else {
	my %args = $self->args('-volume_id',@_);
	push @parms,$self->list_parm('VolumeId',\%args);
	push @parms,$self->filter_parm(\%args);
	push @parms,$self->single_parm('MaxResults',\%args);
	
	if ($args{-max_results}) {
	    $self->{volume_status_token} = 'xyzzy'; # dummy value
	    $self->{volume_status_args} = \@parms;
	}

    }
    return $self->call('DescribeVolumeStatus',@parms);
}

=head2 @data = $ec2->describe_volume_attribute($volume_id,$attribute)

This method returns volume attributes.  Only one attribute can be
retrieved at a time. The following is the list of attributes that can be
retrieved:

 autoEnableIO                      -- boolean
 productCodes                      -- list of scalar

These values can be retrieved more conveniently from the
L<VM::EC2::Volume> object returned from describe_volumes():

 $volume->auto_enable_io(1);
 @codes = $volume->product_codes;

=cut

sub describe_volume_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_volume_attribute(\$instance_id,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my @param  = (VolumeId=>$instance_id,Attribute=>$attribute);
    my $result = $self->call('DescribeVolumeAttribute',@param);
    return $result && $result->attribute($attribute);
}

sub modify_volume_attribute {
    my $self = shift;
    my $volume_id = shift or croak "Usage: modify_volume_attribute(\$volumeId,%param)";
    my %args   = @_;
    my @param  = (VolumeId=>$volume_id);
    push @param,('AutoEnableIO.Value'=>$args{-auto_enable_io} ? 'true':'false');
    return $self->call('ModifyVolumeAttribute',@param);
}

=head2 $boolean = $ec2->enable_volume_io($volume_id)

=head2 $boolean = $ec2->enable_volume_io(-volume_id=>$volume_id)

Given the ID of a volume whose I/O has been disabled (e.g. due to
hardware degradation), this method will reenable the I/O and return
true if successful.

=cut

sub enable_volume_io {
    my $self = shift;
    my %args = $self->args('-volume_id',@_);
    $args{-volume_id} or croak "Usage: enable_volume_io(\$volume_id)";
    my @param = $self->single_parm('VolumeId',\%args);
    return $self->call('EnableVolumeIO',@param);
}

=head2 @snaps = $ec2->describe_snapshots(@snapshot_ids)

=head2 @snaps = $ec2->describe_snapshots(-snapshot_id=>\@ids,%other_args)

Returns a series of VM::EC2::Snapshot objects. All arguments
are optional:

 -snapshot_id     ID of the snapshot

 -owner           Filter by owner ID

 -restorable_by   Filter by IDs of a user who is allowed to restore
                   the snapshot

 -filter          Tags and other filters

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeSnapshots.html

=cut

sub describe_snapshots {
    my $self = shift;
    my %args = $self->args('-snapshot_id',@_);

    my @params;
    push @params,$self->list_parm('SnapshotId',\%args);
    push @params,$self->list_parm('Owner',\%args);
    push @params,$self->list_parm('RestorableBy',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeSnapshots',@params);
}

=head2 @data = $ec2->describe_snapshot_attribute($snapshot_id,$attribute)

This method returns snapshot attributes. The first argument is the
snapshot ID, and the second is the name of the attribute to
fetch. Currently Amazon defines two attributes:

 createVolumePermission   -- return a list of user Ids who are
                             allowed to create volumes from this snapshot.
 productCodes             -- product codes for this snapshot

The result is a raw hash of attribute values. Please see
L<VM::EC2::Snapshot> for a more convenient way of accessing and
modifying snapshot attributes.

=cut

sub describe_snapshot_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_snapshot_attribute(\$instance_id,\$attribute_name)";
    my ($snapshot_id,$attribute) = @_;
    my @param  = (SnapshotId=>$snapshot_id,Attribute=>$attribute);
    my $result = $self->call('DescribeSnapshotAttribute',@param);
    return $result && $result->attribute($attribute);
}

=head2 $boolean = $ec2->modify_snapshot_attribute($snapshot_id,-$argument=>$value)

This method changes snapshot attributes. The first argument is the
snapshot ID, and this is followed by an attribute modification command
and the value to change it to.

Currently the only attribute that can be changed is the
createVolumeAttribute. This is done through the following arguments

 -createvol_add_user         -- scalar or arrayref of UserIds to grant create volume permissions to
 -createvol_add_group        -- scalar or arrayref of Groups to remove create volume permissions from
                               (only currently valid value is "all")
 -createvol_remove_user      -- scalar or arrayref of UserIds to remove from create volume permissions
 -createvol_remove_group     -- scalar or arrayref of Groups to remove from create volume permissions

You can abbreviate these to -add_user, -add_group, -remove_user, -remove_group, etc.

See L<VM::EC2::Snapshot> for more convenient methods for interrogating
and modifying the create volume permissions.

=cut

sub modify_snapshot_attribute {
    my $self = shift;
    my $snapshot_id = shift or croak "Usage: modify_snapshot_attribute(\$snapshotId,%param)";
    my %args   = @_;

    # shortcuts
    foreach (qw(add_user remove_user add_group remove_group)) {
	$args{"-createvol_$_"} ||= $args{"-$_"};
    }

    my @param  = (SnapshotId=>$snapshot_id);
    push @param,$self->create_volume_perm_parm('Add','UserId',   $args{-createvol_add_user});
    push @param,$self->create_volume_perm_parm('Remove','UserId',$args{-createvol_remove_user});
    push @param,$self->create_volume_perm_parm('Add','Group',    $args{-createvol_add_group});
    push @param,$self->create_volume_perm_parm('Remove','Group', $args{-createvol_remove_group});
    return $self->call('ModifySnapshotAttribute',@param);
}

=head2 $boolean = $ec2->reset_snapshot_attribute($snapshot_id,$attribute)

This method resets an attribute of the given snapshot to its default
value. The only valid attribute at this time is
"createVolumePermission."

=cut

sub reset_snapshot_attribute {
    my $self = shift;
    @_      == 2 or 
	croak "Usage: reset_snapshot_attribute(\$snapshotId,\$attribute_name)";
    my ($snapshot_id,$attribute) = @_;
    my %valid = map {$_=>1} qw(createVolumePermission);
    $valid{$attribute} or croak "attribute to reset must be 'createVolumePermission'";
    return $self->call('ResetSnapshotAttribute',
		       SnapshotId => $snapshot_id,
		       Attribute  => $attribute);
}


=head2 $snapshot = $ec2->create_snapshot($volume_id)

=head2 $snapshot = $ec2->create_snapshot(-volume_id=>$vol,-description=>$desc)

Snapshot the EBS volume and store it to S3 storage. To ensure a
consistent snapshot, the volume should be unmounted prior to
initiating this operation.

Arguments:

 -volume_id    -- ID of the volume to snapshot (required)
 -description  -- A description to add to the snapshot (optional)

The return value is a VM::EC2::Snapshot object that can be queried
through its current_status() interface to follow the progress of the
snapshot operation.

Another way to accomplish the same thing is through the
VM::EC2::Volume interface:

  my $volume = $ec2->describe_volumes(-filter=>{'tag:Name'=>'AccountingData'});
  $s = $volume->create_snapshot("Backed up at ".localtime);
  while ($s->current_status eq 'pending') {
     print "Progress: ",$s->progress,"% done\n";
  }
  print "Snapshot status: ",$s->current_status,"\n";

=cut

sub create_snapshot {
    my $self = shift;
    my %args = $self->args('-volume_id',@_);
    my @params   = $self->single_parm('VolumeId',\%args);
    push @params,$self->single_parm('Description',\%args);
    return $self->call('CreateSnapshot',@params);
}

=head2 $boolean = $ec2->delete_snapshot($snapshot_id) 

Delete the indicated snapshot and return true if the request was
successful.

=cut

sub delete_snapshot {
    my $self = shift;
    my %args = $self->args('-snapshot_id',@_);
    my @params   = $self->single_parm('SnapshotId',\%args);
    return $self->call('DeleteSnapshot',@params);
}

=head2 $snapshot = $ec2->copy_snapshot(-source_region=>$region,-source_snapshot_id=>$id,-description=>$desc)

Copies an existing snapshot within the same region or from one region to another.

Required arguments:
 -region       -- The region the existing snapshot to copy resides in
 -snapshot_id  -- The snapshot ID of the snapshot to copy

Optional arguments:
 -description  -- A description of the new snapshot

The return value is a VM::EC2::Snapshot object that can be queried
through its current_status() interface to follow the progress of the
snapshot operation.

=cut

sub copy_snapshot {
    my $self = shift;
    my %args = @_;
    $args{-description} ||= $args{-desc};
    $args{-source_region} ||= $args{-region};
    $args{-source_snapshot_id} ||= $args{-snapshot_id};
    $args{-source_region} or croak "copy_snapshot(): -source_region argument required";
    $args{-source_snapshot_id} or croak "copy_snapshot(): -source_snapshot_id argument required";
    my @params  = $self->single_parm('SourceRegion',\%args);
    push @params, $self->single_parm('SourceSnapshotId',\%args);
    push @params, $self->single_parm('Description',\%args);
    my $snap_id = $self->call('CopySnapshot',@params) or return;
    return eval {
            my $snapshot;
            local $SIG{ALRM} = sub {die "timeout"};
            alarm(60);
            until ($snapshot = $self->describe_snapshots($snap_id)) { sleep 1 }
            alarm(0);
            $snapshot;
    };
}

=head1 SECURITY GROUPS AND KEY PAIRS

The methods in this section allow you to query and manipulate security
groups (firewall rules) and SSH key pairs. See
L<VM::EC2::SecurityGroup> and L<VM::EC2::KeyPair> for functionality
that is available through these objects.

=head2 @sg = $ec2->describe_security_groups(@group_ids)

=head2 @sg = $ec2->describe_security_groups(%args);

=head2 @sg = $ec2->describe_security_groups(\%filters);

Searches for security groups (firewall rules) matching the provided
filters and return a series of VM::EC2::SecurityGroup objects.

In the named-argument form you can provide the following optional
arguments:

 -group_name      A single group name or an arrayref containing a list
                   of names

 -name            Shorter version of -group_name

 -group_id        A single group id (i.e. 'sg-12345') or an arrayref
                   containing a list of ids

 -filter          Filter on tags and other attributes.

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of security group filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeSecurityGroups.html

=cut

sub describe_security_groups {
    my $self = shift;
    my %args = $self->args(-group_id=>@_);
    $args{-group_name} ||= $args{-name};
    my @params = map { $self->list_parm($_,\%args) } qw(GroupName GroupId);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeSecurityGroups',@params);
}

=head2 $group = $ec2->create_security_group(-group_name=>$name,
                                            -group_description=>$description,
                                            -vpc_id     => $vpc_id
    )

Create a security group. Arguments are:

 -group_name              Name of the security group (required)
 -group_description       Description of the security group (required)
 -vpc_id                  Virtual private cloud security group ID
                           (required for VPC security groups)

For convenience, you may use -name and -description as aliases for
-group_name and -group_description respectively. 

If succcessful, the method returns an object of type
L<VM::EC2::SecurityGroup>.

=cut

sub create_security_group {
    my $self = shift;
    my %args = @_;
    $args{-group_name}        ||= $args{-name};
    $args{-group_description} ||= $args{-description};
    $args{-group_name} && $args{-group_description}
    or croak "create_security_group() requires -group_name and -group_description arguments";

    my @param;
    push @param,$self->single_parm($_=>\%args) foreach qw(GroupName GroupDescription VpcId);
    my $g = $self->call('CreateSecurityGroup',@param) or return;
    return eval {
            my $sg;
            local $SIG{ALRM} = sub {die "timeout"};
            alarm(60);
            until ($sg = $self->describe_security_groups($g)) { sleep 1 }
            alarm(0);
            $sg;
    };
}

=head2 $boolean = $ec2->delete_security_group($group_id)

=head2 $boolean = $ec2->delete_security_group(-group_id   => $group_id,
                                              -group_name => $name);

Delete a security group. Arguments are:

 -group_name              Name of the security group
 -group_id                ID of the security group

Either -group_name or -group_id is required. In the single-argument
form, the method deletes the security group given by its id.

If succcessful, the method returns true.

=cut

sub delete_security_group {
    my $self = shift;
    my %args = $self->args(-group_id=>@_);
    $args{-group_name} ||= $args{-name};
    my @param = $self->single_parm(GroupName=>\%args);
    push @param,$self->single_parm(GroupId=>\%args);
    return $self->call('DeleteSecurityGroup',@param);
}

=head2 $boolean = $ec2->update_security_group($security_group)

Add one or more incoming firewall rules to a security group. The rules
to add are stored in a L<VM::EC2::SecurityGroup> which is created
either by describe_security_groups() or create_security_group(). This method combines
the actions AuthorizeSecurityGroupIngress,
AuthorizeSecurityGroupEgress, RevokeSecurityGroupIngress, and
RevokeSecurityGroupEgress.

For details, see L<VM::EC2::SecurityGroup>. Here is a brief summary:

 $sg = $ec2->create_security_group(-name=>'MyGroup',-description=>'Example group');

 # TCP on port 80 for the indicated address ranges
 $sg->authorize_incoming(-protocol  => 'tcp',
                         -port      => 80,
                         -source_ip => ['192.168.2.0/24','192.168.2.1/24'});

 # TCP on ports 22 and 23 from anyone
 $sg->authorize_incoming(-protocol  => 'tcp',
                         -port      => '22..23',
                         -source_ip => '0.0.0.0/0');

 # ICMP on echo (ping) port from anyone
 $sg->authorize_incoming(-protocol  => 'icmp',
                         -port      => 0,
                         -source_ip => '0.0.0.0/0');

 # TCP to port 25 (mail) from instances belonging to
 # the "Mail relay" group belonging to user 12345678.
 $sg->authorize_incoming(-protocol  => 'tcp',
                         -port      => 25,
                         -group     => '12345678/Mail relay');

 $result = $ec2->update_security_group($sg);

or more simply:

 $result = $sg->update();

=cut

sub update_security_group {
    my $self = shift;
    my $sg   = shift;
    my $group_id = $sg->groupId;
    my $result = 1;
    
    for my $action (qw(Authorize Revoke)) {
	for my $direction (qw(Ingress Egress)) {
	    my @permissions = $sg->_uncommitted_permissions($action,$direction) or next;
	    my $call  = "${action}SecurityGroup${direction}";
	    my @param = (GroupId=>$group_id);
	    push @param,$self->_security_group_parm(\@permissions);
	    my $r = $self->call($call=>@param);
	    $result &&= $r;
	}
    }
    return $result;
}

sub _security_group_parm {
    my $self = shift;
    my $permissions = shift;
    my @param;

    for (my $i=0;$i<@$permissions;$i++) {
	my $perm = $permissions->[$i];
	my $n = $i+1;
	push @param,("IpPermissions.$n.IpProtocol"=>$perm->ipProtocol);
	push @param,("IpPermissions.$n.FromPort"  => $perm->fromPort);
	push @param,("IpPermissions.$n.ToPort"    => $perm->toPort);
	my @cidr = $perm->ipRanges;
	for (my $i=0;$i<@cidr;$i++) {
	    my $m = $i+1;
	    push @param,("IpPermissions.$n.IpRanges.$m.CidrIp"=>$cidr[$i]);
	}
	my @groups = $perm->groups;
	for (my $i=0;$i<@groups;$i++) {
	    my $m = $i+1;
	    my $group = $groups[$i];
	    if (defined $group->groupId) {
		push @param,("IpPermissions.$n.Groups.$m.GroupId"  => $group->groupId);
	    } else {
		push @param,("IpPermissions.$n.Groups.$m.UserId"   => $group->userId);
		push @param,("IpPermissions.$n.Groups.$m.GroupName"=> $group->groupName);
	    }
	}
    }
    return @param;
}

=head2 @keys = $ec2->describe_key_pairs(@names);

=head2 @keys = $ec2->describe_key_pairs(\%filters);

=head2 @keys = $ec2->describe_key_pairs(-key_name => \@names,
                                        -filter    => \%filters);

Searches for ssh key pairs matching the provided filters and return
a series of VM::EC2::KeyPair objects.

Optional arguments:

 -key_name      A single key name or an arrayref containing a list
                   of names

 -filter          Filter on tags and other attributes.

The full list of key filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeKeyPairs.html

=cut

sub describe_key_pairs {
    my $self = shift;
    my %args = $self->args(-key_name=>@_);
    my @params = $self->list_parm('KeyName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeKeyPairs',@params);
}

=head2 $key = $ec2->create_key_pair($name)

Create a new key pair with the specified name (required). If the key
pair already exists, returns undef. The contents of the new keypair,
including the PEM-encoded private key, is contained in the returned
VM::EC2::KeyPair object:

  my $key = $ec2->create_key_pair('My Keypair');
  if ($key) {
    print $key->fingerprint,"\n";
    print $key->privateKey,"\n";
  }

=cut

sub create_key_pair {
    my $self = shift; 
    my $name = shift or croak "Usage: create_key_pair(\$name)"; 
    $name =~ /^[\w _-]+$/
	or croak    "Invalid keypair name: must contain only alphanumerics, spaces, dashes and underscores";
    my @params = (KeyName=>$name);
    $self->call('CreateKeyPair',@params);
}

=head2 $key = $ec2->import_key_pair($name,$public_key)

=head2 $key = $ec2->import_key_pair(-key_name            => $name,
                                    -public_key_material => $public_key)

Imports a preexisting public key into AWS under the specified name.
If successful, returns a VM::EC2::KeyPair. The public key must be an
RSA key of length 1024, 2048 or 4096. The method can be called with
two unnamed arguments consisting of the key name and the public key
material, or in a named argument form with the following argument
names:

  -key_name     -- desired name for the imported key pair (required)
  -name         -- shorter version of -key_name

  -public_key_material -- public key data (required)
  -public_key   -- shorter version of the above

This example uses Net::SSH::Perl::Key to generate a new keypair, and
then uploads the public key to Amazon.

  use Net::SSH::Perl::Key;

  my $newkey = Net::SSH::Perl::Key->keygen('RSA',1024);
  $newkey->write_private('.ssh/MyKeypair.rsa');  # save private parts

  my $key = $ec2->import_key_pair('My Keypair' => $newkey->dump_public)
      or die $ec2->error;
  print "My Keypair added with fingerprint ",$key->fingerprint,"\n";

Several different formats are accepted for the key, including SSH
"authorized_keys" format (generated by L<ssh-keygen> and
Net::SSH::Perl::Key), the SSH public keys format, and DER format. You
do not need to base64-encode the key or perform any other
pre-processing.

Note that the algorithm used by Amazon to calculate its key
fingerprints differs from the one used by the ssh library, so don't
try to compare the key fingerprints returned by Amazon to the ones
produced by ssh-keygen or Net::SSH::Perl::Key.

=cut

sub import_key_pair {
    my $self = shift; 
    my %args;
    if (@_ == 2 && $_[0] !~ /^-/) {
	%args = (-key_name            => shift,
		 -public_key_material => shift);
    } else {
	%args = @_;
    }
    my $name = $args{-key_name}           || $args{-name}        or croak "-key_name argument required";
    my $pkm  = $args{-public_key_material}|| $args{-public_key}  or croak "-public_key_material argument required";
    my @params = (KeyName => $name,PublicKeyMaterial=>encode_base64($pkm));
    $self->call('ImportKeyPair',@params);
}

=head2 $result = $ec2->delete_key_pair($name)

Deletes the key pair with the specified name (required). Returns true
if successful.

=cut

sub delete_key_pair {
    my $self = shift; my $name = shift or croak "Usage: delete_key_pair(\$name)"; 
    $name =~ /^[\w _-]+$/
	or croak    "Invalid keypair name: must contain only alphanumerics, spaces, dashes and underscores";
    my @params = (KeyName=>$name);
    $self->call('DeleteKeyPair',@params);
}

=head1 TAGS

These methods allow you to create, delete and fetch resource tags. You
may find that you rarely need to use these methods directly because
every object produced by VM::EC2 supports a simple tag interface:

  $object = $ec2->describe_volumes(-volume_id=>'vol-12345'); # e.g.
  $tags = $object->tags();
  $name = $tags->{Name};
  $object->add_tags(Role => 'Web Server', Status=>'development);
  $object->delete_tags(Name=>undef);

See L<VM::EC2::Generic> for a full description of the uniform object
tagging interface.

These methods are most useful when creating and deleting tags for
multiple resources simultaneously.

=head2 @t = $ec2->describe_tags(-filter=>\%filters);

Return a series of VM::EC2::Tag objects, each describing an
AMI. A single optional -filter argument is allowed.

Available filters are: key, resource-id, resource-type and value. See
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeTags.html

=cut

sub describe_tags {
    my $self = shift;
    my %args = @_;
    my @params = $self->filter_parm(\%args);
    return $self->call('DescribeTags',@params);    
}

=head2 $bool = $ec2->create_tags(-resource_id=>\@ids,-tag=>{key1=>value1...})

Tags the resource indicated by -resource_id with the tag(s) in in the
hashref indicated by -tag. You may specify a single resource by
passing a scalar resourceId to -resource_id, or multiple resources
using an anonymous array. Returns a true value if tagging was
successful.

The method name "add_tags()" is an alias for create_tags().

You may find it more convenient to tag an object retrieved with any of
the describe() methods using the built-in add_tags() method:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 foreach (@snap) {$_->add_tags(ReadyToUse => 'true')}

but if there are many snapshots to tag simultaneously, this will be faster:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 $ec2->add_tags(-resource_id=>\@snap,-tag=>{ReadyToUse=>'true'});

Note that you can tag volumes, snapshots and images owned by other
people. Only you will be able to see these tags.

=cut

sub create_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->list_parm('ResourceId',\%args);
    push @params,$self->tagcreate_parm(\%args);
    return $self->call('CreateTags',@params);    
}

sub add_tags { shift->create_tags(@_) }

=head2 $bool = $ec2->delete_tags(-resource_id=>$id1,-tag=>{key1=>value1...})

Delete the indicated tags from the indicated resource. Pass an
arrayref to operate on several resources at once. The tag syntax is a
bit tricky. Use a value of undef to delete the tag unconditionally:

 -tag => { Role => undef }    # deletes any Role tag

Any scalar value will cause the tag to be deleted only if its value
exactly matches the specified value:

 -tag => { Role => 'Server' }  # only delete the Role tag
                               # if it currently has the value "Server"

An empty string value ('') will only delete the tag if its value is an
empty string, which is probably not what you want.

Pass an array reference of tag names to delete each of the tag names
unconditionally (same as passing a value of undef):

 $ec2->delete_tags(['Name','Role','Description']);

You may find it more convenient to delete tags from objects using
their delete_tags() method:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 foreach (@snap) {$_->delete_tags(Role => undef)}

=cut

sub delete_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->list_parm('ResourceId',\%args);
    push @params,$self->tagdelete_parm(\%args);
    return $self->call('DeleteTags',@params);    
}

=head1 ELASTIC IP ADDRESSES

The methods in this section allow you to allocate elastic IP
addresses, attach them to instances, and delete them. See
L<VM::EC2::ElasticAddress>.

=head2 @addr = $ec2->describe_addresses(@public_ips)

=head2 @addr = $ec2->describe_addresses(-public_ip=>\@addr,-allocation_id=>\@id,-filter->\%filters)

Queries AWS for a list of elastic IP addresses already allocated to
you. All arguments are optional:

 -public_ip     -- An IP address (in dotted format) or an arrayref of
                   addresses to return information about.
 -allocation_id -- An allocation ID or arrayref of such IDs. Only 
                   applicable to VPC addresses.
 -filter        -- A hashref of tag=>value pairs to filter the response
                   on.

The list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeAddresses.html.

This method returns a list of L<VM::EC2::ElasticAddress>.

=cut

sub describe_addresses {
    my $self = shift;
    my %args = $self->args(-public_ip=>@_);
    my @param;
    push @param,$self->list_parm('PublicIp',\%args);
    push @param,$self->list_parm('AllocationId',\%args);
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeAddresses',@param);
}

=head2 $address_info = $ec2->allocate_address([-vpc=>1])

Request an elastic IP address. Pass -vpc=>1 to allocate a VPC elastic
address. The return object is a VM::EC2::ElasticAddress.

=cut

sub allocate_address {
    my $self = shift;
    my %args = @_;
    my @param = $args{-vpc} ? (Domain=>'vpc') : ();
    return $self->call('AllocateAddress',@param);
}

=head2 $boolean = $ec2->release_address($addr)

Release an elastic IP address. For non-VPC addresses, you may provide
either an IP address string, or a VM::EC2::ElasticAddress. For VPC
addresses, you must obtain a VM::EC2::ElasticAddress first 
(e.g. with describe_addresses) and then pass that to the method.

=cut

sub release_address {
    my $self = shift;
    my $addr = shift or croak "Usage: release_address(\$addr)";
    my @param = (PublicIp=>$addr);
    if (my $allocationId = eval {$addr->allocationId}) {
	push @param,(AllocatonId=>$allocationId);
    }
    return $self->call('ReleaseAddress',@param);
}

=head2 $result = $ec2->associate_address($elastic_addr => $instance_id)

Associate an elastic address with an instance id. Both arguments are
mandatory. If you are associating a VPC elastic IP address with the
instance, the result code will indicate the associationId. Otherwise
it will be a simple perl truth value ("1") if successful, undef if
false.

If this is an ordinary EC2 Elastic IP address, the first argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.

=cut

sub associate_address {
    my $self = shift;
    @_ == 2 or croak "Usage: associate_address(\$elastic_addr => \$instance_id)";
    my ($addr,$instance) = @_;

    my @param = (InstanceId=>$instance);
    push @param,eval {$addr->domain eq 'vpc'} ? (AllocationId => $addr->allocationId)
	                                      : (PublicIp     => $addr);
    return $self->call('AssociateAddress',@param);
}

=head2 $bool = $ec2->disassociate_address($elastic_addr)

Disassociate an elastic address from whatever instance it is currently
associated with, if any. The result will be true if disassociation was
successful.

If this is an ordinary EC2 Elastic IP address, the argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.


=cut

sub disassociate_address {
    my $self = shift;
    @_ == 1 or croak "Usage: disassociate_address(\$elastic_addr)";
    my $addr = shift;

    my @param = eval {$addr->domain eq 'vpc'} ? (AssociationId => $addr->associationId)
	                                      : (PublicIp      => $addr);
    return $self->call('DisassociateAddress',@param);
}

=head1 RESERVED INSTANCES

These methods apply to describing, purchasing and using Reserved Instances.

=head2 @offerings = $ec2->describe_reserved_instances_offerings(@offering_ids)

=head2 @offerings = $ec2->describe_reserved_instances_offerings(%args)

This method returns a list of the reserved instance offerings
currently available for purchase. The arguments allow you to filter
the offerings according to a variety of filters. 

All arguments are optional. If no named arguments are used, then the
arguments are treated as Reserved Instance Offering IDs.
 
 -reserved_instances_offering_id  A scalar or arrayref of reserved
                                   instance offering IDs

 -instance_type                   The instance type on which the
                                   reserved instance can be used,
                                   e.g. "c1.medium"

 -availability_zone, -zone        The availability zone in which the
                                   reserved instance can be used.

 -product_description             The reserved instance description.
                                   Valid values are "Linux/UNIX",
                                   "Linux/UNIX (Amazon VPC)",
                                   "Windows", and "Windows (Amazon
                                   VPC)"

 -instance_tenancy                The tenancy of the reserved instance
                                   offering, either "default" or
                                   "dedicated". (VPC instances only)

 -offering_type                  The reserved instance offering type, one of
                                   "Heavy Utilization", "Medium Utilization",
                                   or "Light Utilization".

 -filter                          A set of filters to apply.

For available filters, see http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeReservedInstancesOfferings.html.

The returned objects are of type L<VM::EC2::ReservedInstance::Offering>

This can be combined with the Offering purchase() method as shown here:

 @offerings = $ec2->describe_reserved_instances_offerings(
          {'availability-zone'   => 'us-east-1a',
           'instance-type'       => 'c1.medium',
           'product-description' =>'Linux/UNIX',
           'duration'            => 31536000,  # this is 1 year
           });
 $offerings[0]->purchase(5) and print "Five reserved instances purchased\n";

=cut

sub describe_reserved_instances_offerings {
    my $self = shift;
    my %args = $self->args('-reserved_instances_offering_id',@_);
    $args{-availability_zone} ||= $args{-zone};
    my @param = $self->list_parm('ReservedInstancesOfferingId',\%args);
    push @param,$self->single_parm('ProductDescription',\%args);
    push @param,$self->single_parm('InstanceType',\%args);
    push @param,$self->single_parm('AvailabilityZone',\%args);
    push @param,$self->single_parm('instanceTenancy',\%args);  # should initial "i" be upcase?
    push @param,$self->single_parm('offeringType',\%args);     # should initial "o" be upcase?
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeReservedInstancesOfferings',@param);
}

=head $id = $ec2->purchase_reserved_instances_offering($offering_id)

=head $id = $ec2->purchase_reserved_instances_offering(%args)

Purchase one or more reserved instances based on an offering.

Arguments:

 -reserved_instances_offering_id, -id -- The reserved instance offering ID
                                         to purchase (required).

 -instance_count, -count              -- Number of instances to reserve
                                          under this offer (optional, defaults
                                          to 1).


Returns a Reserved Instances Id on success, undef on failure. Also see the purchase() method of
L<VM::EC2::ReservedInstance::Offering>.

=cut

sub purchase_reserved_instances_offering {
    my $self = shift;
    my %args = $self->args('-reserved_instances_offering_id'=>@_);
    $args{-reserved_instances_offering_id} ||= $args{-id};
    $args{-reserved_instances_offering_id} or 
	croak "purchase_reserved_instances_offering(): the -reserved_instances_offering_id argument is required";
    $args{-instance_count} ||= $args{-count};
    my @param = $self->single_parm('ReservedInstancesOfferingId',\%args);
    push @param,$self->single_parm('InstanceCount',\%args);
    return $self->call('PurchaseReservedInstancesOffering',@param);
}

=head2 @res_instances = $ec2->describe_reserved_instances(@res_instance_ids)

=head2 @res_instances = $ec2->describe_reserved_instances(%args)

This method returns a list of the reserved instances that you
currently own.  The information returned includes the type of
instances that the reservation allows you to launch, the availability
zone, and the cost per hour to run those reserved instances.

All arguments are optional. If no named arguments are used, then the
arguments are treated as Reserved Instance  IDs.
 
 -reserved_instances_id -- A scalar or arrayref of reserved
                            instance IDs

 -filter                -- A set of filters to apply.

For available filters, see http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeReservedInstances.html.

The returned objects are of type L<VM::EC2::ReservedInstance>

=cut

sub describe_reserved_instances {
    my $self = shift;
    my %args = $self->args('-reserved_instances_id',@_);
    my @param = $self->list_parm('ReservedInstancesId',\%args);
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeReservedInstances',@param);
}

=head1 SPOT INSTANCES

These methods allow you to request spot instances and manipulate spot
data feed subscriptions.

=cut

=head2 $subscription = $ec2->create_spot_datafeed_subscription($bucket,$prefix)

This method creates a spot datafeed subscription. Provide the method with the
name of an S3 bucket associated with your account, and a prefix to be appended
to the files written by the datafeed. Spot instance usage logs will be written 
into the requested bucket, and prefixed with the desired prefix.

If no prefix is specified, it defaults to "SPOT_DATAFEED_";

On success, a VM::EC2::Spot::DatafeedSubscription object is returned;

Only one datafeed is allowed per account;

=cut

sub create_spot_datafeed_subscription {
    my $self = shift;
    my ($bucket,$prefix) = @_;
    $bucket or croak "Usage: create_spot_datafeed_subscription(\$bucket,\$prefix)";
    $prefix ||= 'SPOT_DATAFEED_';
    my @param = (Bucket => $bucket,
		 Prefix => $prefix);
    return $self->call('CreateSpotDatafeedSubscription',@param);
}

=head2 $boolean = $ec2->delete_spot_datafeed_subscription()

This method delete's the current account's spot datafeed
subscription, if any. It takes no arguments.

On success, it returns true.

=cut

sub delete_spot_datafeed_subscription {
    my $self = shift;
    return $self->call('DeleteSpotDatafeedSubscription');
}

=head2 $subscription = $ec2->describe_spot_datafeed_subscription()

This method describes the current account's spot datafeed
subscription, if any. It takes no arguments.

On success, a VM::EC2::Spot::DatafeedSubscription object is returned;

=cut

sub describe_spot_datafeed_subscription {
    my $self = shift;
    return $self->call('DescribeSpotDatafeedSubscription');
}

=head2 @spot_price_history = $ec2->describe_spot_price_history(@filters)

This method applies the specified filters to spot instances and
returns a list of instances, timestamps and their price at the
indicated time. Each spot price history point is represented as a
VM::EC2::Spot::PriceHistory object.

Option arguments are:

 -start_time      Start date and time of the desired history
                  data, in the form yyyy-mm-ddThh:mm:ss (GMT).
                  The Perl DateTime module provides a convenient
                  way to create times in this format.

 -end_time        End date and time of the desired history
                  data.

 -instance_type   The instance type, e.g. "m1.small", can be
                  a scalar value or an arrayref.

 -product_description  The product description. One of "Linux/UNIX",
                  "SUSE Linux"  or "Windows". Can be a scalar value
                  or an arrayref.

 -availability_zone A single availability zone, such as "us-east-1a".

 -max_results     Maximum number of rows to return in a single
                  call.

 -next_token      Specifies the next set of results to return; used
                  internally.

 -filter          Hashref containing additional filters to apply, 

The following filters are recognized: "instance-type",
"product-description", "spot-price", "timestamp",
"availability-zone". The '*' and '?' wildcards can be used in filter
values, but numeric comparison operations are not supported by the
Amazon API. Note that wildcards are not generally allowed in the
standard options. Hence if you wish to get spot price history in all
availability zones in us-east, this will work:

 $ec2->describe_spot_price_history(-filter=>{'availability-zone'=>'us-east*'})

but this will return an invalid parameter error:

 $ec2->describe_spot_price_history(-availability_zone=>'us-east*')

If you specify -max_results, then the list of history objects returned
may not represent the complete result set. In this case, the method
more_spot_prices() will return true. You can then call
describe_spot_price_history() repeatedly with no arguments in order to
retrieve the remainder of the results. When there are no more results,
more_spot_prices() will return false.

 my @results = $ec2->describe_spot_price_history(-max_results       => 20,
                                                 -instance_type     => 'm1.small',
                                                 -availability_zone => 'us-east*',
                                                 -product_description=>'Linux/UNIX');
 print_history(\@results);
 while ($ec2->more_spot_prices) {
    @results = $ec2->describe_spot_price_history
    print_history(\@results);
 }

=cut

sub more_spot_prices {
    my $self = shift;
    return $self->{spot_price_history_token} &&
           !$self->{spot_price_history_stop};
}

sub describe_spot_price_history {
    my $self = shift;
    my @parms;

    if (!@_ && $self->{spot_price_history_token} && $self->{price_history_args}) {
	@parms = (@{$self->{price_history_args}},NextToken=>$self->{spot_price_history_token});
    }

    else {
	my %args = $self->args('-filter',@_);
	push @parms,$self->single_parm($_,\%args)
	    foreach qw(StartTime EndTime MaxResults AvailabilityZone);
	push @parms,$self->list_parm($_,\%args)
	    foreach qw(InstanceType ProductDescription);
	push @parms,$self->filter_parm(\%args);

	if ($args{-max_results}) {
	    $self->{spot_price_history_token} = 'xyzzy'; # dummy value
	    $self->{price_history_args} = \@parms;
	}
    }

    return $self->call('DescribeSpotPriceHistory',@parms);
}

=head2 @requests = $ec2->request_spot_instances(%args)

This method will request one or more spot instances to be launched
when the current spot instance run-hour price drops below a preset
value and terminated when the spot instance run-hour price exceeds the
value.

On success, will return a series of VM::EC2::Spot::InstanceRequest
objects, one for each instance specified in -instance_count.

=over 4

=item Required arguments:

  -spot_price        The desired spot price, in USD.

  -image_id          ID of an AMI to launch

  -instance_type     Type of the instance(s) to launch, such as "m1.small"
 
=item Optional arguments:

  -instance_count    Maximum number of instances to launch (default 1)

  -type              Spot instance request type; one of "one-time" or "persistent"

  -valid_from        Date/time the request becomes effective, in format
                       yyyy-mm-ddThh:mm:ss. Default is immediately.

  -valid_until       Date/time the request expires, in format 
                       yyyy-mm-ddThh:mm:ss. Default is to remain in
                       effect indefinitely.

  -launch_group      Name of the launch group. Instances in the same
                       launch group are started and terminated together.
                       Default is to launch instances independently.

  -availability_zone_group  If specified, all instances that are given
                       the same zone group name will be launched into the 
                       same availability zone. This is independent of
                       the -availability_zone argument, which specifies
                       a particular availability zone.

  -key_name          Name of the keypair to use

  -security_group_id Security group ID to use for this instance.
                     Use an arrayref for multiple group IDs

  -security_group    Security group name to use for this instance.
                     Use an arrayref for multiple values.

  -user_data         User data to pass to the instances. Do NOT base64
                     encode this. It will be done for you.

  -availability_zone The availability zone you want to launch the
                     instance into. Call $ec2->regions for a list.
  -zone              Short version of -availability_aone.

  -placement_group   An existing placement group to launch the
                     instance into. Applicable to cluster instances
                     only.
  -placement_tenancy Specify 'dedicated' to launch the instance on a
                     dedicated server. Only applicable for VPC
                     instances.

  -kernel_id         ID of the kernel to use for the instances,
                     overriding the kernel specified in the image.

  -ramdisk_id        ID of the ramdisk to use for the instances,
                     overriding the ramdisk specified in the image.

  -block_devices     Specify block devices to map onto the instances,
                     overriding the values specified in the image.
                     See run_instances() for the syntax of this argument.

  -block_device_mapping  Alias for -block_devices.

  -network_interfaces  Same as the -network_interfaces option in run_instances().

  -monitoring        Pass a true value to enable detailed monitoring.

  -subnet            The ID of the Amazon VPC subnet in which to launch the
                      spot instance (VPC only).

  -subnet_id         deprecated

  -addressing_type   Deprecated and undocumented, but present in the
                       current EC2 API documentation.

  -iam_arn           The Amazon resource name (ARN) of the IAM Instance Profile (IIP)
                       to associate with the instances.

  -iam_name          The name of the IAM instance profile (IIP) to associate with the
                       instances.

  -ebs_optimized     If true, request an EBS-optimized instance (certain
                       instance types only).


=cut

sub request_spot_instances {
    my $self = shift;
    my %args = @_;
    $args{-spot_price}       or croak "-spot_price argument missing";
    $args{-image_id}         or croak "-image_id argument missing";
    $args{-instance_type}    or croak "-instance_type argument missing";

    $args{-availability_zone} ||= $args{-zone};
    $args{-availability_zone} ||= $args{-placement_zone};

    my @p = map {$self->single_parm($_,\%args)}
            qw(SpotPrice InstanceCount Type ValidFrom ValidUntil LaunchGroup AvailabilityZoneGroup Subnet);

    # oddly enough, the following args need to be prefixed with "LaunchSpecification."
    my @launch_spec = map {$self->single_parm($_,\%args)}
            qw(ImageId KeyName UserData AddressingType InstanceType KernelId RamdiskId SubnetId);
    push @launch_spec, map {$self->list_parm($_,\%args)}  qw(SecurityGroup SecurityGroupId);
    push @launch_spec, ('EbsOptimized'=>'true')           if $args{-ebs_optimized};
    push @launch_spec, $self->block_device_parm($args{-block_devices}||$args{-block_device_mapping});
    push @launch_spec, $self->iam_parm(\%args);
    push @launch_spec, $self->network_interface_parm(\%args);

    while (my ($key,$value) = splice(@launch_spec,0,2)) {
	push @p,("LaunchSpecification.$key" => $value);
    }
    
    # a few more oddballs
    push @p,('LaunchSpecification.Placement.AvailabilityZone'=> $args{-availability_zone})
	if $args{-availability_zone};
    push @p,('Placement.GroupName'       =>$args{-placement_group})   if $args{-placement_group};
    push @p,('LaunchSpecification.Monitoring.Enabled'   => 'true')    if $args{-monitoring};
    push @p,('LaunchSpecification.UserData' =>
	     encode_base64($args{-user_data},''))                     if $args{-user_data};
    return $self->call('RequestSpotInstances',@p);
}

=head2 @requests = $ec2->cancel_spot_instance_requests(@request_ids)

This method cancels the pending requests. It does not terminate any
instances that are already running as a result of the requests. It
returns a list of VM::EC2::Spot::InstanceRequest objects, whose fields
will be unpopulated except for spotInstanceRequestId and state.

=cut

sub cancel_spot_instance_requests {
    my $self = shift;
    my %args = $self->args('-spot_instance_request_id',@_);
    my @parm = $self->list_parm('SpotInstanceRequestId',\%args);
    return $self->call('CancelSpotInstanceRequests',@parm);
}


=head2 @requests = $ec2->describe_spot_instance_requests(@spot_instance_request_ids)

=head2 @requests = $ec2->describe_spot_instance_requests(\%filters)

=head2 @requests = $ec2->describe_spot_instance_requests(-spot_instance_request_id=>\@ids,-filter=>\%filters)

This method will return information about current spot instance
requests as a list of VM::EC2::Spot::InstanceRequest objects.

Optional arguments:

 -spot_instance_request_id   -- Scalar or arrayref of request Ids.

 -filter                     -- Tags and other filters to apply.

There are many filters available, described fully at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/index.html?ApiReference-ItemType-SpotInstanceRequestSetItemType.html:

    availability-zone-group
    create-time
    fault-code
    fault-message
    instance-id
    launch-group
    launch.block-device-mapping.delete-on-termination
    launch.block-device-mapping.device-name
    launch.block-device-mapping.snapshot-id
    launch.block-device-mapping.volume-size
    launch.block-device-mapping.volume-type
    launch.group-id
    launch.image-id
    launch.instance-type
    launch.kernel-id
    launch.key-name
    launch.monitoring-enabled
    launch.ramdisk-id
    launch.network-interface.network-interface-id
    launch.network-interface.device-index
    launch.network-interface.subnet-id
    launch.network-interface.description
    launch.network-interface.private-ip-address
    launch.network-interface.delete-on-termination
    launch.network-interface.group-id
    launch.network-interface.group-name
    launch.network-interface.addresses.primary
    product-description
    spot-instance-request-id
    spot-price
    state
    status-code
    status-message
    tag-key
    tag-value
    tag:<key>
    type
    launched-availability-zone
    valid-from
    valid-until

=cut


sub describe_spot_instance_requests {
    my $self = shift;
    my %args = $self->args('-spot_instance_request_id',@_);
    my @params = $self->list_parm('SpotInstanceRequestId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeSpotInstanceRequests',@params);
}

=head1 PLACEMENT GROUPS

Placement groups Provide low latency and high-bandwidth connectivity
between cluster instances within a single Availability Zone. Create
a placement group and then launch cluster instances into it. Instances
launched within a placement group participate in a full-bisection
bandwidth cluster appropriate for HPC applications.

=head2 @groups = $ec2->describe_placement_groups(@group_names)

=head2 @groups = $ec2->describe_placement_groups(\%filters)

=head2 @groups = $ec2->describe_placement_groups(-group_name=>\@ids,-filter=>\%filters)

This method will return information about cluster placement groups
as a list of VM::EC2::PlacementGroup objects.

Optional arguments:

 -group_name         -- Scalar or arrayref of placement group names.

 -filter             -- Tags and other filters to apply.

The filters available are described fully at:
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribePlacementGroups.html

    group-name
    state
    strategy

=cut

sub describe_placement_groups {
    my $self = shift;
    my %args = $self->args('-group_name',@_);
    my @params = $self->list_parm('GroupName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribePlacementGroups',@params);
}

=head2 $success = $ec2->create_placement_group($group_name)

=head2 $success = $ec2->create_placement_group(-group_name=>$name,-strategy=>$strategy)

Creates a placement group that cluster instances are launched into.

Required arguments:
 -group_name          -- The name of the placement group to create

Optional:
 -strategy            -- As of 2012-12-23, the only available option is 'cluster'
                         so the parameter defaults to that.

Returns true on success.

=cut

sub create_placement_group {
    my $self = shift;
    my %args = $self->args('-group_name',@_);
    $args{-strategy} ||= 'cluster';
    my @params  = $self->single_parm('GroupName',\%args);
    push @params, $self->single_parm('Strategy',\%args);
    return $self->call('CreatePlacementGroup',@params);
}

=head2 $success = $ec2->delete_placement_group($group_name)

=head2 $success = $ec2->delete_placement_group(-group_name=>$group_name)

Deletes a placement group from the account.

Required arguments:
 -group_name          -- The name of the placement group to delete

Returns true on success.

=cut

sub delete_placement_group {
    my $self = shift;
    my %args = $self->args('-group_name',@_);
    my @params  = $self->single_parm('GroupName',\%args);
    return $self->call('DeletePlacementGroup',@params);
}

=head1 VIRTUAL PRIVATE CLOUDS

EC2 virtual private clouds (VPCs) provide facilities for creating
tiered applications combining public and private subnetworks, and for
extending your home/corporate network into the cloud.

=cut

=head2 $vpc = $ec2->create_vpc(-cidr_block=>$cidr,-instance_tenancy=>$tenancy)

Create a new VPC. This can be called with a single argument, in which
case it is interpreted as the desired CIDR block, or 

 $vpc = $ec2->$ec2->create_vpc('10.0.0.0/16') or die $ec2->error_str;

Or it can be called with named arguments.

Required arguments:

 -cidr_block      The Classless Internet Domain Routing address, in the
                  form xx.xx.xx.xx/xx. One or more subnets will be allocated
                  from within this block.

Optional arguments:

 -instance_tenancy "default" or "dedicated". The latter requests AWS to
                  launch all your instances in the VPC on single-tenant
                  hardware (at additional cost).

See
http://docs.amazonwebservices.com/AmazonVPC/latest/UserGuide/VPC_Subnets.html
for a description of the valid CIDRs that can be used with EC2.

On success, this method will return a new VM::EC2::VPC object. You can
then use this object to create new subnets within the VPC:

 $vpc     = $ec2->create_vpc('10.0.0.0/16')    or die $ec2->error_str;
 $subnet1 = $vpc->create_subnet('10.0.0.0/24') or die $vpc->error_str;
 $subnet2 = $vpc->create_subnet('10.0.1.0/24') or die $vpc->error_str;
 $subnet3 = $vpc->create_subnet('10.0.2.0/24') or die $vpc->error_str;

=cut

sub create_vpc {
    my $self = shift;
    my %args   = $self->args('-cidr_block',@_);
    $args{-cidr_block} or croak "create_vpc(): must provide a -cidr_block parameter";
    my @parm   = $self->list_parm('CidrBlock',\%args);
    push @parm,  $self->single_parm('instanceTenancy',\%args);
    return $self->call('CreateVpc',@parm);
}

=head2 @vpc = $ec2->describe_vpcs(@vpc_ids)

=head2 @vpc = $ec2->describe_vpcs(\%filter)

=head2 @vpc = $ec2->describe_vpcs(-vpc_id=>\@list,-filter=>\%filter)

Describe VPCs that you own and return a list of VM::EC2::VPC
objects. Call with no arguments to return all VPCs, or provide a list
of VPC IDs to return information on those only. You may also provide a
filter list, or named argument forms.

Optional arguments:

 -vpc_id      A scalar or array ref containing the VPC IDs you want
              information on.

 -filter      A hashref of filters to apply to the query.

The filters you can use are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVpcs.html

=cut

sub describe_vpcs {
    my $self = shift;
    my %args   = $self->args('-vpc_id',@_);
    my @parm   = $self->list_parm('VpcId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeVpcs',@parm);
}

=head2 $success = $ec2->delete_vpc($vpc_id)

=head2 $success = $ec2->delete_vpc(-vpc_id=>$vpc_id)

Delete the indicated VPC, returning true if successful.

=cut

sub delete_vpc {
    my $self = shift;
    my %args  = $self->args(-vpc_id => @_);
    my @param = $self->single_parm(VpcId=>\%args);
    return $self->call('DeleteVpc',@param);
}

=head1 VPC Subnets and Routing

These methods manage subnet objects and the routing among them. A VPC
may have a single subnet or many, and routing rules determine whether
the subnet has access to the internet ("public"), is entirely private,
or is connected to a customer gateway device to form a Virtual Private
Network (VPN) in which your home network's address space is extended
into the Amazon VPC. 

All instances in a VPC are located in one subnet or another. Subnets
may be public or private, and are organized in a star topology with a
logical router in the middle.

Although all these methods can be called from VM::EC2 objects, many
are more conveniently called from the VM::EC2::VPC object family. This
allows for steps that typically follow each other, such as creating a
route table and associating it with a subnet, happen
automatically. For example, this series of calls creates a VPC with a
single subnet, creates an Internet gateway attached to the VPC,
associates a new route table with the subnet and then creates a
default route from the subnet to the Internet gateway.

 $vpc       = $ec2->create_vpc('10.0.0.0/16')     or die $ec2->error_str;
 $subnet1   = $vpc->create_subnet('10.0.0.0/24')  or die $vpc->error_str;
 $gateway   = $vpc->create_internet_gateway       or die $vpc->error_str;
 $routeTbl  = $subnet->create_route_table         or die $vpc->error_str;
 $routeTbl->create_route('0.0.0.0/0' => $gateway) or die $vpc->error_str;

=head2 $subnet = $ec2->create_subnet(-vpc_id=>$id,-cidr_block=>$block)

This method creates a new subnet within the given VPC. Pass a VPC
object or VPC ID, and a CIDR block string. If successful, the method
will return a VM::EC2::VPC::Subnet object.

Required arguments:

 -vpc_id     A VPC ID or previously-created VM::EC2::VPC object.

 -cidr_block A CIDR block string in the form "xx.xx.xx.xx/xx". The
             CIDR address must be within the CIDR block previously
             assigned to the VPC, and must not overlap other subnets
             in the VPC.

Optional arguments:

 -availability_zone  The availability zone for the instances launched
                     within this instance, either an availability zone
                     name, or a VM::EC2::AvailabilityZone object. If
                     this is not specified, then AWS chooses a zone for
                     you automatically.

=cut

sub create_subnet {
    my $self = shift;
    my %args = @_;
    $args{-vpc_id} && $args{-cidr_block} 
      or croak "Usage: create_subnet(-vpc_id=>\$id,-cidr_block=>\$block)";
    my @parm = map {$self->single_parm($_ => \%args)} qw(VpcId CidrBlock AvailabilityZone);
    return $self->call('CreateSubnet',@parm);
}

=head2 $success = $ec2->delete_subnet($subnet_id)

=head2 $success = $ec2->delete_subnet(-subnet_id=>$id)

This method deletes the indicated subnet. It may be called with a
single argument consisting of the subnet ID, or a named argument form
with the argument -subnet_id.

=cut

sub delete_subnet {
    my $self = shift;
    my %args  = $self->args(-subnet_id=>@_);
    my @parm = $self->single_parm(SubnetId=>\%args);
    return $self->call('DeleteSubnet',@parm);
}

=head2 @subnets = $ec2->describe_subnets(@subnet_ids)

=head2 @subnets = $ec2->describe_subnets(\%filters)

=head2 @subnets = $ec2->describe_subnets(-subnet_id=>$id,
                                         -filter   => \%filters)

This method returns a list of VM::EC2::VPC::Subnet objects. Called
with no arguments, it returns all Subnets (not filtered by VPC
Id). Pass a list of subnet IDs or a filter hashref in order to
restrict the search.

Optional arguments:

 -subnet_id     Scalar or arrayref of subnet IDs.
 -filter        Hashref of filters.

Available filters are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeSubnets.html

=cut

sub describe_subnets {
    my $self = shift;
    my %args  = $self->args(-subnet_id => @_);
    my @parm   = $self->list_parm('SubnetId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeSubnets',@parm);
}

=head2 $table = $ec2->create_route_table($vpc_id)

=head2 $table = $ec2->create_route_table(-vpc_id=>$id)

This method creates a new route table within the given VPC and returns
a VM::EC2::VPC::RouteTable object. By default, every route table
includes a local route that enables traffic to flow within the
VPC. You may add additional routes using create_route().

This method can be called using a single argument corresponding to VPC
ID for the new route table, or with the named argument form.

Required arguments:

 -vpc_id     A VPC ID or previously-created VM::EC2::VPC object.

=cut

sub create_route_table {
    my $self = shift;
    my %args = $self->args(-vpc_id => @_);
    $args{-vpc_id} 
      or croak "Usage: create_route_table(-vpc_id=>\$id)";
    my @parm = $self->single_parm(VpcId => \%args);
    return $self->call('CreateRouteTable',@parm);
}

=head2 $success = $ec2->delete_route_table($route_table_id)

=head2 $success = $ec2->delete_route_table(-route_table_id=>$id)

This method deletes the indicated route table and all the route
entries within it. It may not be called on the main route table, or if
the route table is currently associated with a subnet.

The method can be called with a single argument corresponding to the
route table's ID, or using the named form with argument -route_table_id.

=cut

sub delete_route_table {
    my $self = shift;
    my %args  = $self->args(-route_table_id=>@_);
    my @parm = $self->single_parm(RouteTableId=>\%args);
    return $self->call('DeleteRouteTable',@parm);
}

=head2 @tables = $ec2->describe_route_tables(@route_table_ids)

=head2 @tables = $ec2->describe_route_tables(\%filters)

=head2 @tables = $ec2->describe_route_tables(-route_table_id=> \@ids,
                                             -filter        => \%filters);

This method describes all or some of the route tables available to
you. You may use the filter to restrict the search to a particular
type of route table using one of the filters described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeRouteTables.html.

Some of the commonly used filters are:

 vpc-id                  ID of the VPC the route table is in.
 association.subnet-id   ID of the subnet the route table is
                          associated with.
 route.state             State of the route, either 'active' or 'blackhole'
 tag:<key>               Value of a tag

=cut

sub describe_route_tables {
    my $self = shift;
    my %args  = $self->args(-route_table_id => @_);
    my @parm   = $self->list_parm('RouteTableId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeRouteTables',@parm);
}

=head2 $associationId = $ec2->associate_route_table($subnet_id => $route_table_id)

=head2 $associationId = $ec2->associate_route_table(-subnet_id      => $id,
                                                    -route_table_id => $id)

This method associates a route table with a subnet. Both objects must
be in the same VPC. You may use either string IDs, or
VM::EC2::VPC::RouteTable and VM::EC2::VPC::Subnet objects.

On success, an associationID is returned, which you may use to
disassociate the route table from the subnet later. The association ID
can also be found by searching through the VM::EC2::VPC::RouteTable
object.

Required arguments:

 -subnet_id      The subnet ID or a VM::EC2::VPC::Subnet object.

 -route_table_id The route table ID or a VM::EC2::VPC::RouteTable object.

It may be more convenient to call the
VM::EC2::VPC::Subnet->associate_route_table() or
VM::EC2::VPC::RouteTable->associate_subnet() methods, which are front
ends to this method.

=cut

sub associate_route_table {
    my $self = shift;
    my %args;
    if ($_[0] !~ /^-/ && @_ == 2) {
	@args{qw(-subnet_id -route_table_id)} = @_;
    } else {
	%args = @_;
    }
    $args{-subnet_id} && $args{-route_table_id}
       or croak "-subnet_id, and -route_table_id arguments required";
    my @param = ($self->single_parm(SubnetId=>\%args),
                $self->single_parm(RouteTableId=>\%args));
    return $self->call('AssociateRouteTable',@param);
}

=head2 $success = $ec2->dissociate_route_table($association_id)

=head2 $success = $ec2->dissociate_route_table(-association_id => $id)

This method disassociates a route table from a subnet. You must
provide the association ID (either returned from
associate_route_table() or found among the associations() of a
RouteTable object). You may use the short single-argument form, or the
longer named argument form with the required argument -association_id.

The method returns true on success.

=cut

sub disassociate_route_table {
    my $self = shift;
    my %args   = $self->args('-association_id',@_);
    my @params = $self->single_parm('AssociationId',\%args);
    return $self->call('DisassociateRouteTable',@params);
}

=head2 $new_association = $ec2->replace_route_table_association($association_id=>$route_table_id)


=head2 $new_association = $ec2->replace_route_table_association(-association_id => $id,
                                                                -route_table_id => $id)

This method changes the route table associated with a given
subnet. You must pass the replacement route table ID and the
association ID. To replace the main route table, use its association
ID and the ID of the route table you wish to replace it with.

On success, a new associationID is returned.

Required arguments:

 -association_id  The association ID

 -route_table_id   The route table ID or a M::EC2::VPC::RouteTable object.

=cut

sub replace_route_table_association {
    my $self = shift;
    my %args;
    if ($_[0] !~ /^-/ && @_ == 2) {
	@args{qw(-association_id -route_table_id)} = @_;
    } else {
	%args = @_;
    }
    $args{-association_id} && $args{-route_table_id}
       or croak "-association_id, and -route_table_id arguments required";
    my @param = $self->single_parm(AssociationId => \%args),
                $self->single_parm(RouteTableId  => \%args);
    return $self->call('ReplaceRouteTableAssociation',@param);
}

=head2 $success = $ec2->create_route($route_table_id,$destination,$target)

=head2 $success = $ec2->create_route(-route_table_id => $id,
                                     -destination_cidr_block => $block,
                                     -target=>$target)

This method creates a routing rule in a route table within a VPC. It
takes three mandatory arguments consisting of the route table, the
CIDR address block to match packet destinations against, and a target
to route matching packets to. The target may be an internet gateway, a
NAT instance, or a network interface ID.

Network packets are routed by matching their destination addresses
against a CIDR block. For example, 0.0.0.0/0 matches all addresses,
while 10.0.1.0/24 matches 10.0.1.* addresses. When a packet matches
more than one rule, the most specific matching routing rule is chosen.

In the named argument form, the following arguments are recognized:

 -route_table_id    The ID of a route table, or a VM::EC2::VPC::RouteTable
                    object.

 -destination_cidr_block
                    The CIDR address block to match against packet destinations.

 -destination       A shorthand version of -destination_cidr_block.

 -target            The destination of matching packets. See below for valid
                    targets.

The -target value can be any one of the following:

 1. A VM::EC2::VPC::InternetGateway object, or an internet gateway ID matching
    the regex /^igw-[0-9a-f]{8}$/

 2. A VM::EC2::Instance object, or an instance ID matching the regex
 /^i-[0-9a-f]{8}$/.

 3. A VM::EC2::NetworkInterface object, or a network interface ID
    matching the regex /^eni-[0-9a-f]{8}$/.

On success, this method returns true.

=cut

sub create_route {
    my $self = shift;
    return $self->_manipulate_route('CreateRoute',@_);
}

=head2 $success = $ec2->delete_route($route_table_id,$destination_block)

This method deletes a route in the specified routing table. The
destination CIDR block is used to indicate which route to delete. On
success, the method returns true.

=cut

sub delete_route {
    my $self = shift;
    @_ == 2 or croak "Usage: delete_route(\$route_table_id,\$destination_block)";
    my %args;
    @args{qw(-route_table_id -destination_cidr_block)} = @_;
    my @parm = map {$self->single_parm($_,\%args)} qw(RouteTableId DestinationCidrBlock);
    return $self->call('DeleteRoute',@parm);
}

=head2 $success = $ec2->replace_route($route_table_id,$destination,$target)

=head2 $success = $ec2->replace_route(-route_table_id => $id,
                                     -destination_cidr_block => $block,
                                     -target=>$target)

This method replaces an existing routing rule in a route table within
a VPC. It takes three mandatory arguments consisting of the route
table, the CIDR address block to match packet destinations against,
and a target to route matching packets to. The target may be an
internet gateway, a NAT instance, or a network interface ID.

Network packets are routed by matching their destination addresses
against a CIDR block. For example, 0.0.0.0/0 matches all addresses,
while 10.0.1.0/24 matches 10.0.1.* addresses. When a packet matches
more than one rule, the most specific matching routing rule is chosen.

In the named argument form, the following arguments are recognized:

 -route_table_id    The ID of a route table, or a VM::EC2::VPC::RouteTable
                    object.

 -destination_cidr_block
                    The CIDR address block to match against packet destinations.

 -destination       A shorthand version of -destination_cidr_block.

 -target            The destination of matching packets. See below for valid
                    targets.

The -target value can be any one of the following:

 1. A VM::EC2::VPC::InternetGateway object, or an internet gateway ID matching
    the regex /^igw-[0-9a-f]{8}$/

 2. A VM::EC2::Instance object, or an instance ID matching the regex
 /^i-[0-9a-f]{8}$/.

 3. A VM::EC2::NetworkInterface object, or a network interface ID
    matching the regex /^eni-[0-9a-f]{8}$/.

On success, this method returns true.

=cut

sub replace_route {
    my $self = shift;
    return $self->_manipulate_route('ReplaceRoute',@_);
}

sub _manipulate_route {
    my $self = shift;
    my $api_call = shift;

    my %args;
    if ($_[0] !~ /^-/ && @_ == 3) {
	@args{qw(-route_table_id -destination -target)} = @_;
    } else {
	%args = @_;
    }

    $args{-destination_cidr_block} ||= $args{-destination};
    $args{-destination_cidr_block} && $args{-route_table_id} && $args{-target}
       or croak "-route_table_id, -destination_cidr_block, and -target arguments required";

    # figure out what the target is.
    $args{-gateway_id}  = $args{-target} if eval{$args{-target}->isa('VM::EC2::VPC::InternetGateway')}
                                             || $args{-target} =~ /^igw-[0-9a-f]{8}$/;
    $args{-instance_id} = $args{-target} if eval{$args{-target}->isa('VM::EC2::Instance')}
                                             || $args{-target} =~ /^i-[0-9a-f]{8}$/;
    $args{-network_interface_id} = $args{-target} if eval{$args{-target}->isa('VM::EC2::NetworkInterface')}
                                             || $args{-target} =~ /^eni-[0-9a-f]{8}$/;

    my @parm = map {$self->single_parm($_,\%args)} 
               qw(RouteTableId DestinationCidrBlock GatewayId InstanceId NetworkInterfaceId);

    return $self->call($api_call,@parm);
}

=head2 $gateway = $ec2->create_internet_gateway()

This method creates a new Internet gateway. It takes no arguments and
returns a VM::EC2::VPC::InternetGateway object. Gateways are initially
independent of any VPC, but later can be attached to one or more VPCs
using attach_internet_gateway().

=cut

sub create_internet_gateway {
    my $self = shift;
    return $self->call('CreateInternetGateway');
}

=head2 $success = $ec2->delete_internet_gateway($internet_gateway_id)

=head2 $success = $ec2->delete_internet_gateway(-internet_gateway_id=>$id)

This method deletes the indicated internet gateway. It may be called
with a single argument corresponding to the route table's ID, or using
the named form with argument -internet_gateway_id.

=cut

sub delete_internet_gateway {
    my $self = shift;
    my %args  = $self->args(-internet_gateway_id=>@_);
    my @parm = $self->single_parm(InternetGatewayId=>\%args);
    return $self->call('DeleteInternetGateway',@parm);
}


=head2 @gateways = $ec2->describe_internet_gateways(@gateway_ids)

=head2 @gateways = $ec2->describe_internet_gateways(\%filters)

=head2 @gateways = $ec2->describe_internet_gateways(-internet_gateway_id=>\@ids,
                                                    -filter             =>\$filters)

This method describes all or some of the internet gateways available
to you. You may use the filter to restrict the search to a particular
type of internet gateway using one or more of the filters described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeInternetGateways.html.

Some of the commonly used filters are:

 attachment.vpc-id       ID of one of the VPCs the gateway is attached to
 attachment.state        State of the gateway, always "available"
 tag:<key>               Value of a tag

On success this method returns a list of VM::EC2::VPC::InternetGateway
objects.

=cut

sub describe_internet_gateways {
    my $self = shift;
    my %args  = $self->args(-internet_gateway_id => @_);
    my @parm   = $self->list_parm('InternetGatewayId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeInternetGateways',@parm);
}

=head2 $boolean = $ec2->attach_internet_gateway($internet_gateway_id,$vpc_id)

=head2 $boolean = $ec2->attach_internet_gateway(-internet_gateway_id => $id,
                                                -vpc_id              => $id)

This method attaches an internet gateway to a VPC.  You can use
internet gateway and VPC IDs, or their corresponding
VM::EC2::VPC::InternetGateway and VM::EC2::VPC objects.

Required arguments:

 -internet_gateway_id ID of the network interface to attach.
 -vpc_id              ID of the instance to attach the interface to.

On success, this method a true value.

Note that it may be more convenient to attach and detach gateways via
methods in the VM::EC2::VPC and VM::EC2::VPC::Gateway objects.

 $vpc->attach_internet_gateway($gateway);
 $gateway->attach($vpc);

=cut

sub attach_internet_gateway {
    my $self = shift;
    my %args; 
    if ($_[0] !~ /^-/ && @_ == 2) { 
	@args{qw(-internet_gateway_id -vpc_id)} = @_; 
    } else { 
	%args = @_;
    }
    $args{-internet_gateway_id} && $args{-vpc_id}
       or croak "-internet_gateway_id and-vpc_id arguments must be specified";

    $args{-device_index} =~ s/^eth//;
    
    my @param = $self->single_parm(InternetGatewayId=>\%args);
    push @param,$self->single_parm(VpcId=>\%args);
    return $self->call('AttachInternetGateway',@param);
}

=head2 $boolean = $ec2->detach_internet_gateway($internet_gateway_id,$vpc_id)

=head2 $boolean = $ec2->detach_internet_gateway(-internet_gateway_id => $id,
                                                -vpc_id              => $id)

This method detaches an internet gateway to a VPC.  You can use
internet gateway and VPC IDs, or their corresponding
VM::EC2::VPC::InternetGateway and VM::EC2::VPC objects.

Required arguments:

 -internet_gateway_id ID of the network interface to detach.
 -vpc_id              ID of the VPC to detach the gateway from.

On success, this method a true value.

Note that it may be more convenient to detach and detach gateways via
methods in the VM::EC2::VPC and VM::EC2::VPC::Gateway objects.

 $vpc->detach_internet_gateway($gateway);
 $gateway->detach($vpc);

=cut

sub detach_internet_gateway {
    my $self = shift;
    my %args; 
    if ($_[0] !~ /^-/ && @_ == 2) { 
	@args{qw(-internet_gateway_id -vpc_id)} = @_; 
    } else { 
	%args = @_;
    }
    $args{-internet_gateway_id} && $args{-vpc_id}
       or croak "-internet_gateway_id and-vpc_id arguments must be specified";

    $args{-device_index} =~ s/^eth//;
    
    my @param = $self->single_parm(InternetGatewayId=>\%args);
    push @param,$self->single_parm(VpcId=>\%args);
    return $self->call('DetachInternetGateway',@param);
}

=head2 @acls = $ec2->describe_network_acls(-network_acl_id=>\@ids, -filter=>\%filters)

=head2 @acls = $ec2->describe_network_acls(\@network_acl_ids)

=head2 @acls = $ec2->describe_network_acls(%filters)

Provides information about network ACLs.

Returns a series of L<VM::EC2::VPC::NetworkAcl> objects.

Optional parameters are:

 -network_acl_id      -- ID of the network ACL(s) to return information on. 
                         This can be a string scalar, or an arrayref.

 -filter              -- Tags and other filters to apply.

The filter argument is a hashreference in which the keys are the
filter names, and the values are the match strings. Some filters
accept wildcards.

There are a number of filters, which are listed in full at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeNetworkAcls.html

Here is a alpha-sorted list of filter names: 
association.association-id, association.network-acl-id,
association.subnet-id, default, entry.cidr, entry.egress,
entry.icmp.code, entry.icmp.type, entry.port-range.from,
entry.port-range.to, entry.protocol, entry.rule-action,
entry.rule-number, network-acl-id, tag-key, tag-value,
tag:key, vpc-id

=cut

sub describe_network_acls {
    my $self = shift;
    my %args = $self->args('-network_acl_id',@_);
    my @params = $self->list_parm('NetworkAclId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeNetworkAcls',@params);
}

=head2 $acl = $ec2->create_network_acl(-vpc_id=>$vpc_id)

=head2 $acl = $ec2->create_network_acl($vpc_id)

Creates a new network ACL in a VPC. Network ACLs provide an optional layer of 
security (on top of security groups) for the instances in a VPC.

Arguments:

 -vpc_id            -- The VPC ID to create the ACL in

Retuns a VM::EC2::VPC::NetworkAcl object on success.

=cut

sub create_network_acl {
    my $self = shift;
    my %args = $self->args('-vpc_id',@_);
    $args{-vpc_id} or
        croak "create_network_acl(): -vpc_id argument missing";
    my @params = $self->single_parm('VpcId',\%args);
    return $self->call('CreateNetworkAcl',@params);
}

=head2 $boolean = $ec2->delete_network_acl(-network_acl_id=>$id)

=head2 $boolean = $ec2->delete_network_acl($id)

Deletes a network ACL from a VPC. The ACL must not have any subnets associated
with it. The default network ACL cannot be deleted.

Arguments:

 -network_acl_id    -- The ID of the network ACL to delete

Returns true on successful deletion.

=cut

sub delete_network_acl {
    my $self = shift;
    my %args = $self->args('-network_acl_id',@_);
    my @params = $self->single_parm('NetworkAclId',\%args);
    return $self->call('DeleteNetworkAcl',@params);
}

=head2 $boolean = $ec2->create_network_acl_entry(%args)

Creates an entry (i.e., rule) in a network ACL with the rule number you
specified. Each network ACL has a set of numbered ingress rules and a 
separate set of numbered egress rules. When determining whether a packet
should be allowed in or out of a subnet associated with the ACL, Amazon 
VPC processes the entries in the ACL according to the rule numbers, in 
ascending order.

Arguments:

 -network_acl_id       -- ID of the ACL where the entry will be created
                          (Required)
 -rule_number          -- Rule number to assign to the entry (e.g., 100).
                          ACL entries are processed in ascending order by
                          rule number.  Positive integer from 1 to 32766.
                          (Required)
 -protocol             -- The IP protocol the rule applies to. You can use
                          -1 to mean all protocols.  See
                          http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
                          for a list of protocol numbers. (Required)
 -rule_action          -- Indicates whether to allow or deny traffic that
                           matches the rule.  allow | deny (Required)
 -egress               -- Indicates whether this rule applies to egress
                          traffic from the subnet (true) or ingress traffic
                          to the subnet (false).  Default is false.
 -cidr_block           -- The CIDR range to allow or deny, in CIDR notation
                          (e.g., 172.16.0.0/24). (Required)
 -icmp_code            -- For the ICMP protocol, the ICMP code. You can use
                          -1 to specify all ICMP codes for the given ICMP
                          type.  Required if specifying 1 (ICMP) for protocol.
 -icmp_type            -- For the ICMP protocol, the ICMP type. You can use
                          -1 to specify all ICMP types.  Required if
                          specifying 1 (ICMP) for the protocol
 -port_from            -- The first port in the range.  Required if specifying
                          6 (TCP) or 17 (UDP) for the protocol.
 -port_to              -- The last port in the range.  Required if specifying
                          6 (TCP) or 17 (UDP) for the protocol.

Returns true on successful creation.

=cut

sub create_network_acl_entry {
    my $self = shift;
    my %args = @_;
    $args{-network_acl_id} or
        croak "create_network_acl_entry(): -network_acl_id argument missing";
    $args{-rule_number} or
        croak "create_network_acl_entry(): -rule_number argument missing";
    defined $args{-protocol} or
        croak "create_network_acl_entry(): -protocol argument missing";
    $args{-rule_action} or
        croak "create_network_acl_entry(): -rule_action argument missing";
    $args{-cidr_block} or
        croak "create_network_acl_entry(): -cidr_block argument missing";
    if ($args{-protocol} == 1) {
	defined $args{-icmp_type} && defined $args{-icmp_code} or
        croak "create_network_acl_entry(): -icmp_type or -icmp_code argument missing";
    }
    elsif ($args{-protocol} == 6 || $args{-protocol} == 17) {
	defined $args{-port_from} or
		croak "create_network_acl_entry(): -port_from argument missing";
	$args{-port_to} = $args{-port_from} if (! defined $args{-port_to});
    }
    $args{'-Icmp.Type'} = $args{-icmp_type};
    $args{'-Icmp.Code'} = $args{-icmp_code};
    $args{'-PortRange.From'} = $args{-port_from};
    $args{'-PortRange.To'} = $args{-port_to};
    my @params;
    push @params,$self->single_parm($_,\%args) foreach
        qw(NetworkAclId RuleNumber Protocol RuleAction Egress CidrBlock
           Icmp.Code Icmp.Type PortRange.From PortRange.To);
    return $self->call('CreateNetworkAclEntry',@params);
}

=head2 $success = $ec2->delete_network_acl_entry(-network_acl_id=>$id,
                                                 -rule_number   =>$int,
                                                 -egress        =>$bool)

Deletes an ingress or egress entry (i.e., rule) from a network ACL.

Arguments:

 -network_acl_id       -- ID of the ACL where the entry will be created

 -rule_number          -- Rule number of the entry (e.g., 100).

Optional arguments:

 -egress    -- Whether the rule to delete is an egress rule (true) or ingress 
               rule (false).  Default is false.

Returns true on successful deletion.

=cut

sub delete_network_acl_entry {
    my $self = shift;
    my %args = @_;
    $args{-network_acl_id} or
        croak "delete_network_acl_entry(): -network_acl_id argument missing";
    $args{-rule_number} or
        croak "delete_network_acl_entry(): -rule_number argument missing";
    my @params;
    push @params,$self->single_parm($_,\%args) foreach
        qw(NetworkAclId RuleNumber Egress);
    return $self->call('DeleteNetworkAclEntry',@params);
}

=head2 $assoc_id = $ec2->replace_network_acl_association(-association_id=>$assoc_id,
                                                         -network_acl_id=>$id)

Changes which network ACL a subnet is associated with. By default when you
create a subnet, it's automatically associated with the default network ACL.

Arguments:

 -association_id    -- The ID of the association to replace

 -network_acl_id    -- The ID of the network ACL to associated the subnet with

Returns the new association ID.

=cut

sub replace_network_acl_association {
    my $self = shift;
    my %args = @_;
    $args{-association_id} or
        croak "replace_network_acl_association(): -association_id argument missing";
    $args{-network_acl_id} or
        croak "replace_network_acl_association(): -network_acl_id argument missing";
    my @params;
    push @params,$self->single_parm($_,\%args) foreach
        qw(AssociationId NetworkAclId);
    return $self->call('ReplaceNetworkAclAssociation',@params);
}

=head2 $success = $ec2->replace_network_acl_entry(%args)

Replaces an entry (i.e., rule) in a network ACL.

Arguments:

 -network_acl_id       -- ID of the ACL where the entry will be created
                          (Required)
 -rule_number          -- Rule number of the entry to replace. (Required)
 -protocol             -- The IP protocol the rule applies to. You can use
                          -1 to mean all protocols.  See
                          http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
                          for a list of protocol numbers. (Required)
 -rule_action          -- Indicates whether to allow or deny traffic that
                           matches the rule.  allow | deny (Required)
 -egress               -- Indicates whether this rule applies to egress
                          traffic from the subnet (true) or ingress traffic
                          to the subnet (false).  Default is false.
 -cidr_block           -- The CIDR range to allow or deny, in CIDR notation
                          (e.g., 172.16.0.0/24). (Required)
 -icmp_code            -- For the ICMP protocol, the ICMP code. You can use
                          -1 to specify all ICMP codes for the given ICMP
                          type.  Required if specifying 1 (ICMP) for protocol.
 -icmp_type            -- For the ICMP protocol, the ICMP type. You can use
                          -1 to specify all ICMP types.  Required if
                          specifying 1 (ICMP) for the protocol
 -port_from            -- The first port in the range.  Required if specifying
                          6 (TCP) or 17 (UDP) for the protocol.
 -port_to              -- The last port in the range.  Only required if
                          specifying 6 (TCP) or 17 (UDP) for the protocol and
                          is a different port than -port_from.

Returns true on successful replacement.

=cut

sub replace_network_acl_entry {
    my $self = shift;
    my %args = @_;
    $args{-network_acl_id} or
        croak "replace_network_acl_entry(): -network_acl_id argument missing";
    $args{-rule_number} or
        croak "replace_network_acl_entry(): -rule_number argument missing";
    $args{-protocol} or
        croak "replace_network_acl_entry(): -protocol argument missing";
    $args{-rule_action} or
        croak "replace_network_acl_entry(): -rule_action argument missing";
    if ($args{-protocol} == 1) { 
        defined $args{-icmp_type} && defined $args{-icmp_code} or
        croak "replace_network_acl_entry(): -icmp_type or -icmp_code argument missing";
    }
    elsif ($args{-protocol} == 6 || $args{-protocol} == 17) {
	defined $args{-port_from} or
		croak "create_network_acl_entry(): -port_from argument missing";
	$args{-port_to} = $args{-port_from} if (! defined $args{-port_to});
    }
    $args{'-Icmp.Type'} = $args{-icmp_type};
    $args{'-Icmp.Code'} = $args{-icmp_code};
    $args{'-PortRange.From'} = $args{-port_from};
    $args{'-PortRange.To'} = $args{-port_to};
    my @params;
    push @params,$self->single_parm($_,\%args) foreach
        qw(NetworkAclId RuleNumber Protocol RuleAction Egress CidrBlock
           Icmp.Code Icmp.Type PortRange.From PortRange.To);
    return $self->call('ReplaceNetworkAclEntry',@params);
}

=head1 DHCP Options

These methods manage DHCP Option objects, which can then be applied to
a VPC to configure the DHCP options applied to running instances.

=head2 $options = $ec2->create_dhcp_options(\%configuration_list)

This method creates a DhcpOption object, The single required argument is a
configuration list hash (which can be passed either as a hashref or a
flattened hash) with one or more of the following keys:

 -domain_name            Domain name for instances running in this VPC.

 -domain_name_servers    Scalar or arrayref containing up to 4 IP addresses of
                         domain name servers for this VPC.

 -ntp_servers            Scalar or arrayref containing up to 4 IP addresses
                         of network time protocol servers

 -netbios_name_servers   Scalar or arrayref containing up to 4 IP addresses for
                         NetBIOS name servers.

 -netbios_node_type      The NetBios node type (1,2,4 or 8). Amazon recommends
                         using "2" at this time.

On successful completion, a VM::EC2::VPC::DhcpOptions object will be
returned. This can be associated with a VPC using the VPC object's
set_dhcp_options() method:

 $vpc     = $ec2->create_vpc(...);
 $options = $ec2->create_dhcp_options(-domain_name=>'test.com',
                                      -domain_name_servers=>['204.16.255.55','216.239.34.10']);
 $vpc->set_dhcp_options($options);

=cut

# { 'domain-name-servers' => ['192.168.2.1','192.168.2.2'],'domain-name'=>'example.com'}
sub create_dhcp_options {
    my $self = shift;
    my %args;
    if (@_ == 1 && ref $_[0] eq 'HASH') {
	%args = %{$_[0]};
    } else {
	%args = @_;
    }
    my @parm;
    my $count = 1;
    for my $key (sort keys %args) {
	my $value  = $args{$key};
	my @values = ref $value && ref $value eq 'ARRAY' ? @$value : $value;
	$key =~ s/^-//;
	$key =~ s/_/-/g;
	my $item = 1;
	push @parm,("DhcpConfiguration.$count.Key"  => $key);
	push @parm,("DhcpConfiguration.$count.Value.".$item++ => $_) foreach @values;
	$count++;
    }
    return $self->call('CreateDhcpOptions',@parm);
}

=head2 $success = $ec2->delete_dhcp_options($dhcp_id)

Delete the indicated DHCPOptions, returning true if successful. You
may also use the named argument -dhcp_options_id..

=cut

sub delete_dhcp_options {
    my $self = shift;
    my %args  = $self->args(-dhcp_options_id => @_);
    my @param = $self->single_parm(DhcpOptionsId=>\%args);
    return $self->call('DeleteDhcpOptions',@param);
}

=head2 @options = $ec2->describe_dhcp_options(@option_ids)

=head2 @options = $ec2->describe_dhcp_options(\%filters)

=head2 @options = $ec2->describe_dhcp_options(-dhcp_options_id=>$id,
                                              -filter         => \%filters)

This method returns a list of VM::EC2::VPC::DhcpOptions objects, which
describe a set of DHCP options that can be assigned to a VPC. Called
with no arguments, it returns all DhcpOptions. Pass a list of option
IDs or a filter hashref in order to restrict the search.

Optional arguments:

 -dhcp_options_id     Scalar or arrayref of DhcpOption IDs.
 -filter              Hashref of filters.

Available filters are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeDhcpOptions.html.

=cut

sub describe_dhcp_options {
    my $self = shift;
    my %args  = $self->args(-dhcp_options_id => @_);
    my @parm   = $self->list_parm('DhcpOptionsId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeDhcpOptions',@parm);
}

=head2 $success = $ec2->associate_dhcp_options($vpc_id => $dhcp_id)

=head2 $success = $ec2->associate_dhcp_options(-vpc_id => $vpc_id,-dhcp_options_id => $dhcp_id)

Associate a VPC ID with a DHCP option set. Pass an ID of 'default' to
restore the default DHCP options for the VPC.

=cut

sub associate_dhcp_options {
    my $self = shift;
    my %args;
    if ($_[0] !~ /^-/ && @_ == 2) {
	@args{qw(-vpc_id -dhcp_options_id)} = @_;
    } else {
	%args = @_;
    }
    $args{-vpc_id} && $args{-dhcp_options_id}
      or croak "-vpc_id and -dhcp_options_id must be specified";
    my @param    = $self->single_parm(DhcpOptionsId=> \%args);
    push @param,   $self->single_parm(VpcId        => \%args);
    return $self->call('AssociateDhcpOptions',@param);
}

=head1 Virtual Private Networks

These methods create and manage Virtual Private Network (VPN) connections
to an Amazon Virtual Private Cloud (VPC).

=head2 @gtwys = $ec2->describe_vpn_gateways(-vpn_gateway_id=>\@ids,
                                            -filter        =>\%filters)

=head2 @gtwys = $ec2->describe_vpn_gateways(@vpn_gateway_ids)

=head2 @gtwys = $ec2->describe_vpn_gateways(%filters)

Provides information on VPN gateways.

Return a series of VM::EC2::VPC::VpnGateway objects.  When called with no
arguments, returns all VPN gateways.  Pass a list of VPN gateway IDs or
use the assorted filters to restrict the search.

Optional parameters are:

 -vpn_gateway_id         ID of the gateway(s) to return information on. 
                         This can be a string scalar, or an arrayref.

 -filter                 Tags and other filters to apply.

The filter argument is a hashreference in which the keys are the
filter names, and the values are the match strings. Some filters
accept wildcards.

There are a number of filters, which are listed in full at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVpnGateways.html

Here is a alpha-sorted list of filter names: attachment.state,
attachment.vpc-id, availability-zone, state, tag-key, tag-value, tag:key, type,
vpn-gateway-id

=cut

sub describe_vpn_gateways {
    my $self = shift;
    my %args = $self->args('-vpn_gateway_id',@_);
    my @params = $self->list_parm('VpnGatewayId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeVpnGateways',@params);
}

=head2 $vpn_gateway = $ec2->create_vpn_gateway(-type=>$type)

=head2 $vpn_gateway = $ec2->create_vpn_gateway($type)

=head2 $vpn_gateway = $ec2->create_vpn_gateway

Creates a new virtual private gateway. A virtual private gateway is the
VPC-side endpoint for a VPN connection. You can create a virtual private 
gateway before creating the VPC itself.

 -type switch is optional as there is only one type as of API 2012-06-15

Returns a VM::EC2::VPC::VpnGateway object on success

=cut

sub create_vpn_gateway {
    my $self = shift;
    my %args = $self->args('-type',@_);
    $args{-type} ||= 'ipsec.1';
    my @params = $self->list_parm('Type',\%args);
    return $self->call('CreateVpnGateway',@params);
}

=head2 $success = $ec2->delete_vpn_gateway(-vpn_gateway_id=>$id);

=head2 $success = $ec2->delete_vpn_gateway($id);

Deletes a virtual private gateway.  Use this when a VPC and all its associated 
components are no longer needed.  It is recommended that before deleting a 
virtual private gateway, detach it from the VPC and delete the VPN connection.
Note that it is not necessary to delete the virtual private gateway if the VPN 
connection between the VPC and data center needs to be recreated.

Arguments:

 -vpn_gateway_id    -- The ID of the VPN gateway to delete.

Returns true on successful deletion

=cut

sub delete_vpn_gateway {
    my $self = shift;
    my %args = $self->args('-vpn_gateway_id',@_);
    $args{-vpn_gateway_id} or
        croak "delete_vpn_gateway(): -vpn_gateway_id argument missing";
    my @params = $self->single_parm('VpnGatewayId',\%args);
    return $self->call('DeleteVpnGateway',@params);
}

=head2 $state = $ec2->attach_vpn_gateway(-vpn_gateway_id=>$vpn_gtwy_id,
                                         -vpc_id        =>$vpc_id)

Attaches a virtual private gateway to a VPC.

Arguments:

 -vpc_id          -- The ID of the VPC to attach the VPN gateway to

 -vpn_gateway_id  -- The ID of the VPN gateway to attach

Returns the state of the attachment, one of:
   attaching | attached | detaching | detached

=cut

sub attach_vpn_gateway {
    my $self = shift;
    my %args = @_;
    $args{-vpn_gateway_id} or
        croak "attach_vpn_gateway(): -vpn_gateway_id argument missing";
    $args{-vpc_id} or
        croak "attach_vpn_gateway(): -vpc_id argument missing";
    my @params = $self->single_parm('VpnGatewayId',\%args);
    push @params, $self->single_parm('VpcId',\%args);
    return $self->call('AttachVpnGateway',@params);
}

=head2 $success = $ec2->detach_vpn_gateway(-vpn_gateway_id=>$vpn_gtwy_id,
                                           -vpc_id        =>$vpc_id)

Detaches a virtual private gateway from a VPC. You do this if you're
planning to turn off the VPC and not use it anymore. You can confirm
a virtual private gateway has been completely detached from a VPC by
describing the virtual private gateway (any attachments to the 
virtual private gateway are also described).

You must wait for the attachment's state to switch to detached 
before you can delete the VPC or attach a different VPC to the 
virtual private gateway.

Arguments:

 -vpc_id          -- The ID of the VPC to detach the VPN gateway from

 -vpn_gateway_id  -- The ID of the VPN gateway to detach

Returns true on successful detachment.

=cut

sub detach_vpn_gateway {
    my $self = shift;
    my %args = @_;
    $args{-vpn_gateway_id} or
        croak "detach_vpn_gateway(): -vpn_gateway_id argument missing";
    $args{-vpc_id} or
        croak "detach_vpn_gateway(): -vpc_id argument missing";
    my @params = $self->single_parm('VpnGatewayId',\%args);
    push @params, $self->single_parm('VpcId',\%args);
    return $self->call('DetachVpnGateway',@params);
}

=head2 @vpn_connections = $ec2->describe_vpn_connections(-vpn_connection_id=>\@ids,
                                                         -filter=>\%filters);

=head2 @vpn_connections = $ec2->describe_vpn_connections(@vpn_connection_ids)

=head2 @vpn_connections = $ec2->describe_vpn_connections(%filters);

Gives information about VPN connections

Returns a series of VM::EC2::VPC::VpnConnection objects.

Optional parameters are:

 -vpn_connection_id      ID of the connection(s) to return information on. 
                         This can be a string scalar, or an arrayref.

 -filter                 Tags and other filters to apply.

The filter argument is a hashreference in which the keys are the
filter names, and the values are the match strings. Some filters
accept wildcards.

There are a number of filters, which are listed in full at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVpnConnections.html

Here is a alpha-sorted list of filter names:
customer-gateway-configuration, customer-gateway-id, state,
tag-key, tag-value, tag:key, type, vpn-connection-id,
vpn-gateway-id

=cut

sub describe_vpn_connections {
    my $self = shift;
    my %args = $self->args('-vpn_connection_id',@_);
    my @params = $self->list_parm('VpnConnectionId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeVpnConnections',@params);
}

=head2 $vpn_connection = $ec2->create_vpn_connection(-type               =>$type,
                                                     -customer_gateway_id=>$gtwy_id,
                                                     -vpn_gateway_id     =>$vpn_id)

Creates a new VPN connection between an existing virtual private 
gateway and a VPN customer gateway. The only supported connection 
type is ipsec.1.

Required Arguments:

 -customer_gateway_id       -- The ID of the customer gateway

 -vpn_gateway_id            -- The ID of the VPN gateway

Optional arguments:
 -type                      -- Default is the only currently available option:
                               ipsec.1 (API 2012-06-15)

 -static_routes_only        -- Indicates whether or not the VPN connection
                               requires static routes. If you are creating a VPN
                               connection for a device that does not support
                               BGP, you must specify this value as true.

Returns a L<VM::EC2::VPC::VpnConnection> object.

=cut

sub create_vpn_connection {
    my $self = shift;
    my %args = @_;
    $args{-type} ||= 'ipsec.1';
    $args{-vpn_gateway_id} or
        croak "create_vpn_connection(): -vpn_gateway_id argument missing";
    $args{-customer_gateway_id} or
        croak "create_vpn_connection(): -customer_gateway_id argument missing";
    $args{'Options.StaticRoutesOnly'} = $args{-static_routes_only};
    my @params;
    push @params,$self->single_parm($_,\%args) foreach
        qw(VpnGatewayId CustomerGatewayId Type);
    push @params,$self->boolean_parm('Options.StaticRoutesOnly',\%args);
    return $self->call('CreateVpnConnection',@params);
}

=head2 $success = $ec2->delete_vpn_connection(-vpn_connection_id=>$vpn_id)

=head2 $success = $ec2->delete_vpn_connection($vpn_id)

Deletes a VPN connection. Use this if you want to delete a VPC and 
all its associated components. Another reason to use this operation
is if you believe the tunnel credentials for your VPN connection 
have been compromised. In that situation, you can delete the VPN 
connection and create a new one that has new keys, without needing
to delete the VPC or virtual private gateway. If you create a new 
VPN connection, you must reconfigure the customer gateway using the
new configuration information returned with the new VPN connection ID.

Arguments:

 -vpn_connection_id       -- The ID of the VPN connection to delete

Returns true on successful deletion.

=cut

sub delete_vpn_connection {
    my $self = shift;
    my %args = $self->args('-vpn_connection_id',@_);
    $args{-vpn_connection_id} or
        croak "delete_vpn_connection(): -vpn_connection_id argument missing";
    my @params = $self->single_parm('VpnConnectionId',\%args);
    return $self->call('DeleteVpnConnection',@params);
}

=head2 @gtwys = $ec2->describe_customer_gateways(-customer_gateway_id=>\@ids,
                                                 -filter             =>\%filters)

=head2 @gtwys = $ec2->describe_customer_gateways(\@customer_gateway_ids)

=head2 @gtwys = $ec2->describe_customer_gateways(%filters)

Provides information on VPN customer gateways.

Returns a series of VM::EC2::VPC::CustomerGateway objects.

Optional parameters are:

 -customer_gateway_id    ID of the gateway(s) to return information on. 
                         This can be a string scalar, or an arrayref.

 -filter                 Tags and other filters to apply.

The filter argument is a hashreference in which the keys are the filter names,
and the values are the match strings. Some filters accept wildcards.

There are a number of filters, which are listed in full at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeCustomerGateways.html

Here is a alpha-sorted list of filter names: bgp-asn, customer-gateway-id, 
ip-address, state, type, tag-key, tag-value, tag:key

=cut

sub describe_customer_gateways {
    my $self = shift;
    my %args = $self->args('-customer_gateway_id',@_);
    my @params = $self->list_parm('CustomerGatewayId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeCustomerGateways',@params);
}

=head2 $cust_gtwy = $ec2->create_customer_gateway(-type      =>$type,
                                                  -ip_address=>$ip,
                                                  -bgp_asn   =>$asn)

Provides information to AWS about a VPN customer gateway device. The customer 
gateway is the appliance at the customer end of the VPN connection (compared 
to the virtual private gateway, which is the device at the AWS side of the 
VPN connection).

Arguments:

 -ip_address     -- The IP address of the customer gateway appliance

 -bgp_asn        -- The Border Gateway Protocol (BGP) Autonomous System Number
                    (ASN) of the customer gateway

 -type           -- Optional as there is only currently (2012-06-15 API) only
                    one type (ipsec.1)

 -ip             -- Alias for -ip_address

Returns a L<VM::EC2::VPC::CustomerGateway> object on success.

=cut

sub create_customer_gateway {
    my $self = shift;
    my %args = @_;
    $args{-type} ||= 'ipsec.1';
    $args{-ip_address} ||= $args{-ip};
    $args{-ip_address} or
        croak "create_customer_gateway(): -ip_address argument missing";
    $args{-bgp_asn} or
        croak "create_customer_gateway(): -bgp_asn argument missing";
    my @params = $self->single_parm('Type',\%args);
    push @params, $self->single_parm('IpAddress',\%args);
    push @params, $self->single_parm('BgpAsn',\%args);
    return $self->call('CreateCustomerGateway',@params);
}

=head2 $success = $ec2->delete_customer_gateway(-customer_gateway_id=>$id)

=head2 $success = $ec2->delete_customer_gateway($id)

Deletes a VPN customer gateway. You must delete the VPN connection before 
deleting the customer gateway.

Arguments:

 -customer_gateway_id     -- The ID of the customer gateway to delete

Returns true on successful deletion.

=cut

sub delete_customer_gateway {
    my $self = shift;
    my %args = $self->args('-customer_gateway_id',@_);
    $args{-customer_gateway_id} or
        croak "delete_customer_gateway(): -customer_gateway_id argument missing";
    my @params = $self->single_parm('CustomerGatewayId',\%args);
    return $self->call('DeleteCustomerGateway',@params);
}

=head2 $success = $ec2->create_vpn_connection_route(-destination_cidr_block=>$cidr,
                                                    -vpn_connection_id     =>$id)

Creates a new static route associated with a VPN connection between an existing
virtual private gateway and a VPN customer gateway. The static route allows
traffic to be routed from the virtual private gateway to the VPN customer
gateway.

Arguments:

 -destination_cidr_block     -- The CIDR block associated with the local subnet
                                 of the customer data center.

 -vpn_connection_id           -- The ID of the VPN connection.

Returns true on successsful creation.

=cut

sub create_vpn_connection_route {
    my $self = shift;
    my %args = @_;
    $args{-destination_cidr_block} or
        croak "create_vpn_connection_route(): -destination_cidr_block argument missing";
    $args{-vpn_connection_id} or
        croak "create_vpn_connection_route(): -vpn_connection_id argument missing";
    my @params = $self->single_parm($_,\%args)
        foreach qw(DestinationCidrBlock VpnConnectionId);
    return $self->call('CreateVpnConnectionRoute',@params);
}

=head2 $success = $ec2->delete_vpn_connection_route(-destination_cidr_block=>$cidr,
                                                    -vpn_connection_id     =>$id)

Deletes a static route associated with a VPN connection between an existing
virtual private gateway and a VPN customer gateway. The static route allows
traffic to be routed from the virtual private gateway to the VPN customer
gateway.

Arguments:

 -destination_cidr_block     -- The CIDR block associated with the local subnet
                                 of the customer data center.

 -vpn_connection_id           -- The ID of the VPN connection.

Returns true on successsful deletion.

=cut

sub delete_vpn_connection_route {
    my $self = shift;
    my %args = @_;
    $args{-destination_cidr_block} or
        croak "delete_vpn_connection_route(): -destination_cidr_block argument missing";
    $args{-vpn_connection_id} or
        croak "delete_vpn_connection_route(): -vpn_connection_id argument missing";
    my @params = $self->single_parm($_,\%args)
        foreach qw(DestinationCidrBlock VpnConnectionId);
    return $self->call('DeleteVpnConnectionRoute',@params);
}

=head2 $success = $ec2->disable_vgw_route_propogation(-route_table_id=>$rt_id,
                                                      -gateway_id    =>$gtwy_id)

Disables a virtual private gateway (VGW) from propagating routes to the routing
tables of an Amazon VPC.

Arguments:

 -route_table_id        -- The ID of the routing table.

 -gateway_id            -- The ID of the virtual private gateway.

Returns true on successful disablement.

=cut

sub disable_vgw_route_propogation {
    my $self = shift;
    my %args = @_;
    $args{-route_table_id} or
        croak "disable_vgw_route_propogation(): -route_table_id argument missing";
    $args{-gateway_id} or
        croak "disable_vgw_route_propogation(): -gateway_id argument missing";
    my @params = $self->single_parm($_,\%args)
        foreach qw(RouteTableId GatewayId);
    return $self->call('DisableVgwRoutePropagation',@params);
}

=head2 $success = $ec2->enable_vgw_route_propogation(-route_table_id=>$rt_id,
                                                     -gateway_id    =>$gtwy_id)

Enables a virtual private gateway (VGW) to propagate routes to the routing
tables of an Amazon VPC.

Arguments:

 -route_table_id        -- The ID of the routing table.

 -gateway_id            -- The ID of the virtual private gateway.

Returns true on successful enablement.

=cut

sub enable_vgw_route_propogation {
    my $self = shift;
    my %args = @_;
    $args{-route_table_id} or
        croak "enable_vgw_route_propogation(): -route_table_id argument missing";
    $args{-gateway_id} or
        croak "enable_vgw_route_propogation(): -gateway_id argument missing";
    my @params = $self->single_parm($_,\%args)
        foreach qw(RouteTableId GatewayId);
    return $self->call('EnableVgwRoutePropagation',@params);
}

=head1 Elastic Network Interfaces

These methods create and manage Elastic Network Interfaces (ENI). Once
created, an ENI can be attached to instances and/or be associated with
a public IP address. ENIs can only be used in conjunction with VPC
instances.

=head2 $interface = $ec2->create_network_interface($subnet_id)

=head2 $interface = $ec2->create_network_interface(%args)

This method creates an elastic network interface (ENI). If only a
single argument is provided, it is treated as the ID of the VPC subnet
to associate with the ENI. If multiple arguments are provided, they
are treated as -arg=>value parameter pairs.

Arguments:

The -subnet_id argument is mandatory. Others are optional.

 -subnet_id           --  ID of the VPC subnet to associate with the network
                           interface (mandatory)

 -private_ip_address  --  The primary private IP address of the network interface,
                           or a reference to an array of private IP addresses. In the
                           latter case, the first element of the array becomes the
                           primary address, and the subsequent ones become secondary
                           addresses. If no private IP address is specified, one will
                           be chosen for you. See below for more information on this
                           parameter.

 -private_ip_addresses -- Same as -private_ip_address, for readability.

 -secondary_ip_address_count -- An integer requesting this number of secondary IP
                          addresses to be allocated automatically. If present, 
                          cannot provide any secondary addresses explicitly.

 -description          -- Description of this ENI.

 -security_group_id    -- Array reference or scalar containing IDs of the security
                           group(s) to assign to this interface.

You can assign multiple IP addresses to the interface explicitly, or
by allowing EC2 to choose addresses within the designated subnet
automatically. The following examples demonstrate the syntax:

 # one primary address, chosen explicitly
 -private_ip_address => '192.168.0.12'

 # one primary address and two secondary addresses, chosen explicitly
 -private_ip_address => ['192.168.0.12','192.168.0.200','192.168.0.201'] 

 # one primary address chosen explicitly, and two secondaries chosen automatically
 -private_ip_address => ['192.168.0.12','auto','auto']

 # one primary address chosen explicitly, and two secondaries chosen automatically (another syntax)
 -private_ip_address => ['192.168.0.12',2]

 # one primary address chosen automatically, and two secondaries chosen automatically
 -private_ip_address => [auto,2]

You cannot assign some secondary addresses explicitly and others
automatically on the same ENI. If you provide no -private_ip_address
parameter at all, then a single private IP address will be chosen for
you (the same as -private_ip_address=>'auto').

The return value is a VM::EC2::NetworkInterface object

=cut

# NOTE: there is code overlap with network_interface_parm()
sub create_network_interface {
    my $self = shift;
    my %args = $self->args(-subnet_id=>@_);
    $args{-subnet_id} or croak "Usage: create_network_interface(-subnet_id=>\$id,\@more_args)";
    my   @parm = $self->single_parm('SubnetId',\%args);
    push @parm,  $self->single_parm('Description',\%args);
    push @parm,  $self->list_parm('SecurityGroupId',\%args);

    my $address   = $args{-private_ip_address} || $args{-private_ip_addresses};
    my $auto_count;

    if ($address) {
	my $c = 0;

	my @addresses = ref $address && ref $address eq 'ARRAY' ? @$address : ($address);
	my $primary   = shift @addresses;
	unless ($primary eq 'auto') {
	    push @parm, ("PrivateIpAddresses.$c.PrivateIpAddress" => $primary);
	    push @parm, ("PrivateIpAddresses.$c.Primary"          => 'true');
	}

	# deal with automatic secondary addresses .. this seems needlessly complex
	if (my @auto = grep {/auto/i} @addresses) {
	    @auto == @addresses or croak "cannot request both explicit and automatic secondary IP addresses";
	    $auto_count = @auto;
	}
	$auto_count = $addresses[0] if @addresses == 1 && $addresses[0] =~ /^\d+$/;
	$auto_count ||= $args{-secondary_ip_address_count};
	
	unless ($auto_count) {
	    foreach (@addresses) {
		$c++;
		push @parm,("PrivateIpAddresses.$c.PrivateIpAddress" => $_     );
		push @parm,("PrivateIpAddresses.$c.Primary"          => 'false');
	    }
	}
    }
    push @parm,('SecondaryPrivateIpAddressCount'=>$auto_count) if $auto_count ||= $args{-secondary_ip_address_count};

    $self->call('CreateNetworkInterface',@parm);
}

=head2 $result = $ec2->assign_private_ip_addresses(%args)

Assign one or more secondary private IP addresses to a network
interface. You can either set the addresses explicitly, or provide a
count of secondary addresses, and let Amazon select them for you.

Required arguments:

 -network_interface_id    The network interface to which the IP address(es)
                          will be assigned.

 -private_ip_address      One or more secondary IP addresses, as a scalar string
 -private_ip_addresses    or array reference. (The two arguments are equivalent).

Optional arguments:

 -allow_reassignment      If true, allow assignment of an IP address is already in
                          use by another network interface or instance.

The following are valid arguments to -private_ip_address:

 -private_ip_address => '192.168.0.12'                    # single address
 -private_ip_address => ['192.168.0.12','192.168.0.13]    # multiple addresses
 -private_ip_address => 3                                 # autoselect three addresses

The mixed form of address, such as ['192.168.0.12','auto'] is not allowed in this call.

On success, this method returns true.

=cut

sub assign_private_ip_addresses {
    my $self = shift;
    my %args = $self->args(-network_interface_id => @_);
    $args{-private_ip_address} ||= $args{-private_ip_addresses};
    $args{-network_interface_id} && $args{-private_ip_address}
      or croak "usage: assign_private_ip_addresses(-network_interface_id=>\$id,-private_ip_address=>\\\@addresses)";
    my @parms = $self->single_parm('NetworkInterfaceId',\%args);

    if (!ref($args{-private_ip_address}) && $args{-private_ip_address} =~ /^\d+$/) {
	push @parms,('SecondaryPrivateIpAddressCount' => $args{-private_ip_address});
    } else {
	push @parms,$self->list_parm('PrivateIpAddress',\%args);
    }
    push @parms,('AllowReassignment' => $args{-allow_reassignment} ? 'true' : 'false')
	if exists $args{-allow_reassignment};
    $self->call('AssignPrivateIpAddresses',@parms);
}

=head2 $result = $ec2->unassign_private_ip_addresses(%args)

Unassign one or more secondary private IP addresses from a network
interface.

Required arguments:

 -network_interface_id    The network interface to which the IP address(es)
                          will be assigned.

 -private_ip_address      One or more secondary IP addresses, as a scalar string
 -private_ip_addresses    or array reference. (The two arguments are equivalent).


The following are valid arguments to -private_ip_address:

 -private_ip_address => '192.168.0.12'                    # single address
 -private_ip_address => ['192.168.0.12','192.168.0.13]    # multiple addresses

On success, this method returns true.

=cut

sub unassign_private_ip_addresses {
    my $self = shift;
    my %args = $self->args(-network_interface_id => @_);
    $args{-private_ip_address} ||= $args{-private_ip_addresses};
    $args{-network_interface_id} && $args{-private_ip_address}
      or croak "usage: assign_private_ip_addresses(-network_interface_id=>\$id,-private_ip_address=>\\\@addresses)";
    my @parms = $self->single_parm('NetworkInterfaceId',\%args);
    push @parms,$self->list_parm('PrivateIpAddress',\%args);
    $self->call('UnassignPrivateIpAddresses',@parms);
}

=head2 $result = $ec2->delete_network_interface($network_interface_id);

=head2 $result = $ec2->delete_network_interface(-network_interface_id => $id);

Deletes the specified network interface. Returns a boolean indicating
success of the delete operation.

=cut

sub delete_network_interface {
    my $self = shift;
    my %args  = $self->args(-network_interface_id => @_);
    my @param = $self->single_parm(NetworkInterfaceId=>\%args);
    return $self->call('DeleteNetworkInterface',@param);
}

=head2 @ifs = $ec2->describe_network_interfaces(@interface_ids)

=head2 @ifs = $ec2->describe_network_interfaces(\%filters)

=head2 @ifs = $ec2->describe_network_interfaces(-network_interface_id=>\@interface_ids,-filter=>\%filters)

Return a list of elastic network interfaces as
VM::EC2::VPC::NetworkInterface objects. You may restrict the list by
passing a list of network interface IDs, a hashref of filters or by
using the full named-parameter form.

Optional arguments:

 -network_interface_id    A single network interface ID or an arrayref to
                           a list of IDs.

 -filter                  A hashref for filtering on tags and other attributes.

The list of valid filters can be found at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeNetworkInterfaces.html.

=cut

sub describe_network_interfaces {
    my $self = shift;
    my %args = $self->args(-network_interface_id=>@_);
    my @params = $self->list_parm('NetworkInterfaceId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeNetworkInterfaces',@params);
}

=head2 @data = $ec2->describe_network_interface_attribute($network_id,$attribute)

This method returns network interface attributes. Only one attribute
can be retrieved at a time. The following is the list of attributes
that can be retrieved:

 description           -- hashref
 groupSet              -- hashref
 sourceDestCheck       -- hashref
 attachment            -- hashref

These values can be retrieved more conveniently from the
L<VM::EC2::NetworkInterface> object, so there is no attempt to parse
the results of this call into Perl objects.

=cut

sub describe_network_interface_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_network_interface_attribute(\$interface_id,\$attribute_name)";
    my ($interface_id,$attribute) = @_;
    my @param  = (NetworkInterfaceId=>$interface_id,Attribute=>$attribute);
    my $result = $self->call('DescribeNetworkInterfaceAttribute',@param);
    return $result && $result->attribute($attribute);
}

=head2 $boolean = $ec2->modify_network_interface_attribute($interface_id,-$attribute_name=>$value)

This method changes network interface attributes. Only one attribute can be set per call
The following is the list of attributes that can be set:

 -description             -- interface description
 -security_group_id       -- single security group ID or arrayref to a list of group ids
 -source_dest_check       -- boolean; if false enables packets to be forwarded, and is necessary
                               for NAT and other router tasks
 -delete_on_termination   -- [$attachment_id=>$delete_on_termination]; Pass this a two-element
                               array reference consisting of the attachment ID and a boolean 
                               indicating whether deleteOnTermination should be enabled for
                               this attachment.
=cut

sub modify_network_interface_attribute {
    my $self = shift;
    my $interface_id = shift or croak "Usage: modify_network_interface_attribute(\$interfaceId,%param)";
    my %args   = @_;
    my @param  = (NetworkInterfaceId=>$interface_id);
    push @param,$self->value_parm($_,\%args) foreach qw(Description SourceDestCheck);
    push @param,$self->list_parm('SecurityGroupId',\%args);
    if (my $dot = $args{-delete_on_termination}) {
	my ($attachment_id,$delete_on_termination) = @$dot;
	push @param,'Attachment.AttachmentId'=>$attachment_id;
	push @param,'Attachment.DeleteOnTermination'=>$delete_on_termination ? 'true' : 'false';
    }
    return $self->call('ModifyNetworkInterfaceAttribute',@param);
}

=head2 $boolean = $ec2->reset_network_interface_attribute($interface_id => $attribute_name)

This method resets the named network interface attribute to its
default value. Only one attribute can be reset per call. The AWS
documentation is not completely clear on this point, but it appears
that the only attribute that can be reset using this method is:

 source_dest_check       -- Turns on source destination checking 

For consistency with modify_network_interface_attribute, you may
specify attribute names with or without a leading dash, and using
either under_score or mixedCase naming:

 $ec2->reset_network_interface_atribute('eni-12345678' => 'source_dest_check');
 $ec2->reset_network_interface_atribute('eni-12345678' => '-source_dest_check');
 $ec2->reset_network_interface_atribute('eni-12345678' => sourceDestCheck);

=cut

sub reset_network_interface_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: reset_network_interface_attribute(\$interfaceId,\$attribute)";
    my ($interface_id,$attribute) = @_;

    $attribute = s/^-//;
    $attribute = $self->uncanonicalize($attribute);
    my @param = (NetworkInterfaceId=> $interface_id,
		 Attribute         => $attribute
	);
    return $self->call('ResetNetworkInterfaceAttribute',@param);
}

=head2 $attachmentId = $ec2->attach_network_interface($network_interface_id,$instance_id,$device_index)

=head2 $attachmentId = $ec2->attach_network_interface(-network_interface_id => $id,
                                                      -instance_id          => $id,
                                                      -device_index         => $index)

This method attaches a network interface to an instance using the
indicated device index. You can use instance and network interface
IDs, or VM::EC2::Instance and VM::EC2::NetworkInterface objects. You
may use an integer for -device_index, or use the strings "eth0",
"eth1" etc.

Required arguments:

 -network_interface_id ID of the network interface to attach.
 -instance_id          ID of the instance to attach the interface to.
 -device_index         Network device number to use (e.g. 0 for eth0).

On success, this method returns the attachmentId of the new attachment
(not a VM::EC2::NetworkInterface::Attachment object, due to an AWS API
inconsistency).

Note that it may be more convenient to attach and detach network
interfaces via methods in the VM::EC2::Instance and
VM::EC2::NetworkInterface objects:

 $instance->attach_network_interface($interface=>'eth0');
 $interface->attach($instance=>'eth0');

=cut

sub attach_network_interface {
    my $self = shift;
    my %args; 
    if ($_[0] !~ /^-/ && @_ == 3) { 
	@args{qw(-network_interface_id -instance_id -device_index)} = @_; 
    } else { 
	%args = @_;
    }
    $args{-network_interface_id} && $args{-instance_id} && defined $args{-device_index} or
	croak "-network_interface_id, -instance_id and -device_index arguments must all be specified";

    $args{-device_index} =~ s/^eth//;
    
    my @param = $self->single_parm(NetworkInterfaceId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(DeviceIndex=>\%args);
    return $self->call('AttachNetworkInterface',@param);
}

=head2 $boolean = $ec2->detach_network_interface($attachment_id [,$force])

This method detaches a network interface from an instance. Both the
network interface and instance are specified using their
attachmentId. If the $force flag is present, and true, then the
detachment will be forced even if the interface is in use.

Note that it may be more convenient to attach and detach network
interfaces via methods in the VM::EC2::Instance and
VM::EC2::NetworkInterface objects:

 $instance->detach_network_interface($interface);
 $interface->detach();

=cut

sub detach_network_interface {
    my $self = shift;
    my ($attachment_id,$force) = @_;
    $attachment_id or croak "Usage: detach_network_interface(\$attachment_id [,\$force])";
    my @param = (AttachmentId => $attachment_id);
    push @param,(Force => 'true') if defined $force && $force;
    return $self->call('DetachNetworkInterface',@param);
}

=head1 Elastic Load Balancers (ELB)

The methods in this section allow you to retrieve information about
Elastic Load Balancers, create new ELBs, and change the properties
of the ELBs.

The primary object manipulated by these methods is
L<VM::EC2::ELB>. Please see the L<VM::EC2::ELB> manual page

=head2 @lbs = $ec2->describe_load_balancers(-load_balancer_name=>\@names)

=head2 @lbs = $ec2->describe_load_balancers(@names)

Provides detailed configuration information for the specified ELB(s).

Optional parameters are:

    -load_balancer_names     Name of the ELB to return information on. 
                             This can be a string scalar, or an arrayref.

    -lb_name,-lb_names,      
      -load_balancer_name    Aliases for -load_balancer_names

Returns a series of L<VM::EC2::ELB> objects.

=cut

sub describe_load_balancers {
    my $self = shift;
    my %args = $self->args('-load_balancer_names',@_);
    $args{'-load_balancer_names'} ||= $args{-lb_name};
    $args{'-load_balancer_names'} ||= $args{-lb_names};
    $args{'-load_balancer_names'} ||= $args{-load_balancer_name};
    my @params = $self->member_list_parm('LoadBalancerNames',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->elb_call('DescribeLoadBalancers',@params);
}

=head2 $success = $ec2->delete_load_balancer(-load_balancer_name=>$name)

=head2 $success = $ec2->delete_load_balancer($name)

Deletes the specified ELB.

Arguments:

 -load_balancer_name    -- The name of the ELB to delete

 -lb_name               -- Alias for -load_balancer_name

Returns true on successful deletion.  NOTE:  This API call will return
success regardless of existence of the ELB.

=cut

sub delete_load_balancer {
    my $self = shift;
    my %args = $self->args('-load_balancer_name',@_);
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "delete_load_balancer(): -load_balancer_name argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    return $self->elb_call('DeleteLoadBalancer',@params);
}

=head2 $healthcheck = $ec2->configure_health_check(-load_balancer_name  => $name,
                                                   -healthy_threshold   => $cnt,
                                                   -interval            => $secs,
                                                   -target              => $target,
                                                   -timeout             => $secs,
                                                   -unhealthy_threshold => $cnt)

Define an application healthcheck for the instances.

All Parameters are required.

    -load_balancer_name    Name of the ELB.

    -healthy_threashold    Specifies the number of consecutive health probe successes 
                           required before moving the instance to the Healthy state.

    -interval              Specifies the approximate interval, in seconds, between 
                           health checks of an individual instance.

    -target                Must be a string in the form: Protocol:Port[/PathToPing]
                            - Valid Protocol types are: HTTP, HTTPS, TCP, SSL
                            - Port must be in range 1-65535
                            - PathToPing is only applicable to HTTP or HTTPS protocol
                              types and must be 1024 characters long or fewer.

    -timeout               Specifies the amount of time, in seconds, during which no
                           response means a failed health probe.

    -unhealthy_threashold  Specifies the number of consecutive health probe failures
                           required before moving the instance to the Unhealthy state.

    -lb_name               Alias for -load_balancer_name

Returns a L<VM::EC2::ELB::HealthCheck> object.

=cut

sub configure_health_check {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "configure_health_check(): -load_balancer_name argument missing";
    $args{-healthy_threshold} && $args{-interval} &&
        $args{-target} && $args{-timeout} && $args{-unhealthy_threshold} or
        croak "configure_health_check(): healthcheck argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, map {$self->prefix_parm('HealthCheck',$_,\%args)}
        qw(HealthyThreshold Interval Target Timeout UnhealthyThreshold);
    return $self->elb_call('ConfigureHealthCheck',@params);
}

=head2 $success = $ec2->create_app_cookie_stickiness_policy(-load_balancer_name => $name,
                                                            -cookie_name        => $cookie,
                                                            -policy_name        => $policy)

Generates a stickiness policy with sticky session lifetimes that follow that of
an application-generated cookie. This policy can be associated only with
HTTP/HTTPS listeners.

Required arguments:

    -load_balancer_name    Name of the ELB.

    -cookie_name           Name of the application cookie used for stickiness.

    -policy_name           The name of the policy being created. The name must
                           be unique within the set of policies for this ELB. 

    -lb_name               Alias for -load_balancer_name

Returns true on successful execution.

=cut

sub create_app_cookie_stickiness_policy {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "create_app_cookie_stickiness_policy(): -load_balancer_name argument missing";
    $args{-cookie_name} && $args{-policy_name} or
        croak "create_app_cookie_stickiness_policy(): -cookie_name or -policy_name option missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, map {$self->single_parm($_,\%args)} qw(CookieName PolicyName);
    return $self->elb_call('CreateAppCookieStickinessPolicy',@params);
}

=head2 $success = $ec2->create_lb_cookie_stickiness_policy(-load_balancer_name       => $name,
                                                           -cookie_expiration_period => $secs,
                                                           -policy_name              => $policy)

Generates a stickiness policy with sticky session lifetimes controlled by the
lifetime of the browser (user-agent) or a specified expiration period. This
policy can be associated only with HTTP/HTTPS listeners.

Required arguments:

    -load_balancer_name         Name of the ELB.

    -cookie_expiration_period   The time period in seconds after which the
                                cookie should be considered stale. Not
                                specifying this parameter indicates that the
                                sticky session will last for the duration of
                                the browser session.  OPTIONAL

    -policy_name                The name of the policy being created. The name
                                must be unique within the set of policies for 
                                this ELB. 

    -lb_name                    Alias for -load_balancer_name

Returns true on successful execution.

=cut

sub create_lb_cookie_stickiness_policy {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "create_lb_cookie_stickiness_policy(): -load_balancer_name argument missing";
    $args{-cookie_expiration_period} && $args{-policy_name} or
        croak "create_lb_cookie_stickiness_policy(): -cookie_expiration_period or -policy_name option missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, map {$self->single_parm($_,\%args)} qw(CookieExpirationPeriod PolicyName);
    return $self->elb_call('CreateLBCookieStickinessPolicy',@params);
}

=head2 $lb = $ec2->create_load_balancer(-load_balancer_name => $name,
                                        -listeners          => \@listeners,
                                        -availability_zones => \@zones,
                                        -scheme             => $scheme,
)

Creates a new ELB.

Required arguments:

    -load_balancer_name         Name of the ELB.

    -listeners                  Must either be a L<VM::EC2::ELB:Listener> object
                                (or arrayref of objects) or a hashref (or arrayref
                                of hashrefs) containing the following keys:

              Protocol            -- Value as one of: HTTP, HTTPS, TCP, or SSL
              LoadBalancerPort    -- Value in range 1-65535
              InstancePort        -- Value in range 1-65535
                and optionally:
              InstanceProtocol    -- Value as one of: HTTP, HTTPS, TCP, or SSL
              SSLCertificateId    -- Certificate ID from AWS IAM certificate list


    -availability_zones    Literal string or array of strings containing valid
                           availability zones.  Optional if subnets are
                           specified in a VPC usage scenario.

Optional arguments:

    -scheme                The type of ELB.  By default, Elastic Load Balancing
                           creates an Internet-facing LoadBalancer with a
                           publicly resolvable DNS name, which resolves to
                           public IP addresses.  Specify the value 'internal'
                           for this option to create an internal LoadBalancer
                           with a DNS name that resolves to private IP addresses.
                           This option is only available in a VPC.

    -security_groups       The security groups assigned to your ELB within your
                           VPC.  String or arrayref.

    -subnets               A list of subnet IDs in your VPC to attach to your
                           ELB.  String or arrayref.  REQUIRED if availability
                           zones are not specified above.

Argument aliases:

    -zones                 Alias for -availability_zones
    -lb_name               Alias for -load_balancer_name
                          
Returns a L<VM::EC2::ELB> object if successful.

=cut

sub create_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-availability_zones } ||= $args{-zones};
    $args{-load_balancer_name} or
        croak "create_load_balancer(): -load_balancer_name argument missing";
    $args{-listeners} or
        croak "create_load_balancer(): -listeners option missing";
    $args{-availability_zones} || $args{-subnets} or
        croak "create_load_balancer(): -availability_zones option is required if subnets are not specified";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->_listener_parm($args{-listeners});
    push @params, $self->member_list_parm('AvailabilityZones',\%args);
    push @params, $self->single_parm('Scheme',\%args);
    push @params, $self->member_list_parm('SecurityGroups',\%args);
    push @params, $self->member_list_parm('Subnets',\%args);
    return unless $self->elb_call('CreateLoadBalancer',@params);
    return eval {
            my $elb;
            local $SIG{ALRM} = sub {die "timeout"};
            alarm(60);
            until ($elb = $self->describe_load_balancers($args{-load_balancer_name})) { sleep 1 }
            alarm(0);
            $elb;
    };
}


# Internal method for building ELB listener parameters
sub _listener_parm {
    my $self = shift;
    my $l = shift;
    my @param;

    my $i = 1;
    for my $lsnr (ref $l && ref $l eq 'ARRAY' ? @$l : $l) {
        if (ref $lsnr && ref $lsnr eq 'HASH') {
            push @param,("Listeners.member.$i.Protocol"=> $lsnr->{Protocol});
            push @param,("Listeners.member.$i.LoadBalancerPort"=> $lsnr->{LoadBalancerPort});
            push @param,("Listeners.member.$i.InstancePort"=> $lsnr->{InstancePort});
            push @param,("Listeners.member.$i.InstanceProtocol"=> $lsnr->{InstanceProtocol})
                if $lsnr->{InstanceProtocol};
            push @param,("Listeners.member.$i.SSLCertificateId"=> $lsnr->{SSLCertificateId})
                if $lsnr->{SSLCertificateId};
            $i++;
        } elsif (ref $lsnr && ref $lsnr eq 'VM::EC2::ELB::Listener') {
            push @param,("Listeners.member.$i.Protocol"=> $lsnr->Protocol);
            push @param,("Listeners.member.$i.LoadBalancerPort"=> $lsnr->LoadBalancerPort);
            push @param,("Listeners.member.$i.InstancePort"=> $lsnr->InstancePort);
            if (my $InstanceProtocol = $lsnr->InstanceProtocol) {
                push @param,("Listeners.member.$i.InstanceProtocol"=> $InstanceProtocol)
            }
            if (my $SSLCertificateId = $lsnr->SSLCertificateId) {
                push @param,("Listeners.member.$i.SSLCertificateId"=> $SSLCertificateId)
            }
            $i++;
        }
    }
    return @param;
}

=head2 $success = $ec2->create_load_balancer_listeners(-load_balancer_name => $name,
                                                       -listeners          => \@listeners)

Creates one or more listeners on a ELB for the specified port. If a listener 
with the given port does not already exist, it will be created; otherwise, the
properties of the new listener must match the properties of the existing
listener.

 -listeners    Must either be a L<VM::EC2::ELB:Listener> object (or arrayref of
               objects) or a hash (or arrayref of hashes) containing the
               following keys:

             Protocol            -- Value as one of: HTTP, HTTPS, TCP, or SSL
             LoadBalancerPort    -- Value in range 1-65535
             InstancePort        -- Value in range 1-65535
              and optionally:
             InstanceProtocol    -- Value as one of: HTTP, HTTPS, TCP, or SSL
             SSLCertificateId    -- Certificate ID from AWS IAM certificate list

 -lb_name      Alias for -load_balancer_name

Returns true on successful execution.

=cut

sub create_load_balancer_listeners {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "create_load_balancer_listeners(): -load_balancer_name argument missing";
    $args{-listeners} or
        croak "create_load_balancer_listeners(): -listeners option missing";

    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->_listener_parm($args{-listeners});
    return $self->elb_call('CreateLoadBalancerListeners',@params);
}

=head2 $success = $ec2->delete_load_balancer_listeners(-load_balancer_name  => $name,
                                                       -load_balancer_ports => \@ports)

Deletes listeners from the ELB for the specified port.

Arguments:

 -load_balancer_name     The name of the ELB

 -load_balancer_ports    An arrayref of strings or literal string containing
                         the port numbers.

 -ports                  Alias for -load_balancer_ports

 -lb_name                Alias for -load_balancer_name

Returns true on successful execution.

=cut

sub delete_load_balancer_listeners {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_ports} ||= $args{-ports};
    $args{-load_balancer_name} or
        croak "delete_load_balancer_listeners(): -load_balancer_name argument missing";
    $args{-load_balancer_ports} or
        croak "delete_load_balancer_listeners(): -load_balancer_ports argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('LoadBalancerPorts',\%args);
    return $self->elb_call('DeleteLoadBalancerListeners',@params);
}

=head2 @z = $ec2->disable_availability_zones_for_load_balancer(-load_balancer_name => $name,
                                                               -availability_zones => \@zones)

Removes the specified EC2 Availability Zones from the set of configured
Availability Zones for the ELB.  There must be at least one Availability Zone
registered with a LoadBalancer at all times.  Instances registered with the ELB
that are in the removed Availability Zone go into the OutOfService state.

Arguments:

 -load_balancer_name    The name of the ELB

 -availability_zones    Arrayref or literal string of availability zone names
                        (ie. us-east-1a)

 -zones                 Alias for -availability_zones

 -lb_name               Alias for -load_balancer_name


Returns an array of L<VM::EC2::AvailabilityZone> objects now associated with the ELB.

=cut

sub disable_availability_zones_for_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-availability_zones} ||= $args{-zones};
    $args{-load_balancer_name} or
        croak "disable_availability_zones_for_load_balancer(): -load_balancer_name argument missing";
    $args{-availability_zones} or
        croak "disable_availability_zones_for_load_balancer(): -availability_zones argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('AvailabilityZones',\%args);
    my @zones = $self->elb_call('DisableAvailabilityZonesForLoadBalancer',@params) or return;
    return $self->describe_availability_zones(@zones);
}

=head2 @z = $ec2->enable_availability_zones_for_load_balancer(-load_balancer_name => $name,
                                                              -availability_zones => \@zones)

Adds one or more EC2 Availability Zones to the ELB.  The ELB evenly distributes
requests across all its registered Availability Zones that contain instances.

Arguments:

 -load_balancer_name    The name of the ELB

 -availability_zones    Array or literal string of availability zone names
                        (ie. us-east-1a)

 -zones                 Alias for -availability_zones

 -lb_name               Alias for -load_balancer_name

Returns an array of L<VM::EC2::AvailabilityZone> objects now associated with the ELB.

=cut

sub enable_availability_zones_for_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-availability_zones} ||= $args{-zones};
    $args{-load_balancer_name} or
        croak "enable_availability_zones_for_load_balancer(): -load_balancer_name argument missing";
    $args{-availability_zones} or
        croak "enable_availability_zones_for_load_balancer(): -availability_zones argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('AvailabilityZones',\%args);
    my @zones = $self->elb_call('EnableAvailabilityZonesForLoadBalancer',@params) or return;
    return $self->describe_availability_zones(@zones);
}

=head2 @i = $ec2->register_instances_with_load_balancer(-load_balancer_name => $name,
                                                        -instances          => \@instance_ids)

Adds new instances to the ELB.  If the instance is in an availability zone that
is not registered with the ELB will be in the OutOfService state.  Once the zone
is added to the ELB the instance will go into the InService state.

Arguments:

 -load_balancer_name    The name of the ELB

 -instances             An arrayref or literal string of Instance IDs.

 -lb_name               Alias for -load_balancer_name

Returns an array of instances now associated with the ELB in the form of
L<VM::EC2::Instance> objects.

=cut

sub register_instances_with_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-instances} ||= $args{-instance_id};
    $args{-load_balancer_name} or
        croak "register_instances_with_load_balancer(): -load_balancer_name argument missing";
    $args{-instances} or
        croak "register_instances_with_load_balancer(): -instances argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->_perm_parm('Instances','member','InstanceId',$args{-instances});
    my @i = $self->elb_call('RegisterInstancesWithLoadBalancer',@params) or return;
    return $self->describe_instances(@i);
}

=head2 @i = $ec2->deregister_instances_from_load_balancer(-load_balancer_name => $name,
                                                          -instances          => \@instance_ids)

Deregisters instances from the ELB. Once the instance is deregistered, it will
stop receiving traffic from the ELB. 

Arguments:

 -load_balancer_name    The name of the ELB

 -instances             An arrayref or literal string of Instance IDs.

 -lb_name               Alias for -load_balancer_name

Returns an array of instances now associated with the ELB in the form of
L<VM::EC2::Instance> objects.

=cut

sub deregister_instances_from_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-instances} ||= $args{-instance_id};
    $args{-load_balancer_name} or
        croak "deregister_instances_from_load_balancer(): -load_balancer_name argument missing";
    $args{-instances} or
        croak "deregister_instances_from_load_balancer(): -instances argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->_perm_parm('Instances','member','InstanceId',$args{-instances});
    my @i = $self->elb_call('DeregisterInstancesFromLoadBalancer',@params) or return;
    return $self->describe_instances(@i);
}

=head2 $success = $ec2->set_load_balancer_listener_ssl_certificate(-load_balancer_name => $name,
                                                                   -load_balancer_port => $port,
                                                                   -ssl_certificate_id => $cert_id)

Sets the certificate that terminates the specified listener's SSL connections.
The specified certificate replaces any prior certificate that was used on the
same ELB and port.

Required arguments:

 -load_balancer_name    The name of the the ELB.

 -load_balancer_port    The port that uses the specified SSL certificate.

 -ssl_certificate_id    The ID of the SSL certificate chain to use.  See the
                        AWS Identity and Access Management documentation under
                        Managing Server Certificates for more information.

Alias arguments:

 -lb_name    Alias for -load_balancer_name

 -port       Alias for -load_balancer_port

 -cert_id    Alias for -ssl_certificate_id

Returns true on successful execution.

=cut

sub set_load_balancer_listener_ssl_certificate {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_port} ||= $args{-port};
    $args{-ssl_certificate_id} ||= $args{-cert_id};
    $args{-load_balancer_name} or
        croak "set_load_balancer_listener_ssl_certificate(): -load_balancer_name argument missing";
    $args{-load_balancer_port} or
        croak "set_load_balancer_listener_ssl_certificate(): -load_balancer_port argument missing";
    $args{-ssl_certificate_id} or
        croak "set_load_balancer_listener_ssl_certificate(): -ssl_certificate_id argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->single_parm('LoadBalancerPort',\%args);
    push @params,('SSLCertificateId'=>$args{-ssl_certificate_id}) if $args{-ssl_certificate_id};
    return $self->elb_call('SetLoadBalancerListenerSSLCertificate',@params);
}

=head2 @states = $ec2->describe_instance_health(-load_balancer_name => $name,
                                                -instances          => \@instance_ids)

Returns the current state of the instances of the specified LoadBalancer. If no
instances are specified, the state of all the instances for the ELB is returned.

Required arguments:

    -load_balancer_name     The name of the ELB

Optional parameters:

    -instances              Literal string or arrayref of Instance IDs

    -lb_name                Alias for -load_balancer_name

    -instance_id            Alias for -instances

Returns an array of L<VM::EC2::ELB::InstanceState> objects.

=cut

sub describe_instance_health {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-instances} ||= $args{-instance_id};
    $args{-load_balancer_name} or
        croak "describe_instance_health(): -load_balancer_name argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->_perm_parm('Instances','member','InstanceId',$args{-instances});
    return $self->elb_call('DescribeInstanceHealth',@params);
}

=head2 $success = $ec2->create_load_balancer_policy(-load_balancer_name => $name,
                                                    -policy_name        => $policy,
                                                    -policy_type_name   => $type_name,
                                                    -policy_attributes  => \@attrs)

Creates a new policy that contains the necessary attributes depending on the
policy type. Policies are settings that are saved for your ELB and that can be
applied to the front-end listener, or the back-end application server,
depending on your policy type.

Required Arguments:

 -load_balancer_name   The name associated with the LoadBalancer for which the
                       policy is being created. This name must be unique within
                       the client AWS account.

 -policy_name          The name of the ELB policy being created. The name must
                       be unique within the set of policies for this ELB.

 -policy_type_name     The name of the base policy type being used to create
                       this policy. To get the list of policy types, use the
                       describe_load_balancer_policy_types function.

Optional Arguments:

 -policy_attributes    Arrayref of hashes containing AttributeName and AttributeValue

 -lb_name              Alias for -load_balancer_name

Returns true if successful.

=cut

sub create_load_balancer_policy {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "create_load_balancer_policy(): -load_balancer_name argument missing";
    $args{-policy_name} or
        croak "create_load_balancer_policy(): -policy_name argument missing";
    $args{-policy_type_name} or
        croak "create_load_balancer_policy(): -policy_type_name argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->single_parm('PolicyName',\%args);
    push @params, $self->single_parm('PolicyTypeName',\%args);
    push @params, $self->_policy_attr_parm($args{-policy_attributes});
    return $self->elb_call('CreateLoadBalancerPolicy',@params);
}

# internal method for building policy attribute parameters
sub _policy_attr_parm {
    my $self = shift;
    my $p = shift;
    my @param;

    my $i = 1;
    for my $policy (ref $p && ref $p eq 'ARRAY' ? @$p : $p) {
        if (ref $policy && ref $policy eq 'HASH') {
            push @param,("PolicyAttributes.member.$i.AttributeName"=> $policy->{AttributeName});
            push @param,("PolicyAttributes.member.$i.AttributeValue"=> $policy->{AttributeValue});
            $i++;
        } elsif (ref $policy && ref $policy eq 'VM::EC2::ELB::PolicyAttribute') {
            push @param,("PolicyAttributes.member.$i.AttributeName"=> $policy->AttributeName);
            push @param,("PolicyAttributes.member.$i.AttributeValue"=> $policy->AttributeValue);
            $i++;
        }
    }
    return @param;
}

=head2 $success = $ec2->delete_load_balancer_policy(-load_balancer_name => $name,
                                                    -policy_name        => $policy)

Deletes a policy from the ELB. The specified policy must not be enabled for any
listeners.

Arguments:

 -load_balancer_name    The name of the ELB

 -policy_name           The name of the ELB policy

 -lb_name               Alias for -load_balancer_name

Returns true if successful.

=cut

sub delete_load_balancer_policy {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "delete_load_balancer_policy(): -load_balancer_name argument missing";
    $args{-policy_name} or
        croak "delete_load_balancer_policy(): -policy_name argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->single_parm('PolicyName',\%args);
    return $self->elb_call('DeleteLoadBalancerPolicy',@params);
}

=head2 @policy_descs = $ec2->describe_load_balancer_policies(-load_balancer_name => $name,
                                                             -policy_names       => \@names)

Returns detailed descriptions of ELB policies. If you specify an ELB name, the
operation returns either the descriptions of the specified policies, or
descriptions of all the policies created for the ELB. If you don't specify a ELB
name, the operation returns descriptions of the specified sample policies, or 
descriptions of all the sample policies. The names of the sample policies have 
the ELBSample- prefix.

Optional Arguments:

 -load_balancer_name  The name of the ELB.

 -policy_names        The names of ELB policies created or ELB sample policy names.

 -lb_name             Alias for -load_balancer_name

Returns an array of L<VM::EC2::ELB::PolicyDescription> objects if successful.

=cut

sub describe_load_balancer_policies {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-policy_names} ||= $args{-policy_name};
    $args{-load_balancer_name} or
        croak "describe_load_balancer_policies(): -load_balancer_name argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('PolicyNames',\%args);
    return $self->elb_call('DescribeLoadBalancerPolicies',@params);
}

=head2 @policy_types = $ec2->describe_load_balancer_policy_types(-policy_type_names => \@names)

Returns meta-information on the specified ELB policies defined by the Elastic
Load Balancing service. The policy types that are returned from this action can
be used in a create_load_balander_policy call to instantiate specific policy
configurations that will be applied to an ELB.

Required arguemnts:

 -load_balancer_name    The name of the ELB.

Optional arguments:

 -policy_type_names    Literal string or arrayref of policy type names

 -names                Alias for -policy_type_names

Returns an array of L<VM::EC2::ELB::PolicyTypeDescription> objects if successful.

=cut

sub describe_load_balancer_policy_types {
    my $self = shift;
    my %args = @_;
    $args{-policy_type_names} ||= $args{-names};
    my @params = $self->member_list_parm('PolicyTypeNames',\%args);
    return $self->elb_call('DescribeLoadBalancerPolicyTypes',@params);
}

=head2 $success = $ec2->set_load_balancer_policies_of_listener(-load_balancer_name => $name,
                                                               -load_balancer_port => $port,
                                                               -policy_names       => \@names)

Associates, updates, or disables a policy with a listener on the ELB.  Multiple
policies may be associated with a listener.

Required arguments:

 -load_balancer_name    The name associated with the ELB.

 -load_balancer_port    The external port of the LoadBalancer with which this
                        policy applies to.

 -policy_names          List of policies to be associated with the listener.
                        Currently this list can have at most one policy. If the
                        list is empty, the current policy is removed from the
                        listener.  String or arrayref.

Returns true if successful.

=cut

sub set_load_balancer_policies_of_listener {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_port} ||= $args{-port};
    $args{-load_balancer_name} or
        croak "set_load_balancer_policies_of_listener(): -load_balancer_name argument missing";
    $args{-load_balancer_port} or
        croak "set_load_balancer_policies_of_listener(): -load_balancer_port argument missing";
    $args{-policy_names} or
        croak "set_load_balancer_policies_of_listener(): -policy_names argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->single_parm('LoadBalancerPort',\%args);
    push @params, $self->member_list_parm('PolicyNames',\%args);
    return $self->elb_call('SetLoadBalancerPoliciesOfListener',@params);
}

=head2 @sgs = $ec2->apply_security_groups_to_load_balancer(-load_balancer_name => $name,
                                                           -security_groups    => \@groups)

Associates one or more security groups with your ELB in VPC.  The provided
security group IDs will override any currently applied security groups.

Required arguments:

 -load_balancer_name The name associated with the ELB.

 -security_groups    A list of security group IDs to associate with your ELB in
                     VPC. The security group IDs must be provided as the ID and
                     not the security group name (For example, sg-123456).
                     String or arrayref.

Returns a series of L<VM::EC2::SecurityGroup> objects.

=cut

sub apply_security_groups_to_load_balancer {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "apply_security_groups_to_load_balancer(): -load_balancer_name argument missing";
    $args{-security_groups} or
        croak "apply_security_groups_to_load_balancer(): -security_groups argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('SecurityGroups',\%args);
    my @g = $self->elb_call('ApplySecurityGroupsToLoadBalancer',@params) or return;
    return $self->describe_security_groups(@g);
}

=head2 @subnets = $ec2->attach_load_balancer_to_subnets(-load_balancer_name => $name,
                                                        -subnets            => \@subnets)

Adds one or more subnets to the set of configured subnets for the ELB.

Required arguments:

 -load_balancer_name    The name associated with the ELB.

 -subnets               A list of subnet IDs to add for the ELB.  String or
                        arrayref.

Returns a series of L<VM::EC2::VPC::Subnet> objects corresponding to the
subnets the ELB is now attached to.

=cut

sub attach_load_balancer_to_subnets {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "attach_load_balancer_to_subnets(): -load_balancer_name argument missing";
    $args{-subnets} or
        croak "attach_load_balancer_to_subnets(): -subnets argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('Subnets',\%args);
    my @sn = $self->elb_call('AttachLoadBalancerToSubnets',@params) or return;
    return $self->describe_subnets(@sn);
}

=head2 @subnets = $ec2->detach_load_balancer_from_subnets(-load_balancer_name => $name,
                                                          -subnets            => \@subnets)

Removes subnets from the set of configured subnets in the VPC for the ELB.

Required arguments:

 -load_balancer_name    The name associated with the ELB.

 -subnets               A list of subnet IDs to add for the ELB.  String or
                        arrayref.

Returns a series of L<VM::EC2::VPC::Subnet> objects corresponding to the
subnets the ELB is now attached to.

=cut

sub detach_load_balancer_from_subnets {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-load_balancer_name} or
        croak "detach_load_balancer_from_subnets(): -load_balancer_name argument missing";
    $args{-subnets} or
        croak "detach_load_balancer_from_subnets(): -subnets argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->member_list_parm('Subnets',\%args);
    my @sn = $self->elb_call('DetachLoadBalancerFromSubnets',@params) or return;
    return $self->describe_subnets(@sn);
}

=head2 $success = $ec2->set_load_balancer_policies_for_backend_server(-instance_port      => $port,
                                                                      -load_balancer_name => $name,
                                                                      -policy_names       => \@policies)

Replaces the current set of policies associated with a port on which the back-
end server is listening with a new set of policies. After the policies have 
been created, they can be applied here as a list.  At this time, only the back-
end server authentication policy type can be applied to the back-end ports;
this policy type is composed of multiple public key policies.

Required arguments:

 -load_balancer_name    The name associated with the ELB.

 -instance_port         The port number associated with the back-end server.

 -policy_names          List of policy names to be set. If the list is empty,
                        then all current polices are removed from the back-end
                        server.

Aliases:

 -port      Alias for -instance_port
 -lb_name   Alias for -load_balancer_name

Returns true if successful.

=cut

sub set_load_balancer_policies_for_backend_server {
    my $self = shift;
    my %args = @_;
    $args{-load_balancer_name} ||= $args{-lb_name};
    $args{-instance_port} ||= $args{-port};
    $args{-load_balancer_name} or
        croak "set_load_balancer_policies_for_backend_server(): -load_balancer_name argument missing";
    $args{-instance_port} or
        croak "set_load_balancer_policies_for_backend_server(): -instance_port argument missing";
    $args{-policy_names} or
        croak "set_load_balancer_policies_for_backend_server(): -policy_names argument missing";
    my @params = $self->single_parm('LoadBalancerName',\%args);
    push @params, $self->single_parm('InstancePort',\%args);
    push @params, $self->member_list_parm('PolicyNames',\%args);
    return $self->elb_call('SetLoadBalancerPoliciesForBackendServer',@params);
}

=head1 AWS SECURITY TOKENS

AWS security tokens provide a way to grant temporary access to
resources in your EC2 space without giving them permanent
accounts. They also provide the foundation for mobile services and
multifactor authentication devices (MFA).

Used in conjunction with VM::EC2::Security::Policy and
VM::EC2::Security::Credentials, you can create a temporary user who is
authenticated for a limited length of time and pass the credentials to
him or her via a secure channel. He or she can then create a
credentials object to access your AWS resources.

Here is an example:

 # on your side of the connection
 $ec2 = VM::EC2->new(...);  # as usual
 my $policy = VM::EC2::Security::Policy->new;
 $policy->allow('DescribeImages','RunInstances');
 my $token = $ec2->get_federation_token(-name     => 'TemporaryUser',
                                        -duration => 60*60*3, # 3 hrs, as seconds
                                        -policy   => $policy);
 my $serialized = $token->credentials->serialize;
 send_data_to_user_somehow($serialized);

 # on the temporary user's side of the connection
 my $serialized = get_data_somehow();
 my $token = VM::EC2::Security::Credentials->new_from_serialized($serialized);
 my $ec2   = VM::EC2->new(-security_token => $token);
 print $ec2->describe_images(-owner=>'self');

For temporary users who are not using the Perl VM::EC2 API, you can
transmit the required fields individually:

 my $credentials   = $token->credentials;
 my $access_key_id = $credentials->accessKeyId;
 my $secret_key    = $credentials->secretKey;
 my $session_token = $credentials->sessionToken;
 send_data_to_user_somehow($session_token,
                           $access_key_id,
                           $secret_key);

Calls to get_federation_token() return a VM::EC2::Security::Token
object. This object contains two sub-objects, a
VM::EC2::Security::Credentials object, and a
VM::EC2::Security::FederatedUser object. The Credentials object
contains a temporary access key ID, secret access key, and session
token which together can be used to authenticate to the EC2 API.  The
FederatedUser object contains the temporary user account name and ID.

See L<VM::EC2::Security::Token>, L<VM::EC2::Security::FederatedUser>,
L<VM::EC2::Security::Credentials>, and L<VM::EC2::Security::Policy>.

=cut

=head2 $token = $ec2->get_federation_token($username)

=head2 $token = $ec2->get_federation_token(-name=>$username,@args)

This method creates a new temporary user under the provided username
and returns a VM::EC2::Security::Token object that contains temporary
credentials for the user, as well as information about the user's
account. Other options allow you to control the duration for which the
credentials will be valid, and the policy the controls what resources
the user is allowed to access.

=over 4

=item Required arguments:

 -name The username

The username must comply with the guidelines described in
http://docs.amazonwebservices.com/IAM/latest/UserGuide/LimitationsOnEntities.html:
essentially all alphanumeric plus the characters [+=,.@-].

=item Optional arguments:

 -duration_seconds Length of time the session token will be valid for,
                    expressed in seconds. 

 -duration         Same thing, faster to type.

 -policy           A VM::EC2::Security::Policy object, or a JSON string
                     complying with the IAM policy syntax.

The duration must be no shorter than 1 hour (3600 seconds) and no
longer than 36 hours (129600 seconds). If no duration is specified,
Amazon will default to 12 hours. If no policy is provided, then the
user will not be able to execute B<any> actions.

Note that if the temporary user wishes to create a VM::EC2 object and
specify a region name at create time
(e.g. VM::EC2->new(-region=>'us-west-1'), then the user must have
access to the DescribeRegions action:

 $policy->allow('DescribeRegions')

Otherwise the call to new() will fail.

=back

=cut

sub get_federation_token {
    my $self = shift;
    my %args = $self->args('-name',@_);
    $args{-name} or croak "Usage: get_federation_token(-name=>\$name,\@more_args)";
    $args{-duration_seconds} ||= $args{-duration};
    my @p = map {$self->single_parm($_,\%args)} qw(Name DurationSeconds Policy);
    return $self->sts_call('GetFederationToken',@p);
}


=head2 $token = $ec2->get_session_token(%args)

This method creates a temporary VM::EC2::Security::Token object for an
anonymous user. The token has no policy associated with it, and can be
used to run any of the EC2 actions available to the user who created
the token. Optional arguments allow the session token to be used in
conjunction with MFA devices.

=over 4

=item Required arguments:

none

=item Optional arguments:

 -duration_seconds Length of time the session token will be valid for,
                    expressed in seconds.

 -duration         Same thing, faster to type.

 -serial_number    The identification number of the user's MFA device,
                     if any.

 -token_code       The code provided by the MFA device, if any.

If no duration is specified, Amazon will default to 12 hours.

See
http://docs.amazonwebservices.com/IAM/latest/UserGuide/Using_ManagingMFA.html
for information on using AWS in conjunction with MFA devices.

=back

=cut

sub get_session_token {
    my $self = shift;
    my %args = @_;
    my @p = map {$self->single_parm($_,\%args)} qw(SerialNumber DurationSeconds TokenCode);
    return $self->sts_call('GetSessionToken',@p);
}

=head1 LAUNCH CONFIGURATIONS

=head2 @lc = $ec2->describe_launch_configurations(-names => \@names);

=head2 @lc = $ec->describe_launch_configurations(@names);

Provides detailed information for the specified launch configuration(s).

Optional parameters are:

  -launch_configuration_names   Name of the Launch config.
                                  This can be a string scalar or an arrayref.

  -name  Alias for -launch_configuration_names

Returns a series of L<VM::EC2::LaunchConfiguration> objects.

=cut

sub describe_launch_configurations {
    my $self = shift;
    my %args = $self->args('-launch_configuration_names',@_);
    $args{-launch_configuration_names} ||= $args{-names};
    my @params = $self->list_parm('LaunchConfigurationNames',\%args);
    return $self->asg_call('DescribeLaunchConfigurations', @params);
}

=head2 $success = $ec2->create_launch_configuration(%args);

Creates a new launch configuration.

Required arguments:

  -name           -- scalar, name for the Launch config.
  -image_id       -- scalar, AMI id which this launch config will use
  -instance_type  -- scalar, instance type of the Amazon EC2 instance.

Optional arguments:

  -block_device_mappings  -- list of hashref
  -ebs_optimized          -- scalar (boolean). false by default
  -iam_instance_profile   -- scalar
  -instance_monitoring    -- scalar (boolean). true by default
  -kernel_id              -- scalar
  -key_name               -- scalar
  -ramdisk                -- scalar
  -security_groups        -- list of scalars
  -spot_price             -- scalar
  -user_data              -- scalar

Returns true on successful execution.

=cut

sub create_launch_configuration {
    my $self = shift;
    my %args = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my $imageid = $args{-image_id} or croak "-image_id argument is required";
    my $itype = $args{-instance_type} or croak "-instance_type argument is required";

    my @params = (ImageId => $imageid, InstanceType => $itype, LaunchConfigurationName => $name);
    push @params, $self->member_list_parm('BlockDeviceMappings',\%args);
    push @params, $self->member_list_parm('SecurityGroups',\%args);
    push @params, $self->boolean_parm('EbsOptimized', \%args);
    push @params, ('UserData' =>encode_base64($args{-user_data},'')) if $args{-user_data};
    push @params, ('InstanceMonitoring.Enabled' => 'false')
        if (exists $args{-instance_monitoring} and not $args{-instance_monitoring});

    my @p = map {$self->single_parm($_,\%args) }
       qw(IamInstanceProfile KernelId KeyName RamdiskId SpotPrice);
    push @params, @p;

    return $self->asg_call('CreateLaunchConfiguration',@params);
}

=head2 $success = $ec2->delete_launch_configuration(-name => $name);

Deletes a launch config.

  -name     Required. Name of the launch config to delete

Returns true on success.

=cut

sub delete_launch_configuration {
    my $self = shift;
    my %args  = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my @params = (LaunchConfigurationName => $name);
    return $self->asg_call('DeleteLaunchConfiguration', @params);
}

=head1 AUTOSCALING GROUPS

=head2 @asg = $ec2->describe_autoscaling_groups(-auto_scaling_group_names => \@names);

Returns information about autoscaling groups

  -auto_scaling_group_names     List of auto scaling groups to describe
  -names                        Alias of -auto_scaling_group_names

Returns a list of L<VM::EC2::ASG>.

=cut

sub describe_autoscaling_groups {
    my ($self, %args) = @_;
    $args{-auto_scaling_group_names} ||= $args{-names};
    my @params = $self->member_list_parm('AutoScalingGroupNames',\%args);
    return $self->asg_call('DescribeAutoScalingGroups', @params);
}

=head2 $success = $ec2->create_autoscaling_group(-name => $name, 
                                                -launch_config => $lc,
                                                -max_size => $max_size,
                                                -min_size => $min_size);

Creates a new autoscaling group.

Required arguments:

  -name             Name for the autoscaling group
  -launch_config    Name of the launch configuration to be used
  -max_size         Max number of instances to be run at once
  -min_size         Min number of instances

Optional arguments:

  -availability_zones   List of availability zone names
  -load_balancer_names  List of ELB names
  -tags                 List of tags to apply to the instances run
  -termination_policies List of policy names
  -default_cooldown     Time in seconds between autoscaling activities
  -desired_capacity     Number of instances to be run after creation
  -health_check_type    One of "ELB" or "EC2"
  -health_check_grace_period    Mandatory for health check type ELB. Number of
                                seconds between an instance is started and the
                                autoscaling group starts checking its health
  -placement_group      Physical location of your cluster placement group
  -vpc_zone_identifier  Strinc containing a comma-separated list of subnet 
                        identifiers

Returns true on success.

=cut

sub create_autoscaling_group {
    my $self = shift;
    my %args = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my $lconfig = $args{-launch_config} or croak "-launch_config argument is required";
    my $max = $args{-max_size};
    croak "-max_size argument is required" if (not defined $max);
    my $min = $args{-min_size};
    croak "-min_size argument is required" if (not defined $min);

    my @params = (AutoScalingGroupName => $name, LaunchConfigurationName => $lconfig, MaxSize => $max,
                  MinSize => $max);
    push @params, $self->member_list_parm('AvailabilityZones',\%args);
    push @params, $self->member_list_parm('LoadBalancerNames',\%args);
    push @params, $self->member_list_parm('TerminationPolicies',\%args);
    push @params, $self->autoscaling_tags('Tags', \%args);

    my @p = map {$self->single_parm($_,\%args) }
       qw( DefaultCooldown DesiredCapacity HealthCheckGracePeriod HealthCheckType PlacementGroup
           VPCZoneIdentifier);
    push @params, @p;

    return $self->asg_call('CreateAutoScalingGroup',@params);
}

=head2 $success = $ec2->delete_autoscaling_group(-name => $name)

Deletes an autoscaling group.

  -name     Name of the autoscaling group to delete

Returns true on success.

=cut

sub delete_autoscaling_group {
    my $self = shift;
    my %args  = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my @params = (AutoScalingGroupName => $name);
    push @params, $self->single_parm('ForceDelete',\%args);
    return $self->asg_call('DeleteAutoScalingGroup', @params);
}

=head2 $success = $ec2->update_autoscaling_group(-name => $name);

Updates an autoscaling group. Only required parameter is C<-name>

Optional arguments:

  -availability_zones       List of AZ's
  -termination_policies     List of policy names
  -default_cooldown
  -desired_capacity
  -health_check_type
  -health_check_grace_period
  -placement_group
  -vpc_zone_identifier
  -max_size
  -min_size

Returns true on success;

=cut

sub update_autoscaling_group {
    my $self = shift;
    my %args = @_;

    my $name = $args{-name} or croak "-name argument is required";
    my @params = (AutoScalingGroupName => $name);

    push @params, $self->member_list_parm('AvailabilityZones',\%args);
    push @params, $self->member_list_parm('TerminationPolicies',\%args);

    my @p = map {$self->single_parm($_,\%args) }
       qw( DefaultCooldown DesiredCapacity HealthCheckGracePeriod
           HealthCheckType PlacementGroup VPCZoneIdentifier MaxSize MinSize );
    push @params, @p;

    return $self->asg_call('UpdateAutoScalingGroup',@params);
}

=head2 $success = $ec2->suspend_processes(-name => $asg_name,
                                          -scaling_processes => \@procs);

Suspend the requested autoscaling processes.

  -name                 Name of the autoscaling group
  -scaling_processes    List of process names to suspend. Valid processes are:
        Launch
        Terminate
        HealthCheck
        ReplaceUnhealty
        AZRebalance
        AlarmNotification
        ScheduledActions
        AddToLoadBalancer

Returns true on success.

=cut

sub suspend_processes {
    my ($self, %args) = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my @params = (AutoScalingGroupName => $name);
    push @params, $self->member_list_parm('ScalingProcesses', \%args);
    return $self->asg_call('SuspendProcesses', @params);
}

=head2 $success = $ec2->resume_processes(-name => $asg_name,
                                         -scaling_processes => \@procs);

Resumes the requested autoscaling processes. It accepts the same arguments than
C<suspend_processes>.

Returns true on success.

=cut

sub resume_processes {
    my ($self, %args) = @_;
    my $name = $args{-name} or croak "-name argument is required";
    my @params = (AutoScalingGroupName => $name);
    push @params, $self->member_list_parm('ScalingProcesses', \%args);
    return $self->asg_call('ResumeProcesses', @params);
}

# ------------------------------------------------------------------------------------------

=head1 INTERNAL METHODS

These methods are used internally and are listed here without
documentation (yet).

=head2 $underscore_name = $ec2->canonicalize($mixedCaseName)

=cut

sub canonicalize {
    my $self = shift;
    my $name = shift;
    while ($name =~ /\w[A-Z]/) {
	$name    =~ s/([a-zA-Z])([A-Z])/\L$1_$2/g or last;
    }
    return '-'.lc $name;
}

sub uncanonicalize {
    my $self = shift;
    my $name = shift;
    $name    =~ s/_([a-z])/\U$1/g;
    return $name;
}

=head2 $instance_id = $ec2->instance_parm(@args)

=cut

sub instance_parm {
    my $self = shift;
    my %args;
    if ($_[0] =~ /^-/) {
	%args = @_; 
    } elsif (@_ > 1) {
	%args = (-instance_id => [@_]);
    } else {
	%args = (-instance_id => shift);
    }
    my $id = $args{-instance_id};
    return ref $id && ref $id eq 'ARRAY' ? @$id : $id;
}

=head2 @arguments = $ec2->value_parm(ParameterName => \%args)

=cut

sub value_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return unless exists $args->{$name} || exists $args->{"-$argname"};
    my $val = $args->{$name} || $args->{"-$argname"};
    return ("$argname.Value"=>$val);
}

=head2 @arguments = $ec2->single_parm(ParameterName => \%args)

=cut

sub single_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    my $val  = $args->{$name} || $args->{"-$argname"};
    defined $val or return;
    my $v = ref $val  && ref $val eq 'ARRAY' ? $val->[0] : $val;
    return ($argname=>$v);
}

=head2 @parameters = $ec2->prefix_parm($prefix, ParameterName => \%args)

=cut

sub prefix_parm {
    my $self = shift;
    my ($prefix,$argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    my $val  = $args->{$name} || $args->{"-$argname"};
    defined $val or return;
    my $v = ref $val  && ref $val eq 'ARRAY' ? $val->[0] : $val;
    return ("$prefix.$argname"=>$v);
}

=head2 @parameters = $ec2->member_list_parm(ParameterName => \%args)

=cut

sub member_list_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);

    my @params;
    if (my $a = $args->{$name}||$args->{"-$argname"}) {
        my $c = 1;
        for (ref $a && ref $a eq 'ARRAY' ? @$a : $a) {
            push @params,("$argname.member.".$c++ => $_);
        }
    }
    return @params;
}

=head2 @arguments = $ec2->list_parm(ParameterName => \%args)

=cut

sub list_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);

    my @params;
    if (my $a = $args->{$name}||$args->{"-$argname"}) {
	my $c = 1;
	for (ref $a && ref $a eq 'ARRAY' ? @$a : $a) {
	    push @params,("$argname.".$c++ => $_);
	}
    }

    return @params;
}

=head2 @arguments = $ec2->autoscaling_tags($argname, \%args)

=cut

sub autoscaling_tags {
    my $self = shift;
    my ($argname, $args) = @_;

    my $name = $self->canonicalize($argname);
    my @params;
    if (my $a = $args->{$name}||$args->{"-$argname"}) {
        my $c = 1;
        for my $tag (ref $a && ref $a eq 'ARRAY' ? @$a : $a) {
            my $prefix = "$argname.member." . $c++;
            while (my ($k, $v) = each %$tag) {
                push @params, ("$prefix.$k" => $v);
            }
        }
    }

    return @params;
}

=head2 @arguments = $ec2->filter_parm(\%args)

=cut

sub filter_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Filter','Name','Value',$args);
}

=head2 @arguments = $ec2->tagcreate_parm(\%args)

=cut

sub tagcreate_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args);
}

=head2 @arguments = $ec2->tagdelete_parm(\%args)

=cut

sub tagdelete_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args,1);
}

=head2 @arguments = $ec2->key_value_parameters($param_name,$keyname,$valuename,\%args,$skip_undef_values)

=cut

sub key_value_parameters {
    my $self = shift;
    # e.g. 'Filter', 'Name','Value',{-filter=>{a=>b}}
    my ($parameter_name,$keyname,$valuename,$args,$skip_undef_values) = @_;  
    my $arg_name     = $self->canonicalize($parameter_name);
    
    my @params;
    if (my $a = $args->{$arg_name}||$args->{"-$parameter_name"}) {
	my $c = 1;
	if (ref $a && ref $a eq 'HASH') {
	    while (my ($name,$value) = each %$a) {
		push @params,("$parameter_name.$c.$keyname"   => $name);
		if (ref $value && ref $value eq 'ARRAY') {
		    for (my $m=1;$m<=@$value;$m++) {
			push @params,("$parameter_name.$c.$valuename.$m" => $value->[$m-1])
		    }
		} else {
		    push @params,("$parameter_name.$c.$valuename" => $value)
			unless !defined $value && $skip_undef_values;
		}
		$c++;
	    }
	} else {
	    for (ref $a ? @$a : $a) {
		my ($name,$value) = /([^=]+)\s*=\s*(.+)/;
		push @params,("$parameter_name.$c.$keyname"   => $name);
		push @params,("$parameter_name.$c.$valuename" => $value)
		    unless !defined $value && $skip_undef_values;
		$c++;
	    }
	}
    }

    return @params;
}

=head2 @arguments = $ec2->launch_perm_parm($prefix,$suffix,$value)

=cut

sub launch_perm_parm {
    my $self = shift;
    my ($prefix,$suffix,$value) = @_;
    return unless defined $value;
    $self->_perm_parm('LaunchPermission',$prefix,$suffix,$value);
}

sub create_volume_perm_parm {
    my $self = shift;
    my ($prefix,$suffix,$value) = @_;
    return unless defined $value;
    $self->_perm_parm('CreateVolumePermission',$prefix,$suffix,$value);
}

sub _perm_parm {
    my $self = shift;
    my ($base,$prefix,$suffix,$value) = @_;
    return unless defined $value;
    my @list = ref $value && ref $value eq 'ARRAY' ? @$value : $value;
    my $c = 1;
    my @param;
    for my $v (@list) {
	push @param,("$base.$prefix.$c.$suffix" => $v);
	$c++;
    }
    return @param;
}

=head2 @arguments = $ec2->iam_parm($args)

=cut

sub iam_parm {
    my $self = shift;
    my $args = shift;
    my @p;
    push @p,('IamInstanceProfile.Arn'  => $args->{-iam_arn})             if $args->{-iam_arn};
    push @p,('IamInstanceProfile.Name' => $args->{-iam_name})            if $args->{-iam_name};
    return @p;
}

=head2 @arguments = $ec2->block_device_parm($block_device_mapping_string)

=cut

sub block_device_parm {
    my $self    = shift;
    my $devlist = shift or return;

    my @dev     = ref $devlist && ref $devlist eq 'ARRAY' ? @$devlist : $devlist;

    my @p;
    my $c = 1;
    for my $d (@dev) {
	$d =~ /^([^=]+)=([^=]+)$/ or croak "block device mapping must be in format /dev/sdXX=device-name";

	my ($devicename,$blockdevice) = ($1,$2);
	push @p,("BlockDeviceMapping.$c.DeviceName"=>$devicename);

	if ($blockdevice =~ /^vol-/) {  # this is a volume, and not a snapshot
	    my ($volume,$delete_on_term) = split ':',$blockdevice;
	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeId" => $volume);
	    push @p,("BlockDeviceMapping.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if defined $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/
	}
	elsif ($blockdevice eq 'none') {
	    push @p,("BlockDeviceMapping.$c.NoDevice" => '');
	} elsif ($blockdevice =~ /^ephemeral\d$/) {
	    push @p,("BlockDeviceMapping.$c.VirtualName"=>$blockdevice);
	} else {
	    my ($snapshot,$size,$delete_on_term,$vtype,$iops) = split ':',$blockdevice;

	    # Workaround for apparent bug in 2012-12-01 API; instances will crash without volume size
	    # even if a snapshot ID is provided
	    if ($snapshot) {
		$size ||= eval{$self->describe_snapshots($snapshot)->volumeSize};
		push @p,("BlockDeviceMapping.$c.Ebs.SnapshotId" =>$snapshot);
	    }

	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeSize" =>$size)                    if $size;
	    push @p,("BlockDeviceMapping.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if defined $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/;
	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeType"=>$vtype)                    if $vtype;
	    push @p,("BlockDeviceMapping.$c.Ebs.Iops"=>$iops)                           if $iops;
	}
	$c++;
    }
    return @p;
}

# ['eth0=eni-123456','eth1=192.168.2.1,192.168.3.1,192.168.4.1:subnet-12345:sg-12345:true:My Weird Network']
# form 1: ethX=network device id
# form 2: ethX=primary_address,secondary_address1,secondary_address2...:subnetId:securityGroupId:deleteOnTermination:description
# form 3: ethX=primary_address,secondary_address_count:subnetId:securityGroupId:deleteOnTermination:description
sub network_interface_parm {
    my $self = shift;
    my $args    = shift;
    my $devlist = $args->{-network_interfaces} or return;
    my @dev     = ref $devlist && ref $devlist eq 'ARRAY' ? @$devlist : $devlist;

    my @p;
    my $c = 0;
    for my $d (@dev) {
	$d =~ /^eth(\d+)\s*=\s*([^=]+)$/ or croak "network device mapping must be in format ethX=option-string";

	my ($device_index,$device_options) = ($1,$2);
	push @p,("NetworkInterface.$c.DeviceIndex" => $device_index);
	my @options = split ':',$device_options;
	if (@options == 1) {
	    push @p,("NetworkInterface.$c.NetworkInterfaceId" => $options[0]);
	} 
	else {
	    my ($ip_addresses,$subnet_id,$security_group_id,$delete_on_termination,$description) = @options;
	    my @addresses = split /\s*,\s*/,$ip_addresses;
	    for (my $a = 0; $a < @addresses; $a++) {
		if ($addresses[$a] =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
		    push @p,("NetworkInterface.$c.PrivateIpAddresses.$a.PrivateIpAddress" => $addresses[$a]);
		    push @p,("NetworkInterface.$c.PrivateIpAddresses.$a.Primary"          => $a == 0 ? 'true' : 'false');
		}
		elsif ($addresses[$a] =~ /^\d+$/ && $a > 0) {
		    push @p,("NetworkInterface.$c.SecondaryPrivateIpAddressCount"        => $addresses[$a]);
		}
	    }
	    my @sgs = split ',',$security_group_id;
	    for (my $i=0;$i<@sgs;$i++) {
		push @p,("NetworkInterface.$c.SecurityGroupId.$i" => $sgs[$i]);
	    }

	    push @p,("NetworkInterface.$c.SubnetId"              => $subnet_id)             if length $subnet_id;
	    push @p,("NetworkInterface.$c.DeleteOnTermination"   => $delete_on_termination) if length $delete_on_termination;
	    push @p,("NetworkInterface.$c.Description"           => $description)           if length $description;
	}
	$c++;
    }
    return @p;
}

sub boolean_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return unless exists $args->{$name} || exists $args->{$argname};
    my $val = $args->{$name} || $args->{$argname};
    return ($argname => $val ? 'true' : 'false');
}

=head2 $version = $ec2->version()

API version.

=cut

sub version  { 
    my $self = shift;
    return $self->{version} ||=  '2012-12-01';
}

=head2 $ts = $ec2->timestamp

=cut

sub timestamp {
    return strftime("%Y-%m-%dT%H:%M:%SZ",gmtime);
}


=head2 $ua = $ec2->ua

LWP::UserAgent object.

=cut

sub ua {
    my $self = shift;
    return $self->{ua} ||= LWP::UserAgent->new;
}

=head2 @obj = $ec2->call($action,@param);

Make a call to Amazon using $action and the passed arguments, and
return a list of objects.

=cut

sub call {
    my $self    = shift;
    my $response  = $self->make_request(@_);

    my $sleep_time = 2;
    while ($response->decoded_content =~ 'RequestLimitExceeded') {
        last if ($sleep_time > 64); # wait at most 64 seconds
        sleep $sleep_time;
        $sleep_time *= 2;
        $response  = $self->make_request(@_);
    }
    unless ($response->is_success) {
	my $content = $response->decoded_content;
	my $error;
	if ($content =~ /<Response>/) {
	    $error = VM::EC2::Dispatch->create_error_object($response->decoded_content,$self,$_[0]);
	} else {
	    my $code = $response->status_line;
	    my $msg  = $response->decoded_content;
	    $error = VM::EC2::Error->new({Code=>$code,Message=>"$msg from API call '$_[0]')"},$self);
	}
	$self->error($error);
	carp  "$error" if $self->print_error;
	croak "$error" if $self->raise_error;
	return;
    }

    $self->error(undef);
    my @obj = VM::EC2::Dispatch->response2objects($response,$self);

    # slight trick here so that we return one object in response to
    # describe_images(-image_id=>'foo'), rather than the number "1"
    if (!wantarray) { # scalar context
	return $obj[0] if @obj == 1;
	return         if @obj == 0;
	return @obj;
    } else {
	return @obj;
    }
}

sub sts_call {
    my $self = shift;
    local $self->{endpoint} = 'https://sts.amazonaws.com';
    local $self->{version}  = '2011-06-15';
    $self->call(@_);
}

sub elb_call {
    my $self = shift;
    (my $endpoint = $self->{endpoint}) =~ s/ec2/elasticloadbalancing/;
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2012-06-01';
    $self->call(@_);
}

sub asg_call {
    my $self = shift;
    (my $endpoint = $self->{endpoint}) =~ s/ec2/autoscaling/;
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2011-01-01';
    $self->call(@_);
}

=head2 $request = $ec2->make_request($action,@param);

Set up the signed HTTP::Request object.

=cut

sub make_request {
    my $self    = shift;
    my ($action,@args) = @_;
    my $request = $self->_sign(Action=>$action,@args);
    return $self->ua->request($request);
}

=head2 $request = $ec2->_sign(@args)

Create and sign an HTTP::Request.

=cut

# adapted from Jeff Kim's Net::Amazon::EC2 module
sub _sign {
    my $self    = shift;
    my @args    = @_;

    my $action = 'POST';
    my $host   = lc URI->new($self->endpoint)->host;
    my $path   = '/';

    my %sign_hash                = @args;
    $sign_hash{AWSAccessKeyId}   = $self->id;
    $sign_hash{Timestamp}        = $self->timestamp;
    $sign_hash{Version}          = $self->version;
    $sign_hash{SignatureVersion} = 2;
    $sign_hash{SignatureMethod}  = 'HmacSHA256';
    $sign_hash{SecurityToken}    = $self->security_token if $self->security_token;

    my @param;
    my @parameter_keys = sort keys %sign_hash;
    for my $p (@parameter_keys) {
	push @param,join '=',map {uri_escape($_,"^A-Za-z0-9\-_.~")} ($p,$sign_hash{$p});
    }
    my $to_sign = join("\n",
		       $action,$host,$path,join('&',@param));
    my $signature = encode_base64(hmac_sha256($to_sign,$self->secret),'');
    $sign_hash{Signature} = $signature;

    my $uri = URI->new($self->endpoint);
    $uri->query_form(\%sign_hash);

    return POST $self->endpoint,[%sign_hash];
}

=head2 @param = $ec2->args(ParamName=>@_)

Set up calls that take either method(-resource_id=>'foo') or method('foo').

=cut

sub args {
    my $self = shift;
    my $default_param_name = shift;
    return unless @_;
    return @_ if $_[0] =~ /^-/;
    return (-filter=>shift) if @_==1 && ref $_[0] && ref $_[0] eq 'HASH';
    return ($default_param_name => \@_);
}

=head1 MISSING METHODS

As of 24 Dec 2012, the following Amazon API calls were NOT
implemented. Volunteers to implement these calls are most welcome.

BundleInstance
CancelBundleTask
CancelConversionTask
CancelReservedInstancesListing
CreateReservedInstancesListing
DescribeBundleTasks
DescribeConversionTasks
DescribeReservedInstancesListings
ImportInstance
ImportVolume

=head1 OTHER INFORMATION

This section contains technical information that may be of interest to developers.

=head2 Signing and authentication protocol

This module uses Amazon AWS signing protocol version 2, as described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?using-query-api.html.
It uses the HmacSHA256 signature method, which is the most secure
method currently available. For additional security, use "https" for
the communications endpoint:

  $ec2 = VM::EC2->new(-endpoint=>'https://ec2.amazonaws.com');

=head2 Subclassing VM::EC2 objects

To subclass VM::EC2 objects (or implement your own from scratch) you
will need to override the object dispatch mechanism. Fortunately this
is very easy. After "use VM::EC2" call
VM::EC2::Dispatch->register() one or more times:

 VM::EC2::Dispatch->register($call_name => $dispatch).

The first argument, $call_name, is name of the Amazon API call, such as "DescribeImages".

The second argument, $dispatch, instructs VM::EC2::Dispatch how to
create objects from the parsed XML. There are three possible syntaxes:

 1) A CODE references, such as an anonymous subroutine.

    In this case the code reference will be invoked to handle the 
    parsed XML returned from the request. The code will receive 
    two arguments consisting of the parsed
    content of the response, and the VM::EC2 object used to generate the
    request.

 2) A VM::EC2::Dispatch method name, optionally followed by its arguments
    delimited by commas. Example:

           "fetch_items,securityGroupInfo,VM::EC2::SecurityGroup"

    This tells Dispatch to invoke its fetch_items() method with
    the following arguments:

     $dispatch->fetch_items($parsed_xml,$ec2,'securityGroupInfo','VM::EC2::SecurityGroup')

    The fetch_items() method is used for responses in which a
    list of objects is embedded within a series of <item> tags.
    See L<VM::EC2::Dispatch> for more information.

    Other commonly-used methods are "fetch_one", and "boolean".

 3) A class name, such as 'MyVolume'

    In this case, class MyVolume is loaded and then its new() method
    is called with the four arguments ($parsed_xml,$ec2,$xmlns,$requestid),
    where $parsed_xml is the parsed XML response, $ec2 is the VM::EC2
    object that generated the request, $xmlns is the XML namespace
    of the XML response, and $requestid is the AWS-generated ID for the
    request. Only the first two arguments are really useful.

    I suggest you inherit from VM::EC2::Generic and use the inherited new()
    method to store the parsed XML object and other arguments.

Dispatch tries each of (1), (2) and (3), in order. This means that
class names cannot collide with method names.

The parsed content is the result of passing the raw XML through a
XML::Simple object created with:

 XML::Simple->new(ForceArray    => ['item'],
                  KeyAttr       => ['key'],
                  SuppressEmpty => undef);

In general, this will give you a hash of hashes. Any tag named 'item'
will be forced to point to an array reference, and any tag named "key"
will be flattened as described in the XML::Simple documentation.

A simple way to examine the raw parsed XML is to invoke any
VM::EC2::Generic's as_string() method:

 my ($i) = $ec2->describe_instances;
 print $i->as_string;

This will give you a Data::Dumper representation of the XML after it
has been parsed.

The suggested way to override the dispatch table is from within a
subclass of VM::EC2:
 
 package 'VM::EC2New';
 use base 'VM::EC2';
  sub new {
      my $self=shift;
      VM::EC2::Dispatch->register('call_name_1'=>\&subroutine1).
      VM::EC2::Dispatch->register('call_name_2'=>\&subroutine2).
      $self->SUPER::new(@_);
 }

See L<VM::EC2::Dispatch> for a working example of subclassing VM::EC2
and one of its object classes.

=head1 DEVELOPING

The git source for this library can be found at https://github.com/lstein/LibVM-EC2-Perl,
To contribute to development, please obtain a github account and then either:
 
 1) Fork a copy of the repository, make your changes against this repository, 
    and send a pull request to me to incorporate your changes.

 2) Contact me by email and ask for push privileges on the repository.

See http://help.github.com/ for help getting started.

=head1 SEE ALSO

L<Net::Amazon::EC2>
L<VM::EC2::Dispatch>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::BlockDevice::Attachment>
L<VM::EC2::BlockDevice::EBS>
L<VM::EC2::BlockDevice::Mapping>
L<VM::EC2::BlockDevice::Mapping::EBS>
L<VM::EC2::Error>
L<VM::EC2::Generic>
L<VM::EC2::Group>
L<VM::EC2::Image>
L<VM::EC2::Instance>
L<VM::EC2::Instance::ConsoleOutput>
L<VM::EC2::Instance::Metadata>
L<VM::EC2::Instance::MonitoringState>
L<VM::EC2::Instance::PasswordData>
L<VM::EC2::Instance::Set>
L<VM::EC2::Instance::State>
L<VM::EC2::Instance::State::Change>
L<VM::EC2::Instance::State::Reason>
L<VM::EC2::KeyPair>
L<VM::EC2::Region>
L<VM::EC2::ReservationSet>
L<VM::EC2::ReservedInstance>
L<VM::EC2::ReservedInstance::Offering>
L<VM::EC2::SecurityGroup>
L<VM::EC2::Snapshot>
L<VM::EC2::Staging::Manager>
L<VM::EC2::Tag>
L<VM::EC2::Volume>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


1;
