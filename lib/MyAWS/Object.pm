package MyAWS::Object;

use strict;

use XML::Simple;
use URI::Escape;

use constant ObjectRegistration => {
    Error             => 'MyAWS::Object::Error',
    DescribeInstances => 'MyAWS::Object::InstanceSet',
    DescribeSnapshots => 'fetch_items,snapshotSet,MyAWS::Object::Snapshot',
    DescribeVolumes   => 'fetch_items,volumeSet,MyAWS::Object::Volume',
    DescribeImages    => 'fetch_items,imagesSet,MyAWS::Object::Image',
    StartInstances    => 'fetch_items,instancesSet,MyAWS::Object::InstanceStateChange',
    StopInstances     => 'fetch_items,instancesSet,MyAWS::Object::InstanceStateChange',
    DescribeRegions   => 'fetch_items,regionInfo,MyAWS::Object::Region',
    DescribeTags      => 'fetch_items,tagSet,MyAWS::Object::Tag,nokey',
    GetConsoleOutput  => 'fetch_one,MyAWS::Object::ConsoleOutput',
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

    my $class    = $self->class_from_response($response) or return;
    my $content  = $response->decoded_content;

    if ($class =~ /,/) {
	my ($method,@params) = split /,/,$class;
	return $self->$method($aws,$content,@params);
    } else {
	eval "require $class; 1" || die $@ unless $class->can('new');
	my $parser   = $self->new();
	$parser->parse($content,$aws,$class);
    }
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
    my $self  = shift;
    my $nokey = shift;
    return XML::Simple->new(ForceArray    => ['item'],
			    KeyAttr       => $nokey ? [] : ['key'],
			    SuppressEmpty => undef,
	);
}

sub fetch_one {
    my $self = shift;
    my ($aws,$content,$class,$nokey) = @_;
    eval "require $class; 1" || die $@ unless $class->can('new');    
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    return $class->new($parsed,$aws);
}

sub fetch_items {
    my $self = shift;
    my ($aws,$content,$tag,$class,$nokey) = @_;
    eval "require $class; 1" || die $@ unless $class->can('new');
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    my $list   = $parsed->{$tag}{item} or return;
    return map {$class->new($_,$aws)} @$list;
}

sub create_objects {
    my $self   = shift;
    my ($parsed,$aws,$class) = @_;
    return $class->new($parsed,$aws);
}

sub create_error_object {
    my $self = shift;
    my ($content,$aws) = @_;
    my $class   = ObjectRegistration->{Error};
    eval "require $class; 1" || die $@ unless $class->can('new');
    my $parsed = $self->new_xml_parser->XMLin($content);
    return $class->new($parsed->{Errors}{Error},$aws);
}

sub requestId {
    shift->payload->{requestId};
}

sub xmlns {
    shift->payload->{xmlns};
}




1;

