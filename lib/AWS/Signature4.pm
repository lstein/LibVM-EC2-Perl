package AWS::Signature4;

use strict;
use POSIX 'strftime';
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';

=head1 NAME

AWS::Signature4 - Create a version4 signature for Amazon Web Services

=head1 SYNOPSIS

  $request = HTTP::Request->new(GET => 'https://ec2.amazonaws.com?Action=DescribeInstances')
  AWS::Signature4->sign($my_secret_key=>$request);  # sign and update headers
  LWP::UserAgent->new(GET => $request);

NOTE: we hard-code AWS4-HMAC-SHA256 as signing algorithm

=cut

sub sign {
    my $self = shift;
    my ($access_key,$secret_key,$service,$region,$request) = @_;

    my $datetime;
    unless ($datetime = $request->header('x-amz-date')) {
	$datetime    = $self->_zulu_time;
	$request->header('x-amz-date'=>$datetime);
    }
    my ($date)     = $datetime =~ /^(\d+)T/;
    my $scope      = "$date/$region/$service/aws4_request";

    my ($hashed_request,$signed_headers) = $self->_hash_canonical_request($request);
    my $string_to_sign                   = $self->_string_to_sign($datetime,$scope,$hashed_request);
    my $signature                        = $self->_calculate_signature($secret_key,$service,$region,$date,$string_to_sign);
    $request->header(Authorization => "AWS4-HMAC-SHA256 Credential=$access_key/$scope, SignedHeaders=$signed_headers, Signature=$signature");
}

sub _zulu_time { return strftime('%Y%m%dT%H%M%SZ',gmtime) }


sub _hash_canonical_request {
    my $self = shift;
    my $request = shift; # http::request
    my $method         = $request->method;
    my $uri            = $request->uri;
    my $path           = $uri->path;
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
    for my $header (sort keys %$headers) {
	my @values = ref($headers->{$header}) ? @{$headers->{$header}} : $headers->{$header};
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
    my $signed_headers    = join ';',sort keys %$headers;

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

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2014 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


