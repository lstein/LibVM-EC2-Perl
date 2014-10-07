package VM::S3::Lifecycle::Expiration;

use strict;
use base 'VM::S3::Lifecycle::Transition';

sub valid_fields { qw(Date Days) }

1;
