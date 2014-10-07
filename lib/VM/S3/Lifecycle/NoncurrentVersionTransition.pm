package VM::S3::Lifecycle::NoncurrentVersionTransition;

use strict;
use base 'VM::S3::Lifecycle::Transition';

sub valid_fields {
    qw(NoncurrentDays StorageClass);
}

1;
