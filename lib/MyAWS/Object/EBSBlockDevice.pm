package MyAWS::Object::EBSBlockDevice;

use strict;
use base 'MyAWS::Object::Base';

sub valid_fields {
    my $self = shift;
    return qw(snapshotId volumeSize deleteOnTermination);
}

1;
