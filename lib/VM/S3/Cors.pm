package VM::S3::Cors;

use strict;
use base 'VM::S3::Generic';

sub valid_fields {
    return qw(AllowedHeader AllowedMethod AllowedOrigin ExposeHeader ID MaxAgeSeconds);
}

sub short_name {$_[0]->ID||$_[0]}


1;
