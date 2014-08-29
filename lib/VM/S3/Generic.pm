package VM::S3::Generic;

use strict;
use base 'VM::EC2::Generic';

sub s3 { shift->ec2 }
1;

