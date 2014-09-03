package VM::S3;

use strict;
use base 'VM::EC2';
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Digest::MD5 'md5_base64';
use Memoize;
use Carp 'croak';

memoize('bucket_region','valid_bucket_name');

VM::EC2::Dispatch->register(
    'list buckets'   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
			    my $bl =  VM::S3::BucketList->new(@_);
			    return $bl ? $bl->buckets : undef
    },

    'list objects'     => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketKey');
			     my $data = shift;
			     my $s3   = shift;

			     my $contents = $data->{Contents} or return;
			     my @contents = ref($contents) eq 'ARRAY' ? @$contents : $contents;

			     my $buck = $s3->{list_buckets_bucket};

			     if ($data->{IsTruncated} eq 'true') {
				 $s3->{list_buckets_marker}{$buck} = $data->{NextMarker} || $contents[-1]->{Key};
			     } else {
				 delete $s3->{list_buckets_marker}{$buck};
			     }
			     return map {VM::S3::BucketKey->new($_,$s3,@_)} @contents;
    },

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
    $headers   ||= {};
    $payload   ||= '';

    my ($endpoint,$uri,$host) = $self->_get_service_endpoint($bucket);
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2006-03-01';

    ref($params) ? $uri->query_form($params) : $uri->query($params);
    my $code    = eval '\\&'.uc($method);
    my $request = $code->($uri,
			  $host ? (Host => $host) : (),
			  'X-Amz-Content-Sha256'=>sha256_hex($payload),
			  'Content'     => $payload,
			  %$headers,
	);
    AWS::Signature4->new(-access_key=>$self->access_key,
			 -secret_key=>$self->secret
	)->sign($request);
    my $cv = $self->async_request($action,$request);
    if ($VM::EC2::ASYNC) {
	return $cv;
    } else {
	my @obj = $cv->recv;
	$self->error($cv->error) if $cv->error;
	return $obj[0] if @obj == 1;
	return         if @obj == 0;
	return @obj;
    }
}

sub _get_service_endpoint {
    my $self = shift;
    my ($bucket,$key) = @_;
    $key ||= '';

    my ($endpoint,$uri,$host);
    $endpoint = 'https://s3.amazonaws.com';

    if ($bucket) {
	my $region        = $self->bucket_region($bucket);
	$endpoint = "https://s3-$region.amazonaws.com" unless $region eq 'us standard' || $region eq 'us-east-1'; 

	if ($self->valid_bucket_name($bucket)) {
	    $host = "$bucket.s3.amazonaws.com";
	    $uri  = URI->new("$endpoint/$key");
	}  else {
	    $uri = URI->new("$endpoint/$bucket/$key");
	}
    } else {
	$uri  = URI->new("$endpoint/");
    }

    return ($endpoint,$uri,$host);
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

sub bucket_region {
    my $self   = shift;
    my $bucket = shift;
    return 'us standard' unless $self->valid_bucket_name($bucket);

    my $url = "http://$bucket.s3.amazonaws.com";
    my $cv  = AnyEvent->condvar;
    http_head('http://s3.amazonaws.com/',
	      recurse => 0,
	      headers => { Host => $bucket },
	      sub {
		  my ($body,$hdr) = @_;
		  if ($hdr->{Status} == 200 || $hdr->{Status} == 403) {
		      $cv->send('us standard');
		  } elsif ($hdr->{Status} == 307 || $hdr->{Status} == 302) {
		      $hdr->{location} =~ /s3-([\w-]+)\.amazonaws\.com/;
		      $cv->send($1);
		  } else {
		      $cv->send(undef);
		  }
	      }
	);
    return  $cv->recv();
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

    my $on_body    = $options{-on_body};
    my $on_header  = $options{-on_header};
    
    my ($endpoint,$uri,$host) = $self->_get_service_endpoint($bucket,$key);
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2006-03-01';

    my $headers       = $self->_options_to_headers(
	\%options,
	['If-Modified-Since','If-Unmodified-Since','If-Match','If-None-Match']
	);

    my $request = GET($uri,
		      $host ? (Host => $host) : (),
		      'X-Amz-Content-Sha256'=>sha256_hex(''),
		      %$headers);
    AWS::Signature4->new(-access_key=>$self->access_key,
			 -secret_key=>$self->secret
	)->sign($request);
    
    %$headers = ();
    $request->headers->scan(sub {$headers->{$_[0]}=$_[1]});

    my @args;
    push @args,(on_body=>$on_body)     if $on_body;
    push @args,(on_header=>$on_header) if $on_header;

    my $cv = $self->condvar;
    my $callback = sub {
	my ($body,$hdr) = @_;
	if ($hdr->{Status} !~ /^2/) {
	    $self->async_send_error('get object',$hdr,$body,$cv);
	} else {
	    $cv->send($body);
	}
    };

    http_get($request->uri,headers=>$headers,@args,$callback);

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
    my ($options,$keys) = @_;
    $keys ||= [];

    my $headers = {};

    for my $key (@$keys) {
	my $arg = $key;
	$arg =~ s/-/_/g;
	$arg = '-' . lc($arg);

	$headers->{$key} = $options->{$arg} if exists $options->{$arg};
    }
    return $headers;
}

1;



