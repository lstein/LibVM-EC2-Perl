package VM::S3::MultipartUploadResult;

# object that holds the uploadId for a multipart upload result

use strict;
use base 'VM::S3::Generic';

sub valid_fields {
    return qw(Location Bucket Key ETag);
}

sub short_name {shift->location}

1;
