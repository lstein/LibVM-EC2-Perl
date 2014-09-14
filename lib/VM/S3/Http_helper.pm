package VM::S3::Http_helper;

use strict;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use AWS::Signature4;

# utility class for http requests; forms a virtual base class for VM::S3

# Shame on AnyEvent::HTTP! Doesn't correctly support 100-continue, which we need!
use constant MAX_RECURSE    => 5;
use constant CRLF           => "\015\012";
use constant CRLF2          => CRLF.CRLF;
use constant CHUNK_SIZE    => 65536; # 64K
#use constant CHUNK_SIZE    => 8192; # 8K

# chunk metadata overhead calculation
use constant SHA256_HEX_LEN => 64;
use constant CHUNK_SIG_LEN  => length(';chunk-signature=');

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

    my $completion = $state->{on_complete};

    # BUG: ignore http proxy environment variable
    my $handle = $self->_get_http_handle($host,$port,$tls,$cv);
    
    # do the writes
    $handle->push_write("$method $resource HTTP/1.1".CRLF);
    $handle->push_write($headers.CRLF);  # headers already has a crlf, so we get two here

    $self->_push_body_writes($cv,$state,$handle) unless $request->header('Expect') eq '100-continue';

    # read the status line & headers
    $handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($cv,$state,@_)});

    return $cv;
}

sub _get_http_handle {
    my $self = shift;
    my ($host,$port,$tls,$cv) = @_;

    my $handle;

    if (my $ch = $_cached_handles{$host,$port}) {
	$handle = $ch if $ch->ping;
    }

    $handle ||= AnyEvent::PingHandle->new(connect => [$host,$port],
					  $tls ? (tls=>'connect') : (),
					  on_connect=>sub {warn "new connection to $host:$port"});
    
    $handle->on_eof(sub {my $h = shift; warn "EOF! residual= $h->{rbuf}",$h->destroy()}),
    $handle->on_error(sub {
	my ($handle,$fatal,$message) = @_;
	warn "EROR! $message";
	$self->_handle_http_error($cv,$handle,$message,599);
		      });
    return $_cached_handles{$host,$port} = $handle;
}

sub _handle_http_error {
    my $self = shift;
    my ($cv,$handle,$message,$code) = @_;
    $self->error(VM::EC2::Error->new({Message=>$message,Code=>$code},$self));    
    $handle->destroy();
    $cv->send();
    1;
}

sub _handle_http_headers {
    my $self = shift;
    my ($cv,$state,$handle,$str) = @_;
    my $response = HTTP::Response->parse($str);

    if (my $cb = $state->{on_header}) { $cb->($response->headers) }

    $state->{response} = $response;
    # handle continue
    if ($response->code == 100) {
	$self->_push_body_writes($cv,$state,$handle);
	$handle->push_read (line => CRLF2,sub {$self->_handle_http_headers($cv,$state,@_)});	
    } 

    # handle counted content
    elsif (my $len = $response->header('Content-Length')) {
	$state->{length} = $len;
	$handle->on_read(sub {$self->_handle_http_body($cv,$state,@_)} );
    } 

    # handle chunked content
    elsif ($response->header('Transfer-Encoding') =~ /\bchunked\b/) {
	$handle->push_read(line=>CRLF,
			   sub {$self->_handle_http_chunk_header($cv,$state,@_)});
    }

    # no content, just finish up
    else {
	$self->_handle_http_finish($cv,$state,$handle);
    }
}

sub _handle_http_body {
    my $self = shift;
    my ($cv,$state,$handle) = @_;

    my $response = $state->{response} 
       or $self->_handle_http_error($cv,$handle,"garbled http body",500) && return;

    if (my $cb = $state->{on_body}) { 
	$cb->($handle->rbuf,$response->headers);
    } else {
	$state->{body} .= $handle->{rbuf};
    }
    
    $state->{length} -= length $handle->{rbuf};
    
    $self->_on_read_chunk_callback(length $handle->rbuf,$state);

    $handle->rbuf = '';
    $self->_handle_http_finish($cv,$state,$handle) if $state->{length} <= 0;
}


sub _handle_http_chunk_header {
    my $self = shift;
    my ($cv,$state,$handle,$str) = @_;
    $str =~ /^([0-9a-fA-F]+)/  or $self->_handle_http_error($cv,$handle,"garbled http chunk",500) && return;
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

    $self->_on_read_chunk_callback(length $str,$state);

}

sub _handle_http_finish {
    my $self = shift;
    my ($cv,$state,$handle) = @_;
    my $response = $state->{response} 
                   or $self->_handle_http_error($cv,$handle,"no header seen in response",500) && return;

    if ($response->is_redirect) {
	my $location = $response->header('Location');
	my $uri = URI->new($location);
	my $previous      = $state->{request};
	$state->{request} = $previous->clone;
	$state->{request}->previous($previous);
	$state->{request}->uri($uri);
	$state->{request}->header(Host => $uri->host);
	$state->{recurse}--;
	$self->submit_http_request($state->{request},$cv,$state);

    } elsif ($response->is_error) {
	my $error = VM::EC2::Dispatch->create_error_object($state->{body},$self,'put object');
	$cv->error($error);
	$cv->send();
    }

    else {
	$self->error(undef);
	$response->content($state->{body});
	$cv->send($response);
    }

    if ($response->header('Connection') eq 'close') {
	$handle->destroy();
    }

    # run completion routine - we pass headers as a hash in order to be compatible with AnyEvent::HTTP callbacks
    $self->_run_completion_routine($response,$state->{on_complete}) if $state->{on_complete};
}

sub _run_completion_routine {
    my $self = shift;
    my ($response,$cb) = @_;
    my %hdr;
    $response->headers->scan(sub {
	my ($k,$v) = @_;
	if (exists $hdr{$k}) { $hdr{$k} .= ", $v" }
	else                 { $hdr{$k}  = $v     }
			     });
    $hdr{Status} = $response->code;
    $cb->($response->content,\%hdr) 
}

sub _push_body_writes {
    my $self = shift;
    my ($cv,$state,$handle) = @_;
    my $content     = eval{$state->{request}->content} or return;

    if ($self->_stream_size($content)) {
	$self->_chunked_http_write($cv,$state,$handle);
    } else {
	$handle->push_write($content);
    }
}

sub _chunked_http_write {
    my $self = shift;
    my ($cv,$state,$handle) = @_;
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
	$self->_chunked_write_from_callback($cv,$state,$handle,$fh_or_callback);
    } elsif ($fh_or_callback->isa('GLOB')) {
	$self->_chunked_write_from_fh($cv,$state,$handle,$fh_or_callback);
    }
}

sub _chunked_write_from_fh {
    my $self = shift;
    my ($cv,$state,$handle,$fh) = @_;

    my $do_last_chunk = sub { my $rh = shift;
			      $self->_write_chunk($cv,$state,$handle,$rh->{rbuf});
			      $self->_write_chunk($cv,$state,$handle,'');  # last chunk
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
		$self->_handle_http_error($cv,$read_handle,$message,599); # keep $read_handle in scope!
		$rh->destroy;
	    }
	 },
	 on_eof => $do_last_chunk
	 );

    $handle->on_drain(sub {
	$read_handle->push_read(chunk => CHUNK_SIZE,
				sub {
				    my ($rh,$data) = @_;
				    $self->_write_chunk($cv,$state,$handle,$data);
				});
		      });
}

sub _chunked_write_from_callback {
    my $self = shift;
    my ($cv,$state,$handle,$cb) = @_;

    $state->{cb_buffer} = '';

    $handle->on_drain(
	sub {
	    my $data = $cb->(CHUNK_SIZE);
	    if (length $data == 0) {
		$self->_write_chunk($cv,$state,$handle,$state->{cb_buffer});
		$self->_write_chunk($cv,$state,$handle,'');
	    } else {
		$state->{cb_buffer} .= $data;
		$self->_write_chunk($cv,$state,$handle,substr($state->{cb_buffer},0,CHUNK_SIZE,''));
	    }
	});
}

sub _write_chunk {
    my $self = shift;
    my ($cv,$state,$handle,$data) = @_;

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

#    warn "chunk #",$state->{signature}{chunkno}++||0,": $chunk_metadata";

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

package AnyEvent::PingHandle;
use base 'AnyEvent::Handle';

sub ping {
    my $self   = shift;
    my $fileno = fileno($self->fh);
    my $fbits = '';
    vec($fbits,$fileno,1)=1;
    my $nfound = select($fbits, undef, undef, 0);
    return $nfound <= 0;
}


1;
