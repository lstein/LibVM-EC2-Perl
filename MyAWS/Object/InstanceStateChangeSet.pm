package MyAWS::Object::InstanceStateChangeSet;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::InstanceStateChange;

sub instances {
    my $self = shift;
    my $isc  = $self->payload->{instancesSet}{item} or return;
    return map {
	MyAWS::Object::InstanceStateChange->new($_,$self->aws)
    } @$isc;
}


1;

