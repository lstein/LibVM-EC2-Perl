package VM::EC2::Instance::StatusItem;

=head1 NAME

VM::EC2::Instance::StatusItem - Object describing a instance status event

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::State::Reason>
L<VM::EC2::State>
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
    return VM::EC2::Instance::Status::Event->new($e,$self->ec2);
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

