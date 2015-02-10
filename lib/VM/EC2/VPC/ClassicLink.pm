package VM::EC2::VPC::ClassicLink;

=head1 NAME

VM::EC2::VPC::ClassicLink - Virtual Private Cloud Classic Link

=head1 SYNOPSIS

 use VM::EC2;

 my $ec2       = VM::EC2->new(...);
 my @cl        = $ec2->describe_vpc_classic_link();
 print $_->vpcId,"\n" foreach grep { $_->classicLinkEnabled } @cl;

=head1 DESCRIPTION

This object represents an Amazon EC2 VPC Classic Link returned by
VM::EC2->describe_vpc_classic_link()

=head1 METHODS

These object methods are supported:

 classicLinkEnabled           -- Indicates whether the VPC is enabled for
                                 ClassicLink (boolean)
 vpcId                        -- The ID of the VPC.
 tags                         -- tags assigned to the VPC.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate a string
containing the VPC ID and whether ClassicLink is enabled or disabled.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>.

Copyright (c) 2015 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use Carp 'croak';

use overload
    '""'     => sub {
        my $self = shift;
        return $self->vpcId . ':' . $self->classicLinkEnabled ? 'true' : 'false'; },
    fallback => 1;

sub valid_fields {
    my $self  = shift;
    return qw(classicLinkEnabled vpcId tags);
}

sub classicLinkEnabled {
    my $self = shift;
    my $cle = $self->SUPER::classicLinkEnabled;
    return $cle eq 'true';
}

sub tagSet {
    my $self = shift;
    my $tags = $self->SUPER::tags;
    my $result = {};

    my $innerhash = $tags->{item} or return $result;
    for my $key (keys %$innerhash) {
        $result->{$key} = $innerhash->{$key}{value};
    }
    return $result;
}

sub tags { shift->tagSet }

1;

