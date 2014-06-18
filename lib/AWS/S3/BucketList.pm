package AWS::S3::BucketList;

use strict;
use base 'VM::EC2::Generic';

sub valid_fields {
    return qw(Owner Buckets);
}

sub as_string { shift->Owner }

sub Buckets {
    my $self = shift;
    return map {$_->{Name}} @{$self->SUPER::Buckets->{Bucket}};
}

1;

