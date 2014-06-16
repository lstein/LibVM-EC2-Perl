package AWS::Signature4;

=head1 NAME

AWS::Signature4 - Create a version4 signature for Amazon Web Services

=head1 SYNOPSIS

  $request = HTTP::Request->new(GET => 'https://ec2.amazonaws.com?Action=DescribeInstances')
  AWS::Signature4->sign($my_secret_key=>$request);  # sign and update headers
  LWP::UserAgent->new(GET => $request);

NOTE: we hard-code AWS4-HMAC-SHA256 as signing algorithm

=cut

sub sign {
    my $class = shift;
    my ($access_key,$secret_key,$credential_scope,$request) = @_;
    my ($hashed_request,$signed_headers) = $self->_hash_canonical_request($request);
    my $string_to_sign                   = $self->_string_to_sign($credential_scope,$request,$hashed_request);
    my $signature                        = $self->_calculate_signature($secret_key,$credential_scope,$string_to_sign);
    $request->header(Authorization => "AWS4-HMAC-SHA256 Credential=$access_key/$credential_scope, SignedHeaders=$signed_headers, Signature=$signature");
}

sub _canonical_request {
    my $self = shift;
    my $request = shift; # http::request
    $method         = $request->method;
    $uri            = $request->uri;
    @params         =  $method eq 'POST' ? URI->new('?',$method->content)->query_form
	                                 :$uri->query_form;
    $headers        = $request->headers;
    $hashed_payload ||= sha256_hex('');

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
	    $value =~ s/^\s+//;
	    $value =~ s/\s+$//;
	    $value =~ s/(\s)\s+/$1/g;
	}
	push @canonical,"$header:".join(',',@values);
    }
    my $canonical_headers = join "\n",@canonical;
    $canonical_headers   .= "\n";
    my $signed_headers    = join ';',sort keys %$headers;

    my $canonical_request = join("\n",$method,$uri,$canonical_query_string,
				 $canonical_headers,$signed_headers,$hashed_payload);

    my $request_digest    = sha256_hex($canonical_request);
    
    return ($request_digest,$signed_headers);
}

sub _string_to_sign {
    my $self = shift;
    my ($credential_scope,$request,$hashed_request) = @_;
}
