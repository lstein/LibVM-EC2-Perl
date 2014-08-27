package VM::S3::Owner;

use strict;
use base 'VM::S3::Generic';

sub primary_id { shift->ID }

sub short_name { shift->DisplayName}

sub valid_fields {
    return qw(DisplayName ID);
}

1;
