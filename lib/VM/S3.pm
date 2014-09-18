package VM::S3;

use strict;
use base 'VM::EC2';#,'VM::S3::Http_helper';
use AnyEvent::HTTP;
use AnyEvent::Handle;
use HTTP::Request::Common;
use HTTP::Response;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Digest::MD5 'md5_base64';
use Memoize;
use Carp 'croak';

memoize('valid_bucket_name');

VM::EC2::Dispatch->register(
    'list buckets'   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
			    my $bl =  VM::S3::BucketList->new(@_);
			    return $bl ? $bl->buckets : undef
    },

    'list objects'     => \&_list_objects_dispatch,

    'bucket acl'       => 'VM::S3::Acl',

    'bucket cors'      => 'VM::S3::CorsRules',

    'put bucket cors'  => 'response_ok',

    );

sub s3 { shift->ec2 }

sub get_service { shift->_service('get',@_) }
sub put_service { shift->_service('put',@_) }

sub _service {
    my $self     = shift;
    my ($method,$action,$bucket,$params,$payload,$headers) = @_;
    $params    ||= {};
    $headers   ||= [];
    $payload   ||= '';

    # allow user to use -key=>value form
    for my $key (keys %$params) {
	(my $newkey = $key) =~ s/^-//;
	$newkey             =~ s/_/-/g;
	$params->{$newkey}  = $params->{$key};
	delete $params->{$key} unless $key eq $newkey;
    }

    my $cv = $self->condvar;

    my $cv1 = $self->_get_service_endpoint($bucket);
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();

	local $self->{endpoint}   = $endpoint;
	local $self->{version}    = '2006-03-01';

	ref($params) ? $uri->query_form($params) : $uri->query($params);
	my $code    = eval '\\&'.uc($method);
	my $request = $code->($uri,
			      $host ? (Host => $host) : (),
			      'X-Amz-Content-Sha256' => sha256_hex($payload),
			      'Content'              => $payload,
			      @$headers,
	    );
	AWS::Signature4->new(-access_key=>$self->access_key,
			     -secret_key=>$self->secret
	    )->sign($request);

	my $cv2 = $self->async_request($action,$request);
	$cv2->cb(sub {
	    my $cv2  = shift;
	    my @obj  = $cv2->recv();
	    $self->error($cv2->error) if $cv2->error;
	    $cv->send($obj[0]) if @obj == 1;
	    $cv->send()        if @obj == 0;
	    $cv->send(@obj);
		 });
	     });

    return $cv if $VM::EC2::ASYNC;
    return $cv->recv();
}

sub _get_service_endpoint {
    my $self = shift;
    my ($bucket,$key) = @_;
    $key ||= '';

    my $cv = AnyEvent->condvar;
    
    my ($endpoint,$uri,$host);
    $endpoint = 'https://s3.amazonaws.com';

    if ($bucket) {
	my $br_cv = $self->bucket_region_async($bucket);
	$br_cv->cb(sub {
	    my $region = shift->recv();
	    $endpoint  = "https://s3-$region.amazonaws.com" unless $region eq 'us standard' || $region eq 'us-east-1'; 
	    if ($self->valid_bucket_name($bucket)) {
		$host = "$bucket.s3.amazonaws.com";
		$uri  = URI->new("$endpoint/$key");
	    }  else {
		$uri = URI->new("$endpoint/$bucket/$key");
	    }
	    $cv->send($endpoint,$uri,$host);
		   });
	return $cv;
    } else {
	$uri  = URI->new("$endpoint/");
	$cv->send($endpoint,$uri,$host);
	return $cv;
    }
}

sub bucket {
    my $self   = shift;
    my $bucket = shift or croak "usage: \$s3->bucket('bucket-name')";
    my @buckets = $self->list_buckets;
    my ($buck)  = grep {$_->Name eq $bucket} @buckets;
    return $buck;
}

sub list_buckets {
    my $self = shift;
    return $self->get_service('list buckets');
}

sub list_objects {
    my $self   = shift;
    my $bucket = shift;
    my @args   = @_;

    $bucket ||= $self->{list_buckets_bucket};
    if ($self->more_objects($bucket)) {
	@args   = @{$self->{list_buckets_args}{$bucket}};
	push @args,(marker=>$self->{list_buckets_marker}{$bucket});
    } else {
	$self->{list_buckets_bucket}          = $bucket;
	$self->{list_buckets_args}{$bucket}   = \@args;
    }

    $self->get_service('list objects',$bucket,{@args});
}

sub more_objects {
    my $self = shift;
    my $bucket = shift || $self->{list_buckets_bucket};
    return exists $self->{list_buckets_marker}{$bucket};
}

sub object {
    my $self = shift;
    @_ >= 2 or croak "usage: \$s3->object('bucket-name'=>'key-name')";
    my ($bucket,$key) = @_;
    my @objects = $self->list_objects($bucket,-marker=>substr($key,0,-1));
    my ($obj)   = grep {$_->Key eq $key} @objects;
    return $obj;
}

sub _bucket_g {
    my $self   = shift;
    my ($op,$bucket,$headers,) = @_;
    $self->get_service("bucket $op",$bucket,{$op => undef},undef,$headers);
}

sub _bucket_p {
    my $self = shift;
    my ($op,$bucket,$payload,$headers) = @_;
    $self->put_service("put bucket $op",$bucket,{$op=>undef},$payload,$headers);
}

sub bucket_acl             { shift->_bucket_g('acl',@_)       }
sub bucket_cors            { shift->_bucket_g('cors',@_)      }
sub bucket_lifecycle       { shift->_bucket_g('lifecycle',@_) }
sub bucket_policy          { shift->_bucket_g('policy',@_)    }
sub bucket_location        { shift->_bucket_g('location',@_)  }
sub bucket_logging         { shift->_bucket_g('logging',@_)  }
sub bucket_notification    { shift->_bucket_g('notification',@_)  }
sub bucket_tagging         { shift->_bucket_g('tagging',@_)  }
sub bucket_object_versions { shift->_bucket_g('versions',@_)  }
sub bucket_request_payment { shift->_bucket_g('requestPayment',@_)  }
sub bucket_website         { shift->_bucket_g('website',@_)  }

sub put_bucket_cors         { 
    my $self = shift;
    croak "usage: put_bucket_cors(\$bucket,\$cors_xml)" unless @_ == 2;
    my ($bucket,$cors) = @_;
    my $c   = "$cors"; # in case it is an interpolated CorsRules object.
    $c      =~ s/\s+<requestId>.+//;
    $c      =~ s/\s+<xmlns>.+//;
    my $md5 = md5_base64($c);
    $md5   .= '==' unless $md5 =~ /=$/;  # because Digest::MD5 does not generate correct modulo 3 digests
    $self->_bucket_p('cors',$bucket,$c,{'Content-MD5'=>$md5,'Content-length'=>length $c});
}

my %BR_cache;
sub bucket_region {
    my $self   = shift;
    my $bucket = shift;

    my $cv  = AnyEvent->condvar;
    if (exists $BR_cache{$bucket}) {
	$cv->send($BR_cache{$bucket});
    }
    elsif (!$self->valid_bucket_name($bucket)) {
	$cv->send('us standard');
    } else {
	http_head('http://s3.amazonaws.com/',
		  recurse => 0,
		  headers => { Host => $bucket },
		  sub {
		      my ($body,$hdr) = @_;
		      if ($hdr->{Status} == 200 || $hdr->{Status} == 403) {
			  $cv->send($BR_cache{$bucket} = 'us standard');
		      } elsif ($hdr->{Status} == 307 || $hdr->{Status} == 302) {
			  $hdr->{location} =~ /s3-([\w-]+)\.amazonaws\.com/;
			  $cv->send($BR_cache{$bucket} = $1);
		      } else {
			  $cv->send($BR_cache{$bucket} = undef);
		      }
		  }
	    );
    }
    return $cv if $VM::EC2::ASYNC;
    return $cv->recv();
}

# put_object($bucket,$key,$data,@options)
# 
# options:
#    -cache_control => ...
#    -content_disposition => ...
#    -content_encoding => ...
#    -content_type     => ...
#    -expires          => ...
#    -x_amz_meta-*     => ...
#    -x_amz_storage_class => {'STANDARD','REDUCED_REDUNDANCY'}
#    -x_amz_website_redirect_location => ...
#    -x_amz_acl => private | public-read | public-read-write | authenticated-read | bucket-owner-read | bucket-owner-full-control
#    -x_amz_grant_{read,write,read-acp,write-acp,full-control}
#
#  $data can be:
#               1) a simple scalar
#               2) a filehandle on an opened file/pipe
#               3) a callback that will be called to retrieve the next n bytes of data:
#                        callback($bytes_wanted)
#
sub put_object {
    my $self = shift;
    croak "Usage: put_object(\$bucket,\$key,\$data,\@options)" unless @_ >=3;
    my ($bucket,$key,$data,@options) = @_;

    my @x_amz   = map {s/_/-/g; $_} grep {/x_amz_.+/} keys {@options};
    my %opt     = @options;
    
    my $cv = $self->condvar;
    my $cv1 = $self->_get_service_endpoint($bucket,$key);
    
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();

	my $headers       = $self->_options_to_headers(
	    \@options,
	    qw(Cache-Control Content-Disposition Content-Encoding Content-Type Expires X-Amz-Storage-Class X-Amz-Website-Redirect-Location),@x_amz);

	my $chunked_transfer_size = $self->_stream_size($data);
	my $data_len              = $chunked_transfer_size || length $data;

	my @content = $chunked_transfer_size ? (Content_Encoding      => 'aws-chunked',
						Content_Length        => $data_len + $self->_chunked_encoding_overhead($data_len),
						X_Amz_Decoded_Content_Length=> $chunked_transfer_size,
						X_Amz_Content_Sha256  => 'STREAMING-AWS4-HMAC-SHA256-PAYLOAD',
	                                        )
	                                     : (Content_Length        => $data_len,
						X_Amz_Content_Sha256  => sha256_hex($data));

	my $request = PUT($uri,
			  Host                  => $host,
			  Expect                => '100-continue',
			  @content,
			  @$headers,
	    );
	$request->content($data);

	my @signing_parms = $chunked_transfer_size ? ($request,undef,'STREAMING-AWS4-HMAC-SHA256-PAYLOAD') : ($request);

	AWS::Signature4->new(-access_key=>$self->access_key,
			     -secret_key=>$self->secret
	    )->sign(@signing_parms);

	$self->submit_http_request($request,$cv,
				   {
				       on_complete    => $opt{-on_complete},
				       on_header      => $opt{-on_header},
				       on_body        => $opt{-on_body},
				       on_write_chunk => $opt{-on_write_chunk},
				   });
	     });

    my $cv2 = AnyEvent->condvar;
    $cv->cb(sub {
	my $response = shift->recv;
	$self->error($cv->error) if $cv->error;
	$cv2->send(eval{$response->is_success && $response->header('ETag')});
	    });
    
    if ($VM::EC2::ASYNC) {
	return $cv2;
    } else {
	my $etag = $cv2->recv;
	return $etag;
    }

}

# return a cv
sub put_request {
    my $self     = shift;
    my $request  = shift;
    $request->method('PUT');
    $request->header(Expect => '100-continue');
    return $self->submit_http_request($request);
}

# get_object($bucket,$key,
#            -on_body   => \&callback,
#            -on_header => \&callback,
#            -range     => ...
#            -if_modified_since => ...            
#            -if_unmodified_since=> ...
#            -if_match =>  $etag
#            -if_none_match => $etag
sub get_object {
    my $self = shift;
    croak "usage: get_object(\$bucket,\$key,\@params)" unless @_ >= 2;
    my ($bucket,$key) = splice(@_,0,2);
    my %options       = @_;

    my $cv = $self->condvar;
    my $cv1 = $self->_get_service_endpoint($bucket,$key);
    
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();
	my $headers       = $self->_options_to_headers(\@_,'If-Modified-Since','If-Unmodified-Since','If-Match','If-None-Match');

	my $request = GET($uri,
			  $host ? (Host => $host) : (),
			  'X-Amz-Content-Sha256'=>sha256_hex(''),
			  @$headers);
	AWS::Signature4->new(-access_key=>$self->access_key,
			     -secret_key=>$self->secret
	    )->sign($request);

	my $callback = sub {
	    my ($body,$hdr) = @_;
	    if ($hdr->{Status} !~ /^2/) {
		$self->async_send_error('get object',$hdr,$body,$cv);
	    } elsif (!$options{-on_body}) {
		$cv->send($body);
	    } else {
		$cv->send(1);
	    }
	};

	$self->submit_http_request($request,$cv,
				   { on_body       => $options{-on_body},
				     on_header     => $options{-on_header},
				     on_read_chunk => $options{-on_read_chunk},
				     on_complete   => $callback
				   });
	     });

    if ($VM::EC2::ASYNC) {
	return $cv;
    } else {
	my $body = $cv->recv;
	$self->error($cv->error) if $cv->error;
	return $body;
    }
}

sub valid_bucket_name {
    my $self = shift;
    my $bucket = shift;
    return if $bucket =~ /[A-Z]/; # no upcase letters allowed
    return if $bucket =~ /^\./;   # no initial dot
    return if $bucket =~ /\.$/;   # no trailing dot
    return if $bucket =~ /\.\./;  # dots without intervening label  disallowed
    return $bucket =~ /^[a-z0-9.-]{3,63}/;
}

sub _options_to_headers {
    my $self = shift;
    my ($options,@keys) = @_;
    my %keys = map {
	s/^-//;
	s/-/_/g;
	(lc($_)=>1);
    } @keys;

    my @result;
    while (my ($key,$value) = splice(@$options,0,2)) {
	$key =~ s/^-//;
	$key =~ s/-/_/g;
	$key = lc ($key);
	next unless $keys{$key};
	push @result,($key=>$value);
    }
    return \@result;
}

sub _list_objects_dispatch {
    my ($data,$s3) = @_;

    VM::EC2::Dispatch::load_module('VM::S3::BucketKey');
    VM::EC2::Dispatch::load_module('VM::S3::BucketPrefix');
    
    my $contents = $data->{Contents} or return;
    my @contents = ref($contents) eq 'ARRAY' ? @$contents : $contents;
    
    my $buck = $s3->{list_buckets_bucket};
    
    if ($data->{IsTruncated} eq 'true') {
	$s3->{list_buckets_marker}{$buck} = $data->{NextMarker} || $contents[-1]->{Key};
    } else {
	delete $s3->{list_buckets_marker}{$buck};
    }
    my $prefixes = $data->{CommonPrefixes};
    my @prefixes = map { $_->{Prefix} } ref($prefixes) eq 'ARRAY' 
	? @$prefixes : $prefixes;  # nasty
    
    my @bucket_keys      = grep {$_->Key ne $data->{Prefix}}
                                map {VM::S3::BucketKey->new($_,$s3,@_)}       @contents;
    my @bucket_prefixes  = map {VM::S3::BucketPrefix->new({Key=>$_},$s3,@_)}  @prefixes;

    foreach (@bucket_keys,@bucket_prefixes) { $_->bucket($data->{Name}) }

    return sort (@bucket_keys,@bucket_prefixes);
}

1;



