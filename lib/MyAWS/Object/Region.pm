package MyAWS::Object::Region;

use strict;
use base 'MyAWS::Object::Base';

use overload 
    '""'     => sub {shift()->regionName},
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(regionName regionEndpoint);
}

1;
