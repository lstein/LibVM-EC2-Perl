package VM::EC2::Security::Credentials;

=head1 NAME

VM::EC2::Security::Credentials -- ??

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
use Storable 'nfreeze','thaw';
use MIME::Base64 'encode_base64','decode_base64';

sub valid_fields {
    my $self = shift;
    return qw(AccessKeyId Expiration SecretAccessKey SessionToken);
}

# serialize the credentials in a packed form
sub serialize {
    my $self = shift;
    my $data = nfreeze($self);
    return encode_base64($data);
}

sub new_from_serialized {
    my $class = shift;
    my $data  = shift;
    my $obj   = thaw(decode_base64($data));
    return bless $obj,ref $class || $class;
}

sub short_name {shift->access_key_id}

1;
