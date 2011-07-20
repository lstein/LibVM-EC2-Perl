package VM::EC2::Instance::State::Change;

use strict;
use base 'VM::EC2::Generic';
use Carp 'croak';
use VM::EC2::Instance::State;

use overload '""' => sub {shift()->currentState},
    fallback      => 1;

sub valid_fields {
    my $self = shift;
    return qw(instanceId currentState previousState);
}
sub currentState {
    return VM::EC2::Instance::State->new(shift->SUPER::currentState);
}
sub previousState {
    return VM::EC2::Instance::State->new(shift->SUPER::previousState);
}
sub current_status {
    my $self = shift;
    my $ec2  = $self->aws;
    my $id   = $self->instanceId;
    my ($instance) = $ec2->describe_instances(-instance_id=>$id);
    $instance or croak "invalid instance: $id";
    return $instance->instanceState;
}

1;
