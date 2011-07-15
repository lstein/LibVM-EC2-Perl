package MyAWS::Object::Snapshot;

=head1 NAME

MyAWS::Object::Snapshot - Object describing an Amazon EBS snapshot

=head1 SYNOPSIS

  use MyAWS;

  $aws       = MyAWS->new(...);
  @snap = $aws->describe_snapshots;
  for my $snap (@snapshots) {
      $id    = $snap->snapshotId;
      $vol   = $snap->volumeId;
      $state = $snap->status;
      $time  = $snap->startTime;
      $progress = $snap->progress;
      $size  = $snap->size;
      $description = $snap->description;
      $tags  = $snap->tags;
  }

=head1 DESCRIPTION

This object is used to describe an Amazon EBS snapshot.

=head1 METHODS

The following object methods are supported:
 
 snapshotId       -- ID of this snapshot
 ownerId          -- Owner of this snapshot
 volumeId         -- ID of the volume snapshot was taken from
 status           -- Snapshot state, one of "pending", "completed" or "error"
 startTime        -- Timestamp for when snapshot was begun.
 progress         -- The progress of the snapshot, in percent.
 volumeSize       -- Size of the volume, in gigabytes.
 description      -- Description of the snapshot
 ownerAlias       -- AWS account alias, such as "self".
 tags             -- Hashref containing tags associated with this group.
                     See L<MyAWS::Object::Base>.

In addition, this class provides two convenience functions:

=head2 $vol = $snap->from_volume

Returns the MyAWS::Object::Volume object that this snapshot was
originally derived from. If the original volume no longer exists,
returns undef.

=head2 @vol = $snap->to_volumes

Returns all MyAWS::Object::Volume objects that were derived from this
snapshot. If no volumes currently exist that satisfy this criteria,
returns an empty list.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
snapshotId.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::Instance>
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

sub valid_fields {
    my $self  = shift;
    return $self->SUPER::valid_fields,
           qw(snapshotId
              volumeId
              status
              startTime
              progress
              ownerId
              volumeSize
              description
              ownerAlias);
}

sub primary_id { shift->snapshotId }

sub from_volume {
    my $self = shift;
    my $vid = $self->volumeId or return;
    return $self->aws->describe_volumes(-volume_id=>$vid);
}

sub to_volumes {
    my $self = shift;
    return $self->aws->describe_volumes(-filter=>{'snapshot-id'=>$self->snapshotId});
}

1;
