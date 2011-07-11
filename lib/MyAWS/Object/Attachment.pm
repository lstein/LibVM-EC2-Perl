package MyAWS::Object::Attachment;

use strict;
use base 'MyAWS::Object::EBSInstance';

sub valid_fields {
    my $self = shift;
    return qw(volumeId instanceId device status attachTime deleteOnTermination);
}

sub instance {
    my $self = shift;
    return $self->{instance} if exists $self->{instance};
    my @i    = $self->aws->describe_instances(-instance_id => $self->instanceId);
    @i == 1 or die "describe_instances(-instance_id=>",$self->instanceId,") returned more than one volume";
    return $self->{instance} = $i[0];
}



1;
