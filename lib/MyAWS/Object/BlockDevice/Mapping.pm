package MyAWS::Object::BlockDevice::Mapping;

=head1 NAME

MyAWS::Object::BlockDevice::Mapping - Object describing an EC2 block device attached to an instance

=head1 SYNOPSIS

  use MyAWS;

  $aws        = MyAWS->new(...);
  $instance   = $aws->describe_instances(-instance_id=>'i-123456');
  my @devices   = $instance->blockDeviceMapping;
  for my $dev (@devices) {
    $dev       = $dev->deviceName;
    $volume_id = $dev->volumeId;
    $status    = $dev->status;
    $atime     = $dev->attachmentTime;
    $delete    = $dev->deleteOnTermination;
    $volume    = $dev->volume;
  }

=head1 DESCRIPTION

This object represents an Amazon block device associated with an instance;
it is returned by MyAWS->run_instances().

Please see L<MyAWS::Object::Base> for methods shared by all MyAWS
objects.

=head1 METHODS

These object methods are supported:

 deviceName  -- Name of the device, such as /dev/sda1.
 ebs         -- A MyAWS::Object::BlockDevice::Mapping::EBS object
                describing the characteristics of the attached
                EBS volume

For your convenience, a number of the ebs() object's methods are
passed through:

 volumeId         -- ID of the volume.
 status           -- One of "attaching", "attached", "detaching", "detached"
 attachTime       -- Time this volume was attached
 deleteOnTermination -- Whether the volume will be deleted when its attached
                   instance is deleted.

In addition, the following convenience function is provided:

=head2 $volume = $dev->volume

This returns a MyAWS::Object::Volume object from which more
information about the volume, such as its size, can be derived.

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as the
deviceName.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::BlockDevice::Attachment>
L<MyAWS::Object::BlockDevice::Mapping::EBS>
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
use MyAWS::Object::BlockDevice::Mapping::EBS;

use overload '""' => sub {shift()->deviceName},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return qw(deviceName ebs);
}

sub ebs {
    my $self = shift;
    return $self->{ebs} ||= MyAWS::Object::BlockDevice::Mapping::EBS->new($self->SUPER::ebs,$self->aws);
}

sub volumeId     { shift->ebs->volumeId }
sub status       { shift->ebs->status   }
sub attachTime   { shift->ebs->attachTime   }
sub deleteOnTermination   { shift->ebs->deleteOnTermination }
sub volume       { shift->ebs->volume }

1;

