package VM::EC2::REST::classic_link;

use strict;
use VM::EC2 '';  # important not to import anything!
package VM::EC2;  # add methods to VM::EC2

VM::EC2::Dispatch->register(
    AttachClassicLinkVpc         => 'boolean',
    DescribeClassicLinkInstances => 'fetch_items,instancesSet,VM::EC2::Instance::ClassicLink',
    DescribeVpcClassicLink       => 'fetch_items,vpcSet,VM::EC2::VPC::ClassicLink',
    DetachClassicLinkVpc         => 'boolean',
    DisableVpcClassicLink        => 'boolean',
    EnableVpcClassicLink         => 'boolean',
    );

my $VEP = 'VM::EC2::ParmParser';

=head1 NAME VM::EC2::REST:classic_link:

=head1 SYNOPSIS

 use VM::EC2 ':link';

=head1 METHODS

ClassicLink allows you to link your EC2-Classic instance to a VPC in your
account, within the same region.

Implemented:
 AttachClassicLinkVpc
 DescribeClassicLinkInstances
 DescribeVpcClassicLink
 DetachClassicLinkVpc
 DisableVpcClassicLink
 EnableVpcClassicLink

Unimplemented:
 (none)

=cut

=head2 $success = $ec2->attach_classic_link_vpc(-dry_run           => $boolean,
                                        -security_group_id => \@ids,
                                        -instance_id       => $instance_id,
                                        -vpc_id            => $vpc_id )

Links an EC2-Classic instance to a ClassicLink-enabled VPC through one or more
of the VPC's security groups. An EC2-Classic instance cannot be linked to more
than one VPC at a time. Only a running instanced can be linked.  An instance is
automatically unlinked from a VPC when it's stopped - it can be linked to the
VPC again when restarted.

Once an instanced is linked, the VPC security group association cannot be
changed.  To change the security groups, the instanced must be unlinked and
linked again.

Linking an instance to a VPC is sometimes referred to as attaching an instance.

Required arguments:

 -security_group_id  A scalar or list of VPC security group IDs. Security groups
                     must be from from the same VPC.

 -instance_id         ID of an EC2-Classic instance to link to the ClassicLink-
                      enabled VPC.

 -vpc_id              The ID of a ClassicLink-enabled VPC.

Optional arguments:

 -dry_run            Perform a dry run (boolean).

Returns true on success.

=cut

sub attach_classic_link_vpc {
    my $self = shift;
    my %args = @_;
    $args{-security_group_id} && $args{-instance_id} && $args{-vpc_id} or
        croak "attach_classic_link_vpc(): -security_group_id, -instance_id, and -vpc_id parameters required";
    my @param = $VEP->format_parms(\%args,
        {
            list_parm   => 'SecurityGroupId',
            single_parm => [qw(InstanceId VpcId)],
            boolean_parm => 'DryRun',
        });
    return $self->call('AttachClassicLinkVpc',@param);
}

=head2 $@instances = $ec2->describe_classic_link_instances(@instances)

=head2 $@instances = $ec2->describe_classic_link_instances(\%filters)

=head2 $@instances = $ec2->describe_classic_link_instances(-instance_id=>\@ids,-filter=>\%filters)

Describes one or more of your linked EC2-Classic instances. This request only
returns information about EC2-Classic instances linked to a VPC through
ClassicLink; it cannot be used to return information about other instances.

Optional arguments:

 -instance_id         ID of an EC2-Classic instance to link to the ClassicLink-
                      enabled VPC.

 -filter              One or more filters.

                      Valid filters:
                      * group-id
                      * instance-id
                      * tag:key=value
                      * tag-key
                      * tag-value
                      * vpc-id

Returns L<VM::EC2::Instance::ClassicLink> objects.

=cut

sub describe_classic_link_instances {
    my $self = shift;
    my %args = $VEP->args(-instance_id,@_);
    my @param = $VEP->format_parms(\%args,
        {
            list_parm   => 'InstanceId',
            filter_parm => 'Filter',
        });
    return $self->call('DescribeClassicLinkInstances',@param);
}

=head2 @vpcset = $ec2->describe_vpc_classic_link(@vpcs)

=head2 @vpcset = $ec2->describe_vpc_classic_link(%filters)

=head2 @vpcset = $ec2->describe_vpc_classic_link(-vpc_id => \@ids, -filter => \%filters)

Describes the ClassicLink status of one or more VPCs.

Optional arguments:

 -vpc_id              One or more VPCs for which you want to describe the
                      ClassicLink status.

 -filter              One or more filters.

                      * is-classic-link-enabled  
                      * tag:key=value
                      * tag-key
                      * tag-value

=cut

sub describe_vpc_classic_link {
    my $self = shift;
    my %args = $VEP->args(-vpc_id,@_);
    my @param = $VEP->format_parms(\%args,
        {
            list_parm   => 'VpcId',
            filter_parm => 'Filter',
        });
    return $self->call('DescribeVpcClassicLink',@param);
}

=head2 $success = $ec2->detach_classic_link_vpc(-vpc_id      => $vpc_id,
                                                -instance_id => $instance_id)

Unlinks (detaches) a linked EC2-Classic instance from a VPC. After the instance
has been unlinked, the VPC security groups are no longer associated with it. An
instance is automatically unlinked from a VPC when it is stopped

Required arguments:

 -instance_id         ID of an EC2-Classic instance to detach from the VPC.

 -vpc_id              The ID of the VPC to which the instance is attached.

Optional arguments:

 -dry_run            Perform a dry run (boolean).

Returns true on success.

=cut

sub detach_classic_link_vpc {
    my $self = shift;
    my %args = @_;
    $args{-instance_id} && $args{-vpc_id} or
        croak "detach_classic_link_vpc(): -instance_id and -vpc_id parameters required";
    my @param = $VEP->format_parms(\%args,
        {
            single_parm => [qw(InstanceId VpcId)],
            boolean_parm => 'DryRun',
        });
    return $self->call('DetachClassicLinkVpc',@param);
}

=head2 $success = $ec2->disable_vpc_classic_link($vpc_id)

=head2 $success = $ec2->disable_vpc_classic_link(-vpc_id => $vpc_id)

Disables ClassicLink for a VPC. ClassicLink cannot be disabled for a VPC that
has EC2-Classic instances linked to it.

Required arguments:

 -vpc_id              The ID of the VPC.

Returns true on success.

=cut

sub disable_vpc_classic_link {
    my $self = shift;
    my %args = $VEP->args(-vpc_id,@_);
    my @param = $VEP->format_parms(\%args,
        {
            single_parm   => 'VpcId',
        });
    return $self->call('DisableVpcClassicLink',@param);
}

=head2 $success = $ec2->enable_vpc_classic_link($vpc_id)

=head2 $success = $ec2->enable_vpc_classic_link(-vpc_id => $vpc_id)

Enables a VPC for ClassicLink. EC2-Classic instances can be linked to a
ClassicLink-enabled VPC to allow communication over private IP addresses.
ClassicLink cannot be enabled on a VPC if any of the VPC's route tables have
existing routes for address ranges within the 10.0.0.0/8 IP address range,
excluding local routes for VPCs in the 10.0.0.0/16 and 10.1.0.0/16 IP address
ranges. For more information, see ClassicLink in the Amazon Elastic Compute
Cloud User Guide.

Required arguments:

 -vpc_id              The ID of the VPC.

Returns true on success.

=cut

sub enable_vpc_classic_link {
    my $self = shift;
    my %args = $VEP->args(-vpc_id,@_);
    my @param = $VEP->format_parms(\%args,
        {
            single_parm   => 'VpcId',
        });
    return $self->call('EnableVpcClassicLink',@param);
}

=head1 SEE ALSO

L<VM::EC2>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>

Copyright (c) 2015 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


1;
