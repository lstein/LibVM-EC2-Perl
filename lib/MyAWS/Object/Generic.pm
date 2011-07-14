package MyAWS::Object::Generic;

use strict;
use base 'MyAWS::Object::Base';

sub as_xml {
    my $self = shift;
    XML::Simple->new->XMLout($self->payload,
			     NoAttr    => 1,
			     KeyAttr   => ['key'],
			     RootName  => 'xml',
	);
}

1;
