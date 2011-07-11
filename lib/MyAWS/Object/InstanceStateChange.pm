package MyAWS::Object::InstanceStateChange;

use strict;
use base 'MyAWS::Object::Base';
use Carp 'croak';
use MyAWS::Object::InstanceState;

use overload '""' => sub {shift()->instanceId},
    fallback      => 1;

sub valid_fields {
    my $self = shift;
    return qw(instanceId currentState previousState);
}
sub currentState {
    return MyAWS::Object::InstanceState->new(shift->SUPER::currentState);
}
sub previousState {
    return MyAWS::Object::InstanceState->new(shift->SUPER::previousState);
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
