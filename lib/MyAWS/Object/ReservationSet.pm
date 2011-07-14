package MyAWS::Object::ReservationSet;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Instance::Set;
use MyAWS::Object::Group;

sub instances {
    my $self = shift;
    my $r = $self->payload->{reservationSet}{item} or return;
    return map {MyAWS::Object::Instance::Set->new($_,$self->aws)->instances} @$r;
}

1;
