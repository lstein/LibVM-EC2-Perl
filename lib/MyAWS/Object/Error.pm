package MyAWS::Object::Error;

use strict;
use base 'MyAWS::Object::Base';

use overload 
    '""'     => sub {
	my $self = shift;
	return $self->Message. ' [' .$self->Code.']'},
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(Code Message);
}

sub code    {shift->Code}
sub message {shift->message}

1;
