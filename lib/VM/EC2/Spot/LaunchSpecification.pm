package VM::EC2::Spot::LaunchSpecification;
use strict;
use VM::EC2::Group;
use base 'VM::EC2::Generic';

sub valid_fields {
    return qw(imageId keyName groupSet addressingType instanceType
              placement kernelId ramdiskId blockDeviceMapping monitoring
              subnetId);
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    my @mapping = map { VM::EC2::BlockDevice::Mapping->new($_,$self->ec2)} @{$mapping->{item}};
    foreach (@mapping) { $_->instance($self) }
    return @mapping;
}

sub monitoring {
    my $self = shift;
    my $monitoring = $self->SUPER::monitoring or return;
    return $monitoring->{enabled} eq 'true';
}

sub groupSet {
    my $self = shift;
    my $groupSet = $self->SUPER::groupSet;
    return map {VM::EC2::Group->new($_,$self->aws,$self->xmlns,$self->requestId)}
        @{$groupSet->{item}};
}

1;
