package MyAWS::Object::Instance::State::Change;

use strict;
use base 'MyAWS::Object::Base';
use Carp 'croak';
use MyAWS::Object::Instance::State;

use overload '""' => sub {shift()->instanceId},
    fallback      => 1;

sub valid_fields {
    my $self = shift;
    return qw(instanceId currentState previousState);
}
sub currentState {
    return MyAWS::Object::Instance::State->new(shift->SUPER::currentState);
}
sub previousState {
    return MyAWS::Object::Instance::State->new(shift->SUPER::previousState);
}
sub status {
    my $self = shift;
    my $aws  = $self->aws;
    my $id   = $self->instanceId;
    my ($instance) = $aws->describe_instances(-instance_id=>$id);
    $instance or croak "invalid instance: $id";
    return $instance->instanceState;
}

1;
