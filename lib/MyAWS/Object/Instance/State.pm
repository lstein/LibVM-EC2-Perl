package MyAWS::Object::Instance::State;

use strict;
use overload '""'     => 'name',
             fallback => 1;

sub new {
    my $self  = shift;
    my $state = shift;
    return bless \$state,ref $self || $self;
}

sub code { ${shift()}->{code} }
sub name { ${shift()}->{name} }

1;
