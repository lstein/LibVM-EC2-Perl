package MyAWS::Object::State::Reason;

use strict;
use overload '""' => 'message',
    fallback      => 1;

sub new {
    my $self  = shift;
    my $state = shift;
    return bless \$state,ref $self || $self;
}

sub code    { ${shift()}->{code} }
sub message { ${shift()}->{message} }

1;
