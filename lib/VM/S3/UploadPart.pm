package VM::S3::UploadPart;
use strict;

use base 'VM::S3::Generic';

sub valid_fields {
    return qw(ETag UploadId PartNumber);
}

sub new {
    my $self = shift;
    my ($s3,$etag,$uploadId,$partNo) = @_;
    return bless {
	data=>{
	    UploadId   => $uploadId,
	    PartNumber => $partNo,
	    ETag       => $etag,
	},
	aws => $s3,
	xmlns => undef,
	requestId => undef} ref $self || $self;
}

sub short_name {
    my $self = shift;
    return $self->upload_id.' part='.$self->part_number;

1;
