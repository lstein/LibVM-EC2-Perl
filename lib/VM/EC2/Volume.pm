package VM::EC2::Volume;

=head1 NAME

VM::EC2::Volume - Object describing an Amazon EBS volume

=head1 SYNOPSIS

  use VM::EC2;

  $ec2       = VM::EC2->new(...);
  @vol = $ec2->describe_volumes;
  for my $vol (@vols) {
    $id    = $vol->volumeId;
    $size  = $vol->size;
    $snap  = $vol->snapshotId;
    $zone  = $vol->availabilityZone;
    $status = $vol->status;
    $ctime = $vol->createTime;
    @attachments = $vol->attachments;
    $attachment  = $vol->attachment;
    $origin      = $vol->from_snapshot;
    @snapshots   = $vol->to_snapshots;
  }

=head1 DESCRIPTION

This object is used to describe an Amazon EBS volume. It is returned
by VM::EC2->describe_volumes().

=head1 METHODS

The following object methods are supported:
 
 volumeId         -- ID of this volume.
 size             -- Size of this volume (in GB).
 snapshotId       -- ID of snapshot this 
 availabilityZone -- Availability zone in which this volume resides.
 status           -- Volume state, one of "creating", "available",
                     "in-use", "deleting", "deleted", "error"
 createTime       -- Timestamp for when volume was created.
 tags             -- Hashref containing tags associated with this group.
                     See L<VM::EC2::Generic>.

In addition, this class provides several convenience functions:

=head2 $attachment  = $vol->attachment
=head2 @attachments = $vol->attachments

The attachment() method returns a
VM::EC2::BlockDevice::Attachment object describing the
attachment of this volume to an instance. If the volume is unused,
then this returns undef.

The attachments() method is similar, except that it returns a list of
the attachments.  Currently an EBS volume can only be attached to one
instance at a time, but the Amazon call syntax supports multiple
attachments and this method is provided for future compatibility.

=head2 $snap = $vol->from_snapshot

Returns the VM::EC2::Snapshot object that this volume was
originally derived from. It will return undef if the resource no
longer exists, or if the volume was created from scratch.

=head2 @snap = $vol->to_snapshots

If this volume has been used to create one or more snapshots, this
method will return them as a list of VM::EC2::Snapshot objects.

=head2 $status = $vol->current_status

This returns the up-to-date status of the volume. It works by calling
refresh() and then returning status().

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
volumeId.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::Snapshot>
L<VM::EC2::BlockDevice>
L<VM::EC2::BlockDevice::Attachment>

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
use VM::EC2::BlockDevice::Attachment;

sub valid_fields {
    my $self = shift;
    return qw(volumeId size snapshotId availabilityZone status 
              createTime attachmentSet tagSet);
}

sub primary_id {shift->volumeId}

sub attachment {
    my $self = shift;
    my $attachments = $self->attachmentSet or return;
    my $id = $attachments->{item}[0]       or return;
    return VM::EC2::BlockDevice::Attachment->new($id,$self->aws)
}

sub attachments {
    my $self = shift;
    my $attachments = $self->attachmentSet         or return;
    my $items       = $self->attachmentSet->{item} or return;
    my @a = map {VM::EC2::BlockDevice::Attachment->new($_,$self->aws)} @$items;
    return @a;
}

sub from_snapshot {
    my $self = shift;
    my $sid  = $self->snapshotId or return;
    return $self->aws->describe_snapshots(-filter=>{'snapshot-id' => $sid});
}

sub to_snapshots {
    my $self = shift;
    return $self->aws->describe_snapshots(-filter=>{'volume-id' => $self->volumeId});
}

sub current_status {
    my $self = shift;
    $self->refresh;
    $self->status;
}

sub refresh {
    my $self = shift;
    my $v    = $self->aws->describe_volumes($self->volumeId);
    %$self   = %$v;
}

1;
