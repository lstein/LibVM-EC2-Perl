package VM::S3::Acl;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Owner;
use VM::S3::Grant;

sub valid_fields {
    return qw(AccessControlList Owner);
}

sub owner {
    my $self = shift;
    my $o    = $self->SUPER::Owner;
    return VM::S3::Owner->new($o,$self->s3);
}

sub access_control_list {
    my $self = shift;
    my $acl  = $self->SUPER::AccessControlList;
    my @list = ref $acl->{Grant} eq 'ARRAY' ? @{$acl->{Grant}} : $acl->{Grant};
    return map {VM::S3::Grant->new($_,$self->s3,$self->xmlns)} @list;
}

sub acl { shift->access_control_list }


1;
