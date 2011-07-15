package MyAWS::Object::ElasticAddress;

=head1 NAME

MyAWS::Object::ElasticAddress - Object describing an Amazon EC2 Elastic Address

=head1 SYNOPSIS

  use MyAWS;

  $aws     = MyAWS->new(...);
  $addr    = $aws->allocate_address;

  $ip      = $addr->publicIp;
  $domain  = $addr->domain;
  $allId   = $addr->allocationId;

=head1 DESCRIPTION

This object represents an Amazon EC2 elastic address and is returned by
by MyAWS->allocate_address().

=head1 METHODS

These object methods are supported:

 publicIp      -- Public IP of the address
 domain        -- Type of address, either "standard" or "vpc"
 allocationId  -- For VPC addresses only, an allocation ID

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
publicIp.

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

sub primary_id {shift->publicIp}

sub valid_fields {
    my $self = shift;
    return qw(publicIp domain allocationId);
}

1;
