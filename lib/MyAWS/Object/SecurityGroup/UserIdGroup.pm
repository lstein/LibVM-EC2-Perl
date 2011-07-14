package MyAWS::Object::SecurityGroup::UserIdGroup;

use strict;
use base 'MyAWS::Object::Base';

sub valid_fields {
    qw(userId groupId groupName);
}

sub primary_id {shift->groupId};

1;

