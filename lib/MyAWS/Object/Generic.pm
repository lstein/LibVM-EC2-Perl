package MyAWS::Object::Generic;

use strict;
use base 'MyAWS::Object::Base';

=head1 NAME

MyAWS::Object::Generic - Fallback object for unsupported Amazon resources

=head1 SYNOPSIS

  use MyAWS;

  $aws      = MyAWS->new(...);
  $object = $aws->some_incomplete_method;
  print $object->as_xml;

=head1 DESCRIPTION

This is a fallback object that is omitted when the appropriate Perl
wrapper class for an Amazon resource has not yet been implemented. You
should never see this.

=head1 METHODS

These object methods are supported:

 as_xml  -- represent the XML of the response

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object>
L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::BlockDevice::Attachment>
L<MyAWS::Object::BlockDevice::EBS>
L<MyAWS::Object::BlockDevice::Mapping>
L<MyAWS::Object::BlockDevice::Mapping::EBS>
L<MyAWS::Object::ConsoleOutput> 
L<MyAWS::Object::Error>
L<MyAWS::Object::Generic> 
L<MyAWS::Object::Group>
L<MyAWS::Object::Image>
L<MyAWS::Object::Instance>
L<MyAWS::Object::Instance::Set>
L<MyAWS::Object::Instance::State>
L<MyAWS::Object::Instance::State::Change>
L<MyAWS::Object::Instance::State::Reason>
L<MyAWS::Object::Region>
L<MyAWS::Object::ReservationSet>
L<MyAWS::Object::SecurityGroup>
L<MyAWS::Object::Snapshot>
L<MyAWS::Object::Tag>
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

sub as_xml {
    my $self = shift;
    XML::Simple->new->XMLout($self->payload,
			     NoAttr    => 1,
			     KeyAttr   => ['key'],
			     RootName  => 'xml',
	);
}

sub attribute {
    my $self = shift;
    my $attr = shift;
    my $payload = $self->payload   or return;
    my $hr      = $payload->{$attr} or return;
    return $hr->{value}   if $hr->{value};
    return @{$hr->{item}} if $hr->{item};
    return $hr;
}

1;
