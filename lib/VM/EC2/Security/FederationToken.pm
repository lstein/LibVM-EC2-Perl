package VM::EC2::Security::FederationToken;

=head1 NAME

VM::EC2::Security::FederationToken - FederationToken object

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

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
use VM::EC2::Security::FederatedUser;
use VM::EC2::Security::Credentials;

sub valid_fields {
    my $self = shift;
    return qw(Credentials FederatedUser PackedPolicySize);
}

sub credentials { 
    my $self = shift;
    return VM::EC2::Security::Credentials->new($self->{data}{Credentials},$self->ec2);
}
sub federated_user {
    my $self = shift;
    return VM::EC2::Security::FederatedUser->new($self->{data}{FederatedUser},$self->ec2);
}

sub short_name {
    shift->credentials;
}

1;
