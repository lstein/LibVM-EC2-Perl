package VM::EC2::Instance::Status::Details;

=head1 NAME

VM::EC2::Instance::Status::Details - Object describing the details of an instance status check

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

use strict;

sub valid_fields {
    my $self = shift;
    return qw(name status impairedSince);
}

sub short_name {
    my $self = shift;
    my $status = $self->status;
    my $name   = $self->name;
    my $since  = $self->impairedSince;
    if ($since) {
	return "$name $status since $since";
    } else {
	return "$name $status";
    }
}

1;

