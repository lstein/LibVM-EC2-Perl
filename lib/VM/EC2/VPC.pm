package VM::EC2::VPC;

=head1 NAME

VM::EC2::VPC

=head1 SYNOPSIS

  use VM::EC2;
 ...

=head1 DESCRIPTION

Please see L<VM::EC2::Generic> for methods shared by all VM::EC2
objects.

=head1 METHODS

These object methods are supported:

 vpcId         -- ID of the VPC
 state         -- Current state of the VPC (pending, available)
 cidrBlock     -- The CIDR block the VPC covers.
 dhcpOptionsId -- The ID of the set of DHCP options you've associated
                  with the VPC, or "default".
 instanceTenancy  -- Either "dedicated" or "default"

In addition, this object supports the following convenience methods:

    dhcp_options()   -- Return a VM::EC2::VPC::DhcpOptions object.

    current_state()  -- Refresh the object and then return its state

    current_status() -- Same as above (for module consistency)

    set_dhcp_options($options) -- Associate the Dhcp option set with
          this VPC (DhcpOptionsId string or VM::EC2::VPC::DhcpOptions object).
          Use "default" or pass no arguments to assign no Dhcp options.

    internet_gateways() -- Return the list of internet gateways attached to
                           this VPC as a list of VM::EC2::VPC::InternetGateway.

    subnets()           -- Return the list of subnets attached to this VPC
                           as a list of VM::EC2::VPC::Subnet.

    route_tables()      -- Return the list of route tables attached to this VPC
                           as a list of VM::EC2::VPC::RouteTable.

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

sub valid_fields {
    my $self  = shift;
    return qw(vpcId state cidrBlock dhcpOptionsId instanceTenancy);
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_vpcs(-vpc_id=>$self->vpcId) unless $i;
    %$self  = %$i;
}

sub current_state {
    my $self = shift;
    $self->refresh;
    $self->state;
}

sub current_status {shift->current_state(@_)}

sub primary_id { shift->vpcId }

sub dhcp_options {
    my $self = shift;
    return $self->aws->describe_dhcp_options($self->dhcpOptionsId);
}

sub set_dhcp_options {
    my $self = shift;
    my $options = shift || 'default';
    return $self->aws->associate_dhcp_options($self => $options);
}

sub internet_gateways {
    my $self = shift;
    return $self->aws->describe_internet_gateways({'attachment.vpc-id'=>$self->vpcId});
}

sub subnets {
    my $self = shift;
    return $self->aws->describe_subnets({'vpc-id'=>$self->vpcId});
}

sub route_tables {
    my $self = shift;
    return $self->aws->describe_route_tables({'vpc-id'=>$self->vpcId});
}

sub attach_internet_gateway {
    my $self = shift;
    my $gw   = shift;
    return $self->aws->attach_internet_gateway($gw => $self->vpcId);
}

sub detach_internet_gateway {
    my $self = shift;
    my $gw   = shift;
    return $self->aws->detach_internet_gateway($gw=>$self->vpcId);
}

1;

