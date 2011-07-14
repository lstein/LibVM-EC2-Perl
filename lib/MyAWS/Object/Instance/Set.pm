package MyAWS::Object::Instance::Set;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Instance;
use MyAWS::Object::Group;

sub instances {
    my $self = shift;

    my $p = $self->payload;
    my $reservation_id = $p->{reservationId};
    my $owner_id       = $p->{ownerId};
    my $requester_id   = $p->{requesterId};
    my @groups         = map {MyAWS::Object::Group->new($_,$self->aws)} @{$p->{groupSet}{item}};

    my $instances = $p->{instancesSet}{item};
    return map {MyAWS::Object::Instance->new(
		    -instance    => $_,
		    -aws         => $self->aws,
		    -reservation => $reservation_id,
		    -requester   => $requester_id,
		    -owner       => $owner_id,
		    -groups      => \@groups)
    } @$instances;
}


1;
