package MyAWS::Object::BlockDevice;

=head1 NAME

MyAWS::Object::BlockDevice - Object describing an EC2 block device

=head1 SYNOPSIS

  use MyAWS;

  $image = MyAWS->describe_images(-image_id=>'ami-123456');
  my @devices = $image->blockDeviceMapping;
  for my $d (@devices) {
    my $virtual_device = $d->deviceName;
    my $snapshot_id    = $d->snapshotId;
    my $delete         = $d->deleteOnTermination;
  }

=cut


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

