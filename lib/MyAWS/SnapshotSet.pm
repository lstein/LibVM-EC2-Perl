package MyAWS::Object::SnapshotSet;

use strict;

use XML::Simple;
use URI::Escape;

use constant ObjectRegistration => {
    DescribeSnapshots => 'MyAWS::Object::SnapshotSet'
};

sub new {
    my $self     = shift;
    my $payload = shift;
    return bless {
	payload => $payload,
    },ref $self || $self;
}

sub payload {shift->{payload}}

sub class_from_response {
    my $self     = shift;
    my $response = shift;
    my ($action) = $response->request->content =~ /Action=([^&]+)/;
    $action      = uri_unescape($action);
    return ObjectRegistration->{$action} || ref $self;
}

sub response2objects {
    my $self     = shift;
    my $response = shift;
    my $class    = $self->class_from_response($response);
    my $parser   = $class->new();
    $parser->parse($response->decoded_content);
}

sub parser { 
    shift->{xml_parser} ||=  $self->new_xml_parser;
}

sub parse {
    my $self    = shift;
    my $content = shift;
    $self       = $self->new unless ref $self;
    my $parsed  = $self->parser->XMLin($content);
    return $self->create_objects($parsed);
}

sub new_xml_parser {
    my $self = shift;
    return XML::Simple->new(ForceArray=>['item']);
}

sub create_objects {
    my $self   = shift;
    my $parsed = shift;
    return $self->new($parsed);
}

sub requestId {
    shift->payload->{requestId};
}

sub xmlns {
    shift->payload->{xmlns};
}




1;

