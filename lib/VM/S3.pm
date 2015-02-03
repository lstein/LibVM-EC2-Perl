package VM::S3;

=head1 NAME

VM::S3 - Perl interface to Amazon S3 Simple Storage Service

=head1 SYNOPSIS

my $s3 = VM::S3->new(-access_key => 'access key id',
                     -secret_key => 'aws_secret_key');

my @buckets = $s3->list_buckets();

for my $b (@buckets) {
    my $region   = $b->region;
    my @objects  = $b->objects;
    print "$b ($region)\n";
    print "\t$_\n" foreach @objects;
}

my $obj       = $s3->object(MyBucket => 'MyObject.jpg');
my $size      = $obj->size;
my $owner     = $obj->owner;
my $etag      = $obj->e_tag;

# for a small object, read contents into memory
my $contents  = $s3->get;

# for a large object, invoke a callback
open my $f,'>','large_file.jpg' or die $!;
$obj->get(-on_body => sub {
    my $data = shift;
    print $f $data;
    }
close $f;

# upload a new object from memory
my $bucket = $s3->bucket('MyBucket');
my $etag   = $bucket->put('MyObject.mp3' => $data);

# upload from a filehandle
open my $f,'<','large_file.mp3' or die;
my $etag   = $bucket->put('MyObject.mp3' => $f);

# upload from a callback - must know size of object in advance
my $size = 1_234_567
my $etag = $bucket->put('MyObject.mp3' => [\&callback => $size]);

=cut

=head1 DESCRIPTION

=head1 ASYNCHRONOUS CALLS

=head1 CORE METHODS

This section describes the VM::S3 constructor, accessor methods, and
methods relevant to error handling. VM::S3 inherits its methods from
VM::EC2. Please see L<VM::EC2> for additional methods not described
here.

=head2 $s3 = VM::S3->new(-access_key=>$id,-secret_key=>$key)

Create a new Amazon S3 object. Arguments are:

 -access_key     Access ID for an authorized user

 -secret_key     Secret key corresponding to the Access ID

 -security_token Temporary security token obtained through a call to the
                  AWS Security Token Service (STS).

 -raise_error    If true, throw an exception.

 -print_error    If true, print errors to STDERR.

One or more of -access_key or -secret_key can be omitted if the
environment variables EC2_ACCESS_KEY and EC2_SECRET_KEY are
defined. Unlike the EC2 methods (see L<VM::EC2>, you do not need to
specify a region or endpoint. This is handled automatically for you.

-security_token is used in conjunction with temporary security tokens
returned by $ec2->get_federation_token() and $ec2->get_session_token()
to grant restricted, time-limited access to some or all your S3
resources to users who do not have access to your account. If you pass
either a VM::EC2::Security::Token object, or the
VM::EC2::Security::Credentials object contained within the token
object, then new() does not need the -access_key or -secret_key
arguments. You may also pass a session token string scalar to
-security_token, in which case you must also pass the access key ID
and secret keys generated at the same time the session token was
created. See
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/UsingIAM.html
and L</AWS SECURITY TOKENS>.

By default, when the Amazon API reports an error, such as attempting
to perform an invalid operation on an instance, the corresponding
method will return empty and the error message can be recovered from
$s3->error(). However, if you pass -raise_error=>1 to new(), the
module will instead raise a fatal error, which you can trap with
eval{} and report with $@:

  eval {
     $ec2->some_dangerous_operation();
     $ec2->another_dangerous_operation();
  };
  print STDERR "something bad happened: $@" if $@;

The error object can be retrieved with $s3->error() as before.

=cut



use strict;
use base 'VM::EC2';#,'VM::S3::Http_helper';
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

    'bucket lifecycle' => 'VM::S3::LifecycleRules',

    'initiate multipart upload' => 'VM::S3::MultipartUpload',

    'complete multipart upload' => 'VM::S3::MultipartUploadResult',

    );

# huh?
# sub s3 { shift->ec2 }

sub get_service  { shift->_service('get', @_) }
sub put_service  { shift->_service('put', @_) }
sub post_service { shift->_service('post',@_) }

sub _service {
    my $self     = shift;
    my ($method,$action,$bucket,$key,$params,$payload,$headers) = @_;
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

    my $cv1 = $self->_get_service_endpoint($bucket,$key);
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();
	unless ($endpoint) {
	    $cv->send();
	    return;
	}

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
	$request->remove_header('Content-Type'); # just gets us into trouble
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
	$br_cv->cb(
	    sub {
		my $c = shift;
		my $region = $c->recv();
		unless ($region) {
		    $cv->send();
		    return;
		}
		$endpoint  = "https://s3-$region.amazonaws.com" 
		    unless $region eq 'us standard' || $region eq 'us-east-1'; 
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

=head2 @buckets = $s3->list_buckets()

List buckets attached to your account. Each bucket is represented as a
VM::S3::Bucket object.

=cut

sub list_buckets {
    my $self = shift;
    return $self->get_service('list buckets');
}

=head2 $bucket = $s3->bucket('my.bucket.name')

Return the bucket attached to your account matching the name
"my.bucket.name". The bucket is represented as a VM::S3::Bucket object.

=cut

sub bucket {
    my $self   = shift;
    my $bucket = shift or croak "usage: \$s3->bucket('bucket-name')";
    my @buckets = $self->list_buckets;
    my ($buck)  = grep {$_->Name eq $bucket} @buckets;
    return $buck;
}

=head2 @keys = $s3->list_objects('my.bucket.name',@args)

List all the keys in the indicated bucket. Keys are returned as
objects of type VM::S3::BucketKey. Optional arguments are -name=>value
pairs. See
http://docs.aws.amazon.com/AmazonS3/latest/API/RESTBucketGET.html for
more documentation.

 -delimiter      Delimiter character used to group keys.

 -encoding_type  Requests Amazon S3 to encode the response and specifies the 
                  encoding system to use.

 -marker         Specifies the key or partial key to start with when listing 
                  objects in a bucket.

 -max_keys       Sets the maximum number of keys to return in the request
                  (defaults to 1000).

 -prefix         Limits the response to keys that begin with the specified
                  prefix.

=cut

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

    $self->get_service('list objects',$bucket,undef,{@args});
}

=head2 $boolean = $s3->more_objects()

If list_objects() hits the maximum number of keys specified by
-max_keys (or 1000 by default), then a subsequent call to
more_objects() will return true and you can fetch the next group of
objects by calling list_objects() without a bucket name, as
illustrated in the following code snippet:

 @keys = $s3->list_objects('my.bucket.name',-max_keys => 20, -delimiter => '/')
 while ($s3->more_objects) {
    push @keys,$s3->list_objects;
 }


=cut

sub more_objects {
    my $self = shift;
    my $bucket = shift || $self->{list_buckets_bucket};
    return exists $self->{list_buckets_marker}{$bucket};
}

=head2 $key = $s3->object('my.bucket.name' => 'MyObjectKey')

Return the VM::S3::BucketKey corresponding to "MyObjectKey" in
"my.bucket.name". Will return undef if either the bucket or the key are
not found. You can then perform operations on the key, such as
fetching its underlying data or metadata.

=cut

sub object {
    my $self = shift;
    @_ >= 2 or croak "usage: \$s3->object('bucket-name'=>'key-name')";
    my ($bucket,$key) = @_;
    my @objects = $self->list_objects($bucket,-marker=>substr($key,0,-1)) or return;
    my ($obj)   = grep {$_->Key eq $key} @objects;
    return $obj;
}

sub _bucket_g {
    my $self   = shift;
    my ($op,$bucket,$headers,) = @_;
    $self->get_service("bucket $op",$bucket,undef,{$op => undef},undef,$headers);
}

sub _bucket_p {
    my $self = shift;
    my ($op,$bucket,$payload,$headers) = @_;
    $self->put_service("put bucket $op",$bucket,undef,{$op=>undef},$payload,$headers);
}

=head2 $acl = $s3->bucket_acl('my.bucket.name')

Return the Access Control List of the indicated bucket as a
VM::S3::Acl object.

=cut

sub bucket_acl             { shift->_bucket_g('acl',@_)       }

=head2 $cors = $s3->bucket_cors('my.bucket.name')

Return the cross-origin resource sharing policy of the indicated
bucket as a VM::S3::CorsRules object.

=cut

sub bucket_cors            { shift->_bucket_g('cors',@_)      }

=head2 $lifecycle = $s3->bucket_lifecycle('my.bucket.name')

Return the lifecycle of the indicated bucket as a
VM::S3::LifecycleRules object.

BUG: this needs to be implemented - just returns a generic object now.

=cut

sub bucket_lifecycle       { shift->_bucket_g('lifecycle',@_) }

=head2 $policy = $s3->bucket_policy('my.bucket.name')

Return the bucket policy of the indicated bucket as a
VM::S3::BucketPolicy object.

BUG: this needs to be implemented - just returns a generic object now.

=cut

sub bucket_policy          { shift->_bucket_g('policy',@_)    }

=head2 $policy = $s3->bucket_policy('my.bucket.name')

Return the bucket policy of the indicated bucket as a
VM::S3::BucketPolicy object.

BUG: this needs to be implemented - just returns a generic object now.

=cut

sub bucket_location        { shift->_bucket_g('location',@_)  }

=head2 $logging = $s3->bucket_logging('my.bucket.name')

Return the logging policy of the indicated bucket as a
VM::S3::LoggingPolicy object.

BUG: this needs to be implemented - just returns a generic object now.

=cut

sub bucket_logging         { shift->_bucket_g('logging',@_)  }


=head2 $notification = $s3->bucket_notification('my.bucket.name')

Return the notification configuration policy of the indicated bucket
as a VM::S3::Notification object.

BUG: this needs to be implemented - just returns a generic object now.

=cut

sub bucket_notification    { shift->_bucket_g('notification',@_)  }

=head2 $tagging = $s3->bucket_tagging('my.bucket.name')

Return the tag/value pairs attached to the indicated bucket as a hashref.

BUG: this needs to be implemented - just returns a generic object
now. Also, the inherited add_tags() and tags() methods don't work;
need to be overridden for S3.

=cut

sub bucket_tagging         { shift->_bucket_g('tagging',@_)  }

=head2 $versions = $s3->bucket_object_versions('my.bucket.name',@args)

Returns all versions of objects in my.bucket.name. 

BUG: this needs to be implemented - just returns a generic object
now.  Needs description of arguments.

=cut

sub bucket_object_versions { shift->_bucket_g('versions',@_)  }

=head2 $payment_info = $s3->bucket_request_payment('my.bucket.name')

Return information on Requestor Pays policy for the indicated bucket.

BUG: this needs to be implemented - just returns a generic object
now. 

=cut

sub bucket_request_payment { shift->_bucket_g('requestPayment',@_)  }

=head2 $url = $s3->bucket_website('my.bucket.name')

Return the website informattion of the indicated bucket.

BUG: this needs to be implemented - just returns a generic object
now. 

=cut

sub bucket_website         { shift->_bucket_g('website',@_)  }

=head2 $boolean = $s3->put_bucket_cors('my.bucket.name' => $cors)

Add or replace the Cors rules associated with the indicated
bucket. The second argument may be a properly formatted CORS XML, or a
VM::S3::CorsRules object, which provides convenience methods for
creating the proper XML.

If successful, a true value is returned.

=cut

sub put_bucket_cors { 
    my $self = shift;
    croak "usage: put_bucket_cors(\$bucket,\$cors_xml)" unless @_ == 2;
    my ($bucket,$cors) = @_;
    my $c   = "$cors"; # in case it is an interpolated CorsRules object.
    $c      =~ s/\s+<requestId>.+//;
    $c      =~ s/\s+<xmlns>.+//;
    my $md5 = md5_base64($c);
    $md5   .= '==' unless $md5 =~ /=$/;  # because Digest::MD5 does not generate correct modulo 3 digests
    $self->_bucket_p('cors',$bucket,$c,['Content-MD5'=>$md5,'Content-length'=>length $c]);
}

my %BR_cache;

=head2 $region = $s3->bucket_region('my.bucket.name')

Return the region in which the indicated bucket is located. It does
this by performing a HEAD on the bucket and recording the redirect
location, if any. Buckets with poorly-formed names, such as those with
uppercase letters, are only allowed in the standard region, so "us
standard" is automatically returned for these.

=cut

sub bucket_region {
    my $self   = shift;
    my $bucket = shift;

    my $cv  = $self->condvar;
    if (exists $BR_cache{$bucket}) {
	$cv->send($BR_cache{$bucket});
    }
    elsif (!$self->valid_bucket_name($bucket)) {
	$cv->send('us standard');
    } else {
	my $cv1 = $self->condvar;
	$self->submit_http_request(HEAD('http://s3.amazonaws.com/',
					Host=>$bucket),
				   sub { my $response = shift;
					 $cv1->send($response)},
				   { recurse     => 0},
	    );
	$cv1->cb(sub {
	    my $response = shift->recv();
	    my $status = $response->code;
	    if ($response->is_success || $status == 403) {
		$cv->send($BR_cache{$bucket} = 'us standard');
	    } elsif ($status == 307 || $status == 302) {
		$response->header('Location') =~ /s3-([\w-]+)\.amazonaws\.com/;
		$cv->send($BR_cache{$bucket} = $1);
	    } else {
		my $error = VM::EC2::Error->new({Message=>$response->message,
						 Code => $response->code},$self);
		$self->error($error);
		$cv->send($BR_cache{$bucket} = undef);
	    }});
    }
    return $cv if $VM::EC2::ASYNC;
    return $cv->recv();
}

=head2 $etag = $s3->put_object('my.bucket.name'=>'MyKey',$data,@options)

Add or replace an object in bucket "my.bucket.name" with key
"MyKey". The third argument, $data, may be any of the following:

=over 4

=item A scalar. 

The contents of $data will be written to S3.

=item A filehandle, including IO::File and other GLOB-like objects. 

Perl B<must> be able to determine the ultimate size of the
contents of the filehandle by calling stat(). This means that you
cannot stream from STDIN or a pipe. If you wish to do this, use
put_multipart_object() instead (not currently implemented).

=item A two-element array of the form [$total_size,\&callback]

The first element of the array is the total finished size of the data,
and the second is a coderef that will be invoked repeatedly until the
data has been loaded. The signature of the coderef is
$callback->($bytes_wanted). It is expected to return the number of
bytes requested.

=back

@options are an optional list of -key=>value pairs. Some provide
callbacks that can be used to monitor the progress of a long file
transfer. Others control the metadata of the uploaded object. 

Callbacks:

 -on_header            callback to invoke when the PUT header is received.
                         The callback will be passed a single argument 
                         consisting of the HTTP::Response object

 -on_write_chunk       callback to invoke when a chunk of data has been written.
                         It will be invoked with a two argument list consisting
                         of the number of bytes transferred so far, and the
                         number of bytes to transfer in total. It can be used
                         to implement a nifty progress bar.

Metadata control. See
http://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectPUT.html for
full details:

 -cache_control          cache control directive, e.g. "no-cache"

 -content_disposition    content disposition instruction, 
                           e.g. "attachment; filename='foo.txt'"

 -content_encoding       content encoding, e.g. "gzip"

 -content_type           content type, e.g. "text/plain"

 -expires                date and time at which the object is no longer cacheable, 
                          e.g. "Thu, 01 Dec 2014 16:00:00 GMT"

 -x_amz_meta_*           any metadata you wish to stoe with the object

 -x_amz_storage_class    one of "STANDARD" or "REDUCED_REDUNDANCY"

 -x_amz_website_redirect_location 
                         redirect requests for this object to another object 
                          in the same bucket or another website

 -x_amz_acl              a canned ACL. One of "private", "public-read-write", 
                            "authenticated-read","bucket-owner-read", or "bucket-owner-full-control"

 -x_amz_grant_read       list of email addresses, Amazon user IDs or group URLs to grant object read
                           permissions to.

 -x_amz_grant_write      list of email addresses, Amazon user IDs or group URLs to grant object write
                           permissions to.

 -x_amz_grant_read_acp   list of email addresses, Amazon user IDs or group URLs who can read the ACL

 -x_amz_grant_write_acp  list of email addresses, Amazon user IDs or group URLs who can write the ACL

 -x_amz_grant_all        list of email addresses, Amazon user IDs or group URLs who have all privileges

The -x_amz_grant* options accept list of email addresses and/or Amazon IDs in the form:

 -x_amz_grant_read => 'emailAddress="test.user@gmail.com", emailAddress="user2@yahoo.com", id=1234567

You may also provide a "url" argument that points to a predefined group.

Upon completion the method returns the ETag of the created/updated
object. In asynchronous mode, returns a condition variable that will
return the etag upon a call to recv().

=cut

sub put_object {
    my $self = shift;
    my ($bucket,$key,$data,@options) = @_;
    croak "Usage: put_object(\$bucket,\$key,\$data,\@options)" unless @_ >=3;
    return $self->_put_object($bucket,$key,$data,0,0,\@options);
}

# _put_object($bucket,$key,$data,$partNumber,$uploadId,@options)
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
#    -x_amz-server-side-encryption
#    -x_amz-server-side-encryption-*
#
#  $data can be:
#               1) a simple scalar
#               2) a filehandle on an opened file/pipe
#               3) a callback that will be called to retrieve the next n bytes of data:
#                        callback($bytes_wanted)
#
sub _put_object {
    my $self = shift;
    croak "Usage: put_object(\$bucket,\$key,\$data,\$partNumber,\$uploadId,\\\@options)" unless @_ >= 5;
    my ($bucket,$key,$data,$partNumber,$uploadId,$options) = @_;

    $options  ||= [];
    my %opt     = @$options;
    my @x_amz   = map {s/_/-/g; $_} grep {/x_amz_.+/} keys %opt;
    
    my $cv = $self->condvar;
    my $cv1 = $self->_get_service_endpoint($bucket,$key);
    
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();
	unless ($endpoint) {
	    $cv->error($cv1->error);
	    $cv->send();
	    return;
	}

	my $headers       = $self->_options_to_headers(
	    $options,
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

	$uri .= "?partNumber=$partNumber&uploadId=$uploadId" if $partNumber && $uploadId;
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

	$self->submit_http_request($request,
				   sub {
				       my $request = shift;
				       $cv->send($request);
				   },
				   {
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

=head2 $multipart_upload_object = $s3->initiate_multipart_upload($bucket,$key)

Initiate a multipart upload on the indicated bucket and object key.

The returned multipart upload object has the methods:

   $muo->upload_id
   $muo->bucket
   $muo->key

=cut

sub initiate_multipart_upload {
    my $self = shift;
    my ($bucket,$key) = @_;
    $self->post_service('initiate multipart upload',$bucket,$key,{'uploads'=>undef});
}

=head2 $multipart_upload_part = $s3->upload_part($bucket,$key,$partNo,$data,@options)

Upload an object part. Options are the same as put_object() except
that you provide a $partNo indicating the sequence of the piece of
data being uploaded.

Returned object is a VM::S3::UploadPart (or a CondVar in asynchronous mode).

=cut

sub upload_part {
    my $self = shift;
    my ($bucket,$key,$uploadId,$partNo,$data,@options) = @_;

    eval "use VM::S3::UploadPart" unless VM::S3::UploadPart->can('new');

    my $cv = $self->condvar;

    my $cv1 = $self->_put_object_async($bucket,$key,$data,$partNo,$uploadId,\@options);
    $cv1->cb(sub {
	my $cv1       = shift;
	my $etag     = $cv1->recv;
	my $obj      = VM::S3::UploadPart->new({UploadId   => $uploadId,
						PartNumber => $partNo,
						ETag       => $etag},
					       $self);
	$cv->send($obj);
	    });
    
    return $cv if $VM::EC2::ASYNC;
    return $cv->recv();
}

=head2 $multipart_load_completion_object = $s3->complete_multipart_upload($bucket,$key,$uploadId,\@parts)

Provide uploadId and list of VM::S3::UploadPart objects.

The returned VM::S3::MultipartCompletion object has the methods:

   $mco->location
   $mco->bucket
   $mco->key
   $mco->etag

=cut

sub complete_multipart_upload {
    my $self = shift;
    my ($bucket,$key,$uploadId,$partlist) = @_;
    my @parts     = map {{
	PartNumber => $_->part_number,
	ETag       => $_->e_tag}
    } @$partlist;
    my $payload = XML::Simple->new->XMLout({Part=>\@parts},RootName=>'CompleteMultipartUpload',NoAttr=>1);
    $self->post_service('complete multipart upload',$bucket,$key,{uploadId=>$uploadId},$payload);
}

=head2 $cv = put_request($request)

Needs documentation!

=cut

# return a cv
sub put_request {
    my $self     = shift;
    my $request  = shift;
    $request->method('PUT');
    $request->header(Expect => '100-continue');
    return $self->submit_http_request($request);
}

=head2 $data = $s3->get_object('my.bucket.name','ObjectKey',@options)

Fetch the object named "ObjectKey" in bucket "my.bucket.name" and
return its contents into memory. You can use options to set callbacks,
most commonly to write a large object to disk, or to download the
object only under certain conditions.

Callbacks:

 -on_body              Callback invoked when the content, or a portion of the
                         content is received. The callback will be invoked with
                         a single scalar argument containing the data received.
                         When this callback is present, get_object() will not
                         store the data and return it at the end of the call.

 -on_header            Callback invoked when the HTTP header is received. The single
                         argument is the HTTP::Request object that contains the status
                         response line and headers. The callback may cancel
                         the request at this point by returning a false value.

 -on_read_chunk        This callback acts independently of -on_body to periodically
                         return data transfer progress information. The callback is
                         invoked with two arguments consisting of the number of bytes
                         read and the total bytes expected. It can be used to display
                         a progress bar or to measure transfer speed.

Request modifiers:

 -range                An HTTP byte range used to retrieve a partial object. The byte
                         range is in any of the formats described at 
                         http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.35.1.
                         The most common format is "bytes=XX-YY", where XX and YY are the
                         desired start and end bytes of the range.

 -if_modified_since    An HTTP date and time in the format described at 
                         http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.18.
                         The object will only be returned if its modification date is more
                         recent than the requested date.

 -if_unmodified_since  An HTTP date and time. The object will only be returned if its 
                         modification date is less recent than the requested date.

 -if_match             An ETag. The object will only be returned if its ETag matches.

 -if_none_match        An ETag. The object will be returned if the ETag doesn't match.

=cut

# get_object($bucket,$key,
#            -on_body   =>     \&callback,
#            -on_header =>     \&callback,
#            -on_read_chunk => \&callback,
#            -range     => ...
#            -if_modified_since => ...            
#            -if_unmodified_since=> ...
#            -if_match =>  $etag
#            -if_none_match => $etag
sub get_object {
    my $self = shift;
    croak "usage: get_object(\$bucket,\$key,\@params)" unless @_ >= 2;
    my ($bucket,$key) = splice(@_,0,2);
    my @options       = @_;
    my %options       = @options;


    my $cv = $self->condvar;
    my $cv1 = $self->_get_service_endpoint($bucket,$key);
    
    $cv1->cb(sub {
	my ($endpoint,$uri,$host) = shift->recv();
	unless ($endpoint) {
	    $cv->error($cv1->error);
	    $cv->send();
	    return;
	}
	my $headers       = $self->_options_to_headers(\@options,
						       'Range',
						       'If-Modified-Since',
						       'If-Unmodified-Since',
						       'If-Match',
						       'If-None-Match');

	my $request = GET($uri,
			  $host ? (Host => $host) : (),
			  'X-Amz-Content-Sha256'=>sha256_hex(''),
			  @$headers);
	AWS::Signature4->new(-access_key=>$self->access_key,
			     -secret_key=>$self->secret
	    )->sign($request);

	my $callback = sub {
	    my $response = shift;
	    if (!$response->is_success) {
		$self->async_send_error('get object',$response,$response->decoded_content,$cv);
	    } elsif (!$options{-on_body}) {
		$cv->send($response->decoded_content);
	    } else {
		$cv->send(1);
	    }
	};

	$self->submit_http_request($request,
				   $callback,
				   { on_body       => $options{-on_body},
				     on_header     => $options{-on_header},
				     on_read_chunk => $options{-on_read_chunk},
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

    my @prefixes;
    if (my $prefixes = $data->{CommonPrefixes}) {
	@prefixes = map { $_->{Prefix} } ref($prefixes) eq 'ARRAY' 
	    ? @$prefixes : $prefixes;  # nasty
    }
    
    my @bucket_keys      = grep {$_->Key ne $data->{Prefix}}
                                map {VM::S3::BucketKey->new($_,$s3,@_)}       @contents;
    my @bucket_prefixes  = map {VM::S3::BucketPrefix->new({Key=>$_},$s3,@_)}  @prefixes;

    foreach (@bucket_keys,@bucket_prefixes) { $_->bucket($data->{Name}) }

    return sort (@bucket_keys,@bucket_prefixes);
}

1;

=head1 SEE ALSO

L<VM::EC2>
L<VM::S3::Bucket>
L<VM::S3::BucketKey>
L<VM::S3::Cors>
L<VM::S3::CorsRules>
L<VM::S3::Grant>
L<VM::S3::Owner>
L<VM::S3::Acl>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2014 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
