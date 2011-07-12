package MyAWS::Object::Tag;

use strict;
use base 'MyAWS::Object::Base';

use overload 
    '""'     => sub {
	my $self = shift;
	return $self->resourceId},
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(resourceId resourceType key value);
}

1;
