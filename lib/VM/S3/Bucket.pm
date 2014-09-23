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

sub objects {
    my $self = shift;
    $self->s3->list_objects($self->Name);
}

sub keys {
    my $self = shift;
    $self->s3->list_objects($self->Name);
}

sub cors {
    my $self = shift;
    if (@_) {
	return $self->s3->put_bucket_cors($self->Name,shift);
    } else {
	return $self->s3->bucket_cors($self->Name);
    }
}

sub put {
    my $self = shift;
    $self->s3->put_object($self->Name,@_);
}

1;
