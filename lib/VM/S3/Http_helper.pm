package VM::S3::Http_helper;

use strict;
use Carp 'croak';

# utility class for http requests

# Shame on AnyEvent::HTTP! Doesn't correctly support 100-continue, which we need!
# BUG: put this into its own module
use constant MAX_RECURSE => 5;
use constant CRLF        => "\015\012";
use constant CRLF2       => CRLF.CRLF;

my %_cached_handles;
sub submit_http_request {
    my $self    = shift;
    my ($req,$cv,$state) = @_;

    # force the request into shape
    my $request = $req->clone();
    $request->header(Host   => $request->uri->host) unless $request->header('Host');
 
    # state variables for recursion handling
    $cv               ||= $self->condvar;
    $state            ||= {};
    $state->{recurse}   = MAX_RECURSE unless exists $state->{recurse};
    if ($state->{recurse} <= 0) {
	$self->error(VM::EC2::Error->new({Message=>'too many redirects',Code=>500},$self));
	$cv->send();
	return $cv;
    }
    $state->{request}  ||= $request;
    $state->{response} ||= undef;

    my $uri      = $request->uri;
    my $method   = $request->method;
    my $headers  = $request->headers->as_string;
    my $host     = $uri->host;
    my $scheme   = $uri->scheme;
    my $resource = $uri->path;
    my $port     = $uri->port;
    my $tls      = $scheme eq 'https';

    # BUG: ignore http proxy environment variable
    my $handle = $self->_get_http_handle($host,$port,$tls,$cv);
    
    # do the writes
    $handle->push_write("PUT $resource HTTP/1.1".CRLF);
    $handle->push_write($headers.CRLF);  # headers already has a crlf, so we get two

    # read the status line & headers
    $handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($cv,$state,@_)});

    return $cv;
}

sub _get_http_handle {
    my $self = shift;
    my ($host,$port,$tls,$cv) = @_;

    if ($_cached_handles{$host,$port}) {
	return $_cached_handles{$host,$port} unless $_cached_handles{$host,$port}->destroyed;
    }

    my $handle; 
    $handle = AnyEvent::Handle->new(connect => [$host,$port],
				    $tls ? (tls=>'connect') : (),

				    on_eof => sub {$handle->destroy()},

				    on_error => sub {
					my ($handle,$fatal, $message) = @_;
					warn "ERROR $message";
					$self->error(VM::EC2::Error->new({Message=>$message,Code=>500},$self));
					$handle->destroy();
					$cv->send();
				    }
	);

    return $_cached_handles{$host,$port} = $handle;
}

sub _handle_http_headers {
    my $self = shift;
    my ($cv,$state,$handle,$str) = @_;
    my $response = HTTP::Response->parse($str);

    $state->{response} = $response;
    # handle continue
    if ($response->code == 100) {
	$handle->push_write($state->{request}->content);
	$handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($cv,$state,@_)});	
    } 

    # handle counted content
    elsif (my $len = $response->header('Content-Length')) {
	$state->{length} = $len;
	$handle->on_read(sub {$self->_handle_http_body($cv,$state,@_)} );
    } 

    # handle chunked content
    elsif ($response->header('Transfer-Encoding') =~ /\bchunked\b/) {
	$handle->push_read(line=>CRLF,sub {$self->_handle_http_chunk_header($cv,$state,@_)});
    }

    # no content, just finish up
    else {
	$self->_handle_http_finish($cv,$state);
    }
}

sub _handle_http_body {
    my $self = shift;
    my ($cv,$state,$handle) = @_;
    my $headers = $state->{response} or croak "garbled body"; # BUG: report error properly
    my $data    = $handle->rbuf;
    $state->{body} .= $data;
    $handle->rbuf = '';
    $state->{length} -= length $data;
    $self->_handle_http_finish($cv,$state) if $state->{length} <= 0;
}


sub _handle_http_chunk_header {
    my $self = shift;
    my ($cv,$state,$handle,$str) = @_;
    $str =~ /^([0-9a-fA-F]+)/ or croak "garbled body"; # BUG: report error properly
    my $chunk_len = hex $1;
    if ($chunk_len > 0) {
	$state->{length} = $chunk_len + 2;  # extra CRLF terminates chunk
	$handle->push_read(chunk=>$state->{length}, sub {$self->_handle_http_chunk($cv,$state,@_)});
    } else {
	$handle->push_read(line=>CRLF, sub {$self->_handle_http_finish($cv,$state,$handle)});
    }
}

sub _handle_http_chunk {
    my $self = shift;
    my ($cv,$state,$handle,$str) = @_;
    $state->{length} -= length $str;

    local $/ = CRLF;
    chomp($str);
    $state->{body}   .= $str;

    if ($state->{length} > 0) { # more to fetch
	$handle->push_read(chunk=>$state->{length}, sub {$self->_handle_http_chunk($cv,$state,@_)});
    } else { # next chunk
	$handle->push_read(line=>CRLF,sub {$self->_handle_http_chunk_header($cv,$state,@_)});
    }

}

sub _handle_http_finish {
    my $self = shift;
    my ($cv,$state,$handle) = @_;
    my $response = $state->{response} or croak "something wrong"; # BUG: report properly
    if ($response->is_redirect) {
	my $location = $response->header('Location');
	my $uri = URI->new($location);
	$state->{request}->uri($uri);
	$state->{request}->header(Host => $uri->host);
	$state->{recurse}--;
	$self->submit_http_request($state->{request},$cv,$state);
    } else {
	$response->content($state->{body});
	$cv->send($response);
    }
    $handle->destroy() if $response->header('Connection') eq 'close';
}

1;
