package VM::EC2::REST::reserved_instance;

use strict;
use VM::EC2 '';  # important not to import anything!
package VM::EC2;  # add methods to VM::EC2

VM::EC2::Dispatch->register(
    DescribeReservedInstances          => 'fetch_items,reservedInstancesSet,VM::EC2::ReservedInstance',
    DescribeReservedInstancesOfferings  => 'fetch_items,reservedInstancesOfferingsSet,VM::EC2::ReservedInstance::Offering',
    PurchaseReservedInstancesOffering  => sub { my ($data,$ec2) = @_;
						my $ri_id = $data->{reservedInstancesId} or return;
						return $ec2->describe_reserved_instances($ri_id); },
    );

=head1 NAME VM::EC2::REST::reserved_instance

=head1 SYNOPSIS

 use VM::EC2 ':misc'

=head1 METHODS

These methods apply to describing, purchasing and using Reserved Instances.

Implemented:
 DescribeReservedInstances
 DescribeReservedInstancesOfferings
 PurchaseReservedInstancesOffering

Unimplemented:
 CancelReservedInstancesListing
 CreateReservedInstancesListing
 DescribeReservedInstancesListings

=head2 @offerings = $ec2->describe_reserved_instances_offerings(@offering_ids)

=head2 @offerings = $ec2->describe_reserved_instances_offerings(%args)

This method returns a list of the reserved instance offerings
currently available for purchase. The arguments allow you to filter
the offerings according to a variety of filters. 

All arguments are optional. If no named arguments are used, then the
arguments are treated as Reserved Instance Offering IDs.
 
 -reserved_instances_offering_id  A scalar or arrayref of reserved
                                   instance offering IDs

 -instance_type                   The instance type on which the
                                   reserved instance can be used,
                                   e.g. "c1.medium"

 -availability_zone, -zone        The availability zone in which the
                                   reserved instance can be used.

 -product_description             The reserved instance description.
                                   Valid values are "Linux/UNIX",
                                   "Linux/UNIX (Amazon VPC)",
                                   "Windows", and "Windows (Amazon
                                   VPC)"

 -instance_tenancy                The tenancy of the reserved instance
                                   offering, either "default" or
                                   "dedicated". (VPC instances only)

 -offering_type                  The reserved instance offering type, one of
                                   "Heavy Utilization", "Medium Utilization",
                                   or "Light Utilization".

 -filter                          A set of filters to apply.

For available filters, see http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeReservedInstancesOfferings.html.

The returned objects are of type L<VM::EC2::ReservedInstance::Offering>

This can be combined with the Offering purchase() method as shown here:

 @offerings = $ec2->describe_reserved_instances_offerings(
          {'availability-zone'   => 'us-east-1a',
           'instance-type'       => 'c1.medium',
           'product-description' =>'Linux/UNIX',
           'duration'            => 31536000,  # this is 1 year
           });
 $offerings[0]->purchase(5) and print "Five reserved instances purchased\n";

=cut

sub describe_reserved_instances_offerings {
    my $self = shift;
    my %args = $self->args('-reserved_instances_offering_id',@_);
    $args{-availability_zone} ||= $args{-zone};
    my @param = $self->list_parm('ReservedInstancesOfferingId',\%args);
    push @param,$self->single_parm('ProductDescription',\%args);
    push @param,$self->single_parm('InstanceType',\%args);
    push @param,$self->single_parm('AvailabilityZone',\%args);
    push @param,$self->single_parm('instanceTenancy',\%args);  # should initial "i" be upcase?
    push @param,$self->single_parm('offeringType',\%args);     # should initial "o" be upcase?
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeReservedInstancesOfferings',@param);
}

=head $id = $ec2->purchase_reserved_instances_offering($offering_id)

=head $id = $ec2->purchase_reserved_instances_offering(%args)

Purchase one or more reserved instances based on an offering.

Arguments:

 -reserved_instances_offering_id, -id -- The reserved instance offering ID
                                         to purchase (required).

 -instance_count, -count              -- Number of instances to reserve
                                          under this offer (optional, defaults
                                          to 1).


Returns a Reserved Instances Id on success, undef on failure. Also see the purchase() method of
L<VM::EC2::ReservedInstance::Offering>.

=cut

sub purchase_reserved_instances_offering {
    my $self = shift;
    my %args = $self->args('-reserved_instances_offering_id'=>@_);
    $args{-reserved_instances_offering_id} ||= $args{-id};
    $args{-reserved_instances_offering_id} or 
	croak "purchase_reserved_instances_offering(): the -reserved_instances_offering_id argument is required";
    $args{-instance_count} ||= $args{-count};
    my @param = $self->single_parm('ReservedInstancesOfferingId',\%args);
    push @param,$self->single_parm('InstanceCount',\%args);
    return $self->call('PurchaseReservedInstancesOffering',@param);
}

=head2 @res_instances = $ec2->describe_reserved_instances(@res_instance_ids)

=head2 @res_instances = $ec2->describe_reserved_instances(%args)

This method returns a list of the reserved instances that you
currently own.  The information returned includes the type of
instances that the reservation allows you to launch, the availability
zone, and the cost per hour to run those reserved instances.

All arguments are optional. If no named arguments are used, then the
arguments are treated as Reserved Instance  IDs.
 
 -reserved_instances_id -- A scalar or arrayref of reserved
                            instance IDs

 -filter                -- A set of filters to apply.

For available filters, see http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeReservedInstances.html.

The returned objects are of type L<VM::EC2::ReservedInstance>

=cut

sub describe_reserved_instances {
    my $self = shift;
    my %args = $self->args('-reserved_instances_id',@_);
    my @param = $self->list_parm('ReservedInstancesId',\%args);
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeReservedInstances',@param);
}

=head1 SEE ALSO

L<VM::EC2>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


1;
