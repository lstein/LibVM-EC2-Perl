package VM::S3::CorsRules;

use strict;
use base 'VM::S3::Generic';
use VM::S3::Cors;
use Carp 'croak';

my %VALID_COMPONENT = (
    AllowedOrigin=>1,
    AllowedMethod=>1,
    AllowedHeader=>1,
    MaxAgeSeconds=>1,
    ExposeHeader=>1,
    );

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
    return qw(CORSRule);
}

sub rules {
    my $self = shift;
    my $cors = $self->CORSRule;
    my @cors = ref $cors eq 'ARRAY' ? @$cors : $cors;
    my $s3    = $self->s3;
    my $xmlns = $self->xmlns;
    return map {VM::S3::Cors->new($_,$s3,$xmlns)} @cors;
}

# add_rule(AllowedOrigin=>'http://www.example.com',AllowedMethod=>['PUT','POST'])
sub add_rule {
    my $self = shift;
    my $hash = {};
    while (my($key,$value) = splice(@_,0,2)) {
	croak "invalid rule component" unless $VALID_COMPONENT{$key};
	if ($hash->{$key}) { # already exists
	    if (ref $hash->{$key} eq 'ARRAY') {
		push @{$hash->{$key}},$value;
	    } else {
		$hash->{$key} = [$hash->{$key},$value]
	    }
	} else {
	    $hash->{$key} = $value;
	}
    }
    push @{$self->{data}{CORSRule}},$hash;
}

sub as_xml {
    my $self = shift;
    my $parser = XML::Simple->new();
    return $parser->XMLout($self->{data},RootName=>'CORSConfiguration',NoAttr=>1);
}

1;
