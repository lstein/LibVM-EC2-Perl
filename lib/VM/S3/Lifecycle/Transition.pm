package VM::S3::Lifecycle::Transition;

use strict;
use base 'VM::S3::Generic';

sub valid_fields {
    qw(Days Date StorageClass);
}

sub short_name {shift->as_xml}

sub as_xml {
    my $self = shift;
    my $parser = XML::Simple->new();
    (my $type = ref $self) =~ s/^\S+:://;
    return $parser->XMLout($self->{data},RootName=>$type,NoAttr=>1);
}

1;
