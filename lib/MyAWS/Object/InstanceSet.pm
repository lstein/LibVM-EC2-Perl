package MyAWS::Object::InstanceSet;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Instance;
use MyAWS::Object::Group;

sub instances {
    my $self = shift;
    my @instances;

    my $reservations = $self->payload->{reservationSet}{item} or return;
    for my $r (@$reservations) {
	my $instances      = $r->{instancesSet}{item};
	my $reservation_id = $r->{reservationId};
	my $owner_id       = $r->{ownerId};
	my @groups         = map {MyAWS::Object::Group->new($_,$self->aws)} @{$r->{groupSet}{item}};
	push @instances,map {MyAWS::Object::Instance->new(
				 -instance    => $_,
				 -aws         => $self->aws,
				 -reservation => $reservation_id,
				 -owner       => $owner_id,
				 -groups      => \@groups)
	} @$instances;
    }
    return @instances;
}


1;

