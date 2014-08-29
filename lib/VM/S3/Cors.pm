package VM::S3::Cors;

use strict;
use base 'VM::S3::Generic';

sub valid_fields {
    return qw(AllowedHeader AllowedMethod AllowedOrigin ExposeHeader ID MaxAgeSeconds);
}

sub short_name {shift->as_xml}

sub as_xml {
    my $self = shift;
    my $parser = XML::Simple->new();
    return $parser->XMLout($self->{data},RootName=>'CORSRule',NoAttr=>1);
}

1;
