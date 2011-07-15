package MyAWS::Object::BlockDevice;

=head1 NAME

MyAWS::Object::BlockDevice - Object describing an EC2 block device attached to an image

=head1 SYNOPSIS

  use MyAWS;

  $aws        = MyAWS->new(...);
  $image      = $aws->describe_images(-image_id=>'ami-123456');
  my @devices = $image->blockDeviceMapping;
  for my $d (@devices) {
    my $virtual_device = $d->deviceName;
    my $snapshot_id    = $d->snapshotId;
    my $delete         = $d->deleteOnTermination;
  }

=head1 DESCRIPTION

This object represents an Amazon block device associated with an AMI;
it is returned by MyAWS->describe_images(), MyAWS->run_instances(),
and other image-related operations.

Please see L<MyAWS::Object::Base> for methods shared by all MyAWS
objects.

=head1 METHODS

These object methods are supported:

 deviceName  -- name of the device, such as /dev/sda1
 virtualName -- virtual device name, such as "ephemeral0"
 noDevice    -- true if no device associated
 ebs         -- parameters used to automatically set up Amazon EBS
                volumes when an instance is booted. This returns
                a MyAWS::Object::BlockDevice::EBS object.

For your convenience, a number of the ebs() object's methods are
passed through:

 snapshotId  -- ID of the snapshot used to create this EBS when an
                instance is launched from this image.
 volumeSize  -- Size of the EBS volume (in gigs).
 deleteOnTermination -- Whether this EBS will be deleted when the
                instance terminates.

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as:

 deviceName=snapshotId:volumeSize:deleteOnTermination

e.g.

 /dev/sdg=snap-12345:20:true

This happens to be the same syntax used to specify block device
mappings in run_instances(). See L<MyAWS>.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object>
L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::BlockDevice::Attachment>
L<MyAWS::Object::BlockDevice::EBS>
L<MyAWS::Object::BlockDevice::Mapping>
L<MyAWS::Object::BlockDevice::Mapping::EBS>
L<MyAWS::Object::ConsoleOutput>
L<MyAWS::Object::Error>
L<MyAWS::Object::Generic>
L<MyAWS::Object::Group>
L<MyAWS::Object::Image>
L<MyAWS::Object::Instance>
L<MyAWS::Object::Instance::Set>
L<MyAWS::Object::Instance::State>
L<MyAWS::Object::Instance::State::Change>
L<MyAWS::Object::Instance::State::Reason>
L<MyAWS::Object::Region>
L<MyAWS::Object::ReservationSet>
L<MyAWS::Object::SecurityGroup>
L<MyAWS::Object::Snapshot>
L<MyAWS::Object::Tag>
L<MyAWS::Object::Volume>

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
use MyAWS::Object::BlockDevice::EBS;

use overload '""' => sub {shift()->as_string},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return qw(deviceName virtualName ebs);
}

sub noDevice {
    my $self = shift;
    return exists $self->payload->{noDevice};
}

sub ebs {
    my $self = shift;
    return $self->{ebs} = MyAWS::Object::BlockDevice::EBS->new($self->SUPER::ebs,$self->aws);
}

sub snapshotId { shift->ebs->snapshotId }
sub volumeSize { shift->ebs->volumeSize }
sub deleteOnTermination { shift->ebs->deleteOnTermination }

sub as_string {
    my $self = shift;
    return $self->deviceName.'='.
	join ':',$self->snapshotId,$self->volumeSize,$self->deleteOnTermination;
}

1;

