package VM::EC2::Http_helper;

use strict;
use HTTP::Response;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use AWS::Signature4;
use AnyEvent::Util;
use Carp 'croak';

# utility class for http requests; forms a virtual base class for VM::S3

# Shame on AnyEvent::HTTP! Doesn't correctly support 100-continue, which we need!
use constant MAX_RECURSE    => 5;
use constant CRLF           => "\015\012";
use constant CRLF2          => CRLF.CRLF;
use constant CHUNK_SIZE    => 65536; # 64K
use constant TIMEOUT       => 30;
#use constant CHUNK_SIZE    => 8192; # 8K
use constant DEBUG => 0;
use constant DEBUG_CONNECTION => 0;

# chunk metadata overhead calculation
use constant SHA256_HEX_LEN => 64;
use constant CHUNK_SIG_LEN  => length(';chunk-signature=');

sub submit_http_request {
    my $self    = shift;
    my ($req,$cb,$state) = @_;

    # force the request into shape
    my $request = $req->clone();
    $request->header(Host   => $request->uri->host) unless $request->header('Host');

    warn $request->as_string if DEBUG;

    # state variables for recursion handling
    $state                ||= {};
    $state->{recurse}       = MAX_RECURSE unless exists $state->{recurse};
    $state->{_recurse}      = $state->{recurse};
    $state->{request}     ||= $request;
    $state->{response}    ||= undef;
    $state->{on_complete} ||= $cb;

    my $uri      = $request->uri;
    my $method   = $request->method;
    my $headers  = $request->headers->as_string;
    my $host     = $uri->host;
    my $scheme   = $uri->scheme;
    my $resource = $uri->path_query || '/';
    my $port     = $uri->port;

    $resource = $uri if $scheme eq 'http' && $self->get_proxy($scheme,$host);

    my $conversation = sub {
	my $handle = shift;

	# do the writes
	$handle->push_write("$method $resource HTTP/1.1".CRLF);
	$handle->push_write($headers.CRLF);  # headers already has a crlf, so we get two here

	$self->_push_body_writes($state,$handle) unless $request->header('Expect') eq '100-continue';

	# read the status line & headers
	$handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($state,@_)});
    };

    my $handle = $self->_run_request($state,$host,$port,$scheme,$conversation);
    return wantarray && AnyEvent::Util::guard { 
	$handle->destroy(); 
	$self->_handle_http_error($state,$handle,'request cancelled by user',599)};
}

sub env_proxy {
    my $self = shift;
    for my $e (keys %ENV) {
	next unless $e =~ /(\w+)_proxy$/i;
	$self->proxy(lc $1,$ENV{$e});
    }
}

sub proxy {
    my $self = shift;
    # setting proxy
    croak 'usage: ',ref($self),'->proxy($scheme,$url)' unless @_ >= 2;
    my ($schemes,$url) = @_;
    my @s = ref $schemes ? @$schemes : ($schemes);
    for my $s (@s) {
	$self->{proxies}{$s} = $url;
    }
}

sub get_proxy {
    my $self = shift;
    my ($scheme,$host) = @_;
    my $proxy = $self->{proxies}{$scheme};
    return unless $proxy;

    my $no_proxy = $self->{proxies}{no} || '';
    return if $no_proxy =~ /\b$host\b/;

    return URI->new($proxy);
}

sub _run_request {
    my $self = shift;
    my ($state,$host,$port,$scheme,$conversation) = @_;

    my $proxy  = $self->get_proxy($scheme,$host);
    my $tls    = $proxy ? $proxy->scheme eq 'tls' : $scheme eq 'https';

    my $handle = AnyEvent::PoolHandle->new(connect => [$host,$port],
					   $proxy ? (proxy   => [$proxy->host,$proxy->port]) : (),
					   $tls   ? (tls=>'connect')                         : (),
					   on_connect => sub {my $handle = shift;
							      warn "connecting $handle to $host:$port via ",$proxy||'no proxy' 
								  if DEBUG || DEBUG_CONNECTION},
	);

    $handle->on_eof(sub {
	my $h = shift; 
	$h->destroy()}),

    $handle->on_error(sub {
	my ($handle,$fatal,$message) = @_;
	$self->_handle_http_error($state,$handle,$message,599)});

    # run CONNECT conversation
    if ($proxy && $scheme eq 'https' && $handle->is_new) {
	$handle->push_write("CONNECT $host:$port HTTP/1.1".CRLF2);
	$handle->push_read(line => CRLF2,sub {
	    my ($handle,$str) = @_;
	    my $r = HTTP::Response->parse($str);
	    $self->_handle_http_error($state,$handle,$r->code,$r->message)
		unless $r->is_success;
	    if ($scheme eq 'https' && !exists $handle->{tls}) {
		$handle->starttls('connect');
		$conversation->($handle);
	    }});
    }

    else {
	$conversation->($handle);
    }
}

sub _handle_http_error {
    my $self = shift;
    my ($state,$handle,$message,$code) = @_;
    my $response = $state->{response} ||= HTTP::Response->new($code,$message);
    $handle->finished();
    $state->{on_complete}->($response) if $state->{on_complete};
}

sub _handle_http_headers {
    my $self = shift;
    my ($state,$handle,$str) = @_;
    my $response = HTTP::Response->parse($str);

    warn $str if DEBUG;

    if (my $cb = $state->{on_header}) { $cb->($response->headers) }

    $state->{response} = $response;
    # handle continue
    if ($response->code == 100) {
	$self->_push_body_writes($state,$handle);
	$handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($state,@_)});	
    } 

    elsif ($state->{request}->method =~ /HEAD/i) { # ignore body
	$self->_handle_http_finish($state,$handle);
    }

    # handle counted content
    elsif (my $len = $response->header('Content-Length')) {
	$state->{length} = $len;
	$handle->on_read(sub {$self->_handle_http_body($state,@_)} );
    } 

    # handle chunked content
    elsif ($response->header('Transfer-Encoding') =~ /\bchunked\b/) {
	$handle->push_read(line=>CRLF,
			   sub {$self->_handle_http_chunk_header($state,@_)});
    }

    elsif ($response->header('Content-length') == 0) {
	$self->_handle_http_finish($state,$handle);
    }

    # no content or transfer encoding! - read till end
    else {
	$handle->on_read(sub {$self->_handle_http_body($state,@_)});
    }
}

sub _handle_http_body {
    my $self = shift;
    my ($state,$handle) = @_;

    my $response = $state->{response} 
       or $self->_handle_http_error($state,$handle,"garbled http body",500) && return;

    if (my $cb = $state->{on_body}) { 
	$cb->($handle->rbuf,$response->headers);
    } else {
	$state->{body} .= $handle->{rbuf};
    }
    
    $state->{length} -= length $handle->{rbuf};
    
    $self->_on_read_chunk_callback(length $handle->rbuf,$state);

    $handle->rbuf = '';
    $self->_handle_http_finish($state,$handle) if $state->{length} <= 0;
}


sub _handle_http_chunk_header {
    my $self = shift;
    my ($state,$handle,$str) = @_;
    warn "chunk header: $str" if DEBUG;
    $str =~ /^([0-9a-fA-F]+)/  or $self->_handle_http_error($state,$handle,"garbled http chunk",500) && return;
    my $chunk_len = hex $1;
    if ($chunk_len > 0) {
	$state->{length} = $chunk_len + 2;  # extra CRLF terminates chunk
	$handle->push_read(chunk=>$state->{length}, sub {$self->_handle_http_chunk($state,@_)});
    } else {
	$handle->push_read(line=>CRLF, sub {$self->_handle_http_finish($state,$handle)});
    }
}

sub _handle_http_chunk {
    my $self = shift;
    my ($state,$handle,$str) = @_;

    warn "chunk body: $str" if DEBUG;
    $state->{length} -= length $str;

    local $/ = CRLF;
    chomp($str);
    $state->{body}   .= $str;

    if ($state->{length} > 0) { # more to fetch
	$handle->push_read(chunk=>$state->{length}, sub {$self->_handle_http_chunk($state,@_)});
    } else { # next chunk
	$handle->push_read(line=>CRLF,sub {$self->_handle_http_chunk_header($state,@_)});
    }

    $self->_on_read_chunk_callback(length $str,$state);

}

sub _handle_http_finish {
    my $self = shift;
    my ($state,$handle) = @_;
    my $response = $state->{response} 
                   or $self->_handle_http_error($state,$handle,"no header seen in response",500) && return;

    $response->content($state->{body});

    if ($response->is_redirect) {
	if ($state->{recurse} > 0) {
	    my $location = $response->header('Location');
	    my $uri = URI->new($location);
	    my $previous      = $state->{request};
	    $state->{request} = $previous->clone;
	    $state->{response}->previous($previous);
	    $state->{request}->uri($uri);
	    $state->{request}->header(Host => $uri->host);
	    $state->{_recurse}--;
	    $self->submit_http_request($state->{request},undef,$state);
	} else {
	    $state->{on_complete}->($state->{response});
	}

    } elsif ($response->is_error && $state->{body}) {
	my $error = VM::EC2::Dispatch->create_error_object($state->{body},$self,'put object');
	$self->error($error);
    }

    else {
	$self->error(undef);
    }

    if ($response->header('Connection') eq 'close') {
	$handle->destroy();
    }

    # mark potentially available
    $handle->finished();

    # run completion routine
    $state->{on_complete}->($response) if $state->{on_complete};
}

sub _push_body_writes {
    my $self = shift;
    my ($state,$handle) = @_;
    my $content     = eval{$state->{request}->content} or return;

    if ($self->_stream_size($content)) {
	$self->_chunked_http_write($state,$handle);
    } else {
	$handle->push_write($content);
    }
}

sub _chunked_http_write {
    my $self = shift;
    my ($state,$handle) = @_;
    my $request = $state->{request} or return;
    my $content = $request->content or return;

    # we get here if we are uploading from a filehandle
    # using chunked transfer-encoding
    my $authorization                = $request->header('Authorization');
    $state->{signature}{timedate}    = $request->header('X-Amz-Date');
    ($state->{signature}{previous})  = $authorization =~ /Signature=([0-9a-f]+)/;
    ($state->{signature}{scope})     = $authorization =~ m!Credential=[^/]+/([^,]+),!;
    my ($date,$region,$service)      = split '/',$state->{signature}{scope};
    $state->{signature}{signing_key} = AWS::Signature4->signing_key($self->secret,$service,$region,$date);

    my ($size,$fh_or_callback) = $self->_stream_size($content);
    if (ref $fh_or_callback eq 'CODE') {
	$self->_chunked_write_from_callback($state,$handle,$fh_or_callback);
    } elsif ($fh_or_callback->isa('GLOB')) {
	$self->_chunked_write_from_fh($state,$handle,$fh_or_callback);
    }
}

sub _chunked_write_from_fh {
    my $self = shift;
    my ($state,$handle,$fh) = @_;

    my $do_last_chunk = sub { my $rh = shift;
			      $self->_write_chunk($state,$handle,$rh->{rbuf});
			      $self->_write_chunk($state,$handle,'');  # last chunk
			      delete $rh->{rbuf};
			      $rh->destroy();
    };

     my $read_handle; $read_handle = AnyEvent::Handle->new(
	fh        => $fh,
	on_error => sub {
	    my ($rh,$fatal,$message) = @_;
	    if ($message =~ /pipe/) {
		$do_last_chunk->($rh);
	    } else {
		$self->_handle_http_error($state,$read_handle,$message,599); # keep $read_handle in scope!
		$rh->destroy;
	    }
	 },
	 on_eof => $do_last_chunk
	 );

    $handle->on_drain(sub {
	$read_handle->push_read(chunk => CHUNK_SIZE,
				sub {
				    my ($rh,$data) = @_;
				    $self->_write_chunk($state,$handle,$data);
				});
		      });
}

sub _chunked_write_from_callback {
    my $self = shift;
    my ($state,$handle,$cb) = @_;

    $state->{cb_buffer} = '';

    $handle->on_drain(
	sub {
	    my $data = $cb->(CHUNK_SIZE);
	    if (length $data == 0) {
		$self->_write_chunk($state,$handle,$state->{cb_buffer});
		$self->_write_chunk($state,$handle,'');
	    } else {
		$state->{cb_buffer} .= $data;
		$self->_write_chunk($state,$handle,substr($state->{cb_buffer},0,CHUNK_SIZE,''));
	    }
	});
}

sub _write_chunk {
    my $self = shift;
    my ($state,$handle,$data) = @_;

    # first compute the chunk signature
    my $hash = sha256_hex($data);
    my $string_to_sign = join("\n",
			      'AWS4-HMAC-SHA256-PAYLOAD',
			      $state->{signature}{timedate},
			      $state->{signature}{scope},
			      $state->{signature}{previous},
			      sha256_hex(''),
			      $hash);

    my $signature = hmac_sha256_hex($string_to_sign,$state->{signature}{signing_key});
    $state->{signature}{previous} = $signature;

    my $len            = sprintf('%x',length $data);
    my $chunk_metadata = "$len;chunk-signature=$signature"; 
    my $chunk          = join (CRLF,$chunk_metadata,$data).CRLF;

    if (length $data == 0) {
	delete $state->{signature};
	$handle->on_drain(undef);
    }

    if (length($data) && (my $cb = $state->{on_write_chunk})) {
	$state->{bytes_written} += length $data;
	$cb->($state->{bytes_written},$state->{request}->header('X-Amz-Decoded-Content-Length'));
    }

    $handle->push_write($chunk);
}

sub _on_read_chunk_callback {
    my $self = shift;
    my ($data_len,$state) = @_;

    if ($data_len && (my $cb = $state->{on_read_chunk})) {
	$state->{bytes_read} += $data_len;
	$cb->($state->{bytes_read},$state->{response}->header('Content-Length'));
    }

}

sub _stream_size {
    my $self = shift;
    my $obj  = shift;
    return unless ref $obj;

    if (ref $obj eq 'ARRAY') { # [ $size => $callback ]
	my ($size,$cb) = @$obj;
	return wantarray ? ($size,$cb) : $size;
    } 

    else  {
	return unless eval {$obj->isa('GLOB')};
	my @s = stat($obj);
	defined $s[7] or return;
	return wantarray ? ($s[7],$obj) : $s[7];
    }

}

sub _chunked_encoding_overhead {
    my $self = shift;
    my $data_len       = shift;
    my $chunk_count    = int($data_len/CHUNK_SIZE);
    my $last_chunk_len = $data_len % CHUNK_SIZE;

    my $full_chunk_len = length(sprintf('%x',CHUNK_SIZE))    # length of the chunksize, in hex
	               + CHUNK_SIG_LEN                       # the ";chunk-signature=' part
                       + SHA256_HEX_LEN                      # the hmac signature
		       + length(CRLF)*2;                     # the CRLFs at the end of the signature and the chunk data

    my $final_chunk_len = length(sprintf('%x',$last_chunk_len))  # length of the chunk size
	                + CHUNK_SIG_LEN
                        + SHA256_HEX_LEN
			+ length(CRLF) * 2;

    my $terminal_chunk  = length('0')
	                + CHUNK_SIG_LEN
                        + SHA256_HEX_LEN
			+ length(CRLF) * 2;

    return $chunk_count * $full_chunk_len + $final_chunk_len + $terminal_chunk;
}

package AnyEvent::PoolHandle;
use base 'AnyEvent::Handle';

my %CONNECTION_CACHE;
my %HANDLE_AVAILABLE;

sub new {
    my $class = shift;
    my %args  = @_;

    return $class->SUPER::new(@_) unless $args{connect};

    my ($host,$port) = @{$args{connect}};

    my $ch;
    for my $h (values %{$CONNECTION_CACHE{$host,$port}}) {
	next unless $HANDLE_AVAILABLE{$h};
	if ($h->ping) {
	    $ch = $h;
	    last;
	} else {
	    warn "$h is dead, removing it from pool" if VM::EC2::Http_helper::DEBUG || VM::EC2::Http_helper::DEBUG_CONNECTION;
	    delete $CONNECTION_CACHE{$host,$port}{$h};
	    delete $HANDLE_AVAILABLE{$h};
	}
    }
    
    if ($ch) {
	delete $HANDLE_AVAILABLE{$ch};
	warn "reusing $ch for connection" if VM::EC2::Http_helper::DEBUG || VM::EC2::Http_helper::DEBUG_CONNECTION;
	return $ch;
    }
    
    $args{connect} = $args{proxy} if $args{proxy};
    my $handle = $class->SUPER::new(%args);
    return $CONNECTION_CACHE{$host,$port}{$handle} = $handle;
}

sub finished {
    my $self = shift;
    $self->{_used}++;
    warn "returning $self to pool" if VM::EC2::Http_helper::DEBUG || VM::EC2::Http_helper::DEBUG_CONNECTION;
    $HANDLE_AVAILABLE{$self}++ unless $self->destroyed;
}

sub ping {
    my $self   = shift;
    my $fileno = fileno($self->fh);
    my $fbits = '';
    vec($fbits,$fileno,1)=1;
    my $nfound = select($fbits, undef, undef, 0);
    my $success = $nfound <= 0;
    return $success;
}

sub is_new { shift->used == 0 }

sub used {
    my $self = shift;
    return $self->{_used}||0;
}


1;
