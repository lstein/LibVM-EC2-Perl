package MyAWS::Object::BlockDevice::Attachment;

use strict;
use base 'MyAWS::Object::Base';

sub valid_fields {
    my $self = shift;
    return qw(volumeId instanceId device status attachTime deleteOnTermination);
}

sub primary_id {
    my $self = shift;
    return join ('=>',$self->volumeId,$self->instanceId);
}

sub instance {
    my $self = shift;
    return $self->{instance} if exists $self->{instance};
    my @i    = $self->aws->describe_instances(-instance_id => $self->instanceId);
    @i == 1 or die "describe_instances(-instance_id=>",$self->instanceId,") returned more than one volume";
    return $self->{instance} = $i[0];
}

sub volume {
    my $self = shift;
    return $self->{volume} if exists $self->{volume};
    my @i    = $self->aws->describe_volumes(-volume_id => $self->volumeId);
    @i == 1 or die "describe_volumes(-volume_id=>",$self->volumeId,") returned more than one volume";
    return $self->{volume} = $i[0];
}



1;
