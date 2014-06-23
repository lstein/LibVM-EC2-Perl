package AWS::Signature4;

use strict;
use POSIX 'strftime';
use URI;
use URI::QueryParam;
use URI::Escape;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Carp 'croak';

=head1 NAME

AWS::Signature4 - Create a version4 signature for Amazon Web Services

=head1 SYNOPSIS

 use AWS::Signature4;
 use HTTP::Request::Common;

 my $signer = AWS;:Signature4->new(-access_key => 'AKIDEXAMPLE',
                                   -secret_key => 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY');

 # Example post
 my $request = POST('https://iam.amazonaws.com',
		    [Action=>'ListUsers',
		     Version=>'2010-05-08']));
 $signer->sign($request);

 # Example get
 my $uri     = URI->new('https://iam.amazonaws.com');
 $uri->query_form(Action=>'ListUsers',
		  Version=>'2010-05-08');
 my $url = $signer->signed_url($request);
 my $response = LWP::UserAgent->new->request($request);

=head1 DESCRIPTION

This module implement's Amazon Web Service's Signature version 4
(http://docs.aws.amazon.com/general/latest/gr/signature-version-4.html).

=head1 METHODS

=over 4

=item $signer = AWS::Signature4->new(-access_key => $account_id,-secret_key => $private_key);

=cut

sub new {
    my $self = shift;
    my %args = @_;

    my ($id,$secret,$token);
    if (ref $args{-security_token} && $args{-security_token}->can('access_key_id')) {
	$id     = $args{-security_token}->accessKeyId;
	$secret = $args{-security_token}->secretAccessKey;
    }

    $id           ||= $args{-access_key} || $ENV{EC2_ACCESS_KEY}
                      or croak "Please provide -access_key parameter or define environment variable EC2_ACCESS_KEY";
    $secret       ||= $args{-secret_key} || $ENV{EC2_SECRET_KEY}
                      or croak "Please provide -secret_key or define environment variable EC2_SECRET_KEY";

    return bless {
	access_key => $id,
	secret_key => $secret},ref $self || $self;
}

sub access_key { shift->{access_key } } 
sub secret_key { shift->{secret_key } }

=item $signer->sign($request)

The request must include a URL from which the endpoint and service are
derived, such as ec2.us-east-1.amazonaws.com. The module will compute
a version 4 signature using the AWS4-HMAC-SHA256 cryptographic method
and sign the request. 

The "X-Amz-Date" and "Authorization" headers are added to the
request. Nothing is returned.

=item $url = $signer->signed_url($request)

This method will generate a signed GET URL for the request. The URL
will include everything needed to perform the request.

=back

=cut

sub sign {
    my $self = shift;
    my $request = shift;
    $self->_add_date_header($request);
    $self->_sign($request);
}

sub _add_date_header {
    my $self = shift;
    my $request = shift;
    my $datetime;
    unless ($datetime = $request->header('x-amz-date')) {
	$datetime    = $self->_zulu_time;
	$request->header('x-amz-date'=>$datetime);
    }
}

sub _scope {
    my $self    = shift;
    my $request = shift;
    my $host     = $request->uri->host;
    my $datetime = $self->_datetime($request);
    my ($date)   = $datetime =~ /^(\d+)T/;
    my ($service)  = $host =~ /^(\w+)/;
    my ($region)   = $host =~ /^\w+\.([^.]+)\.amazonaws\.com/;
    $region      ||= 'us-east-1';
    return "$date/$region/$service/aws4_request";
}

sub _parse_scope {
    my $self = shift;
    my $scope = shift;
    return split '/',$scope;
}

sub _datetime {
    my $self = shift;
    my $request = shift;
    return $self->{datetime}{$request} if exists $self->{datetime}{$request};
    return $self->{datetime}{$request} = $request->header('x-amz-date') || $self->_zulu_time;    
}

sub _algorithm { return 'AWS4-HMAC-SHA256' }

sub _sign {
    my $self    = shift;
    my $request = shift;

    my $datetime = $self->_datetime($request);

    my $host        = $request->uri->host;
    $request->header(host=>$host);

    my $scope      = $self->_scope($request);
    my ($date,$region,$service) = $self->_parse_scope($scope);

    my $secret_key = $self->secret_key;
    my $access_key = $self->access_key;
    my $algorithm  = $self->_algorithm;

    my ($hashed_request,$signed_headers) = $self->_hash_canonical_request($request);
    my $string_to_sign                   = $self->_string_to_sign($datetime,$scope,$hashed_request);
    my $signature                        = $self->_calculate_signature($secret_key,$service,$region,$date,$string_to_sign);
    $request->header(Authorization => "$algorithm Credential=$access_key/$scope, SignedHeaders=$signed_headers, Signature=$signature");
}

sub signed_url {
    my $self    = shift;
    my $request = shift;

    my $uri = $request->uri;
    $uri->query_param_append('X-Amz-Algorithm'  => $self->_algorithm);
    $uri->query_param_append('X-Amz-Credential' => $self->access_key . '/' . $self->_scope($request));
    $uri->query_param_append('X-Amz-Date'       => $self->_datetime($request));
    $uri->query_param_append('X-Amz-SignedHeaders' => 'host');

    $self->_sign($request);
    my ($algorithm,$credential,$signedheaders,$signature) =
	$request->header('Authorization') =~ /^(\S+) Credential=(\S+), SignedHeaders=(\S+), Signature=(\S+)/;
    $uri->query_param_append('X-Amz-Signature'     => $signature);
    return $uri;
}

sub _zulu_time { return strftime('%Y%m%dT%H%M%SZ',gmtime) }


sub _hash_canonical_request {
    my $self = shift;
    my $request = shift; # http::request
    my $method         = $request->method;
    my $uri            = $request->uri;
    my $path           = $uri->path || '/';
    my @params         = $uri->query_form;
    my $headers        = $request->headers;
    my $hashed_payload = sha256_hex($request->content);

    # canonicalize query string
    my %canonical;
    while (my ($key,$value) = splice(@params,0,2)) {
	$key   = uri_escape($key);
	$value = uri_escape($value);
	push @{$canonical{$key}},$value;
    }
    my $canonical_query_string = join '&',map {my $key = $_; map {"$key=$_"} sort @{$canonical{$key}}} sort keys %canonical;

    # canonicalize the request headers
    my @canonical;
    for my $header (sort map {lc} $headers->header_field_names) {
	my @values = $headers->header($header);
	# remove redundant whitespace
	foreach (@values ) {
	    next if /^".+"$/;
	    s/^\s+//;
	    s/\s+$//;
	    s/(\s)\s+/$1/g;
	}
	push @canonical,"$header:".join(',',@values);
    }
    my $canonical_headers = join "\n",@canonical;
    $canonical_headers   .= "\n";
    my $signed_headers    = join ';',sort map {lc} $headers->header_field_names;

    my $canonical_request = join("\n",$method,$path,$canonical_query_string,
				 $canonical_headers,$signed_headers,$hashed_payload);

    my $request_digest    = sha256_hex($canonical_request);
    
    return ($request_digest,$signed_headers);
}

sub _string_to_sign {
    my $self = shift;
    my ($datetime,$credential_scope,$hashed_request) = @_;
    return join("\n",'AWS4-HMAC-SHA256',$datetime,$credential_scope,$hashed_request);
}

sub _calculate_signature {
    my $self = shift;
    my ($kSecret,$service,$region,$date,$string_to_sign) = @_;
    my $kDate    = hmac_sha256($date,'AWS4'.$kSecret);
    my $kRegion  = hmac_sha256($region,$kDate);
    my $kService = hmac_sha256($service,$kRegion);
    my $kSigning = hmac_sha256('aws4_request',$kService);
    return hmac_sha256_hex($string_to_sign,$kSigning);
}

1;


=head1 SEE ALSO

L<VM::EC2>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2014 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


