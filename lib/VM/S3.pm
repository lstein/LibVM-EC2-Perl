package VM::S3;

use strict;
use base 'VM::EC2';
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Carp 'croak';

VM::EC2::Dispatch->register(
    ''   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
		 my $bl =  VM::S3::BucketList->new(@_);
		 return $bl ? $bl->buckets : undef
    },
    'get bucket' => 'VM::S3::Generic',
    );

sub get_service {
    my $self     = shift;
    my ($action,$bucket,$params,$endpoint) = @_;
    $params    ||= {};

    local $self->{endpoint} = $endpoint || 'https://s3.amazonaws.com';
    local $self->{version}  = '2006-03-01';

    $self->{endpoint} = "https://".$self->endpoint unless $self->endpoint =~ /^http/;

    my $uri     = URI->new($self->endpoint.($bucket ? "/$bucket/" : '/'));

    ref($params) ? $uri->query_form($params) : $uri->query($params);
    my $request = GET($uri,
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
    return $self->get_service();
}

sub list_objects {
    my $self   = shift;
    my $bucket = shift;
    my $endpoint = shift;
    $self->get_service('get bucket',$bucket,'',$endpoint);
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

1;



