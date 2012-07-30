package VM::EC2::Instance::StatusItem;

=head1 NAME

VM::EC2::Instance::StatusItem - Object describing a instance status event

=head1 SYNOPSIS

 @status_items = $ec2->describe_instance_status();
 for my $i (@status_items) {
    print $i->instance_id,
           ': instance check=',$i->instance_status,
           ', system check=',$i->system_status,"\n";
    if (my $e = $i->events) {
       print $i->instance_id,' event = ',$e;
    }
 }

=head1 DESCRIPTION

This object represents an instance status returned by
$ec2->describe_instance_status().

=head1 METHODS

These object methods are supported:

 instance_id()          -- The ID of the affected instance.
 availability_zone      -- The availability zone of this instance.
 events                 -- A list of VM::EC2::Instance::Status::Event objects
                           representing a scheduled maintenance events on this
                           instance (see note).
 instance_state         -- The state of this instance (e.g. "running")
 system_status          -- A VM::EC2::Instance::Status object indicating the
                            status of the system check.
 instance_status        -- A VM::EC2::Instance::Status object indicating the
                            status of the instance availability check.

NOTE: There is an inconsistency in the AWS documentation for this data
type. The events field is documented as being a list, but the examples
shown show a single object. At release time, I was unable to verify
which is correct and have written the code such that it will return a
list, depending on what is detected in the response object.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::Instance>
L<VM::EC2::Tag>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use VM::EC2::Instance::State;
use VM::EC2::Instance::Status;
use VM::EC2::Instance::Status::Event;

sub valid_fields {
    my $self = shift;
    return qw(instanceId availabilityZone eventsSet instanceState systemStatus instanceStatus);
}

sub events {
    my $self = shift;
    my $e    = $self->eventsSet or return;
    if (ref $e && $e->{items}) {
	return map {VM::EC2::Instance::Status::Event->new($_,$self->ec2)} @{$e->{items}};
    }  else {
	return VM::EC2::Instance::Status::Event->new($e,$self->ec2);
    }
}

sub instanceState {
    my $self = shift;
    my $s    = $self->SUPER::instanceState or return;
    return VM::EC2::Instance::State->new($s,$self->ec2);
}

sub systemStatus {
    my $self = shift;
    my $s    = $self->SUPER::systemStatus or return;
    return VM::EC2::Instance::Status->new($s,$self->ec2);
}

sub instanceStatus {
    my $self = shift;
    my $s    = $self->SUPER::systemStatus or return;
    return VM::EC2::Instance::Status->new($s,$self->ec2);
}


1;

