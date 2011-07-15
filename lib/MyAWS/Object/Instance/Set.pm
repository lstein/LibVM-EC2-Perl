package MyAWS::Object::Instance::Set;

=head1 NAME

MyAWS::Object::Instance::Set - Object describing a set of instances

=head1 SYNOPSIS

  use MyAWS;

  $aws       = MyAWS->new(...);
  @instances = $aws->run_instances(-image_id=>'ami-12345');
  for my $i (@instances) {
     $res    = $i->reservationId;
     $req    = $i->requesterId;
     $owner  = $i->ownerId;
     @groups = $i->groups;
  }

=head1 DESCRIPTION

This object is used internally to manage the output of
MyAWS->run_instances(), which returns information about the
reservation and security groups as well as the list of launched
instances. Because reservations are infrequently used, this object is
not used directly; instead the reservation and requester IDs contained
within it are stored in the MyAWS::Object::Instance objects returned
by run_instances().

=head1 METHODS

One object method is supported:

=head2 @instances = $reservation_set->instances()

This will return the instances contained within the instance set.

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
use MyAWS::Object::Instance;
use MyAWS::Object::Group;

sub instances {
    my $self = shift;

    my $p = $self->payload;
    my $reservation_id = $p->{reservationId};
    my $owner_id       = $p->{ownerId};
    my $requester_id   = $p->{requesterId};
    my @groups         = map {MyAWS::Object::Group->new($_,$self->aws,
							$self->xmlns,$self->requestId)} @{$p->{groupSet}{item}};

    my $instances = $p->{instancesSet}{item};
    return map {MyAWS::Object::Instance->new(
		    -instance    => $_,
		    -aws         => $self->aws,
		    -xmlns       => $self->xmlns,
		    -requestId   => $self->requestId,
		    -reservation => $reservation_id,
		    -requester   => $requester_id,
		    -owner       => $owner_id,
		    -groups      => \@groups)
    } @$instances;
}


1;
