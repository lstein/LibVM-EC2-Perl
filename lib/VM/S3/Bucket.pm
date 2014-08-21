package VM::S3::Bucket;

use strict;
use base 'VM::S3::Generic';

sub new {
    my $self = shift;
    my ($data,$ec2,$owner) = @_;
    my $obj  = $self->SUPER::new($data,$ec2);
    $obj->owner($owner) if defined $owner;
    $obj;
}

sub primary_id { shift->Name }

sub valid_fields {
    return qw(CreationDate Name);
}

sub owner {
    my $self = shift;
    $self->{data}{owner} = shift if @_;
    $self->{data}{owner};
}

1;
