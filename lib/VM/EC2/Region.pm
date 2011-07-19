package VM::EC2::Region;

=head1 NAME

VM::EC2::Region - Object describing an Amazon availability region

=head1 SYNOPSIS

  use VM::EC2;

  $ec2       = VM::EC2->new(...);
  @regions   = $ec2->describe_regions();

  $region  = $regions[0];
  $name    = $region->regionName;
  $url     = $region->regionEndpoint;

=head1 DESCRIPTION

This object represents an Amazon EC2 availability region, and is returned
by VM::EC2->describe_regions().

=head1 METHODS

These object methods are supported:

 regionName      -- Name of the region, e.g. "eu-west-1"
 regionEndpoint  -- URL endpoint for AWS API calls, e.g. 
                    "ec2.eu-west-1.amazonaws.com"

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
regionName.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

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
use base 'VM::EC2::Generic';

use overload 
    '""'     => sub {shift()->regionName},
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(regionName regionEndpoint);
}

1;
