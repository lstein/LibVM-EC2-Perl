package VM::S3;

use strict;
use base 'VM::EC2';
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Memoize;
use Carp 'croak';

memoize('bucket_region','valid_bucket_name');

VM::EC2::Dispatch->register(
    'get service'   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
			    my $bl =  VM::S3::BucketList->new(@_);
			    return $bl ? $bl->buckets : undef
    },
    'get bucket'     => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketKey');
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
    );

sub get_service {
    my $self     = shift;
    my ($action,$bucket,$params) = @_;
    $params    ||= {};

    local $self->{endpoint} = 'https://s3.amazonaws.com';
    local $self->{version}  = '2006-03-01';

    my ($uri,$host);
    if ($bucket) {
	my $region        = $self->bucket_region($bucket);
	$self->{endpoint} = "https://s3-$region.amazonaws.com" unless $region eq 'us standard';
	if ($self->valid_bucket_name($bucket)) {
	    $host = "$bucket.s3.amazonaws.com";
	    $uri  = URI->new($self->endpoint.'/');
	}  else {
	    $uri = URI->new($self->endpoint."/$bucket/");
	}
    } else {
	$uri  = URI->new($self->endpoint.'/');
    }

    ref($params) ? $uri->query_form($params) : $uri->query($params);
    my $request = GET($uri,
		      $host ? (Host => $host) : (),
		      'X-Amz-Content-Sha256'=>sha256_hex('')
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

sub list_buckets {
    my $self = shift;
    return $self->get_service('get service');
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

    $self->get_service('get bucket',$bucket,{@args});
}

sub more_objects {
    my $self = shift;
    my $bucket = shift || $self->{list_buckets_bucket};
    return exists $self->{list_buckets_marker}{$bucket};
}

sub bucket_location {
    my $self   = shift;
    my $bucket = shift;

    $self->get_service('get location',$bucket,{location=>undef});
}

sub bucket_policy {
    my $self   = shift;
    my $bucket = shift;

    $self->get_service('get policy',$bucket,{policy=>undef});
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

sub valid_bucket_name {
    my $self = shift;
    my $bucket = shift;
    return if $bucket =~ /[A-Z]/; # no upcase letters allowed
    return if $bucket =~ /^\./;   # no initial dot
    return if $bucket =~ /\.$/;   # no trailing dot
    return if $bucket =~ /\.\./;  # dots without intervening label  disallowed
    return $bucket =~ /^[a-z0-9.-]{3,63}/;
}

1;



