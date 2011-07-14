package MyAWS::Object::SecurityGroup;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::SecurityGroup::IpPermission;

sub valid_fields {
    return qw(ownerId groupId groupName groupDescription vpcId ipPermissions ipPermissionEgress tagSet);
}

sub primary_id { shift->groupId }

sub name { shift->groupName }

sub inbound_permissions  { shift->ipPermissions }
sub outbound_permissions { shift->ipPermissionsEgress }

sub ipPermissions {
    my $self = shift;
    my $p    = $self->SUPER::ipPermissions or return;
    return map { MyAWS::Object::SecurityGroup::IpPermission->new($_,$self->aws)} @{$p->{item}};
}

sub ipPermissionsEgress {
    my $self = shift;
    my $p    = $self->SUPER::ipPermissionsEgress or return;
    return map { MyAWS::Object::SecurityGroup::IpPermission->new($_,$self->aws)} @{$p->{item}};
}

1;
