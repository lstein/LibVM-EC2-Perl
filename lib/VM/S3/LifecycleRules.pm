package VM::S3::LifecycleRules;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Lifecycle;
use Carp 'croak';

sub new {
    my $self = shift;
    if (!@_) { # no arguments!
	return $self->SUPER::new({},undef);
    } else {
	return $self->SUPER::new(@_);
    }
}

sub short_name { shift->as_xml }

sub valid_fields {
    return qw(Rule);
}

sub rules {
    my $self = shift;
    my $life = $self->Rule;
    my @life = ref $life eq 'ARRAY' ? @$life : $life;
    my $s3    = $self->s3;
    my $xmlns = $self->xmlns;
    return map {VM::S3::Lifecycle->new($_,$s3,$xmlns)} @life;
}

# add_rule(???)
# NEEDS IMPLEMENTATION
sub add_rule {
    my $self = shift;
    my $hash = {};
    while (my($key,$value) = splice(@_,0,2)) {
    }
    push @{$self->{data}{Rule}},$hash;
}

sub as_xml {
    my $self = shift;
    my $parser = XML::Simple->new();
    local $self->{data} = $self->{data};
    delete $self->{data}{xmlns};
    delete $self->{data}{requestId};
    return $parser->XMLout($self->{data},RootName=>'LifecycleConfiguration',NoAttr=>1);
}

1;
