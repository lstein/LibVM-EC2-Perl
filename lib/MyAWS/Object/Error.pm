package MyAWS::Object::Error;

=head1 NAME

MyAWS::Object::Error - Object describing an error emitted by the Amazon API

=head1 SYNOPSIS

  use MyAWS;

  $aws      = MyAWS->new(...);
  $instance = $aws->describe_instance(-instance_id=>'invalid-name');
  die $aws->error if $aws->is_error;

=head1 DESCRIPTION

This object represents an error emitted by the Amazon API. MyAWS
method calls may return undef under either of two conditions: the
request may simply have no results that satisfy it (for example,
asking to describe an instance whose ID does not exist), or an error
occurred due to invalid parameters or communication problems.

As described in L<MyAWS>, the MyAWS->is_error method returns true if
the last method call resulted in an error, and MyAWS->error returns
the content of the error message.

=head1 METHODS

These object methods are supported:

 message -- the error message
 code    -- the error code

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the code
and message into a single string in the format "Message [Code]".

=head1 SEE ALSO

L<MyAWS> L<MyAWS::Object> L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::BlockDevice::Attachment>
L<MyAWS::Object::BlockDevice::EBS>
L<MyAWS::Object::BlockDevice::Mapping>
L<MyAWS::Object::BlockDevice::Mapping::EBS>
L<MyAWS::Object::ConsoleOutput> L<MyAWS::Object::Error>
L<MyAWS::Object::Generic> L<MyAWS::Object::Group>
L<MyAWS::Object::Image> L<MyAWS::Object::Instance>
L<MyAWS::Object::Instance::Set> L<MyAWS::Object::Instance::State>
L<MyAWS::Object::Instance::State::Change>
L<MyAWS::Object::Instance::State::Reason> L<MyAWS::Object::Region>
L<MyAWS::Object::ReservationSet> L<MyAWS::Object::SecurityGroup>
L<MyAWS::Object::Snapshot> L<MyAWS::Object::Tag>
L<MyAWS::Object::Volume>

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

use overload 
    '""'     => sub {
	my $self = shift;
	return $self->Message. ' [' .$self->Code.']'},
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(Code Message);
}

sub code    {shift->Code}
sub message {shift->message}

1;
