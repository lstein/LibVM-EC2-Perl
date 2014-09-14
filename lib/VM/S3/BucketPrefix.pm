package VM::S3::BucketPrefix;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Owner;

sub valid_fields {
    return qw(Key);
}

sub short_name { shift->Key }

sub bucket {
    my $self = shift;
    my $d    = $self->{bucket};
    $self->{bucket} = shift if @_;
    $d;
}

sub is_directory { 1; }

1;

