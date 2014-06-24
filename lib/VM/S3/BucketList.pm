package VM::S3::BucketList;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Bucket;
use VM::S3::Owner;

sub valid_fields {
    return qw(Owner Buckets);
}

sub short_name { shift->owner }

sub owner {
    my $self = shift;
    return VM::S3::Owner->new($self->Owner,$self->ec2);
}

sub buckets {
    my $self = shift;
    my $ec2  = $self->ec2;
    return map {VM::S3::Bucket->new($_,$ec2)} @{$self->SUPER::Buckets->{Bucket}};
}

1;

