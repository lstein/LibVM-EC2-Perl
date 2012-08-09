package VM::EC2::NetworkInterface;

=head1 NAME

VM::EC2::NetworkInterface

=head1 SYNOPSIS

  use VM::EC2;
 ...

=head1 DESCRIPTION

Please see L<VM::EC2::Generic> for methods shared by all VM::EC2
objects.

=head1 METHODS

These object methods are supported:

 networkInterfaceId
 subnetId
 vpcId
 description
 ownerId
 status
 privateIpAddress
 privateDnsName
 sourceDestCheck
 groupSet
 attachment
 association
 privateIpAddressesSet
 availabilityZone
 macAddress

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
use VM::EC2::NetworkInterface::PrivateIpAddress;
use VM::EC2::NetworkInterface::Attachment;

sub valid_fields {
    my $self  = shift;
    return qw(networkInterfaceId subnetId vpcId description ownerId status privateIpAddress privateDnsName
              sourceDestCheck groupSet attachment association privateIpAddressesSet macAddress requesterManaged
              availabilityZone);
}

sub refresh {
    my $self = shift;
    my $i    = shift;
    ($i) = $self->aws->describe_network_interfaces(-network_interface_id=>$self->networkInterfaceId) unless $i;
    %$self  = %$i;
}

sub current_status {
    my $self = shift;
    $self->refresh;
    $self->status;
}

sub primary_id {shift->networkInterfaceId}

sub groups {
    my $self = shift;
    my $groupSet = $self->SUPER::groupSet;
    return map {VM::EC2::Group->new($_,$self->aws,$self->xmlns,$self->requestId)}
        @{$groupSet->{item}};
}

sub privateIpAddresses {
    my $self = shift;
    my $set  = $self->SUPER::privateIpAddressesSet;
    return map {VM::EC2::NetworkInterface::PrivateIpAddress->new($_,$self->aws)} @{$set->{item}};
}

sub attachment {
    my $self = shift;
    my $a    = $self->SUPER::attachment;
    return VM::EC2::NetworkInterface::Attachment->new($a,$self->aws);
}

sub vpc {
    my $self = shift;
    return $self->describe_vpcs($self->vpcId);
}

1;

