package MyAWS::Object::SecurityGroup;

=head1 NAME

MyAWS::Object::SecurityGroup - Object describing an Amazon EC2 security group

=head1 SYNOPSIS

  use MyAWS;

  $aws       = MyAWS->new(...);
  @sg = $aws->describe_security_groups;
  for my $sg (@sg) {
      $name = $sg->groupName;
      $id   = $sg->groupId;
      $desc = $sg->groupDescription;
      $tags = $sg->tags;
      @inbound_permissions  = $sg->ipPermissions;
      @outbound_permissions = $sg->ipPermissionEgress;
      for $i (@inbound_permissions) {
         $protocol = $i->ipProtocol;
         $fromPort = $i->fromPort;
         $toPort   = $i->toPort;
         @ranges   = $i->ipRanges;
      }
  }

=head1 DESCRIPTION

This object is used to describe an Amazon EC2 security group. It is
returned by MyAWS->describe_security_groups(). You may also obtain
this object by calling an Instance object's groups() method, and then
invoking one of the group's permissions() method. See
L<MyAWS::Object::Group>.

=head1 METHODS

The following object methods are supported:
 
 ownerId          -- Owner of this security group
 groupId          -- ID of this security group
 groupName        -- Name of this security group
 groupDescription -- Description of this group
 vpcId            -- Virtual Private Cloud ID, if applicable
 ipPermissions    -- A list of rules that govern incoming connections
                     to instances running under this security group.
                     Each rule is a
                     MyAWS::Object::SecurityGroup::IpPermission object.
 ipPermissionsEgress -- A list of rules that govern outgoing connections
                     from instances running under this security group.
                     Each rule is a
                     MyAWS::Object::SecurityGroup::IpPermission object.
 tags             -- Hashref containing tags associated with this group.
                     See L<MyAWS::Object::Base>.

For convenience, the following aliases are provided for commonly used methods:

 inbound_permissions  -- same as ipPermissions()
 outbound_permissions -- same as ipPermissionsEgress()
 name                 -- same as groupName()

See L<MyAWS::Object::SecurityGroup::IpPermission> for methods that
return information about incoming and outgoing firewall rules.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
groupId.

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object::Base>
L<MyAWS::Object::Instance>
L<MyAWS::Object::Group>
L<MyAWS::Object::SecurityGroup::IpPermission>

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
use base 'MyAWS::Object::Base';
use MyAWS::Object::SecurityGroup::IpPermission;

sub valid_fields {
    return qw(ownerId groupId groupName groupDescription vpcId ipPermissions ipPermissionsEgress tagSet);
}

sub primary_id { shift->groupId }

sub name { shift->groupName }

sub inbound_permissions  { shift->ipPermissions }
sub outbound_permissions { shift->ipPermissionsEgress }

sub ipPermissions {
    my $self = shift;
    my $p    = $self->SUPER::ipPermissions or return;
    return map { MyAWS::Object::SecurityGroup::IpPermission->new($_,$self->aws,$self->xmlns,$self->requestId)} @{$p->{item}};
}

sub ipPermissionsEgress {
    my $self = shift;
    my $p    = $self->SUPER::ipPermissionsEgress or return;
    return map { MyAWS::Object::SecurityGroup::IpPermission->new($_,$self->aws,$self->xmlns,$self->requestId)} @{$p->{item}};
}

1;
