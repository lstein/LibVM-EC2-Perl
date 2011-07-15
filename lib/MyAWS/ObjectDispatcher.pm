package MyAWS::ObjectDispatcher;

use strict;

use XML::Simple;
use URI::Escape;

=head1 NAME

MyAWS::ObjectDispatcher - Create Perl objects from AWS XML requests

=head1 SYNOPSIS

  use MyAWS;

  MyAWS::ObjectDispatcher->add_override('DescribeRegions'=>\&mysub);

  MyAWS::ObjectDispatcher->add_override('DescribeTags'=>'My::Object::Type');
  
  sub mysub {
      my ($parsed_xml_object,$aws) = @_;
      my $payload = $parsed_xml_object->{regionInfo}
      return My::Object::Type->new($payload,$aws);
  }

=head1 DESCRIPTION

This class handles turning the XML response to AWS requests into perl
objects. Only one method is likely to be useful to developers, the
add_override() class method. This allows you to replace the built-in
request to object mapping with your own objects.

=head2 MyAWS::ObjectDispatcher->add_override($request_name => \&sub)
=head2 MyAWS::ObjectDispatcher->add_override($request_name => 'Class::Name')

Before invoking a MyAWS request you wish to customize, call the
add_override() method with two arguments. The first argument is the
name of the request you wish to customize, such as
"DescribeVolumes". The second argument is either a code reference, or
a string containing a class name.

In the case of a code reference as the second argument, the subroutine
you provide will be invoked with two arguments consisting of the
parsed XML response and the MyAWS object.

In the case of a string containing a classname, the class will be
loaded if it needs to be, and then its new() method invoked as
follows:

  Your::Class->new($parsed_xml,$aws)

Your new() method should return one or more objects.

In either case, the parsed XML response will have been passed through
XML::Simple with the options:

  $parser = XML::Simple->new(ForceArray    => ['item'],
                             KeyAttr       => ['key'],
                             SuppressEmpty => undef);
  $parsed = $parser->XMLin($raw_xml)

In general, this will give you a hash of hashes. Any tag named 'item'
will be forced to point to an array reference, and any tag named "key"
will be flattened as described in the XML::Simple documentation.

A simple way to examine the raw parsed XML is to invoke any
MyAWS::Object's as_string method:

 my ($i) = $aws->describe_instances;
 print $i->as_string;

This will give you a Data::Dumper representation of the XML after it
has been parsed.

=cut

my %OVERRIDE;

use constant ObjectRegistration => {
    Error             => 'MyAWS::Object::Error',
    DescribeInstances => sub { load_module('MyAWS::Object::ReservationSet');
			       my $r = MyAWS::Object::ReservationSet->new(@_) or return;
			       return $r->instances;
    },
    RunInstances      => sub { load_module('MyAWS::Object::Instance::Set');
			       my $s = MyAWS::Object::Instance::Set->new(@_) or return;
			       return $s->instances;
    },
    DescribeSnapshots => 'fetch_items,snapshotSet,MyAWS::Object::Snapshot',
    DescribeVolumes   => 'fetch_items,volumeSet,MyAWS::Object::Volume',
    DescribeImages    => 'fetch_items,imagesSet,MyAWS::Object::Image',
    DescribeRegions   => 'fetch_items,regionInfo,MyAWS::Object::Region',
    DescribeSecurityGroups   => 'fetch_items,securityGroupInfo,MyAWS::Object::SecurityGroup',
    DescribeTags      => 'fetch_items,tagSet,MyAWS::Object::Tag,nokey',
    CreateTags        => 'boolean,return',
    DeleteTags        => 'boolean,return',
    StartInstances       => 'fetch_items,instancesSet,MyAWS::Object::Instance::State::Change',
    StopInstances        => 'fetch_items,instancesSet,MyAWS::Object::Instance::State::Change',
    TerminateInstances   => 'fetch_items,instancesSet,MyAWS::Object::Instance::State::Change',
    GetConsoleOutput  => 'fetch_one,MyAWS::Object::ConsoleOutput',
};

sub new {
    my $self    = shift;
    my $payload = shift;
    return bless {
	payload => $payload,
    },ref $self || $self;
}

sub add_override {
    my $self = shift;
    my ($request_name,$object_creator) = @_;
    $OVERRIDE{$request_name} = $object_creator;
}

sub response2objects {
    my $self     = shift;
    my ($response,$aws) = @_;

    my $class    = $self->class_from_response($response) or return;
    my $content  = $response->decoded_content;

    if (ref $class eq 'CODE') {
	my $parsed = $self->new_xml_parser->XMLin($content);
	$class->($parsed,$aws,@{$parsed}{'xmlns','requestId'});
    }
    elsif ($class =~ /^MyAWS::Object/) {
	load_module($class);
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
    return $OVERRIDE{$action} || ObjectRegistration->{$action} || 'MyAWS::Object::Generic';
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
    load_module($class);
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    return $class->new($parsed,$aws,@{$parsed}{'xmlns','requestId'});
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
    load_module($class);
    my $parser = $self->new_xml_parser($nokey);
    my $parsed = $parser->XMLin($content);
    my $list   = $parsed->{$tag}{item} or return;
    return map {$class->new($_,$aws,@{$parsed}{'xmlns','requestId'})} @$list;
}

sub create_objects {
    my $self   = shift;
    my ($parsed,$aws,$class) = @_;
    return $class->new($parsed,$aws,@{$parsed}{'xmlns','requestId'});
}

sub create_error_object {
    my $self = shift;
    my ($content,$aws) = @_;
    my $class   = ObjectRegistration->{Error};
    eval "require $class; 1" || die $@ unless $class->can('new');
    my $parsed = $self->new_xml_parser->XMLin($content);
    return $class->new($parsed->{Errors}{Error},$aws,@{$parsed}{'xmlns','requestId'});
}

# not a method!
sub load_module {
    my $class = shift;
    eval "require $class; 1" || die $@ unless $class->can('new');
}

=head1 SEE ALSO

L<MyAWS>
L<MyAWS::Object>
L<MyAWS::Object::Base>
L<MyAWS::Object::BlockDevice>
L<MyAWS::Object::BlockDevice::Attachment>
L<MyAWS::Object::BlockDevice::Mapping>
L<MyAWS::Object::BlockDevice::Mapping::EBS>
L<MyAWS::Object::ConsoleOutput>
L<MyAWS::Object::Error>
L<MyAWS::Object::Generic>
L<MyAWS::Object::Group>
L<MyAWS::Object::Image>
L<MyAWS::Object::Instance>
L<MyAWS::Object::Instance::Set>
L<MyAWS::Object::Instance::State>
L<MyAWS::Object::Instance::State::Change>
L<MyAWS::Object::Instance::State::Reason>
L<MyAWS::Object::Region>
L<MyAWS::Object::ReservationSet>
L<MyAWS::Object::SecurityGroup>
L<MyAWS::Object::Snapshot>
L<MyAWS::Object::Tag>
L<MyAWS::Object::Volume>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;

