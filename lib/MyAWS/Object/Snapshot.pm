package MyAWS::Object::Snapshot;

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

1;

