package MyAWS::Object::ConsoleOutput;

use strict;
use base 'MyAWS::Object::Base';
use MIME::Base64;

use overload '""' => sub {shift()->output},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return $self->SUPER::valid_fields,
           qw(requestId instanceId timestamp output);
}

sub output {
    my $self = shift;
    my $out  = $self->SUPER::output;
    return decode_base64($out);
}

1;

