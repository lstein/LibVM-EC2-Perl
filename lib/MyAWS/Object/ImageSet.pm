package MyAWS::Object::ImageSet;

use strict;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Image;

sub images {
    my $self = shift;
    my $i    = $self->payload->{imagesSet}{item} or return;
    return map {MyAWS::Object::Image->new($_,$self->aws)} @$i;
}

1;

