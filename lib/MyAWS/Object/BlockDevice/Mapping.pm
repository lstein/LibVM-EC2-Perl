package MyAWS::Object::BlockDevice::Mapping;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::BlockDevice::Mapping::EBS;

use overload '""' => sub {shift()->deviceName},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return qw(deviceName ebs);
}

sub ebs {
    my $self = shift;
    return $self->{ebs} ||= MyAWS::Object::BlockDevice::Mapping::EBS->new($self->SUPER::ebs,$self->aws);
}

sub volumeId     { shift->ebs->volumeId }
sub status       { shift->ebs->status   }
sub attachTime   { shift->ebs->attachTime   }
sub deleteOnTermination   { shift->ebs->deleteOnTermination }
sub volume       { shift->ebs->volume }

1;

