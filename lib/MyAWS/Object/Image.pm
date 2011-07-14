package MyAWS::Object::Image;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::BlockDevice;
use MyAWS::Object::StateReason;

sub valid_fields {
    my $self = shift;
    return qw(imageId imageLocation imageState imageOwnerId isPublic
              productCodes architecture imageType kernelId ramdiskId
              platform stateReason imageOwnerAlias name description
              rootDeviceType rootDeviceName blockDeviceMapping
              virtualizationType tagSet hypervisor);
}

sub primary_id { shift->imageId }

sub stateReason {
    my $self  = shift;
    my $state = $self->SUPER::stateReason;
    return MyAWS::Object::stateReason->new($state);

}

sub productCodes {
    my $self = shift;
    my $codes = $self->SUPER::productCodes or return;
    return map {$_->{productCode}} @{$codes->{item}};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { MyAWS::Object::BlockDevice->new($_,$self->aws)} @{$mapping->{item}};
}


sub run_instances {
    my $self = shift;
    my %args = @_;
    $args{-image_id} = $self->imageId;
    $self->aws->run_instances(%args);
}

1;
