package VM::S3::Lifecycle;

# a single lifecycle rule

use strict;
use VM::S3::Lifecycle::Transition;
use VM::S3::Lifecycle::Expiration;
use VM::S3::Lifecycle::NoncurrentVersionTransition;
use VM::S3::Lifecycle::NoncurrentVersionExpiration;
use base 'VM::S3::Generic';

sub valid_fields {
    return qw(ID Prefix Status
              Transition Expiration
              NoncurrentVersionTransition NoncurrentVersionExpiration);
}

sub transition {
    my $self = shift;
    my $t    = $self->SUPER::Transition or return;
    return VM::S3::Lifecycle::Transition->new($t,$self->s3);
}

sub expiration {
    my $self = shift;
    my $e    = $self->SUPER::Expiration or return;
    return VM::S3::Lifecycle::Expiration->new($e,$self->s3);
}

sub noncurrent_version_transition {
    my $self = shift;
    my $nvt  = $self->SUPER::NoncurrentVersionTransition or return;
    return VM::S3::Lifecycle::NoncurrentVersionTransition->new($nvt,$self->s3);
}

sub noncurrent_version_expiration {
    my $self = shift;
    my $nve  = $self->SUPER::NoncurrentVersionExpiration or return;
    return VM::S3::Lifecycle::NoncurrentVersionExpiration->new($nve,$self->s3);
}

sub short_name {shift->as_xml}

sub as_xml {
    my $self = shift;
    my $parser = XML::Simple->new();
    return $parser->XMLout($self->{data},RootName=>'Rule',NoAttr=>1);
}

1;
