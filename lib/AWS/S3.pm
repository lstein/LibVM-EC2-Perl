package AWS::S3;

use strict;
use base 'VM::EC2';
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';

VM::EC2::Dispatch->register(
#    ''   => sub {VM::EC2::Dispatch::load_module('AWS::S3::BucketList');
#		 return AWS::S3::BucketList->new(@_);
#    }
    '' => 'AWS::S3::BucketList',
    );

sub get_service {
    my $self   = shift;
    my $action = shift || '';

    local $self->{endpoint} = 'https://s3.amazonaws.com';
    local $self->{version}  = '2006-03-01';
    my $request = GET($self->endpoint.'/',
		      Host=>URI->new($self->endpoint)->host,
		      'X-Amz-Content-Sha256'=>sha256_hex('')
	);
    AWS::Signature4->sign($self->access_key,$self->secret,$self->endpoint,$request);
    my $cv = $self->async_get($action,$request);
    return $cv->recv();
}

sub get_bucket {
    my $self   = shift;
    my $bucket = shift;
    my $action = shift;
    local $self->{endpoint} = "https://$bucket.s3.amazonaws.com";
    local $self->{version}  = '2006-03-01';
    my $request = GET($self->endpoint);
    $self->async_get($action,$request);
}

1;



