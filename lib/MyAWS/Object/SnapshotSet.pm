package MyAWS::Object::SnapshotSet;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Snapshot;

sub snapshots {
    my $self = shift;
    return map {MyAWS::Object::Snapshot->new($_,$self->aws)} @{$self->payload->{snapshotSet}{item}};
}


1;

