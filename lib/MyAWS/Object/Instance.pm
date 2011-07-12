package MyAWS::Object::Instance;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::InstanceState;
use MyAWS::Object::BlockDeviceMapping;
use Carp 'croak';
use overload '""' => sub {shift()->instanceId},
    fallback      => 1;

sub new {
    my $self = shift;
    my %args = @_;
    return bless {
	data        => $args{-instance},
	reservation => $args{-reservation},
	owner       => $args{-owner},
	groups      => $args{-groups},
	aws         => $args{-aws},
    },ref $self || $self;
}

sub reservationId {shift->{reservation} }
sub ownerId       {shift->{owner}       }
sub groups        {@{shift->{groups}}   }
sub group         {shift()->{groups}[0] }

sub valid_fields {
    my $self  = shift;
    return qw(instanceId
              imageId
              instanceState
              privateDnsName
              dnsName
              reason
              keyName
              amiLaunchIndex
              productCodes
              instanceType
              launchTime
              placement
              kernelId
              ramdiskId
              monitoring
              privateIpAddress
              ipAddress
              sourceDestCheck
              architecture
              rootDeviceType
              rootDeviceName
              blockDeviceMapping
              instanceLifecycle
              spotInstanceRequestId
              virtualizationType
              clientToken
              hypervisor
              tagSet
             );
}

sub instanceState {
    my $self = shift;
    my $state = $self->SUPER::instanceState;
    return MyAWS::Object::InstanceState->new($state);
}

sub placement {
    return shift->placement->{availabilityZone};
}

sub monitoring {
    return shift->monitoring->{state};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { MyAWS::Object::BlockDeviceMapping->new($_,$self->aws)} @{$mapping->{item}};
}

sub status {
    my $self = shift;
    my ($i)  = $self->aws->describe_instances(-instance_id=>$self->instanceId);
    $i or croak "invalid instance: ",$self->instanceId;
    $self->refresh($i);
    return $i->instanceState;
}

sub start {
    my $self = shift;
    my $nowait = shift;

    my $s    = $self->status;
    croak "Can't start $self: run state=$s" unless $s eq 'stopped';
    my ($i) = $self->aws->start_instances($self) or return;
    unless ($nowait) {
	while ($i->status eq 'pending') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub stop {
    my $self = shift;
    my $nowait = shift;

    my $s    = $self->status;
    croak "Can't stop $self: run state=$s" unless $s eq 'running';

    my ($i) = $self->aws->stop_instances($self);
    unless ($nowait) {
	while ($i->status ne 'stopped') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_instances(-instance_id=>$self->instanceId) unless $i;
    %$self  = %$i;
}

sub console_output {
    my $self = shift;
    my $output = $self->aws->get_console_output(-instance_id=>$self->instanceId);
    return $output->output;
}

1;

