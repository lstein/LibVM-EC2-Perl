package MyAWS::Object::Volume;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::Attachment;

sub valid_fields {
    my $self = shift;
    return qw(volumeId size snapshotId availabilityZone status 
              createTime attachmentSet tagSet);
}

sub primary_id {shift->volumeId}

sub attachment {
    my $self = shift;
    my $attachments = $self->attachmentSet or return;
    return MyAWS::Object::Attachment->new($attachments->{item}[0],$self->aws)
}

1;
