package MyAWS::Object::ConsoleOutput;

=head1 NAME

MyAWS::Object::ConsoleOutput - Object describing console output from
an Amazon EC2 instance

=head1 SYNOPSIS

  use MyAWS;

  $aws      = MyAWS->new(...);
  $instance = $aws->describe_instance(-instance_id=>'i-123456'); 

  my $out = $instance->console_output; 

  print $out,"\n"; 
  my $ts       = $out->timestamp; 
  my $instance = $out->instanceId;

=head1 DESCRIPTION

This object represents the output from the console of a Amazon EC2
instance. The instance may be running, pending or stopped. It is
returned by MyAWS->get_console_output(), as well as
MyAWS::Object::Instance->console_output.

Please see L<MyAWS::Object::Base> for methods shared by all MyAWS
objects.

=head1 METHODS

These object methods are supported:

 requestId  -- ID of the request that generated this object
 instanceId -- ID of the instance that generated this output 
 timestamp -- Time that this output was generated 
 output    -- Text of the console output

=head1 STRING OVERLOADING

When used in a string context, this object will act as if its output()
method was called, allowing it to be printed or searched directly.

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
use MIME::Base64;

use overload '""' => sub {shift()->output},
    fallback      => 1;

sub valid_fields {
    my $self  = shift;
    return $self->SUPER::valid_fields,
           qw(requestId instanceId timestamp output);
}

sub output {
    my $self = shift;
    my $out  = $self->SUPER::output;
    return decode_base64($out);
}

1;

