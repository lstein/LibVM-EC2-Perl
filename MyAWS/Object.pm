package MyAWS::Object;

use strict;

use XML::Simple;
use URI::Escape;

use constant ObjectRegistration => {
    DescribeSnapshots => 'MyAWS::Object::SnapshotSet',
    DescribeInstances => 'MyAWS::Object::InstanceSet',
    DescribeVolumes   => 'MyAWS::Object::VolumeSet',
    DescribeImages    => 'MyAWS::Object::ImageSet',
    StartInstances    => 'MyAWS::Object::InstanceStateChangeSet',
    StopInstances     => 'MyAWS::Object::InstanceStateChangeSet',
};

sub new {
    my $self    = shift;
    my $payload = shift;
    return bless {
	payload => $payload,
    },ref $self || $self;
}

sub response2objects {
    my $self     = shift;
    my ($response,$aws) = @_;

    my $class    = $self->class_from_response($response);
    eval "require $class; 1" || die $@ unless $class->can('new');
    my $parser   = $self->new();

    $parser->parse($response->decoded_content,$aws,$class);
}

sub payload {shift->{payload}}

sub class_from_response {
    my $self     = shift;
    my $response = shift;
    my ($action) = $response->request->content =~ /Action=([^&]+)/;
    $action      = uri_unescape($action);
    return ObjectRegistration->{$action} || ref $self || $self;
}

sub parser { 
    my $self = shift;
    return $self->{xml_parser} ||=  $self->new_xml_parser;
}

sub parse {
    my $self    = shift;
    my ($content,$aws,$class) = @_;
    $self       = $self->new unless ref $self;
    my $parsed  = $self->parser->XMLin($content);
    return $self->create_objects($parsed,$aws,$class);
}

sub new_xml_parser {
    my $self = shift;
    return XML::Simple->new(ForceArray    => ['item'],
			    KeyAttr       => ['key'],
			    SuppressEmpty => undef,
	);
}

sub create_objects {
    my $self   = shift;
    my ($parsed,$aws,$class) = @_;
    return $class->new($parsed,$aws);
}

sub requestId {
    shift->payload->{requestId};
}

sub xmlns {
    shift->payload->{xmlns};
}




1;

