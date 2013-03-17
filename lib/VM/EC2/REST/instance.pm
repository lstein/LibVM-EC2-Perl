package VM::EC2::REST::instance;

use VM::EC2 '';  # important not to import anything!
package VM::EC2;  # add methods to VM::EC2

VM::EC2::Dispatch->register(
    RunInstances      => sub { VM::EC2::Dispatch::load_module('VM::EC2::Instance::Set');
						       my $s = VM::EC2::Instance::Set->new(@_) or return;
						       return $s->instances;
			    },
    StartInstances       => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    StopInstances        => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    TerminateInstances   => 'fetch_items,instancesSet,VM::EC2::Instance::State::Change',
    RebootInstances      => 'boolean',
    ConfirmProductInstance      => 'boolean',
    ConfirmProductInstance => 'boolean',
    ModifyInstanceAttribute => 'boolean',
    ResetInstanceAttribute => 'boolean',
    DescribeInstanceStatus => 'fetch_items_iterator,instanceStatusSet,VM::EC2::Instance::StatusItem,instance_status',
    );

=head1 NAME

VM::EC2::REST::instance - VM::EC2 methods for controlling instances

=head1 SYNOPSIS

 use VM::EC2 ':standard';

=head1 METHODS

The methods in this section allow you to retrieve information about
EC2 instances, launch new instances, control the instance lifecycle
(e.g. starting and stopping them), and fetching the console output
from instances.

The primary object manipulated by these methods is
L<VM::EC2::Instance>. Please see the L<VM::EC2::Instance> manual page
for additional methods that allow you to attach and detach volumes,
modify an instance's attributes, and convert instances into images.

=head2 @instances = $ec2->describe_instances(@instance_ids)

=head2 @instances = $ec2->describe_instances(\%filters)

=head2 @instances = $ec2->describe_instances(-instance_id=>\@ids,-filter=>\%filters)

Return a series of VM::EC2::Instance objects. Optional arguments are:

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

There are a large number of filters, which are listed in full at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeInstances.html.

Here is a alpha-sorted list of filter names: architecture,
availability-zone, block-device-mapping.attach-time,
block-device-mapping.delete-on-termination,
block-device-mapping.device-name, block-device-mapping.status,
block-device-mapping.volume-id, client-token, dns-name, group-id,
group-name, hypervisor, image-id, instance-id, instance-lifecycle,
instance-state-code, instance-state-name, instance-type,
instance.group-id, instance.group-name, ip-address, kernel-id,
key-name, launch-index, launch-time, monitoring-state, owner-id,
placement-group-name, platform, private-dns-name, private-ip-address,
product-code, ramdisk-id, reason, requester-id, reservation-id,
root-device-name, root-device-type, source-dest-check,
spot-instance-request-id, state-reason-code, state-reason-message,
subnet-id, tag-key, tag-value, tag:key, virtualization-type, vpc-id.

Note that the objects returned from this method are the instances
themselves, and not a reservation set. The reservation ID can be
retrieved from each instance by calling its reservationId() method.

=cut

sub describe_instances {
    my $self = shift;
    my %args = VM::EC2::ParmParser->args(-instance_id,@_);
    my ($async,@params) = VM::EC2::ParmParser->format_parms(\%args,
							    {
								list_parm   => 'InstanceId',
								filter_parm => 'Filter'
							    });
    return $self->call('DescribeInstances',@params);
}

VM::EC2::Dispatch->register(DescribeInstances => sub { VM::EC2::Dispatch::load_module('VM::EC2::ReservationSet');
						       my $r = VM::EC2::ReservationSet->new(@_) or return;
						       return $r->instances;
			    });

=head2 @i = $ec2->run_instances($ami_id)

=head2 @i = $ec2->run_instances(-image_id=>$id,%other_args)

This method will provision and launch one or more instances given an
AMI ID. If successful, the method returns a series of
VM::EC2::Instance objects.

If called with a single argument this will be interpreted as the AMI
to launch, and all other arguments will take their
defaults. Otherwise, the arguments will be taken as a
-parameter=>$argument list.

=over 4

=item Required arguments:

  -image_id       ID of an AMI to launch
 
=item Optional arguments:

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

  -network_interfaces  A single network interface specification string
                     or a list of them as an array reference (VPC only).
                     These are described in more detail below.
                     
  -iam_arn           The Amazon resource name (ARN) of the IAM Instance Profile (IIP)
                       to associate with the instances.

  -iam_name          The name of the IAM instance profile (IIP) to associate with the
                       instances.

  -ebs_optimized     Boolean. If true, create an EBS-optimized instance
                     (valid only for certain instance types.

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

     - 'vol-12345678': A volume ID will attempt to attach the given volume to the
       instance, contingent on volume state and availability zone.

     - 'none': Suppress this block device, even if it is mapped in the AMI.
          
     - '[<snapshot-id>][:<size>[:<delete-on-termination>[:<volume-type>[:<iops>]]]]': 
       indicates that an Amazon EBS volume, created from the specified Amazon EBS
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

         - '<volume-type>': The volume type. One of "standard" or "io1".

         - '<iops>': The number of I/O operations per second (IOPS) that
           the volume suports. A number between 100 to 2000. Only valid
           for volumes of type "io1".
          
         Examples: -block_devices => '/dev/sdb=snap-7eb96d16'
                   -block_devices => '/dev/sdc=snap-7eb96d16:80:false'
                   -block_devices => '/dev/sdd=:120'
                   -block_devices => '/dev/sdc=:120:true:io1:500'

To provide multiple mappings, use an array reference. In this example,
we launch two 'm1.small' instance in which /dev/sdb is mapped to
ephemeral storage and /dev/sdc is mapped to a new 100 G EBS volume:

 @i=$ec2->run_instances(-image_id  => 'ami-12345',
                        -min_count => 2,
                        -block_devices => ['/dev/sdb=ephemeral0',
                                           '/dev/sdc=:100:true']
    )

=item Network interface syntax

Each instance has a single primary network interface and private IP
address that is ordinarily automatically assigned by Amazon. When you
are running VPC instances, however, you can add additional elastic
network interfaces (ENIs) to the instance and add secondary private IP
addresses to one or more of these ENIs. ENIs can exist independently
of instances, and be detached and reattached in much the same way as
EBS volumes. This is explained in detail at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/using-instance-addressing.html.

The network configuration can be specified using the
-network_interface parameter:

 -network_interfaces => ['eth0=10.10.0.12:subnet-1234567:sg-1234567:true:My Custom Eth0',
                         'eth1=10.10.1.12,10.10.1.13:subnet-999999:sg-1234567:true:My Custom Eth1',

The format is '<device>=<specification>'. The device is an ethernet
interface name such as eth0, eth1, eth2, etc. The specification has up
to five fields, each separated by the ":" character. All fields are
optional and can be left blank. If missing, AWS will choose a default.

  10.10.1.12,10.10.1.13:subnet-999999:sg-1234567:true:My Custom Eth1

B<1. IP address(es)>: A single IP address in standard dot form, or a
list of IP addresses separated by commas. The first address in the
list will become the primary private IP address for the
interface. Subsequent addresses will become secondary private
addresses. You may specify "auto" or leave the field blank to have AWS
choose an address automatically from within the subnetwork. To
allocate several secondary IP addresses and have AWS pick the
addresses automatically, give the count of secondary addresses you
wish to allocate as an integer following the primary IP address. For
example, "auto,3" will allocate an automatic primary IP address and
three automatic secondary addresses, while "10.10.1.12,3" will force
the primary address to be 10.10.1.12 and create three automatic
secondary addresses.

B<2. Subnetwork ID>: The ID of the VPC subnetwork in which the ENI
resides. An instance may have several ENIs associated with it, and
each ENI may be attached to a different subnetwork.

B<3. Security group IDs>: A comma-delimited list of the security group
IDs to associate with this ENI.

B<4. DeleteOnTerminate>: True if this ENI should be automatically
deleted when the instance terminates.

B<5. Description>: A human-readable description of the ENI.

As an alternative syntax, you may specify the ID of an existing ENI in
lieu of the primary IP address and other fields. The ENI will be
attached to the instance if its permissions allow:

 -network_interfaces => 'eth0=eni-123456'

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
    my %args = VM::EC2::ParmParser->args('-image_id',@_);
    $args{-image_id}  or croak "run_instances(): -image_id argument missing";
    $args{-min_count} ||= 1;
    $args{-max_count} ||= $args{-min_count};
    $args{-availability_zone} ||= $args{-zone};
    $args{-availability_zone} ||= $args{-placement_zone};

    my @p = map {$self->single_parm($_,\%args) }
       qw(ImageId MinCount MaxCount KeyName KernelId RamdiskId PrivateIpAddress
          InstanceInitiatedShutdownBehavior ClientToken SubnetId InstanceType);
    push @p,map {$self->list_parm($_,\%args)} qw(SecurityGroup SecurityGroupId);
    push @p,('UserData' =>encode_base64($args{-user_data},''))        if $args{-user_data};
    push @p,('Placement.AvailabilityZone'=>$args{-availability_zone}) if $args{-availability_zone};
    push @p,('Placement.GroupName'=>$args{-placement_group})          if $args{-placement_group};
    push @p,('Placement.Tenancy'=>$args{-tenancy})                    if $args{-placement_tenancy};
    push @p,('Monitoring.Enabled'   =>'true')                         if $args{-monitoring};
    push @p,('DisableApiTermination'=>'true')                         if $args{-termination_protection};
    push @p,('EbsOptimized'=>'true')                                  if $args{-ebs_optimized};
    push @p,('InstanceInitiatedShutdownBehavior'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};
    push @p,$self->block_device_parm($args{-block_devices}||$args{-block_device_mapping});
    push @p,$self->network_interface_parm(\%args);
    push @p,$self->iam_parm(\%args);
    return $self->call('RunInstances',@p);
}

=head2 @s = $ec2->start_instances(@instance_ids)

=head2 @s = $ec2->start_instances(-instance_id=>\@instance_ids)

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
    return $self->call('StartInstances',@params);
}

=head2 @s = $ec2->stop_instances(@instance_ids)

=head2 @s = $ec2->stop_instances(-instance_id=>\@instance_ids,-force=>1)

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
    return $self->call('StopInstances',@params);
}

=head2 @s = $ec2->terminate_instances(@instance_ids)

=head2 @s = $ec2->terminate_instances(-instance_id=>\@instance_ids)

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
    return $self->call('TerminateInstances',@params);
}

=head2 @s = $ec2->reboot_instances(@instance_ids)

=head2 @s = $ec2->reboot_instances(-instance_id=>\@instance_ids)

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
    return $self->call('RebootInstances',@params);
}

=head2 $boolean = $ec2->confirm_product_instance($instance_id,$product_code)

Return "true" if the instance indicated by $instance_id is associated
with the given product code.

=cut

sub confirm_product_instance {
    my $self = shift;
    @_ == 1 or croak "Usage: confirm_product_instance(\$instance_id,\$product_code)";
    my ($instance_id,$product_code) = @_;
    my @params = (InstanceId=>$instance_id,
		  ProductCode=>$product_code);
    return $self->call('ConfirmProductInstance',@params);
}

=head2 $password_data = $ec2->get_password_data($instance_id);

=head2 $password_data = $ec2->get_password_data(-instance_id=>$id);

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

=head2 $meta = VM::EC2->instance_metadata

=head2 $meta = $ec2->instance_metadata

B<For use on running EC2 instances only:> This method returns a
VM::EC2::Instance::Metadata object that will return information about
the currently running instance using the HTTP:// metadata fields
described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?instancedata-data-categories.html. This
is usually fastest way to get runtime information on the current
instance.

Note that this method can be called as either an instance or a class
method.

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

=head2 @status_list = $ec2->describe_instance_status(@instance_ids);

=head2 @status_list = $ec2->describe_instance_status(-instance_id=>\@ids,-filter=>\%filters,%other_args);

=head2 @status_list = $ec2->describe_instance_status(\%filters);

This method returns a list of VM::EC2::Instance::Status objects
corresponding to status checks and scheduled maintenance events on the
instances of interest. You may provide a list of instances to return
information on, a set of filters, or both.

The filters are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeInstanceStatus.html. The
brief list is:

availability-zone, event.code, event.description, event.not-after,
event.not-before, instance-state-name, instance-state-code,
system-status.status, system-status.reachability,
instance-status.status, instance-status.reachability.

Request arguments are:

  -instance_id            Scalar or array ref containing the instance ID(s) to return
                           information about (optional).

  -filter                 Filters to apply (optional).

  -include_all_instances  If true, include all instances, including those that are 
                           stopped, pending and shutting down. Otherwise, returns
                           the status of running instances only.

 -max_results             An integer corresponding to the number of instance items
                           per response (must be greater than 5).

If -max_results is specified, then the call will return at most the
number of instances you requested. You may see whether there are additional
results by calling more_instance_status(), and then retrieve the next set of
results with additional call(s) to describe_instance_status():

 my @results = $ec2->describe_instance_status(-max_results => 10);
 do_something(\@results);
 while ($ec2->more_instance_status) {
    @results = $ec2->describe_instance_status;
    do_something(\@results);
 }

NOTE: As of 29 July 2012, passing -include_all_instances causes an EC2
"unknown parameter" error, indicating some mismatch between the
documented API and the actual one.

=cut

sub more_instance_status {
    my $self = shift;
    return $self->{instance_status_token} &&
           !$self->{instance_status_stop};
}

sub describe_instance_status {
    my $self = shift;
    my @parms;

    if (!@_ && $self->{instance_status_token} && $self->{instance_status_args}) {
	@parms = (@{$self->{instance_status_args}},NextToken=>$self->{instance_status_token});
    }
    
    else {
	my %args = $self->args('-instance_id',@_);
	push @parms,$self->list_parm('InstanceId',\%args);
	push @parms,$self->filter_parm(\%args);
	push @parms,$self->boolean_parm('IncludeAllInstances',\%args);
	push @parms,$self->single_parm('MaxResults',\%args);
	
	if ($args{-max_results}) {
	    $self->{instance_status_token} = 'xyzzy'; # dummy value
	    $self->{instance_status_args} = \@parms;
	}

    }
    return $self->call('DescribeInstanceStatus',@parms);
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


=head1 SEE ALSO

L<VM::EC2>

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
