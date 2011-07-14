package MyAWS::Object::BlockDevice;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::BlockDevice::EBS;

use overload '""' => sub {shift()->as_string},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return qw(deviceName virtualName ebs);
}

sub noDevice {
    my $self = shift;
    return exists $self->payload->{noDevice};
}

sub ebs {
    my $self = shift;
    return $self->{ebs} = MyAWS::Object::BlockDevice::EBS->new($self->SUPER::ebs,$self->aws);
}

sub snapshotId { shift->ebs->snapshotId }
sub volumeSize { shift->ebs->volumeSize }
sub deleteOnTermination { shift->ebs->deleteOnTermination }

sub as_string {
    my $self = shift;
    return $self->deviceName.'='.
	join ':',$self->snapshotId,$self->volumeSize,$self->deleteOnTermination;
}

1;

