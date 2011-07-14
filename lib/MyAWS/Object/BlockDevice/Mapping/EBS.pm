package MyAWS::Object::BlockDevice::Mapping::EBS;

use strict;
use base 'MyAWS::Object::Base';

sub valid_fields {
    my $self = shift;
    return qw(volumeId status attachTime deleteOnTermination);
}

sub volume {
    my $self = shift;
    return $self->{volume} if exists $self->{volume};
    my @vols = $self->aws->describe_volumes(-volume_id=>$self->volumeId) or return;
    @vols == 1 or die "describe_volumes(-volume_id=>",$self->volumeId,") returned more than one volume";
    return $self->{volume} = $vols[0];
}

1;
