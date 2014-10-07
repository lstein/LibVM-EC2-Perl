package VM::S3::Lifecycle::NoncurrentVersionExpiration;

use strict;
use base 'VM::S3::Lifecycle::Transition';

sub valid_fields {
    qw(NoncurrentDays);
}

1;
