package VM::EC2::Snapshot;

=head1 NAME

VM::EC2::Snapshot - Object describing an Amazon EBS snapshot

=head1 SYNOPSIS

  use VM::EC2;

  $ec2       = VM::EC2->new(...);
  @snap = $ec2->describe_snapshots;
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
                     See L<VM::EC2::Generic>.

In addition, this class provides several convenience functions:

=head2 $vol = $snap->from_volume

Returns the VM::EC2::Volume object that this snapshot was originally
derived from. If the original volume no longer exists because it has
been deleted, this will return undef; if -raise_error was passed to
the VM::EC2 object, this will raise an exception.

=head2 @vol = $snap->to_volumes

Returns all VM::EC2::Volume objects that were derived from this
snapshot. If no volumes currently exist that satisfy this criteria,
returns an empty list, but will not raise an error.

=head2 $status = $snap->current_status

Refreshes the snapshot and returns its current status.

=head2 $snap->refresh

Refreshes the snapshot from information provided by AWS. Use before
checking progress or other changeable elements.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
snapshotId.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::Instance>
L<VM::EC2::Volume>

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
    # may throw an error if volume no longer exists
    return $self->aws->describe_volumes(-volume_id=>$vid);
}

sub to_volumes {
    my $self = shift;
    return $self->aws->describe_volumes(-filter=>{'snapshot-id'=>$self->snapshotId});
}

sub refresh {
    my $self = shift;
    my $s = $self->aws->describe_snapshots($self);
    %$self  = %$s;
}

sub current_status {
    my $self = shift;
    $self->refresh;
    return $self->status;
}
1;
