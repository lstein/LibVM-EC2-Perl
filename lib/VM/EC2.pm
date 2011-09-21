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
                                        'run-state-name' => 'stopped'});
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

This is an interface to the 2011-05-15 version of the Amazon AWS API
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

In addition, there are several utility classes:

 VM::EC2::Generic                   -- Base class for all AWS objects
 VM::EC2::Error                     -- Error messages
 VM::EC2::Dispatch                  -- Maps AWS XML responses onto perl object classes
 VM::EC2::ReservationSet            -- Hidden class used for describe_instances() request;
                                               The reservation Ids are copied into the Instance
                                               object.

The interface provided by these modules is based on that described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/. The
following caveats apply:

 1) Not all of the Amazon API is currently implemented. Specifically,
    calls dealing with Virtual Private Clouds (VPC), cluster management,
    and spot instances are not currently supported.
    See L</MISSING METHODS> for a list of all the unimplemented API calls. 

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
    parameters, communications problems, service interruptions) will
    return undef and set the VM::EC2->is_error() method to true. The
    error message and its code can then be recovered by calling
    VM::EC2->error.

      $i = $ec2->describe_instance('i-123456');
      unless ($i) {
          warn 'Got no instance. Message was: ',$ec2->error;
      }

    You may also elect to raise an exception when an error occurs.
    See the new() method for details.

=head1 CORE METHODS

This section describes the VM::EC2 constructor, accessor methods, and
methods relevant to error handling.

=cut

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(hmac_sha256 sha1_hex);
use POSIX 'strftime';
use URI;
use URI::Escape;
use VM::EC2::Dispatch;
use VM::EC2::Error;
use Carp 'croak','carp';

our $VERSION = '1.07';
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


=head2 $ec2 = VM::EC2->new(-access_key=>$id,-secret_key=>$key,-endpoint=>$url)

Create a new Amazon access object. Required parameters are:

 -access_key   Access ID for an authorized user

 -secret_key   Secret key corresponding to the Access ID

 -endpoint     The URL for making API requests

 -raise_error  If true, throw an exception.

 -print_error  If true, print errors to STDERR.

One or more of -access_key, -secret_key and -endpoint can be omitted
if the environment variables EC2_ACCESS_KEY, EC2_SECRET_KEY and
EC2_URL are defined.

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
    my $id           = $args{-access_key} || $ENV{EC2_ACCESS_KEY}
                       or croak "Please provide AccessKey parameter or define environment variable EC2_ACCESS_KEY";
    my $secret       = $args{-secret_key} || $ENV{EC2_SECRET_KEY} 
                       or croak "Please provide SecretKey parameter or define environment variable EC2_SECRET_KEY";
    my $endpoint_url = $args{-endpoint}   || $ENV{EC2_URL} || 'http://ec2.amazonaws.com/';
    $endpoint_url   .= '/' unless $endpoint_url =~ m!/$!;

    my $raise_error  = $args{-raise_error};
    my $print_error  = $args{-print_error};
    return bless {
	id              => $id,
	secret          => $secret,
	endpoint        => $endpoint_url,
	idempotent_seed => sha1_hex(rand()),
	raise_error     => $raise_error,
	print_error     => $print_error,
    },ref $self || $self;
}

=head2 $access_key = $ec2->access_key(<$new_access_key>)

Get or set the ACCESS KEY

=cut

sub access_key {shift->id(@_)}

sub id       { 
    my $self = shift;
    my $d    = $self->{id};
    $self->{id} = shift if @_;
    $d;
}

=head2 $secret = $ec2->secret(<$new_secret>)

Get or set the SECRET KEY

=cut

sub secret   {
    my $self = shift;
    my $d    = $self->{secret};
    $self->{secret} = shift if @_;
    $d;
}

=head2 $endpoint = $ec2->endpoint(<$new_endpoint>)

Get or set the ENDPOINT URL.

=cut

sub endpoint { 
    my $self = shift;
    my $d    = $self->{endpoint};
    $self->{endpoint} = shift if @_;
    $d;
 }

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

=head1 EC2 REGIONS AND AVAILABILITY ZONES

This section describes methods that allow you to fetch information on
EC2 regions and availability zones. These methods return objects of
type L<VM::EC2::Region> and L<VM::EC2::AvailabilityZone>.

=head2 @regions = $ec2->describe_regions(-region_name=>\@list)

=head2 @regionss = $ec2->describe_regions(@list)

Describe regions and return a list of VM::EC2::Region objects. Call
with no arguments to return all regions. You may provide a list of
regions in either of the two forms shown above in order to restrict
the list returned. Glob-style wildcards, such as "*east") are allowed.

=cut

sub describe_regions {
    my $self = shift;
    my %args = $self->args('-region_name',@_);
    my @params = $self->list_parm('RegionName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeRegions',@params);
}

=head2 @zones = $ec2->describe_availability_zones(-zone_name=>\@names,-filter=>\%filters)

=head2 @zones = $ec2->describe_availability_zones(@names)

Describe availability zones and return a list of
VM::EC2::AvailabilityZone objects. Call with no arguments to return
all availability regions. You may provide a list of zones in either
of the two forms shown above in order to restrict the list
returned. Glob-style wildcards, such as "*east") are allowed.

If you provide a single argument consisting of a hashref, it is
treated as a -filter argument. In other words:

 $ec2->describe_availability_zones({state=>'available'})

is equivalent to

 $ec2->describe_availability_zones(-filter=>{state=>'available'})

Availability zone filters are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeAvailabilityZones.html

=cut

sub describe_availability_zones {
    my $self = shift;
    my %args = $self->args('-zone_name',@_);
    my @params = $self->list_parm('ZoneName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeAvailabilityZones',@params);
}

=head1 EC2 INSTANCES

The methods in this section allow you to retrieve information about
EC2 instances, launch new instances, control the instance lifecycle
(e.g. starting and stopping them), and fetching the console output
from instances.

The primary object manipulated by these methods is
L<VM::EC2::Instance>. Please see the L<VM::EC2::Instance> manual page
for additional methods that allow you to attach and detach volumes,
modify an instance's attributes, and convert instances into images.

=head2 @instances = $ec2->describe_instances(-instance_id=>\@ids,-filter=>\%filters)

=head2 @instances = $ec2->describe_instances(@instance_ids)

=head2 @instances = $ec2->describe_instances(\%filters)

Return a series of VM::EC2::Instance objects. Optional parameters are:

 -instance_id     ID of the instance(s) to return information on. 
                  This can be a string scalar, or an arrayref.

 -filter          Tags and other filters to apply.

The filter argument is a hashreference in which the keys are the
filter names, and the values are the match strings. Some filters
accept wildcards.

A typical filter example:

  $ec2->describe_instances(
    -filter        => {'block-device-mapping.device-name'=>'/dev/sdh',
                       'architecture'                    => 'i386',
                       'tag:Role'                        => 'Server'
                      });

You may omit the -filter argument name if there are no other arguments:

  $ec2->describe_instances({'block-device-mapping.device-name'=>'/dev/sdh',
                            'architecture'                    => 'i386',
                             'tag:Role'                        => 'Server'});

There are a large number of potential filters, which are listed at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeInstances.html.

Note that the objects returned from this method are the instances
themselves, and not a reservation set. The reservation ID can be
retrieved from each instance by calling its reservationId() method.

=cut

sub describe_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params = $self->list_parm('InstanceId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeInstances',@params);
}

=head2 @i = $ec2->run_instances(%param)

This method will provision and launch one or more instances given an
AMI ID. If successful, the method returns a series of
VM::EC2::Instance objects.

=over 4

=item Required parameters:

  -image_id       ID of an AMI to launch
 
=item Optional parameters:

  -min_count         Minimum number of instances to launch [1]
  -max_count         Maximum number of instances to launch [1]
  -key_name          Name of the keypair to use
  -security_group_id Security group ID to use for this instance.
                     Use an arrayref for multiple group IDs
  -security_group    Security group name to use for this instance.
                     Use an arrayref for multiple values.
  -user_data         User data to pass to the instances. Do NOT base64
                     encode this. It will be done for you.
  -instance_type     Type of the instance to use. See below for a
                     list.
  -availability_zone The availability zone you want to launch the
                     instance into. Call $ec2->regions for a list.
  -zone              Short version of -availability_aone.
  -placement_zone    Deprecated version of -availability_zone.
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
                     See below for the syntax of this argument.
  -block_device_mapping  Alias for -block_devices.
  -monitoring        Pass a true value to enable detailed monitoring.
  -subnet_id         ID of the subnet to launch the instance
                     into. Only applicable for VPC instances.
  -termination_protection  Pass true to lock the instance so that it
                     cannot be terminated using the API. Use
                     modify_instance() to unset this if youu wish to
                     terminate the instance later.
  -disable_api_termination -- Same as above.
  -shutdown_behavior Pass "stop" (the default) to stop the instance
                     and save its disk state when "shutdown" is called
                     from within the instance. Stopped instances can
                     be restarted later. Pass "terminate" to
                     instead terminate the instance and discard its
                     state completely.
  -instance_initiated_shutdown_behavior -- Same as above.
  -private_ip_address Assign the instance to a specific IP address
                     from a VPC subnet (VPC only).
  -client_token      Unique identifier that you can provide to ensure
                     idempotency of the request. You can use
                     $ec2->token() to generate a suitable identifier.
                     See http://docs.amazonwebservices.com/AWSEC2/
                         latest/UserGuide/Run_Instance_Idempotency.html

=item Instance types

The following is the list of instance types currently allowed by
Amazon:

   m1.small   c1.medium  m2.xlarge   cc1.4xlarge  cg1.4xlarge  t1.micro
   m1.large   c1.xlarge  m2.2xlarge   
   m1.xlarge             m2.4xlarge

=item Block device syntax

The syntax of -block_devices is identical to what is used by the
ec2-run-instances command-line tool. Borrowing from the manual page of
that tool:

The format is '<device>=<block-device>', where 'block-device' can be one of the
following:
          
    - 'none': indicates that a block device that would be exposed at the
       specified device should be suppressed. For example: '/dev/sdb=none'
          
     - 'ephemeral[0-3]': indicates that the Amazon EC2 ephemeral store
       (instance local storage) should be exposed at the specified device.
       For example: '/dev/sdc=ephemeral0'.
          
     - '[<snapshot-id>][:<size>[:<delete-on-termination>]]': indicates
       that an Amazon EBS volume, created from the specified Amazon EBS
       snapshot, should be exposed at the specified device. The following
       combinations are supported:
          
         - '<snapshot-id>': the ID of an Amazon EBS snapshot, which must
           be owned by or restorable by the caller. May be left out if a
           <size> is specified, creating an empty Amazon EBS volume of
           the specified size.
          
         - '<size>': the size (GiBs) of the Amazon EBS volume to be
           created. If a snapshot was specified, this may not be smaller
           than the size of the snapshot itself.
          
         - '<delete-on-termination>': indicates whether the Amazon EBS
            volume should be deleted on instance termination. If not
            specified, this will default to 'true' and the volume will be
            deleted.
          
         Examples: -block_devices => '/dev/sdb=snap-7eb96d16'
                   -block_devices => '/dev/sdc=snap-7eb96d16:80:false'
                   -block_devices => '/dev/sdd=:120'

To provide multiple mappings, use an array reference. In this example,
we launch two 'm1.small' instance in which /dev/sdb is mapped to
ephemeral storage and /dev/sdc is mapped to a new 100 G EBS volume:

 @i=$ec2->run_instances(-image_id  => 'ami-12345',
                        -min_count => 2,
                        -block_devices => ['/dev/sdb=ephemeral0',
                                           '/dev/sdc=:100:true']
    )

=item Return value

On success, this method returns a list of VM::EC2::Instance
objects. If called in a scalar context AND only one instance was
requested, it will return a single instance object (rather than
returning a list of size one which is then converted into numeric "1",
as would be the usual Perl behavior).

Note that this behavior is different from the Amazon API, which
returns a ReservationSet. In this API, ask the instances for the
the reservation, owner, requester, and group information using
reservationId(), ownerId(), requesterId() and groups() methods.

=item Tips

1. If you have a VM::EC2::Image object returned from
   Describe_images(), you may run it using run_instances():

 my $image = $ec2->describe_images(-image_id  => 'ami-12345');
 $image->run_instances( -min_count => 10,
                        -block_devices => ['/dev/sdb=ephemeral0',
                                           '/dev/sdc=:100:true']
    )

2. It may take a short while for a newly-launched instance to be
    returned by describe_instances(). You may need to sleep for 1-2 seconds
    before current_status() returns the correct value.

3. Each instance object has a current_status() method which will
   return the current run state of the instance. You may poll this
   method to wait until the instance is running:

   my $instance = $ec2->run_instances(...);
   sleep 1;
   while ($instance->current_status ne 'running') {
      sleep 5;
   }

4. The utility method wait_for_instances() will wait until all
   passed instances are in the 'running' or other terminal state.

   my @instances = $ec2->run_instances(...);
   $ec2->wait_for_instances(@instances);

=back
 
=cut

sub run_instances {
    my $self = shift;
    my %args = @_;
    $args{-image_id}  or croak "run_instances(): -image_id argument missing";
    $args{-min_count} ||= 1;
    $args{-max_count} ||= $args{-min_count};
    $args{-availability_zone} ||= $args{-zone};
    $args{-availability_zone} ||= $args{-placement_zone};

    my @p = map {$self->single_parm($_,\%args) }
       qw(ImageId MinCount MaxCount KeyName KernelId RamdiskId PrivateIPAddress
          InstanceInitiatedShutdownBehavior ClientToken SubnetId InstanceType);
    push @p,map {$self->list_parm($_,\%args)} qw(SecurityGroup SecurityGroupId);
    push @p,('UserData' =>encode_base64($args{-user_data}))           if $args{-user_data};
    push @p,('Placement.AvailabilityZone'=>$args{-availability_zone}) if $args{-availability_zone};
    push @p,('Placement.GroupName'=>$args{-placement_group})          if $args{-placement_group};
    push @p,('Placement.Tenancy'=>$args{-tenancy})                    if $args{-placement_tenancy};
    push @p,('Monitoring.Enabled'   =>'true')                         if $args{-monitoring};
    push @p,('DisableApiTermination'=>'true')                         if $args{-termination_protection};
    push @p,('InstanceInitiatedShutdownBehavior'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};
    push @p,$self->block_device_parm($args{-block_devices}||$args{-block_device_mapping});
    return $self->call('RunInstances',@p);
}

=head2 @s = $ec2->start_instances(-instance_id=>\@instance_ids)
=head2 @s = $ec2->start_instances(@instance_ids)

Start the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects.

To wait for the all the instance ids to reach their final state
("running" unless an error occurs), call wait_for_instances().

Example:

    # find all stopped instances
    @instances = $ec2->describe_instances(-filter=>{'instance-state-name'=>'stopped'});

    # start them
    $ec2->start_instances(@instances)

    # pause till they are running (or crashed)
    $ec2->wait_for_instances(@instances)

You can also start an instance by calling the object's start() method:

    $instances[0]->start('wait');  # start instance and wait for it to
				   # be running

The objects returned by calling start_instances() indicate the current
and previous states of the instance. The previous state is typically
"stopped" and the current state is usually "pending." This information
is only current to the time that the start_instances() method was called.
To get the current run state of the instance, call its status()
method:

  die "ouch!" unless $instances[0]->current_status eq 'running';

=cut

sub start_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "usage: start_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('StartInstances',@params) or return;
}

=head2 @s = $ec2->stop_instances(-instance_id=>\@instance_ids,-force=>1)

=head2 @s = $ec2->stop_instances(@instance_ids)

Stop the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects. In the named parameter
version of this method, you may optionally provide a -force argument,
which if true, forces the instance to halt without giving it a chance
to run its shutdown procedure (the equivalent of pulling a physical
machine's plug).

To wait for instances to reach their final state, call
wait_for_instances().

Example:

    # find all running instances
    @instances = $ec2->describe_instances(-filter=>{'instance-state-name'=>'running'});

    # stop them immediately and wait for confirmation
    $ec2->stop_instances(-instance_id=>\@instances,-force=>1);
    $ec2->wait_for_instances(@instances);

You can also stop an instance by calling the object's start() method:

    $instances[0]->stop('wait');  # stop first instance and wait for it to
			          # stop completely

=cut

sub stop_instances {
    my $self = shift;
    my (@instance_ids,$force);

    if ($_[0] =~ /^-/) {
	my %argv   = @_;
	@instance_ids = ref $argv{-instance_id} ?
	               @{$argv{-instance_id}} : $argv{-instance_id};
	$force     = $argv{-force};
    } else {
	@instance_ids = @_;
    }
    @instance_ids or croak "usage: stop_instances(\@instance_ids)";    

    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    push @params,Force=>1 if $force;
    return $self->call('StopInstances',@params) or return;
}

=head2 @s = $ec2->terminate_instances(-instance_id=>\@instance_ids)

=head2 @s = $ec2->terminate_instances(@instance_ids)

Terminate the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects. This method will fail
for any instances whose termination protection field is set.

To wait for the all the instances to reach their final state, call
wait_for_instances().

Example:

    # find all instances tagged as "Version 0.5"
    @instances = $ec2->describe_instances({'tag:Version'=>'0.5'});

    # terminate them
    $ec2->terminate_instances(@instances);

You can also terminate an instance by calling its terminate() method:

    $instances[0]->terminate;

=cut

sub terminate_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "usage: start_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('TerminateInstances',@params) or return;
}

=head2 @s = $ec2->reboot_instances(-instance_id=>\@instance_ids)

=head2 @s = $ec2->reboot_instances(@instance_ids)

Reboot the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects.

To wait for the all the instances to reach their final state, call
wait_for_instances().

You can also reboot an instance by calling its terminate() method:

    $instances[0]->reboot;

=cut

sub reboot_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "Usage: reboot_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('RebootInstances',@params) or return;
}

=head2 $t = $ec2->token

Return a client token for use with start_instances().

=cut

sub token {
    my $self = shift;
    my $seed = $self->{idempotent_seed};
    $self->{idempotent_seed} = sha1_hex($seed);
    $seed =~ s/(.{6})/$1-/g;
    return $seed;
}

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

=head1 $timeout = $ec2->wait_for_timeout([$new_timeout]);

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

=head2 $password_data = $ec2->get_password_data(-instance_id=>'i-12345');

=head2 $password_data = $ec2->get_password_data('i-12345');

For Windows instances, get the administrator's password as a
L<VM::EC2::Instance::PasswordData> object.

=cut

sub get_password_data {
    my $self = shift;
    my %args = $self->args(-instance_id=>@_);
    $args{-instance_id} or croak "Usage: get_password_data(-instance_id=>\$id)";
    my @params = $self->single_parm('InstanceId',\%args);
    return $self->call('GetPasswordData',@params);
}

=head2 $output = $ec2->get_console_output(-instance_id=>'i-12345')

=head2 $output = $ec2->get_console_output('i-12345');

Return the console output of the indicated instance. The output is
actually a VM::EC2::ConsoleOutput object, but it is
overloaded so that when treated as a string it will appear as a
large text string containing the  console output. When treated like an
object it provides instanceId() and timestamp() methods.

=cut

sub get_console_output {
    my $self = shift;
    my %args = $self->args(-instance_id=>@_);
    $args{-instance_id} or croak "Usage: get_console_output(-instance_id=>\$id)";
    my @params = $self->single_parm('InstanceId',\%args);
    return $self->call('GetConsoleOutput',@params);
}

=head2 @monitoring_state = $ec2->monitor_instances(@list_of_instanceIds)

=head2 @monitoring_state = $ec2->monitor_instances(-instance_id=>\@instanceIds)

This method enables monitoring for the listed instances and returns a
list of VM::EC2::Instance::MonitoringState objects. You can
later use these objects to activate and inactivate monitoring.

=cut

sub monitor_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params = $self->list_parm('InstanceId',\%args);
    return $self->call('MonitorInstances',@params);
}

=head2 @monitoring_state = $ec2->unmonitor_instances(@list_of_instanceIds)

=head2 @monitoring_state = $ec2->unmonitor_instances(-instance_id=>\@instanceIds)

This method disables monitoring for the listed instances and returns a
list of VM::EC2::Instance::MonitoringState objects. You can
later use these objects to activate and inactivate monitoring.

=cut

sub unmonitor_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params = $self->list_parm('InstanceId',\%args);
    return $self->call('UnmonitorInstances',@params);
}

=head2 $meta = $ec2->instance_metadata

B<For use on running EC2 instances only:> This method returns a
VM::EC2::Instance::Metadata object that will return information about
the currently running instance using the HTTP:// metadata fields
described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?instancedata-data-categories.html. This
is usually fastest way to get runtime information on the current
instance.

=cut

sub instance_metadata {
    VM::EC2::Dispatch::load_module('VM::EC2::Instance::Metadata');
    return VM::EC2::Instance::Metadata->new();
}

=head2 @data = $ec2->describe_instance_attribute($instance_id,$attribute)

This method returns instance attributes. Only one attribute can be
retrieved at a time. The following is the list of attributes that can be
retrieved:

 instanceType                      -- scalar
 kernel                            -- scalar
 ramdisk                           -- scalar
 userData                          -- scalar
 disableApiTermination             -- scalar
 instanceInitiatedShutdownBehavior -- scalar
 rootDeviceName                    -- scalar
 blockDeviceMapping                -- list of hashref
 sourceDestCheck                   -- scalar
 groupSet                          -- list of scalar

All of these values can be retrieved more conveniently from the
L<VM::EC2::Instance> object returned from describe_instances(), so
there is no attempt to parse the results of this call into Perl
objects. Therefore, some of the attributes, in particular
'blockDeviceMapping' will be returned as raw hashrefs.

=cut

sub describe_instance_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_instance_attribute(\$instance_id,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my @param  = (InstanceId=>$instance_id,Attribute=>$attribute);
    my $result = $self->call('DescribeInstanceAttribute',@param);
    return $result && $result->attribute($attribute);
}

=head2 $boolean = $ec2->modify_instance_attribute($instance_id,-$attribute_name=>$value)

This method changes instance attributes. It can only be applied to stopped instances.
The following is the list of attributes that can be set:

 -instance_type           -- type of instance, e.g. "m1.small"
 -kernel                  -- kernel id
 -ramdisk                 -- ramdisk id
 -user_data               -- user data
 -termination_protection  -- true to prevent termination from the console
 -disable_api_termination -- same as the above
 -shutdown_behavior       -- "stop" or "terminate"
 -instance_initiated_shutdown_behavior -- same as above
 -root_device_name        -- root device name
 -source_dest_check       -- enable NAT (VPC only)
 -group_id                -- VPC security group
 -block_devices           -- Specify block devices to change 
                             deleteOnTermination flag
 -block_device_mapping    -- Alias for -block_devices

Only one attribute can be changed in a single request. For example:

  $ec2->modify_instance_attribute('i-12345',-kernel=>'aki-f70657b2');

The result code is true if the attribute was successfully modified,
false otherwise. In the latter case, $ec2->error() will provide the
error message.

The ability to change the deleteOnTermination flag for attached block devices
is not documented in the official Amazon API documentation, but appears to work.
The syntax is:

# turn on deleteOnTermination
 $ec2->modify_instance_attribute(-block_devices=>'/dev/sdf=v-12345')
# turn off deleteOnTermination
 $ec2->modify_instance_attribute(-block_devices=>'/dev/sdf=v-12345')

The syntax is slightly different from what is used by -block_devices
in run_instances(), and is "device=volumeId:boolean". Multiple block
devices can be specified using an arrayref.

=cut

sub modify_instance_attribute {
    my $self = shift;
    my $instance_id = shift or croak "Usage: modify_instance_attribute(\$instanceId,%param)";
    my %args   = @_;

    my @param  = (InstanceId=>$instance_id);
    push @param,$self->value_parm($_,\%args) foreach 
	qw(InstanceType Kernel Ramdisk UserData DisableApiTermination
           InstanceInitiatedShutdownBehavior SourceDestCheck);
    push @param,$self->list_parm('GroupId',\%args);
    push @param,('DisableApiTermination.Value'=>'true') if $args{-termination_protection};
    push @param,('InstanceInitiatedShutdownBehavior.Value'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};
    my $block_devices = $args{-block_devices} || $args{-block_device_mapping};
    push @param,$self->block_device_parm($block_devices);

    return $self->call('ModifyInstanceAttribute',@param);
}

=head2 $boolean = $ec2->reset_instance_attribute($instance_id,$attribute)

This method resets an attribute of the given instance to its default
value. Valid attributes are "kernel", "ramdisk" and
"sourceDestCheck". The result code is true if the reset was
successful.

=cut

sub reset_instance_attribute {
    my $self = shift;
    @_      == 2 or croak "Usage: reset_instance_attribute(\$instanceId,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my %valid = map {$_=>1} qw(kernel ramdisk sourceDestCheck);
    $valid{$attribute} or croak "attribute to reset must be one of 'kernel', 'ramdisk', or 'sourceDestCheck'";
    return $self->call('ResetInstanceAttribute',InstanceId=>$instance_id,Attribute=>$attribute);
}

=head1 EC2 AMAZON MACHINE IMAGES

The methods in this section allow you to query and manipulate Amazon
machine images (AMIs). See L<VM::EC2::Image>.

=head2 @i = $ec2->describe_images(-image_id=>\@id,-executable_by=>$id,
                                  -owner=>$id, -filter=>\%filters)

=head2 @i = $ec2->describe_images(@image_ids)

Return a series of VM::EC2::Image objects, each describing an
AMI. Optional parameters:

 -image_id        The id of the image, either a string scalar or an
                  arrayref.

 -executable_by   Filter by images executable by the indicated user account

 -owner           Filter by owner account

 -filter          Tags and other filters to apply

If there are no other arguments, you may omit the -filter argument
name and call describe_images() with a single hashref consisting of
the search filters you wish to apply.

The full list of image filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeImages.html

=cut

sub describe_images {
    my $self = shift;
    my %args = $self->args(-image_id=>@_);
    my @params;
    push @params,$self->list_parm($_,\%args) foreach qw(ExecutableBy ImageId Owner);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeImages',@params) or return;
}

=head2 $image = $ec2->create_image(%args)

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

=cut

sub create_image {
    my $self = shift;
    my %args = @_;
    $args{-instance_id} && $args{-name}
      or croak "Usage: create_image(-instance_id=>\$id,-name=>\$name)";
    my @param = $self->single_parm('InstanceId',\%args);
    push @param,$self->single_parm('Name',\%args);
    push @param,$self->single_parm('Description',\%args);
    push @param,$self->boolean_parm('NoReboot',\%args);
    return $self->call('CreateImage',@param);
}

=head2 $image = $ec2->register_image(%args)

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
 -kernel_id           ID fo the kernel to use
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
    return $self->call('DeregisterImage',@param) or return;
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

Return a series of VM::EC2::Volume objects. Optional parameters:

 -volume_id    The id of the volume to fetch, either a string
               scalar or an arrayref.

 -filter       One or more filters to apply to the search

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of volume filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeVolumes.html

=cut

sub describe_volumes {
    my $self = shift;
    my %args = $self->args(-volume_id=>@_);
    my @params;
    push @params,$self->list_parm('VolumeId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeVolumes',@params) or return;
}

=head2 $v = $ec2->create_volume(-availability_zone=>$zone,-snapshot_id=>$snapshotId,-size=>$size)

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

The returned object is a VM::EC2::Volume object.

=cut

sub create_volume {
    my $self = shift;
    my %args = @_;
    my $zone = $args{-availability_zone} || $args{-zone} or croak "-availability_zone argument is required";
    my $snap = $args{-snapshot_id}       || $args{-snapshot};
    my $size = $args{-size};
    $snap || $size or croak "One or both of -snapshot_id or -size are required";
    my @params = (AvailabilityZone => $zone);
    push @params,(SnapshotId   => $snap) if $snap;
    push @params,(Size => $size)         if $size;
    return $self->call('CreateVolume',@params) or return;
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
    return $self->call('DeleteVolume',@param) or return;
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
    $args{-volume_id} && $args{-instance_id} && $args{-device}
      or croak "-volume_id, -instance_id and -device arguments must all be specified";
    my @param = $self->single_parm(VolumeId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(Device=>\%args);
    return $self->call('AttachVolume',@param) or return;
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
    return $self->call('DetachVolume',@param) or return;
}

=head2 @snaps = $ec2->describe_snapshots(-snapshot_id=>\@ids,%other_param)

=head2 @snaps = $ec2->describe_snapshots(@snapshot_ids)

Returns a series of VM::EC2::Snapshot objects. All parameters
are optional:

 -snapshot_id     ID of the snapshot

 -owner           Filter by owner ID

 -restorable_by   Filter by IDs of a user who is allowed to restore
                   the snapshot

 -filter          Tags and other filters

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeSnapshots.html

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
fetch. Currently Amazon defines only one attribute,
"createVolumePermission", which will return a list of user Ids who are
allowed to create volumes from this snapshot.

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

=head1 SECURITY GROUPS AND KEY PAIRS

The methods in this section allow you to query and manipulate security
groups (firewall rules) and SSH key pairs. See
L<VM::EC2::SecurityGroup> and L<VM::EC2::KeyPair> for functionality
that is available through these objects.

=head2 @sg = $ec2->describe_security_groups(-group_id  => \@ids,
                                            -group_name=> \@names,
                                            -filter    => \%filters);

=head2 @sg = $ec2->describe_security_groups(@group_ids)

Searches for security groups (firewall rules) matching the provided
filters and return a series of VM::EC2::SecurityGroup objects.

Optional parameters:

 -group_name      A single group name or an arrayref containing a list
                   of names

 -name            Shorter version of -group_name

 -group_id        A single group id (i.e. 'sg-12345') or an arrayref
                   containing a list of ids

 -filter          Filter on tags and other attributes.

The -filter argument name can be omitted if there are no other
arguments you wish to pass.

The full list of security group filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeSecurityGroups.html

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
    return $self->describe_security_groups($g);
}

=head2 $boolean = $ec2->delete_security_group($group_id)

=head2 $boolean = $ec2->delete_security_group(-group_id=>$group_id,
                                              -group_name=>$name);

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

=head2 @keys = $ec2->describe_key_pairs(-key_name => \@names,
                                   -filter    => \%filters);
=head2 @keys = $ec2->describe_key_pairs(@names);

Searches for ssh key pairs matching the provided filters and return
a series of VM::EC2::KeyPair objects.

Optional parameters:

 -key_name      A single key name or an arrayref containing a list
                   of names
 -filter          Filter on tags and other attributes.

The full list of key filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeKeyPairs.html

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

=head2 $key = $ec2->import_key_pair(-key_name=>$name,
                                    -public_key_material=>$public_key)

=head2 $key = $ec2->import_key_pair($name,$public_key)

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
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeTags.html

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

=head2 @addr = $ec2->describe_addresses(-public_ip=>\@addr,-allocation_id=>\@id,-filter->\%filters)

=head2 @addr = $ec2->describe_addresses(@public_ips)

Queries AWS for a list of elastic IP addresses already allocated to
you. All parameters are optional:

 -public_ip     -- An IP address (in dotted format) or an arrayref of
                   addresses to return information about.
 -allocation_id -- An allocation ID or arrayref of such IDs. Only 
                   applicable to VPC addresses.
 -filter        -- A hashref of tag=>value pairs to filter the response
                   on.

The list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeAddresses.html.

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
    @_ == 1 or croak "Usage: associate_address(\$elastic_addr)";
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

 -filter                          A set of filters to apply.

For available filters, see http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeReservedInstancesOfferings.html.

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
    push @param,$self->single_parm('InstanceTenancy',\%args);  # should initial "i" be upcase?
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

For available filters, see http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeReservedInstances.html.

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

These methods allow you to request spot instances and manipulte spot
data feed subscriptoins.

=cut

=head2 $subscription = $ec2->create_spot_datafeed_subscription($bucket,$prefix)

This method creates a spot datafeed subscription. Provide the method with the
name of an S3 bucket associated with your account, and a prefix to be appended
to the files written by the datafeed. Spot instance usage logs will be written 
into the requested bucket, and prefixed with the desired prefix.

If no prefix is specified, it defaults to "SPOT_DATAFEED_";

On success, a VM::EC2::Spot:DatafeedSubscription object is returned;

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

On success, a VM::EC2::Spot:DatafeedSubscription object is returned;

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

Option parameters are:

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

    if ($self->{spot_price_history_stop}) {
	delete $self->{spot_price_history_stop};
	return;
    }

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

=head2 @requests = $ec2->request_spot_instances(%param)

This method will request one or more spot instances to be launched
when the current spot instance run-hour price drops below a preset
value and terminated when the spot instance run-hour price exceeds the
value.

On success, will return a series of VM::EC2::Spot::InstanceRequest
objects, one for each instance specified in -instance_count.

=over 4

=item Required parameters:

  -spot_price        The desired spot price, in USD.

  -image_id          ID of an AMI to launch

  -instance_type     Type of the instance(s) to launch, such as "m1.small"
 
=item Optional parameters:

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

  -monitoring        Pass a true value to enable detailed monitoring.

  -subnet_id         Subnet ID in which to place instances launched under
                      this request (VPC only).

  -addressing_type   Deprecated and undocumented, but present in the
                       current EC2 API documentation.

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
            qw(SpotPrice InstanceCount Type ValidFrom ValidUntil LaunchGroup AvailabilityZoneGroup);

    # oddly enough, the following args need to be prefixed with "LaunchSpecification."
    my @launch_spec = map {$self->single_parm($_,\%args)}
            qw(ImageId KeyName UserData AddressingType InstanceType KernelId RamdiskId SubnetId);
    push @launch_spec, map {$self->list_parm($_,\%args)}
         qw(SecurityGroup SecurityGroupId);
    push @launch_spec, $self->block_device_parm($args{-block_devices}||$args{-block_device_mapping});

    while (my ($key,$value) = splice(@launch_spec,0,2)) {
	push @p,("LaunchSpecification.$key" => $value);
    }
    
    # a few more oddballs
    push @p,('LaunchSpecification.Placement.AvailabilityZone'=>$args{-availability_zone})
	if $args{-availability_zone};
    push @p,('Placement.GroupName'       =>$args{-placement_group})   if $args{-placement_group};
    push @p,('LaunchSpecification.Monitoring.Enabled'   => 'true')    if $args{-monitoring};
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


=head2 @requests = $ec2->describe_spot_instance_requests(-spot_instance_request_id=>\@ids,-filter=>\%filters)

=head2 @requests = $ec2->describe_spot_instance_requests(@spot_instance_request_ids)

=head2 @requests = $ec2->describe_spot_instance_requests(\%filters)

This method will return information about current spot instance
requests as a list of VM::EC2::Spot::InstanceRequest objects.

Optional parameters:

 -spot_instance_request_id   -- Scalar or arrayref of request Ids.

 -filter                     -- Tags and other filters to apply.

There are many filters available, described fully at http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/index.html?ApiReference-ItemType-SpotInstanceRequestSetItemType.html:

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
    launch.group-id
    launch.image-id
    launch.instance-type
    launch.kernel-id
    launch.key-name
    launch.monitoring-enabled
    launch.ramdisk-id
    product-description
    spot-instance-request-id
    spot-price
    state
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
    } else {
	%args = (-instance_id => shift);
    }
    my $id = $args{-instance_id};
    return ref $id && ref $id eq 'ARRAY' ? @$id : $id;
}

=head2 @parameters = $ec2->value_parm(ParameterName => \%args)

=cut

sub value_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return unless exists $args->{$name} || exists $args->{"-$argname"};
    my $val = $args->{$name} || $args->{"-$argname"};
    return ("$argname.Value"=>$val);
}

=head2 @parameters = $ec2->single_parm(ParameterName => \%args)

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

=head2 @parameters = $ec2->list_parm(ParameterName => \%args)

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

=head2 @parameters = $ec2->filter_parm(\%args)

=cut

sub filter_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Filter','Name','Value',$args);
}

=head2 @parameters = $ec2->tagcreate_parm(\%args)

=cut

sub tagcreate_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args);
}

=head2 @parameters = $ec2->tagdelete_parm(\%args)

=cut

sub tagdelete_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args,1);
}

=head2 @parameters = $ec2->key_value_parm($param_name,$keyname,$valuename,\%args,$skip_undef_values)

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

=head2 @parameters = $ec2->launch_perm_parm($prefix,$suffix,$value)

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

=head2 @parameters = $ec2->block_device_parm($block_device_mapping_string)

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
	    my ($snapshot,$size,$delete_on_term) = split ':',$blockdevice;
	    push @p,("BlockDeviceMapping.$c.Ebs.SnapshotId" =>$snapshot)                if $snapshot;
	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeSize" =>$size)                   if $size;
	    push @p,("BlockDeviceMapping.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if defined $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/
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

sub version  { '2011-05-15'      }

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

Make a call to Amazon using $action and the passed parameters, and
return a list of objects.

=cut

sub call {
    my $self    = shift;
    my $response  = $self->make_request(@_);

    unless ($response->is_success) {
	my $content = $response->decoded_content;
	my $error;
	if ($content =~ /<Response>/) {
	    $error = VM::EC2::Dispatch->create_error_object($response->decoded_content,$self);
	} else {
	    my $code = $response->status_line;
	    my $msg  = $response->decoded_content;
	    $error = VM::EC2::Error->new({Code=>$code,Message=>$msg},$self);
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

As of 27 July 2011, the following Amazon API calls were NOT implemented:

AssociateDhcpOptions
AssociateRouteTable
AttachInternetGateway
AttachVpnGateway
BundleInstance
CancelBundleTask
CancelConversionTask
CancelSpotInstanceRequests
ConfirmProductInstance
CreateCustomerGateway
CreateDhcpOptions
CreateInternetGateway
CreateNetworkAcl
CreateNetworkAclEntry
CreatePlacementGroup
CreateRoute
CreateRouteTable
CreateSpotDatafeedSubscription
CreateSubnet
CreateVpc
CreateVpnConnection
CreateVpnGateway
DeleteCustomerGateway
DeleteDhcpOptions
DeleteInternetGateway
DeleteNetworkAcl
DeleteNetworkAclEntry
DeletePlacementGroup
DeleteRoute
DeleteRouteTable
DeleteSpotDatafeedSubscription
DeleteSubnet
DeleteVpc
DeleteVpnConnection
DeleteVpnGateway
DescribeBundleTasks
DescribeConversionTasks
DescribeCustomerGateways
DescribeDhcpOptions
DescribeNetworkAcls
DescribePlacementGroups
DescribeRouteTables
DescribeSpotDatafeedSubscription
DescribeSpotInstanceRequests
DescribeSpotPriceHistory
DescribeSubnets
DescribeVpcs
DescribeVpnConnections
DescribeVpnGateways
DetachInternetGateway
DetachVpnGateway
DisassociateRouteTable
ImportInstance
ReplaceNetworkAclAssociation
ReplaceNetworkAclEntry
ReplaceRoute
ReplaceRouteTableAssociation
RequestSpotInstances

=head1 OTHER INFORMATION

This section contains technical information that may be of interest to developers.

=head2 Signing and authentication protocol

This module uses Amazon AWS signing protocol version 2, as described
at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?using-query-api.html. It
uses the HmacSHA256 signature method, which is the most secure method
currently available. For additional security, use "https" for the
communications endpoint:

  $ec2 = VM::EC2->new(-endpoint=>'https://ec2.amazonaws.com');

=head2 Subclassing VM::EC2 objects

To subclass VM::EC2 objects (or implement your own from scratch) you
will need to override the object dispatch mechanism. Fortunately this
is very easy. After "use VM::EC2" call
VM::EC2::Dispatch->add_override() one or more times:

 VM::EC2::Dispatch->add_override($call_name => $dispatch).

The first argument, $call_name, is name of the Amazon API call, such as "DescribeImages".

The second argument, $dispatch, instructs VM::EC2::Dispatch how to
create objects from the parsed XML. There are three possible syntaxes:

 1) A CODE references, such as an anonymous subroutine.

    In this case the code reference will be invoked to handle the 
    parsed XML returned from the request. The code will receive 
    two arguments consisting of the parsed
    content of the response, and the VM::EC2 object used to generate the
    request.

 2) A VM::EC2::Dispatch method name, optionally followed by its parameters
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
      VM::EC2::Dispatch->add_override('call_name_1'=>\&subroutine1).
      VM::EC2::Dispatch->add_override('call_name_2'=>\&subroutine2).
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
