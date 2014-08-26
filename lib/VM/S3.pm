package VM::S3;

use strict;
use base 'VM::EC2';
use Net::DNS;
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Carp 'croak';

VM::EC2::Dispatch->register(
    'get service'   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
			    my $bl =  VM::S3::BucketList->new(@_);
			    return $bl ? $bl->buckets : undef
    },
    'get bucket' => 'VM::S3::Generic',
    );

sub get_service {
    my $self     = shift;
    my ($action,$bucket,$params,$region,$endpoint) = @_;
    $params    ||= {};

    local $self->{endpoint} = $endpoint || 'https://s3.amazonaws.com';
    local $self->{version}  = '2006-03-01';

    $self->{endpoint} = "https://".$self->endpoint unless $self->endpoint =~ /^http/;

    my ($uri,$host);
    if ($bucket) {
	if ($bucket =~ /^([a-z0-9][a-z0-9-.]*)/) {
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
	)->sign($request,$region);
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
    my $region   = shift;
    my $endpoint = shift;

    $self->get_service('get bucket',$bucket,'',$region,$endpoint);
}

sub bucket_location {
    my $self   = shift;
    my $bucket = shift;
    my $region = shift;
    $self->get_service('get location',$bucket,{location=>undef},$region);
}

sub bucket_policy {
    my $self   = shift;
    my $bucket = shift;
    my $region = shift;
    $self->get_service('get policy',$bucket,{policy=>undef},$region);
}

sub get_bucket_region_dns {
    my $self = shift;
    my $bucket = shift;
    my $name   = "$bucket.s3.amazonaws.com";
    my $query = Net::DNS::Resolver->new()->search($name);
    return unless $query;
    my $cname;
    foreach my $r ($query->answer) {
	next unless $r->type eq 'CNAME';
	$cname = $r->cname;
    }
    if ($cname =~ /^s3-(\w+-\w+-\d+).*\.amazonaws.com/) {
	return $1;
    } elsif ($cname =~ /^s3-(\d+).*\.amazonaws.com/) {
	return "us-east-$1";
    }
    return;
}

sub get_bucket_region {
    my $self   = shift;
    my $bucket = shift;
    my $url    = "http://$bucket.s3.amazonaws.com";
    my $cv = AnyEvent->condvar;
    http_head('http://s3.amazonaws.com/',
	      recurse => 0,
	      headers => { Host => $bucket },
	      sub {
		  my ($body,$hdr) = @_;
		  if ($hdr->{Status} == 200 || $hdr->{Status} == 403) {
		      $cv->send('us-east-1');
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

1;



