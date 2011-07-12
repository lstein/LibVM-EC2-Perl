package MyAWS::Object::Base;

use strict;
use Carp 'croak';

our $AUTOLOAD;

use overload
    '""'     => sub {shift->primary_id},
    fallback => 1;

sub new {
    my $self = shift;
    @_ == 2 or croak "Usage: $self->new(\$data,\$aws)";
    my ($data,$aws) = @_;
    return bless {data => $data,
		  aws  => $aws,
    },ref $self || $self;
}

sub primary_id {
    my $self = shift;
    return overload::StrVal($self);
}

sub aws {
    my $self = shift;
    my $d    = $self->{aws};
    $self->{aws} = shift if @_;
    $d;
}

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my %fields = map {$_=>1} $self->valid_fields;
    croak "Can't locate object method \"$func_name\" via package \"$pack\""
	unless $fields{$func_name};
    return $self->{data}{$func_name};
}

sub can {
    my $self = shift;
    my $method = shift;

    my $can  = $self->SUPER::can($method);
    return $can if $can;
    
    my %fields = map {$_=>1} $self->valid_fields;
    return \&AUTOLOAD if $fields{$method};

    return;
}

sub payload { shift->{data} }

sub valid_fields {
    return qw(xmlns requestId tagSet)
}

sub tags {
    my $self = shift;
    my $result = {};
    my $set  = $self->tagSet      or return $result;
    my $innerhash = $set->{item} or return $result;
    for my $key (keys %$innerhash) {
	$result->{$key} = $innerhash->{$key}{value};
    }
    return $result;
}

1;

