package MyAWS::Object;

use strict;

use XML::Simple;
use URI::Escape;

# two formats recognized:
# 1) A class name in form MyAWS::Object::...
#     Will return MyAWS::Object::...->new($parsed_content,$aws)
#
# 2) A comma-delimited list in format "method_name,arg1,arg2,arg3..."
#     Will call method method_name() with arguments ($content,$aws,arg1,arg2...)
#
# parsed_content is the result of calling XML::Simple->XMLin()
#
# Note that format (1) receives parsed contents (a hashref), whereas
# format (2) receives unparsed XML text.
#
# The $aws object is the MyAWS used to generate the request. Can be stored
# and used for additional requests.
#
use constant ObjectRegistration => {
    Error             => 'MyAWS::Object::Error',
    DescribeInstances => 'MyAWS::Object::ReservationSet',
    DescribeSnapshots => 'fetch_items,snapshotSet,MyAWS::Object::Snapshot',
    DescribeVolumes   => 'fetch_items,volumeSet,MyAWS::Object::Volume',
    DescribeImages    => 'fetch_items,imagesSet,MyAWS::Object::Image',
    DescribeRegions   => 'fetch_items,regionInfo,MyAWS::Object::Region',
    DescribeTags      => 'fetch_items,tagSet,MyAWS::Object::Tag,nokey',
    CreateTags        => 'boolean,return',
    DeleteTags        => 'boolean,return',
    RunInstances      => 'MyAWS::Object::Instance::Set',
    StartInstances    => 'fetch_items,instancesSet,MyAWS::Object::Instance::State::Change',
    StopInstances     => 'fetch_items,instancesSet,MyAWS::Object::Instance::State::Change',
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

    if ($class =~ /^MyAWS::Object/) {
	eval "require $class; 1" || die $@ unless $class->can('new');
	my $parser   = $self->new();
	$parser->parse($content,$aws,$class);
    } else {
	my ($method,@params) = split /,/,$class;
	return $self->$method($content,$aws,@params);
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
    my ($content,$aws,$class,$nokey) = @_;
    eval "require $class; 1" || die $@ unless $class->can('new');    
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    return $class->new($parsed,$aws);
}

sub boolean {
    my $self = shift;
    my ($content,$aws,$tag) = @_;
    my $parsed = $self->new_xml_parser()->XMLin($content);
    return $parsed->{return} eq 'true';
}

sub fetch_items {
    my $self = shift;
    my ($content,$aws,$tag,$class,$nokey) = @_;
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

