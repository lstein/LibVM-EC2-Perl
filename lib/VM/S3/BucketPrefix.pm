package VM::S3::BucketPrefix;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Owner;

sub valid_fields {
    return qw(Key);
}

sub short_name { shift->Key }

sub owner {
    my $self = shift;
    return VM::S3::Owner->new($self->Owner,$self->ec2);
}

1;

