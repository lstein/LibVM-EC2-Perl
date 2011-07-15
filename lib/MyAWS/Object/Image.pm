package MyAWS::Object::Image;

=head1 NAME

MyAWS::Object::Image - Object describing an Amazon Machine Image (AMI)

=head1 SYNOPSIS

  use MyAWS;

  $aws      = MyAWS->new(...);
  $image    = $aws->describe_images(-image_id=>'ami-12345');


=head1 DESCRIPTION

This object represents the name and ID of a security group. It is
returned by an instance's groups() method. This object does not
provide any of the details about the security group, but you can use
it in a call to MyAWS->describe_security_group() to get details about
the security group's allowed ports, etc.

=head1 METHODS

These object methods are supported:

 groupId   -- the group ID
 groupName -- the group's name

For convenience, the object also provides a permissions() method that
will return the fully detailed MyAWS::Object::SecurityGroup:

 $details = $group->permissions()

See L<MyAWS::Object::SecurityGroup>

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
groupId.

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
use MyAWS::Object::BlockDevice;
use MyAWS::Object::Instance::State::Reason;

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
    return MyAWS::Object::Instance::State::Reason->new($state);

}

sub productCodes {
    my $self = shift;
    my $codes = $self->SUPER::productCodes or return;
    return map {$_->{productCode}} @{$codes->{item}};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { MyAWS::Object::BlockDevice->new($_,$self->aws)} @{$mapping->{item}};
}


sub run_instances {
    my $self = shift;
    my %args = @_;
    $args{-image_id} = $self->imageId;
    $self->aws->run_instances(%args);
}

1;
