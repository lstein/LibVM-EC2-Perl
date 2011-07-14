package MyAWS::Object::BlockDevice::EBS;

use strict;
use base 'MyAWS::Object::Base';

sub valid_fields {
    my $self = shift;
    return qw(snapshotId volumeSize deleteOnTermination);
}

1;
