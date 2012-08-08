package VM::EC2::VPC::DhcpOptions;

=head1 NAME

VM::EC2::VPC::DhcpOptions -- DHCP options set for an AWS Virtual Private Cloud

=head1 SYNOPSIS

  use VM::EC2;
 ...

=head1 DESCRIPTION

Please see L<VM::EC2::Generic> for methods shared by all VM::EC2
objects.

=head1 METHODS

These object methods are supported:

 dhcpOptionsId         -- ID of the dhcp options
 dhcpConfigurationSet  -- Hash of options

In addition, this object supports the following convenience methods:

 options()                -- return list of DHCP options contained in this set
 option('option-name')    -- return list of values for the named option. Note
                               that all options correspond to a list; calling in
                               a scalar context will return size of the list
 as_string()              -- returns a string concatenation of all options

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as the
dhcp ID.

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

sub valid_fields {
    my $self  = shift;
    return qw(dhcpOptionsId dhcpConfigurationSet);
}

sub primary_id { shift->dhcpOptionsId }

sub option {
    my $self = shift;
    my $key  = shift;
    my $hash  = $self->dhcpConfigurationSet or return;
    my @items = @{$hash->{item}}            or return;
    my @result;
    foreach (@items) {
	next unless $_->{key} eq $key;
	push @result,map {$_->{value}} @{$_->{valueSet}{item}}
    }
    return @result;
}

sub options {
    my $self = shift;
    my $hash  = $self->dhcpConfigurationSet or return;
    my @items = @{$hash->{item}}            or return;
    return map {$_->{key}} @items;
}

sub as_string {
    my $self = shift;
    my @options = $self->options;
    my @results = map {"$_ = ".join(',',$self->option($_))} @options;
    return join '; ',@results;
}

1;

