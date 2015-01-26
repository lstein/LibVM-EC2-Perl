package VM::S3::MultipartUpload;

# object that holds the uploadId for a multipart upload

use strict;
use base 'VM::S3::Generic';

sub valid_fields {
    return qw(Bucket Key UploadId);
}

sub short_name {shift->upload_id}

1;
