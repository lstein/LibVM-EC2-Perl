package VM::EC2::NetworkInterface::Attachment;

=head1 NAME

VM::EC2::NetworkInterface::Attachment

=head1 SYNOPSIS

  use VM::EC2;
 ...

=head1 DESCRIPTION

Please see L<VM::EC2::Generic> for methods shared by all VM::EC2
objects.

=head1 METHODS

These object methods are supported:

 attachmentId
 instanceId
 instanceOwnerId
 deviceIndex
 status
 attachmentTime
 deleteOnTermination

In addition, this object supports the following convenience methods:

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as the
VPC ID.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

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

sub valid_fields { return qw(attachmentId instanceId instanceOwnerId deviceIndex status
                             attachTime deleteOnTermination) }

sub short_name { shift->attachmentId }

sub device { my $index = shift->deviceIndex; return "eth${index}"}

sub instance {
    my $self = shift;
    my $id   = $self->instanceId;
    return $self->aws->describe_instances($id);
}

sub deleteOnTermination {
    return shift->SUPER::deleteOnTermination =~ /true/i;
}


1;
