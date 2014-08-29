package VM::S3::Owner;

use strict;
use base 'VM::S3::Generic';

sub primary_id { shift->ID }

sub short_name { $_[0]->DisplayName || $_[0]->URI}

sub valid_fields {
    return qw(DisplayName ID URI);
}

1;
