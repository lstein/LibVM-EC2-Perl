package MyAWS::Object::Instance::MonitoringState;

=head1 NAME

MyAWS::Object::MonitoringState - Object describing the monitoring state of an EC2 instance

=head1 SYNOPSIS

  use MyAWS;

  $aws        = MyAWS->new(...);
  $monitor    = $aws->monitor_instances('i-12345');
  $instance   = $monitor->instanceId;
  $monitoring = $monitor->monitoring;

  $monitor->enable;
  $monitor->disable;

=head1 DESCRIPTION

This object represents the monitoring state of an Amazon EC2 instance.

=head1 METHODS

These object methods are supported:
 
 instanceId       -- The instance that is being reported
 monitoring       -- The monitoring state: one of "disabled", "enabled", "pending"

To turn monitoring of an instance on, call:

 $monitor->enable();

to unmonitor an instance, call:

 $monitor>disable();

It is probably easier to control this using the Instance object's monitoring() method.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
string "$instanceId monitoring is $monitoring".

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::Instance>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'MyAWS::Object::Base';
use overload '""'     => sub { 
    my $self      = shift;
    my $instance   = $self->instanceId;
    my $monitoring = $self->monitoring;
    return "$instance monitoring is $monitoring";
    },
    fallback => 1;

sub valid_fields {
    return qw(instanceId monitoring);
}

sub monitoring {
    my $self = shift;
    my $m    = $self->SUPER::monitoring;
    return $m->{state};
}

sub enable {
    my $self = shift;
    return $self->aws->monitor_instances($self->instanceId);
}

sub disable {
    my $self = shift;
    return $self->aws->unmonitor_instances($self->instanceId);
}

1;
