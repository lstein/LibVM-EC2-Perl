package MyAWS::Object::Instance;

=head1 NAME

MyAWS::Object::Instance - Object describing an Amazon EC2 instance

=head1 SYNOPSIS

  use MyAWS;

  $aws      = MyAWS->new(...);
  $instance = $aws->describe_instances(-instance_id=>'i-12345');

  $instanceId    = $instance->instanceId;
  $ownerId       = $instance->ownerId;
  $reservationId = $instance->reservationId;
  $imageId       = $instance->imageId;
  $state         = $instance->instanceState;
  @groups        = $instance->groups;
  $private_ip    = $instance->privateIpAddress;
  $public_ip     = $instance->ipAddress;
  $private_dns   = $instance->privateDnsName;
  $public_dns    = $instance->dnsName;
  $time          = $instance->runTime;
  $status        = $instance->status;
  $tags          = $instance->tags;

  $stateChange = $instance->start();
  $stateChange = $instance->stop();
  $stateChange = $instance->reboot();
  $stateChange = $instance->terminate();

=head1 DESCRIPTION

This object represents an Amazon EC2 instance, and is returned by
MyAWS->describe_instances(). In addition to methods to query the
instance's attributes, there are methods that allow you to manage the
instance's lifecycle, including start, stopping, and terminating it.

Note that the information about security groups and reservations that
is returned by describe_instances() is copied into each instance
before returning it, so there is no concept of a "reservation set" in
this interface.

=head1 METHODS

These object methods are supported:
 
 instanceId     -- ID of this instance.
 imageId        -- ID of the image used to launch this instance.
 instanceState  -- The current state of the instance at the time
                   that describe_instances() was called, as a
                   MyAWS::Object::Instance::State object. Also
                   see the status() method, which re-queries EC2 for
                   the current state of the instance.
 privateDnsName -- The private DNS name assigned to the instance within
                   Amazon's EC2 network. This element is defined only
                   for running instances.
 dnsName        -- The public DNS name assigned to the instance, defined
                   only for running instances.
 reason         -- Reason for the most recent state transition, 
                   if applicable.
 keyName        -- Name of the associated key pair, if applicable.
 amiLaunchIndex -- The AMI launch index, which can be used to find
                   this instance within the launch group.
 productCodes   -- A list of product codes that apply to this instance.
 instanceType   -- The instance type, such as "t1.micro".
 launchTime     -- The time the instance launched.
 placement      -- The placement of the instance. Returns a
                   MyAWS::Object::Placement object.
 kernelId       -- ID of the instance's kernel.
 ramdiskId      -- ID of the instance's RAM disk.
 platform       -- Platform of the instance, either "windows" or empty.
 monitoring     -- State of monitoring for the instance. One of 
                   "disabled", "enabled", or "pending".
 subnetId       -- The Amazon VPC subnet ID in which the instance is 
                   running, for Virtual Private Cloud instances only.
 vpcId          -- The Virtual Private Cloud ID for VPC instances.
 privateIpAddress -- The private (internal Amazon) IP address assigned
                   to the instance.
 ipAddress      -- The public IP address of the instance.
 sourceDestCheck -- Whether source destination checking is enabled on
                   this instance. This returns a Perl boolean rather than
                   the string "true". This method is used in conjunction
                   with VPC NAT functionality. See the Amazon VPC User
                   Guide for details.
 groupSet       -- List of MyAWS::Object::Group objects indicating the VPC
                   security groups in which this instance resides. Not to be
                   confused with groups(), which returns the security groups
                   of non-VPC instances.
 stateReason    -- A MyAWS::Object::Instance::State::Reason object which
                   indicates the reason for the instance's most recent
                   state change. See http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-ItemType-StateReasonType.html
 architecture   -- The architecture of the image. Either "i386" or "x86_64".
 rootDeviceType -- The type of the root device used by the instane. One of "ebs"
                   or "instance-store".
 blockDeviceMapping -- The block device mappings for the instance, represented
                   as a list of MyAWS::Object::BlockDevice::Mapping objects.
 instanceLifeCycle-- "spot" if this instance is a spot instance, otherwise empty.
 spotInstanceRequestId -- The ID of the spot instance request, if applicable.
 virtualizationType -- Either "paravirtual" or "hvm".
 clientToken    -- The idempotency token provided at the time of the AMI launch,
                   if any.
 hypervisor     -- The instance's hypervisor type, either "ovm" or "xen".
 tagSet         -- Tags for the instance as a hashref.

The object also supports the tags() method described in
L<MyAWS::Object::Base>:

 print "ready for production\n" if $image->tags->{Released};

In addition, the following convenience functions are provided

=head2 $state = $instance->status

This method queries AWS for the instance's current state and returns
it as a MyAWS::Object::Instance::State object. This enables you to 
poll the instance until it is in the desired state:

 while ($instance->status eq 'pending') { sleep 5 }

=head2 $state_change = $instance->start([$wait])

This method will start the current instance and returns a
MyAWS::Object::Instance::State::Change object that can be used to
monitor the status of the instance. By default the method returns
immediately, but you can pass a true value as an argument in order to
pause execution until the instance is in the "running" state.

Here's a polling example:

  $state = $instance->start;
  while ($state->status eq 'pending') { sleep 5 }

Here's an example that will pause until the instance is running:

  $instance->start('wait');

Attempting to start an already running instance, or one that is
in transition, will throw a fatal error.

=head2 $state_change = $instance->stop([$wait])

This method is similar to start(), except that it can be used to
stop a running instance.

=head2 $state_change = $instance->terminate([$wait])

This method is similar to start(), except that it can be used to
terminate an instance. It can only be called on instances that
are either "running" or "stopped".

=head2 $instance->refresh

This method will refresh the object from AWS, updating all values to
their current ones. You can call it after starting an instance in
order to get its IP address. Note that refresh() is called
automatically for you if you call start(), stop() or terminate() with
a true $wait argument.

=head2 $text = $instance->console_output

Return the console output of the instance as a
MyAWS::Object::ConsoleOutput object. This object can be treated as a
string, or as an object with methods

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
instanceId.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object>
L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::State::Reason>
L<MyAWS::Object::State>
L<MyAWS::Object::Instance>
L<MyAWS::Object::Tag>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Group;
use MyAWS::Object::Instance::State;
use MyAWS::Object::Instance::State::Reason;
use MyAWS::Object::BlockDevice::Mapping;
use Carp 'croak';

sub new {
    my $self = shift;
    my %args = @_;
    return bless {
	data        => $args{-instance},
	reservation => $args{-reservation},
	requester   => $args{-requester},
	owner       => $args{-owner},
	groups      => $args{-groups},
	aws         => $args{-aws},
	xmlns       => $args{-xmlns},
	requestId   => $args{-requestId},
    },ref $self || $self;
}

sub reservationId {shift->{reservation} }
sub requesterId   {shift->{requester}   }
sub ownerId       {shift->{owner}       }
sub groups        {@{shift->{groups}}   }
sub group         {shift()->{groups}[0] }
sub primary_id    {shift()->instanceId  }

sub valid_fields {
    my $self  = shift;
    return qw(instanceId
              imageId
              instanceState
              privateDnsName
              dnsName
              reason
              keyName
              amiLaunchIndex
              productCodes
              instanceType
              launchTime
              placement
              kernelId
              ramdiskId
              monitoring
              privateIpAddress
              ipAddress
              sourceDestCheck
              architecture
              rootDeviceType
              rootDeviceName
              blockDeviceMapping
              instanceLifecycle
              spotInstanceRequestId
              virtualizationType
              clientToken
              hypervisor
              tagSet
             );
}

sub instanceState {
    my $self = shift;
    my $state = $self->SUPER::instanceState;
    return MyAWS::Object::Instance::State->new($state);
}

sub sourceDestCheck {
    my $self = shift;
    my $check = $self->SUPER::sourceDestCheck;
    return $check eq 'true';
}

sub groupSet {
    my $self = shift;
    my $groupSet = $self->SUPER::groupSet;
    return map {MyAWS::Object::Group->new($_,$self->aws,$self->xmlns,$self->requestId)}
        @{$groupSet->{item}};
}

sub placement {
    my $self = shift;
    my $p = $self->placement or return;
    return MyAWS::Object::Placement->new($p,$self->aws,$self->xmlns,$self->requestId);
}

sub monitoring {
    return shift->monitoring->{state};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { MyAWS::Object::BlockDevice::Mapping->new($_,$self->aws)} @{$mapping->{item}};
}

sub stateReason {
    my $self = shift;
    my $reason = $self->SUPER::stateReason;
    return MyAWS::Object::Instance::State::Reason->new($reason,$self->_object_args);
}

sub status {
    my $self = shift;
    my ($i)  = $self->aws->describe_instances(-instance_id=>$self->instanceId);
    $i or croak "invalid instance: ",$self->instanceId;
    $self->refresh($i);
    return $i->instanceState;
}

sub start {
    my $self = shift;
    my $wait = shift;

    my $s    = $self->status;
    croak "Can't start $self: run state=$s" unless $s eq 'stopped';
    my ($i) = $self->aws->start_instances($self) or return;
    if ($wait) {
	while ($i->status eq 'pending') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub stop {
    my $self = shift;
    my $wait = shift;

    my $s    = $self->status;
    croak "Can't stop $self: run state=$s" unless $s eq 'running';

    my ($i) = $self->aws->stop_instances($self);
    if ($wait) {
	while ($i->status ne 'stopped') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub terminate {
    my $self = shift;
    my $nowait = shift;

    my $s    = $self->status;
    croak "Can't terminate $self: run state=$s"
	unless $s eq 'running' or $s eq 'stopped';

    my ($i) = $self->aws->terminate_instances($self);
    unless ($nowait) {
	while ($i->status ne 'terminated') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_instances(-instance_id=>$self->instanceId) unless $i;
    %$self  = %$i;
}

sub console_output {
    my $self = shift;
    my $output = $self->aws->get_console_output(-instance_id=>$self->instanceId);
    return $output->output;
}

sub productCodes {
    my $self = shift;
    my $codes = $self->SUPER::productCodes or return;
    return map {$_->{productCode}} @{$codes->{item}};
}

1;

