package VM::S3::Grant;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Owner;

sub valid_fields {
    return qw(Grantee Permission);
}

sub short_name {
    return $_[0]->grantee.' '.$_[0]->permission;
}

sub grantee {
    my $self = shift;
    my $o    = $self->SUPER::Grantee;
    return VM::S3::Owner->new($o,$self->s3);
}


1;
