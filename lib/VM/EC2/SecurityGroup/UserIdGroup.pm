package VM::EC2::SecurityGroup::UserIdGroup;

use strict;
use base 'VM::EC2::Generic';

sub valid_fields {
    qw(userId groupId groupName);
}

sub primary_id {
    my $self = shift;
    return $self->groupId || $self->userId .'/'.$self->groupName;
}

1;

