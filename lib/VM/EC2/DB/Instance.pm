package VM::EC2::DB::Instance;

=head1 NAME

VM::EC2::DB::Instance - Object describing an Amazon RDS instance

=head1 SYNOPSIS

  use VM::EC2;

  $ec2      = VM::EC2->new(...);
  $db_instance = $ec2->describe_db_instances('mydbinstance');


=head1 DESCRIPTION

This object represents an Amazon RDS DB instance, and is returned by
VM::EC2->describe_db_instances(). In addition to methods to query the
instance's attributes, there are methods that allow you to manage the
instance's lifecycle, including start, stopping, and terminating it.

=head1 METHODS

These object methods are supported:
 
The object also supports the tags() method described in
L<VM::EC2::Generic>:

 print "ready for production\n" if $image->tags->{Released};

All methods return read-only values except for those marked CHANGEABLE
in the list above. For these, you can change the instance attribute on
stopped instances by invoking the method with an appropriate new
value. For example, to change the instance type from "t1.micro" to
"m1.small", you can do this:

 my @tiny_instances = $ec2->describe_instances(-filter=>{'instance-type'=>'t1.micro'});
 for my $i (@tiny_instances) {
    next unless $i->instanceState eq 'stopped';
    $i->instanceType('m1.small') or die $ec2->error;
 }

When you attempt to change an attribute of an instance, the method
will return true on success, false on failure. On failure, the
detailed error messages can be recovered from the VM::EC2 object's
error() method.

=head1 LIFECYCLE METHODS

In addition, the following convenience functions are provided

=head2 $state = $instance->current_status

This method queries AWS for the instance's current state and returns
it as a VM::EC2::Instance::State object. This enables you to 
poll the instance until it is in the desired state:

 while ($instance->current_status eq 'pending') { sleep 5 }

=head2 $state = $instance->current_state

An alias for current_status().

=head2 $state_change = $instance->start([$wait])

This method will start the current instance and returns a
VM::EC2::Instance::State::Change object that can be used to
monitor the status of the instance. By default the method returns
immediately, but you can pass a true value as an argument in order to
pause execution until the instance is in the "running" state.

Here's a polling example:

  $state = $instance->start;
  while ($state->status eq 'pending') { sleep 5 }

Here's an example that will pause until the instance is running:

  $instance->start(1);

Attempting to start an already running instance, or one that is
in transition, will throw a fatal error.

=head2 $state_change = $instance->stop([$wait])

This method is similar to start(), except that it can be used to
stop a running instance.

=head2 $state_change = $instance->terminate([$wait])

This method is similar to start(), except that it can be used to
terminate an instance. It can only be called on instances that
are either "running" or "stopped".

=head2 $state_change = $instance->reboot()

Reboot the instance. Rebooting doesn't occur immediately; instead the
request is queued by the Amazon system and may be satisfied several
minutes later. For this reason, there is no "wait" argument.

=head2 $seconds = $instance->up_time()

Return the number of seconds since the instance was launched. Note
that this includes time that the instance was either in the "running"
or "stopped" state.

=head2 $result = $instance->associate_address($elastic_address)

Associate an elastic address with this instance. If you are
associating a VPC elastic IP address with the instance, the result
code will indicate the associationId. Otherwise it will be a simple
perl truth value ("1") if successful, undef if false.

In the case of an ordinary EC2 Elastic IP address, the first argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.

=head2 $bool = $instance->disassociate_address

Disassociate an elastic IP address from this instance. if any. The
result will be true if disassociation was successful. Note that for a
short period of time (up to a few minutes) after disassociation, the
instance will have no public IP address and will be unreachable from
the internet.

=head2 @list = $instance->network_interfaces

Return the network interfaces attached to this instance as a set of
VM::EC2::NetworkInterface objects (VPC only).

=head2 $instance->refresh

This method will refresh the object from AWS, updating all values to
their current ones. You can call it after starting an instance in
order to get its IP address. Note that refresh() is called
automatically for you if you call start(), stop() or terminate() with
a true $wait argument.

=head2 $text = $instance->console_output

Return the console output of the instance as a
VM::EC2::ConsoleOutput object. This object can be treated as a
string, or as an object with methods

=head1 CREATING IMAGES

The create_image() method provides a handy way of creating and
registering an AMI based on the current state of the instance. All
currently-associated block devices will be snapshotted and associated
with the image.

Note that this operation can take a long time to complete. You may
follow its progress by calling the returned image object's
current_status() method.

=head2 $imageId = $instance->create_image($name [,$description])

=head2 $imageId = $instance->create_image(-name=>$name,-description=>$description,-no_reboot=>$boolean)

Create an image from this instance and return a VM::EC2::Image object.
The instance must be in the "stopped" or "running" state. In the
latter case, Amazon will stop the instance, create the image, and then
restart it unless the -no_reboot argument is provided.

Arguments:

 -name           Name for the image that will be created. (required)
 -description    Description of the new image.
 -no_reboot      If true, don't reboot the instance.

In the unnamed argument version you can provide the name and
optionally the description of the resulting image.

=head2 $boolean = $instance->confirm_product_code($product_code)

Return true if this instance is associated with the given product code.

=head1 VOLUME MANAGEMENT

=head2 $attachment = $instance->attach_volume($volume_id,$device)

=head2 $attachment = $instance->attach_volume(-volume_id=>$volume_id,-device=>$device)

Attach volume $volume_id to this instance using virtual device
$device. Both arguments are required. The result is a
VM::EC2::BlockDevice::Attachment object which you can monitor by
calling current_status():

    my $a = $instance->attach_volume('vol-12345'=>'/dev/sdg');
    while ($a->current_status ne 'attached') {
       sleep 2;
    }
    print "volume is ready to go\n";

=head2 $attachment = $instance->detach_volume($vol_or_device)

=head2 $attachment = $instance->detach_volume(-volume_id => $volume_id
                                              -device    => $device,
                                              -force     => $force);

Detaches the specified volume. In the single-argument form, you may
provide either a volume or a device name. In the named-argument form,
you may provide both the volume and the device as a check that you are
detaching exactly the volume you think you are.

Optional arguments:

 -volume_id      -- ID of the instance to detach from.
 -device         -- How the device is exposed to the instance.
 -force          -- Force detachment, even if previous attempts were
                    unsuccessful.

The result is a VM::EC2::BlockDevice::Attachment object which
you can monitor by calling current_status():

    my $a = $instance->detach_volume('/dev/sdg');
    while ($a->current_status ne 'detached') {
       sleep 2;
    }
    print "volume is ready to go\n";

=head1 NETWORK INTERFACE MANAGEMENT

=head2 $attachment_id = $instance->attach_network_interface($interface_id => $device)

=head2 $attachment_id = $instance->attach_network_interface(-network_interface_id=>$id,
                                                            -device_index   => $device)

This method attaches a network interface to the current instance using
the indicated device index. You can use either an elastic network
interface ID, or a VM::EC2::NetworkInterface object. You may use an
integer for -device_index, or use the strings "eth0", "eth1" etc.

Required arguments:

 -network_interface_id ID of the network interface to attach.
 -device_index         Network device number to use (e.g. 0 for eth0).

On success, this method returns the attachmentId of the new attachment
(not a VM::EC2::NetworkInterface::Attachment object, due to an AWS API
inconsistency).

=head2 $boolean = $instance->detach_network_interface($interface_id [,$force])

This method detaches a network interface from the current instance. If
a true second argument is provided, then the detachment will be
forced, even if the interface is in use.

On success, this method returns a true value.

=head1 ACCESSING INSTANCE METADATA

=head2 $meta = $instance->metadata

B<For use on running EC2 instances only:> This method returns a
VM::EC2::Instance::Metadata object that will return information about
the currently running instance using the HTTP:// metadata fields
described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?instancedata-data-categories.html. This
is usually fastest way to get runtime information on the current
instance.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
instanceId.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::Instance::State>
L<VM::EC2::Instance::State::Reason>
L<VM::EC2::Instance::Metadata>
L<VM::EC2::Instance::Placement>
L<VM::EC2::Tag>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>.

Copyright (c) 2013 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use Carp 'croak';
use VM::EC2::DB::ParameterGroup::Status;
use VM::EC2::DB::SecurityGroup::Membership;
use VM::EC2::DB::Endpoint;
use VM::EC2::DB::PendingModifiedValues;

sub valid_fields {
    my $self  = shift;
    return qw(AllocatedStorage
              AutoMinorVersionUpgrade
              AvailabilityZone
              BackupRetentionPeriod
              CharacterSetName
              DBInstanceClass
              DBInstanceIdentifier
              DBInstanceStatus
              DBName
              DBParameterGroups
              DBSecurityGroups
              DBSubnetGroup
              Endpoint
              Engine
              EngineVersion
              InstanceCreateTime
              Iops
              LatestRestorableTime
              LicenseModel
              MasterUsername
              MultiAZ
              OptionGroupMemberships
              PendingModifiedValues
              PreferredBackupWindow
              PreferredMaintenanceWindow
              PubliclyAccessible
              ReadReplicaDBInstanceIdentifiers
              ReadReplicaSourceDBInstanceIdentifier
              SecondaryAvailabilityZone
              VpcSecurityGroups
             );
}

sub AutoMinorVersionUpgrade {
    my $self = shift;
    my $auto = $self->SUPER::AutoMinorVersionUpgrade;
    return $auto eq 'true';
}

sub MultiAZ {
    my $self = shift;
    my $multi = $self->SUPER::MultiAZ;
    return $multi eq 'true';
}

sub DBParameterGroups {
    my $self = shift;
    my $groups = $self->SUPER::DBParameterGroups;
    return unless $groups;
    $groups = $groups->{DBParameterGroup};
    return ref $groups eq 'HASH' ?
        (VM::EC2::DB::Parameter::Group::Status->new($groups,$self->aws)) :
        map { VM::EC2::DB::Parameter::Group::Status->new($_,$self->aws) } @$groups;
}

sub DBSecurityGroups {
    my $self = shift;
    my $groups = $self->SUPER::DBSecurityGroups;
    return unless $groups;
    $groups = $groups->{DBSecurityGroup};
    return ref $groups eq 'HASH' ?
        (VM::EC2::DB::SecurityGroup::Membership->new($groups,$self->aws)) :
        map { VM::EC2::DB::SecurityGroup::Membership->new($_,$self->aws) } @$groups;
}

sub DBSubnetGroup {
    my $self = shift;
    my $group = $self->SUPER::DBSubnetGroup;
    return unless $group;
    return VM::EC2::DB::Subnet::Group->new($group->{DBSubnetGroup},$self->aws);
}

sub Endpoint {
    my $self = shift;
    my $endpoint = $self->SUPER::Endpoint;
    return VM::EC2::DB::EndPoint->new($endpoint,$self->aws);
}

sub OptionGroupMemberships {
    my $self = shift;
    my $groups = $self->SUPER::OptionGroupMemberships;
    return unless $groups;
    $groups = $groups->{OptionGroupMembership};
    return ref $groups eq 'HASH' ?
        (VM::EC2::DB::Option::Group::Membership->new($groups,$self->aws)) :
        map { VM::EC2::DB::Option::Group::Membership->new($_,$self->aws) } @$groups;
}

sub PendingModifiedValues {
    my $self = shift;
    my $values = $self->SUPER::PendingModifiedValues;
    return VM::EC2::DB::PendingModifiedValues->new($values,$self->aws);
}

sub PubliclyAccessible {
    my $self = shift;
    my $public = $self->SUPER::PubliclyAccessible;
    return $public eq 'true';
}

sub VpcSecurityGroups {
    my $self = shift;
    my $groups = $self->SUPER::VpcSecurityGroups;
    return unless $groups;
    $groups = $groups->{VpcSecurityGroup};
    return ref $groups eq 'HASH' ?
        (VM::EC2::DB::VpcSecurityGroup::Membership->new($groups,$self->aws)) :
        map { VM::EC2::DB::VpcSecurityGroup::Membership->new($_,$self->aws) } @$groups;
}

1;
