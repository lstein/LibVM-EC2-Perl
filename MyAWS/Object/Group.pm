package MyAWS::Object::Group;

use strict;
use base 'MyAWS::Object::Base';

use overload '""' => sub {shift()->groupName},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return $self->SUPER::valid_fields,
           qw(groupId groupName);
}

1;

