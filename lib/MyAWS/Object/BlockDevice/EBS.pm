package MyAWS::Object::BlockDevice::EBS;

=head1 NAME

MyAWS::Object::BlockDevice::EBS - Object describing how to initialize an Amazon EBS volume from an image

=head1 SYNOPSIS

  use MyAWS;

  $image      = $aws->describe_images(-image_id=>'ami-123456');
  my @devices = $image->blockDeviceMapping;
  for my $d (@devices) {
    my $ebs = $d->ebs;
    my $snapshot_id    = $ebs->snapshotId;
    my $size           = $ebs->volumeSize;
    my $delete         = $ebs->deleteOnTermination;
  }

=head1 DESCRIPTION

This object is used to describe the parameters used to create an
Amazon EBS volume when running an image. Generally you will not call
this directly, as all its methods are passed through by the
MyAWS::Object::BlockDevice object returned from the
blockDeviceMapping() call.

See L<MyAWS::Object::BlockDevice> for a simpler way to get the
information needed.

It is easy to confuse this with
MyAWS::Object::BlockDevice::Mapping::EBS, which describes the
attachment of an existing EBS volume to an instance. This class is
instead used to store the parameters that will be used to generate a
new EBS volume when an image is launched.

=head1 METHODS

The following object methods are supported:
 
 snapshotId  -- ID of the snapshot used to create this EBS when an
                instance is launched from this image.
 volumeSize  -- Size of the EBS volume (in gigs).
 deleteOnTermination -- Whether this EBS will be deleted when the
                instance terminates.

=head1 STRING OVERLOADING

NONE.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::Snapshot>
L<MyAWS::Object::BlockDevice>

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

sub valid_fields {
    my $self = shift;
    return qw(snapshotId volumeSize deleteOnTermination);
}

1;
