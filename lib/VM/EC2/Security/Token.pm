package VM::EC2::Security::Token;

=head1 NAME

VM::EC2::Security::Token - Temporary security token object

=head1 SYNOPSIS

  # on your side of the connection
 $ec2 = VM::EC2->new(...);  # as usual
 my $policy = VM::EC2::Security::Policy->new;
 $policy->allow('DescribeImages','RunInstances');
 my $token = $ec2->get_federation_token(-name     => 'TemporaryUser',
                                        -duration => 60*60*3, # 3 hrs, as seconds
                                        -policy   => $policy);
 print $token->session_token,"\n";
 print $token->access_key_id,"\n";
 print $token->secret_access_key,"\n";
 print $token->federated_user,"\n";

 my $new_ec2 = VM::EC2->new(-security_token => $token);
 print $ec2->describe_images(-owner=>'self');

=head1 DESCRIPTION

VM::EC2::Security::Token objects are returned by calls to
VM::EC2->get_federation_token() and get_session_token(). The token
object can then be passed to VM::EC2->new() to gain access to EC2
resources with temporary credentials, or interrogated to obtain the
various components of the temporary credentials.

=head1 METHODS

 credentials()     -- The VM::EC2::Security::Credentials object
                        that contains the session token, access key ID,
                        and secret key.

 federatedUser()  -- the VM::EC2::Security::FederatedUser object that
                        contains information about the temporary user
                        account.

 packedPolicySize() -- A percentage value indicating the size of the policy in
                         packed form relative to the maximum allowed size. 
                         Policies in excess of 100% will be rejected by the
                         service.

 secret_access_key()-- Convenience method that calls the credentials object's
                        secret_access_key() method.

 access_key_id() --    Convenience method that calls the credentials object's
                        access_key_id() method.

 session_token() --    Convenience method that calls the credentials object's
                        session_token() method.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate as the
session token, and can be used for the -security_token parameter in
VM::EC2->new().

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::Security::Credentials>
L<VM::EC2::Security::FederatedUser>

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
    return VM::EC2::Security::Credentials->new($self->SUPER::credentials,undef);
}

sub federated_user { 
    my $self = shift;
    my $user = $self->SUPER::federated_user or return;
    return VM::EC2::Security::FederatedUser->new($user,undef);
}

sub secret_access_key { shift->credentials->secret_access_key }
sub access_key_id     { shift->credentials->access_key_id     }
sub session_token     { shift->credentials->session_token     }

sub short_name { shift->session_token; }

1;
