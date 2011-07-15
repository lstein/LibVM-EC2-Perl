package MyAWS::Object::ReservationSet;

=head1 NAME

MyAWS::Object::Reservation - Object describing an instance reservation set

=head1 SYNOPSIS

  use MyAWS;

  $aws       = MyAWS->new(...);
  @instances = $aws->describe_instances();
  for my $i (@instances) {
     $res    = $i->reservationId;
     $req    = $i->requesterId;
     $owner  = $i->ownerId;
     @groups = $i->groups;
  }

=head1 DESCRIPTION

This object is used internally to manage the output of
MyAWS->describe_instances(). Because reservations are infrequently
used, this object is not used directly; instead the reservation and
requester IDs contained within it are stored in the
MyAWS::Object::Instance objects returned by describe_instances().

=head1 METHODS

One object method is supported:

=head2 @instances = $reservation_set->instances()

This will return the instances contained within the reservation set.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::Instance>

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
use MyAWS::Object::Instance::Set;
use MyAWS::Object::Group;

sub instances {
    my $self = shift;
    my $r = $self->payload->{reservationSet}{item} or return;
    return map {MyAWS::Object::Instance::Set->new($_,$self->aws,$self->xmlns,$self->requestId)->instances} @$r;
}

1;
