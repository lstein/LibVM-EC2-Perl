package VM::EC2::VPC::Subnet;

=head1 NAME

VM::EC2::VPC::Subnet -- A VPC subnet

=head1 SYNOPSIS

 use VM::EC2;
 my $ec2     = VM::EC2->new(...);
 my $vpc     = $ec2->create_vpc('10.0.0.0/16');
 my $subnet  = $vpc->create_subnet('10.0.0.0/24')  or die $vpc->error_str;
 @subnets    = $ec2->describe_subnets;
 
 for my $sn (@subnets) {
    print $sn->subnetId,"\n",
          $sn->state,"\n",
          $sn->vpcId,"\n",
          $sn->cidrBlock,"\n",
          $sn->availableIpAddressCount,"\n",
          $sn->availabilityZone,"\n";
 }

=head1 DESCRIPTION

This object supports the EC2 Virtual Private Cloud subnet
interface. Please see L<VM::EC2::Generic> for methods shared by all
VM::EC2 objects.

=head1 METHODS

These object methods are supported:
 
 subnetId   -- the ID of the subnet
 state      -- The current state of the subnet, either "pending" or "available"
 vpcId      -- The ID of the VPC the subnet is in.
 cidrBlock  -- The CIDR block assigned to the subnet.
 availableIpAddressCount -- The number of unused IP addresses in the subnet.
 availableZone -- This subnet's availability zone.

This class supports the VM::EC2 tagging interface. See
L<VM::EC2::Generic> for information.

In addition, this object supports the following convenience methods:

 vpc()                -- Return the associated VM::EC2::VPC object.
 zone()               -- Return the associated VM::EC2::AvailabilityZone object.
 refresh()            -- Refreshes the object from its current state in EC2.
 current_state()      -- Refreshes the object and returns its current state.

=head1 STRING OVERLOADING

When used in a string context, this object will be interpolated as the
subnet ID.

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
use Carp 'croak';
use base 'VM::EC2::Generic';

sub valid_fields {
    my $self  = shift;
    return qw(subnetId state vpcId cidrBlock availableIpAddressCount
              availabilityZone);
}

sub primary_id { shift->subnetId }

sub vpc {
    my $self = shift;
    return $self->aws->describe_vpcs($self->vpcId);
}

sub zone {
    my $self = shift;
    return $self->aws->describe_availability_zones($self->availabilityZone);
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_subnets($self->subnetId) unless $i;
    %$self  = %$i;
}

sub current_state {
    my $self = shift;
    $self->refresh;
    $self->state;
}

1;

