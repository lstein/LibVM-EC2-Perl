package VM::EC2::REST::vpc;

use strict;
use VM::EC2 '';  # important not to import anything!
package VM::EC2;  # add methods to VM::EC2

VM::EC2::Dispatch->register(
    CreateVpc                         => 'fetch_one,vpc,VM::EC2::VPC',
    DeleteVpc                         => 'boolean',
    DescribeVpcs                      => 'fetch_items,vpcSet,VM::EC2::VPC',
    ModifyVpcAttribute                => 'boolean',
    DescribeVpcAttribute              => 'boolean',
    );

=head1 NAME VM::EC2::REST::vpc

=head1 SYNOPSIS

 use VM::EC2 ':vpc';

=head1 METHODS

EC2 virtual private clouds (VPCs) provide facilities for creating
tiered applications combining public and private subnetworks, and for
extending your home/corporate network into the cloud.

Implemented:
 CreateVpc
 DeleteVpc
 DescribeVpcs
 DescribeVpcAttribute
 ModifyVpcAttribute

Unimplemented:
 (none)

=cut

=head2 $vpc = $ec2->create_vpc(-cidr_block=>$cidr,-instance_tenancy=>$tenancy)

Create a new VPC. This can be called with a single argument, in which
case it is interpreted as the desired CIDR block, or 

 $vpc = $ec2->$ec2->create_vpc('10.0.0.0/16') or die $ec2->error_str;

Or it can be called with named arguments.

Required arguments:

 -cidr_block      The Classless Internet Domain Routing address, in the
                  form xx.xx.xx.xx/xx. One or more subnets will be allocated
                  from within this block.

Optional arguments:

 -instance_tenancy "default" or "dedicated". The latter requests AWS to
                  launch all your instances in the VPC on single-tenant
                  hardware (at additional cost).

See
http://docs.amazonwebservices.com/AmazonVPC/latest/UserGuide/VPC_Subnets.html
for a description of the valid CIDRs that can be used with EC2.

On success, this method will return a new VM::EC2::VPC object. You can
then use this object to create new subnets within the VPC:

 $vpc     = $ec2->create_vpc('10.0.0.0/16')    or die $ec2->error_str;
 $subnet1 = $vpc->create_subnet('10.0.0.0/24') or die $vpc->error_str;
 $subnet2 = $vpc->create_subnet('10.0.1.0/24') or die $vpc->error_str;
 $subnet3 = $vpc->create_subnet('10.0.2.0/24') or die $vpc->error_str;

=cut

sub create_vpc {
    my $self = shift;
    my %args   = $self->args('-cidr_block',@_);
    $args{-cidr_block} or croak "create_vpc(): must provide a -cidr_block parameter";
    my @parm   = $self->list_parm('CidrBlock',\%args);
    push @parm,  $self->single_parm('instanceTenancy',\%args);
    return $self->call('CreateVpc',@parm);
}

=head2 @vpc = $ec2->describe_vpcs(@vpc_ids)

=head2 @vpc = $ec2->describe_vpcs(\%filter)

=head2 @vpc = $ec2->describe_vpcs(-vpc_id=>\@list,-filter=>\%filter)

Describe VPCs that you own and return a list of VM::EC2::VPC
objects. Call with no arguments to return all VPCs, or provide a list
of VPC IDs to return information on those only. You may also provide a
filter list, or named argument forms.

Optional arguments:

 -vpc_id      A scalar or array ref containing the VPC IDs you want
              information on.

 -filter      A hashref of filters to apply to the query.

The filters you can use are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeVpcs.html

=cut

sub describe_vpcs {
    my $self = shift;
    my %args   = $self->args('-vpc_id',@_);
    my @parm   = $self->list_parm('VpcId',\%args);
    push @parm,  $self->filter_parm(\%args);
    return $self->call('DescribeVpcs',@parm);
}

=head2 $success = $ec2->delete_vpc($vpc_id)

=head2 $success = $ec2->delete_vpc(-vpc_id=>$vpc_id)

Delete the indicated VPC, returning true if successful.

=cut

sub delete_vpc {
    my $self = shift;
    my %args  = $self->args(-vpc_id => @_);
    my @param = $self->single_parm(VpcId=>\%args);
    return $self->call('DeleteVpc',@param);
}

=head2 $attr = $ec2->describe_vpc_attribute(-vpc_id => $id, -attribute => $attr)

Describes an attribute of the specified VPC.

Required arguments:

 -vpc_id                  The ID of the VPC.

 -attribute               The VPC attribute.
                          Valid values:
                          enableDnsSupport | enableDnsHostnames

Returns true if attribute is set.

=cut

sub describe_vpc_attribute {
    my $self = shift;
    my %args  = @_;
    $args{-vpc_id} or croak "modify_vpc_attribute(): -vpc_id argument missing";
    $args{-attribute} or croak "modify_vpc_attribute(): -attribute argument missing";
    my @param = $self->single_parm(VpcId=>\%args);
    push @param, $self->single_parm('Attribute',\%args);
    my $result = $self->call('DescribeVpcAttribute',@param);
    return $result && $result->attribute($args{-attribute}) eq 'true';
}

=head2 $success = $ec2->modify_vpc_attribute(-vpc_id               => $id,
                                             -enable_dns_support   => $boolen,
                                             -enable_dns_hostnames => $boolean)

Modify attributes of a VPC.

Required Arguments:

 -vpc_id                  The ID of the VPC.

 -enable_dns_support      Specifies whether the DNS server provided
                          by Amazon is enabled for the VPC.

Optional arguments:

 -enable_dns_hostnames    Specifies whether DNS hostnames are provided
                          for the instances launched in this VPC. You
                          can only set this attribute to true if
                          -enable_dns_support is also true.

Returns true on success.

=cut

sub modify_vpc_attribute {
    my $self = shift;
    my %args  = @_;
    $args{-vpc_id} or croak "modify_vpc_attribute(): -vpc_id argument missing";
    $args{-enable_dns_support} or
        croak "modify_vpc_attribute(): -enable_dns_support argument missing";
    my @param = $self->single_parm(VpcId=>\%args);
    push @param, $self->boolean_parm($_,\%args)
        foreach qw(enableDnsSupport enableDnsHostnames);
    return $self->call('ModifyVpcAttribute',@param);
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
