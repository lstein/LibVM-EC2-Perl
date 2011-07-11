package MyAWS::Object::BlockDeviceMapping;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::EBSInstance;

use overload '""' => sub {shift()->deviceName},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return qw(deviceName ebs);
}

sub ebs {
    my $self = shift;
    return $self->{ebs} ||= MyAWS::Object::EBSInstance->new($self->SUPER::ebs,$self->aws);
}

sub volumeId     { shift->ebs->volumeId }
sub status       { shift->ebs->status   }
sub attachTime   { shift->ebs->attachTime   }
sub deleteOnTermination   { shift->ebs->deleteOnTermination }
sub volume       { shift->ebs->volume }

1;

