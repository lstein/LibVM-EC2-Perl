package VM::EC2::Image;

=head1 NAME

VM::EC2::Image - Object describing an Amazon Machine Image (AMI)

=head1 SYNOPSIS

  use VM::EC2;

  $ec2     = VM::EC2->new(...);
  $image   = $ec2->describe_images(-image_id=>'ami-12345');

  $state   = $image->imageState;
  $owner   = $image->imageOwnerId;
  $rootdev = $image->rootDeviceName;
  @devices = $image->blockDeviceMapping;
  $tags    = $image->tags;

  @instances = $image->run_instances(-min_count=>10);

=head1 DESCRIPTION

This object represents an Amazon Machine Image (AMI), and is returned
by VM::EC2->describe_images(). In addition to methods to query the
image's attributes, the run_instances() method allows you to launch
and configure EC2 instances based on the AMI.

=head1 METHODS

These object methods are supported:

 imageId       -- AMI ID
 imageLocation -- Location of the AMI
 imageState    -- Current state of the AMI. One of "available",
                  "pending" or "failed". Only "available" AMIs
                  can be launched.
 imageOwnerId  -- AWS account ID of the image owner.
 isPublic      -- Returns true if this image has public launch
                  permissions. Note that this is a Perl boolean,
                  and not the string "true".
 productCodes  -- A list of product codes associated with the image.
 architecture  -- The architecture of the image.
 imageType     -- The image type (machine, kernel or RAM disk).
 kernelId      -- The kernel associated with the image.
 ramdiskId     -- The RAM disk associated with the image.
 platform      -- "Windows" for Windows AMIs, otherwise undef.
 stateReason   -- Explanation of a "failed" imageState. This is
                  a VM::EC2::Instance::State::Reason
                  object.
 imageOwnerAlias -The AWS account alias (e.g. "self") or AWS
                  account ID that owns the AMI.
 name          -- Name of the AMI provided during image creation.
 description   -- Description of the AMI provided during image
                  creation.
 rootDeviceType -- The root device type. One of "ebs" or
                  "instance-store".
 rootDeviceMape -- Name of the root device, e.g. "/dev/sda1"
 blockDeviceMapping -- List of block devices attached to this
                   image. Each element is a
                   VM::EC2::BlockDevice.
 virtualizationType -- One of "paravirtual" or "hvm".
 hypervisor     -- One of "ovm" or "xen"

In addition, the object supports the tags() method described in
L<VM::EC2::Generic>:

 print "ready for production\n" if $image->tags->{Released};

=head2 $image->refresh

This method will refresh the object from AWS, updating all values to
their current ones. You can call it after tagging or otherwise
changing image attributes.

=head2 @instances = $image->run_instances(@params)

The run_instance() method will launch one or more instances based on
this AMI. The method takes all the arguments recognized by
VM::EC2->run_instances(), except for the -image_id argument. The method
returns a list of VM::EC2::Instance objects, which you may
monitor periodically until they are up and running.

See L<VM::EC2> for details.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
imageId.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Object>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::StateReason>
L<VM::EC2::Instance>
L<VM::EC2::Tag>

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
use base 'VM::EC2::Generic';
use VM::EC2::BlockDevice;
use VM::EC2::Instance::State::Reason;

use Carp 'croak';

sub valid_fields {
    my $self = shift;
    return qw(imageId imageLocation imageState imageOwnerId isPublic
              productCodes architecture imageType kernelId ramdiskId
              platform stateReason imageOwnerAlias name description
              rootDeviceType rootDeviceName blockDeviceMapping
              virtualizationType tagSet hypervisor);
}

sub primary_id { shift->imageId }

sub stateReason {
    my $self  = shift;
    my $state = $self->SUPER::stateReason;
    return VM::EC2::Instance::State::Reason->new($state);

}

sub productCodes {
    my $self = shift;
    my $codes = $self->SUPER::productCodes or return;
    return map {$_->{productCode}} @{$codes->{item}};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { VM::EC2::BlockDevice->new($_,$self->aws)} @{$mapping->{item}};
}

sub isPublic {
    my $self = shift;
    return $self->SUPER::isPublic eq 'true';
}

sub run_instances {
    my $self = shift;
    my %args = @_;
    croak "$self is unavailable for launching because its state is ",$self->imageState
	      unless $self->imageState eq 'available';
    $args{-image_id} = $self->imageId;
    $self->aws->run_instances(%args);
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_images(-image_id=>$self->imageId) unless $i;
    %$self  = %$i;
}

1;
