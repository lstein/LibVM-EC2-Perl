package MyAWS::Object::Base;

use strict;
use Carp 'croak';
use Data::Dumper;

our $AUTOLOAD;
$Data::Dumper::Terse++;
$Data::Dumper::Indent=1;

use overload
    '""'     => sub {my $self = shift;
		     if ($self->can('primary_id')) {
			 return $self->primary_id;
		     } else {
			 return overload::StrVal($self);
		     }
                  },
    fallback => 1;

sub new {
    my $self = shift;
    @_ == 2 or croak "Usage: $self->new(\$data,\$aws)";
    my ($data,$aws) = @_;
    return bless {data => $data,
		  aws  => $aws,
    },ref $self || $self;
}

sub aws {
    my $self = shift;
    my $d    = $self->{aws};
    $self->{aws} = shift if @_;
    $d;
}

sub add_tags {
    my $self = shift;
    my $taglist = ref $_[0] && ref $_[0] eq 'HASH' ? shift : {@_};
    $self->can('primary_id') or croak "You cannot tag objects of type ",ref $self;
    $self->aws->create_tags(-resource_id => $self->primary_id,
			    -tag         => $taglist);
}

# various ways of deleting tags
#
# delete Foo tag if it has value "bar" and Buzz tag if it has value 'bazz'
# $i->delete_tags({Foo=>'bar',Buzz=>'bazz'})  
#
# same as above
# $i->delete_tags(Foo=>'bar',Buzz=>'bazz')  
#
# delete Foo tag if it has any value, Buzz if it has value 'bazz'
# $i->delete_tags({Foo=>undef,Buzz=>'bazz'})
#
# delete Foo and Buzz tags unconditionally
# $i->delete_tags(['Foo','Buzz'])
#
# delete Foo tag unconditionally
# $i->delete_tags('Foo');

sub delete_tags {
    my $self = shift;
    my $taglist;

    if (ref $_[0]) {
	if (ref $_[0] eq 'HASH') {
	    $taglist = shift;
	} elsif (ref $_[0] eq 'ARRAY') {
	    $taglist = {map {$_=>undef} @{$_[0]} };
	}
    } else {
	if (@_ == 1) {
	    $taglist = {shift()=>undef};
	} else {
	    $taglist = {@_};
	}
    }

    $self->can('primary_id') or croak "You cannot delete tags from objects of type ",ref $self;
    $self->aws->delete_tags(-resource_id => $self->primary_id,
			    -tag         => $taglist);
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

sub fields    { shift->valid_fields }
sub as_string {
    my $self = shift;
    return Dumper($self->{data});
}

1;

