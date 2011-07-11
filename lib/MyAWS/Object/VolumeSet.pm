package MyAWS::Object::VolumeSet;

use strict;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Volume;

sub volumes {
    my $self = shift;
    return map {MyAWS::Object::Volume->new($_,$self->aws)} @{$self->payload->{volumeSet}{item}};

}

1;

