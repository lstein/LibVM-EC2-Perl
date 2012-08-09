package VM::EC2::NetworkInterface;

=head1 NAME

VM::EC2::NetworkInterface - Object describing an Amazon Elastic Network Interface (ENI)

=head1 SYNOPSIS

  use VM::EC2;
  my $ec2 = VM::EC2->new(...);
  my $interface = $ec2->describe_network_interfaces('eni-12345');
  print $interface->subNetId,"\n",
        $interface->description,"\n",
        $interface->vpcId,"\n",
        $interface->status,"\n",
        $interface->privateIpAddress,"\n",
        $interface->macAddress,"\n";
  
=head1 DESCRIPTION

This object provides access to information about Amazon Elastic
Network Interface objects, which are used in conjunction with virtual
private cloud (VPC) instances to create multi-homed web servers,
routers, firewalls, and so forth.

Please see L<VM::EC2::Generic> for methods shared by all VM::EC2
objects.

=head1 METHODS

These object methods are supported:

 networkInterfaceId       -- The ID of this ENI
 subnetId                 -- The ID of the subnet this ENI belongs to
 vpcId                    -- The ID of the VPC this ENI belongs to
 description              -- Description of the ENI
 ownerId                  -- Owner of the ENI
 status                   -- ENI status, one of "available" or "in-use"
 privateIpAddress         -- Primary private IP address of the ENI
 privateDnsName           -- Primary private DNS name of the ENI
 sourceDestCheck          -- Boolean value. If true, prevent this ENI from
                             forwarding packets between subnets.
 groups                   -- List of security groups this ENI belongs to,
                             as a set of VM::EC2::Group objects.
 attachment               -- Information about the attachment of this ENI to
                             an instance, as a VM::EC2::NetworkInterface::Attachment
                             object.
 association              -- Information about the association of this ENI with
                             an elastic public IP address.
 privateIpAddresses       -- List of private IP addresses assigned to this ENI,
                             as a list of VM::EC2::NetworkInterface::PrivateIpAddress
                             objects.
 availabilityZone         -- Availability zone for this ENI as a VM::EC2::AvailabilityZone
                             object.
 macAddress               -- MAC address for this interface.

In addition, this object supports the following convenience methods:

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as the
networkInterfaceId

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::NetworkInterface>
L<VM::EC2::NetworkInterface::Attachment>
L<VM::EC2::NetworkInterface::Association>

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
use VM::EC2::Group;
use VM::EC2::NetworkInterface::PrivateIpAddress;
use VM::EC2::NetworkInterface::Attachment;
use VM::EC2::NetworkInterface::Association;

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
    my $a    = $self->SUPER::attachment or return;
    return VM::EC2::NetworkInterface::Attachment->new($a,$self->aws);
}

sub association {
    my $self = shift;
    my $a    = $self->SUPER::association or return;
    return VM::EC2::NetworkInterface::Association->new($a,$self->aws);
}

sub vpc {
    my $self = shift;
    return $self->describe_vpcs($self->vpcId);
}

# get/set methods
sub description {
    my $self = shift;
    my $d    = $self->aws->describe_network_interface_attribute($self,'description');
    $self->aws->modify_network_interface_attribute($self,-description=>shift) if @_;
    return $d;
}

sub security_groups {
    my $self = shift;
    my @d    = $self->aws->describe_network_interface_attribute($self,'groupSet');
    $self->aws->modify_network_interface_attribute($self,-security_group_id=>\@_) if @_;
    return map {VM::EC2::Group->new($_,$self->aws)} @d;
}

sub source_dest_check {
    my $self = shift;
    my $d    = $self->aws->describe_network_interface_attribute($self,'sourceDestCheck');
    $self->aws->modify_network_interface_attribute($self,-source_dest_check=>(shift() ? 'true' : 'false')) if @_;    
    return $d eq 'true';
}

sub attachment {
    my $self = shift;
    my $d    = $self->aws->describe_network_interface_attribute($self,'attachment');
    $self->aws->modify_network_interface_attribute($self,-attachment=>shift) if @_;
    return VM::EC2::NetworkInterface::Attachment->new($d,$self->aws);
}

sub availabilityZone {
    my $self = shift;
    my $z    = $self->SUPER::availabilityZone or return;
    return $self->aws->describe_availability_zones($z);
}

1;

