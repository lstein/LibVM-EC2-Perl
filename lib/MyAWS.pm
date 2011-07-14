package MyAWS;

=head1 NAME

MyAWS - Lincoln's simple AWS interface

=head1 SYNOPSIS

 # set environment variables EC2_ACCESS_KEY, EC2_SECRET_KEY and/or EC2_URL
 # to fill in arguments automatically

 my $aws = MyAWS->new(-access_key => 'access key id',
                      -secret_key => 'aws_secret_key',
                      -endpoint   => 'http://ec2.us-east-1.amazonaws.com');

 my ($image) = $aws->describe_images(-image_id=>'ami-12345');
 $image->run_instances(-key_name      =>'My_key',
                       -security_group=>'default',
                       -min_count=>2,
                       -instance_type => 't1.micro'

 my @snapshots = $aws->describe_snapshots(-snapshot_id => 'id',
                                          -owner         => 'ownerid',
                                          -restorable_by => 'userid',
                                          -filter        => ['tag:Name=Root','tag:Role=Server']);

 foreach (@snapshots) { $_->add_tags('Version'=>'1.0') }

 my @instances = $aws->describe_instances(-instance_id => 'id',
                                          -filter      => ['architecture=i386',
                                                           'tag:Role=Server']);
 my @volumes = $aws->describe_volumes(-volume_id => 'id',
                                      -filter    => ['tag:Role=Server']);

=head1 DESCRIPTION

This is a partial interface to the 2011-05-15 version of the Amazon AWS API. It was written 
primarily to provide access to the new tag & metadata interface that is not currently supported
by Net::Amazon::EC2.

The main interface is the MyAWS object, which provides methods for
interrogating the Amazon EC2, launching instances, and managing
instance lifecycle. These methods return the following major object
classes which act as specialized interfaces to AWS:

 MyAWS::Object::Attachment          -- Attachment of a EBS volume to a machine instance
 MyAWS::Object::BlockDevice         -- A block device
 MyAWS::Object::BlockDeviceMapping  -- Mapping of a virtual storage device to a block device
 MyAWS::Object::Instance            -- Virtual machine instances
 MyAWS::Object::Image               -- Amazon Machine Images (AMIs)
 MyAWS::Object::Snapshot            -- EBS snapshots
 MyAWS::Object::EBS                 -- Elastic Block Store (EBS) disk volumes
 MyAWS::Object::Group               -- Security groups
 MyAWS::Object::Region              -- Availability regions
 MyAWS::Object::Tag                 -- Metadata tags

In addition, there are several utility classes:

 M
    
=head1 METHODS

=over 4

=item $aws = MyAWS->new(-access_key=>$id,-secret_key=>$key,-endpoint=>$url)

Create a new Amazon access object. Required parameters are:

 -access_key   Access ID for an authorized user
 -secret_key   Secret key corresponding to the Access ID
 -endpoint     The URL for making API requests

One or more of these options can be omitted if the environment variables EC2_ACCESS_KEY,
EC2_SECRET_KEY and EC2_URL are defined.

=item @instances = $aws->describe_instances(-instance_id=>$id,-filter=>\@filters)

Return a series of MyAWS::Object::Instance objects. Optional parameters are:

 -instance_id     ID of the instance to return information on
 -filter          A string scalar, anonymous hash, or anonymous array 
                   containing filters to apply.

There are a large number of potential filters, which are listed at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeInstances.html

Three syntaxes are supported:

  -filter => $scalar   Scalar in format 'filter_type=value'
  -filter => [array]   Array reference in format ['filter1=value1','filter2=value2'...]
  -filter => {hash}    Hash reference in format {filter1=>'value1',filter2=>'value2...}

When multiple filters are provided, they are ANDed together

Examples:

  # fetch all instances you have access to which have a /dev/sdh
  # block device mapping
  @i = $aws->describe_instances(-filter=>'block-device-mapping.device_name=/dev/sdh')

  # fetch all instances with architecture i386 and a tag-value pair of
  # Role=>'Server'
  @i = $aws->describe_instances(-filter=>['architecture=i386',
                                          'tag:Role=Server']);
  # same as above
  @i = $aws->describe_instances(-filter=>{architecture=> 'i386',
                                         'tag:Role'   => 'Server'});

=item @snaps = $aws->describe_snapshots(-snapshot_id=>$id,-owner=>$owner,-restorable_by=>$id,-filter=>\%filters)

Returns a series of MyAWS::Object::Snapshot objects. All parameters
are optional:

 -snapshot_id     ID of the snapshot
 -owner           Filter by owner ID
 -restorable_by   Filter by IDs of a user who is allowed to restore
                   the snapshot
 -filter          A series of filters

Filters are specified using the syntax described in
describe_instances(). The full list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeSnapshots.html

=item @v = $aws->describe_volumes(-volume_id=>$id,-filter=>\%filters)

Return a series of MyAWS::Object::Volume objects. Optional parameters:

 -volume_id    The id of the volume to fetch
 -filter       One or more filters to apply to the search

The list of filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeVolumes.html

=back

=cut

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(hmac_sha256);
use POSIX 'strftime';
use URI;
use URI::Escape;
use MyAWS::Object;
use Carp 'croak';
our $VERSION = '0.1';

sub new {
    my $self = shift;
    my %args = @_;
    my $id           = $args{-access_key} || $ENV{EC2_ACCESS_KEY} or croak "Please provide AccessKey parameter";
    my $secret       = $args{-secret_key} || $ENV{EC2_SECRET_KEY} or croak "Please provide SecretKey parameter";
    my $endpoint_url = $args{-endpoint}   || $ENV{EC2_URL}        or croak "Please provide EndPoint  parameter";  
    $endpoint_url   .= '/' unless $endpoint_url =~ m!/$!;
    return bless {
	id       => $id,
	secret   => $secret,
	endpoint => $endpoint_url,
    },ref $self || $self;
}

sub describe_regions {
    my $self = shift;
    my %args;
    if ($_[0] =~ /^-/) {
	%args = @_;
    } else {
	%args = (-region_name => \@_) if @_;
    }

    my @params = $self->mfilter_parm('RegionName',\%args);
    push @params,$self->tagfilter_parm(\%args);
    return $self->call('DescribeRegions',@params);
}

sub describe_snapshots {
    my $self = shift;
    my %args = @_;
    my @params;

    push @params,$self->mfilter_parm('SnapshotId',\%args);
    push @params,$self->mfilter_parm('Owner',\%args);
    push @params,$self->mfilter_parm('RestorableBy',\%args);
    push @params,$self->tagfilter_parm(\%args);
    return $self->call('DescribeSnapshots',@params) or return;
}

sub describe_instances {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->mfilter_parm('InstanceId',\%args);
    push @params,$self->tagfilter_parm(\%args);
    my $reservation_set = $self->call('DescribeInstances',@params) or return;
    my @i = $reservation_set->instances;
    if (!wantarray) { # scalar context
	return       if @i == 0;
	return $i[0] if @i == 1;
    } else {
	return @i
    }
}

sub describe_volumes {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->mfilter_parm('VolumeId',\%args);
    push @params,$self->tagfilter_parm(\%args);
    return $self->call('DescribeVolumes',@params) or return;
}

sub describe_images {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->mfilter_parm('ExecutableBy',\%args);
    push @params,$self->mfilter_parm('ImageId',\%args);
    push @params,$self->mfilter_parm('Owner',\%args);
    push @params,$self->tagfilter_parm(\%args);
    return $self->call('DescribeImages',@params) or return;
}

sub describe_tags {
    my $self = shift;
    my %args = @_;
    my @params = $self->tagfilter_parm(\%args);
    return $self->call('DescribeTags',@params);    
}

sub create_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->mfilter_parm('ResourceId',\%args);
    push @params,$self->tagcreate_parm(\%args);
    return $self->call('CreateTags',@params);    
}

sub delete_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->mfilter_parm('ResourceId',\%args);
    push @params,$self->tagdelete_parm(\%args);
    return $self->call('DeleteTags',@params);    
}

sub run_instances {
    my $self = shift;
    my %args = @_;
    $args{-image_id}  or croak "run_instances(): -image_id argument missing";
    $args{-min_count} ||= 1;
    $args{-max_count} ||= $args{-min_count};

    my @p  =$self->filter_parm('ImageId',\%args);
    push @p,$self->filter_parm('MinCount',\%args);
    push @p,$self->filter_parm('MaxCount',\%args);
    push @p,$self->filter_parm('KeyName',\%args)                      if $args{-key_name};
    push @p,$self->mfilter_parm('SecurityGroupId',\%args);
    push @p,$self->mfilter_parm('SecurityGroup',\%args);
    push @p,$self->filter_parm('InstanceType',\%args)                 if $args{-instance_type};
    push @p,(UserData=>encode_base64($args{user_data}))               if $args{-user_data};
    push @p,('Placement.AvailabilityZone'=>$args{-availability_zone}) if $args{-availability_zone};
    push @p,('Placement.GroupName'=>$args{-group_name})               if $args{-group_name};
    push @p,('Placement.Tenancy'=>$args{-tenancy})                    if $args{-tenancy};
    push @p,$self->filter_parm('RamdiskId',\%args)                    if $args{-ramdisk_id};
    push @p,$self->block_device_parm($args{-block_devices})           if $args{-block_devices};
    push @p,('Monitoring.Enabled'=>'true')                            if $args{-monitoring};
    push @p,('DisableApiTermination'=>'true')                         if $args{-termination_protection};
    push @p,('InstanceInitiatedShutdownBehavior'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};
    push @p,('PrivateIpAddress'=>$args{-private_address})             if $args{-private_address};

    my $instanceset = $self->call('RunInstances',@p);
    return $instanceset->instances;
}

sub start_instances {
    my $self = shift;
    my @instance_ids = @_;
    @instance_ids or croak "usage: start_instances(@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('StartInstances',@params) or return;
}

sub stop_instances {
    my $self = shift;
    my (@instance_ids,$force);

    if ($_[0] =~ /^-/) {
	my %argv   = @_;
	@instance_ids = ref $argv{-instance_ids} ?
	               @{$argv{-instance_ids}} : $argv{-instance_ids};
	$force     = $argv{-force};
    } else {
	@instance_ids = @_;
    }
    @instance_ids or croak "usage: stop_instances(@instance_ids)";    

    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    push @params,Force=>1 if $force;
    return $self->call('StopInstances',@params) or return;
}

sub get_console_output {
    my $self = shift;
    my %args;
    if ($_[0] =~ /^-/) {
	%args = @_; 
    } else {
	%args = (-instance_id => shift);
    }
    $args{-instance_id} or croak "Usage: get_console_output(-instance_id=>\$id)";
    my @params = $self->mfilter_parm('InstanceId',\%args);
    return $self->call('GetConsoleOutput',@params) or return;
}

# ------------------------------------------------------------------------------------------

sub is_error {
    defined shift->error();
}

sub error {
    my $self = shift;
    my $d    = $self->{error};
    $self->{error} = shift if @_;
    $d;
}

sub canonicalize {
    my $self = shift;
    my $name = shift;
    while ($name =~ /\w[A-Z]/) {
	$name    =~ s/([a-zA-Z])([A-Z])/\L$1_$2/g;
    }
    return '-'.lc $name;
}

sub filter_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return ($argname=>$args->{$name}) if exists $args->{$name};
}

sub mfilter_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);

    my @params;
    if (my $a = $args->{$name}) {
	my $c = 1;
	for (ref $a && ref $a eq 'ARRAY' ? @$a : $a) {
	    push @params,("$argname.".$c++ => $_);
	}
    }

    return @params;
}

sub tagfilter_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Filter','Name','Value',$args);
}

sub tagcreate_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args);
}

sub tagdelete_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args,1);
}

sub key_value_parameters {
    my $self = shift;
    # e.g. 'Filter', 'Name','Value',{-filter=>{a=>b}}
    my ($parameter_name,$keyname,$valuename,$args,$skip_undef_values) = @_;  
    my $arg_name     = $self->canonicalize($parameter_name);
    
    my @params;
    if (my $a = $args->{$arg_name}) {
	my $c = 1;
	if (ref $a && ref $a eq 'HASH') {
	    while (my ($name,$value) = each %$a) {
		push @params,("$parameter_name.$c.$keyname"   => $name);
		push @params,("$parameter_name.$c.$valuename" => $value)
		    unless !defined $value && $skip_undef_values;
		$c++;
	    }
	} else {
	    for (ref $a ? @$a : $a) {
		my ($name,$value) = /([^=]+)\s*=\s*(.+)/;
		push @params,("$parameter_name.$c.$keyname"   => $name);
		push @params,("$parameter_name.$c.$valuename" => $value)
		    unless !defined $value && $skip_undef_values;
		$c++;
	    }
	}
    }

    return @params;
}

sub block_device_parm {
    my $self    = shift;
    my $devlist = shift;

    my @dev     = ref $devlist ? @$devlist : $devlist;

    my @p;
    my $c = 1;
    for my $d (@dev) {
	$d =~ /^([^=]+)=([^=]+)$/ or croak "block device mapping must be in format /dev/sdXX=device-name";

	my ($devicename,$blockdevice) = ($1,$2);
	push @p,("BlockDeviceMapping.$c.DeviceName"=>$devicename);

	if ($blockdevice eq 'none') {
	    push @p,("BlockDeviceMapping.$c.NoDevice" => '');
	} elsif ($blockdevice =~ /^ephemeral\d$/) {
	    push @p,("BlockDeviceMapping.$c.VirtualName"=>$blockdevice);
	} else {
	    my ($snapshot,$size,$delete_on_term) = split ':',$blockdevice;
	    push @p,("BlockDeviceMapping.$c.Ebs.SnapshotId"=>$snapshot)                if $snapshot;
	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeSize" =>$size)                   if $size;
	    push @p,("BlockDeviceMapping.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/
	}
	$c++;
    }
    return @p;
}

sub id       { shift->{id}       }
sub secret   { shift->{secret}   }
sub endpoint { shift->{endpoint} }
sub version  { '2011-05-15'      }
sub timestamp {
    return strftime("%Y-%m-%dT%H:%M:%SZ",gmtime);
}
sub ua {
    my $self = shift;
    return $self->{ua} ||= LWP::UserAgent->new;
}

sub call {
    my $self    = shift;
    my $response  = $self->make_request(@_);

    unless ($response->is_success) {
	if ($response->code == 400) {
	    my $error = MyAWS::Object->create_error_object($response->decoded_content,$self);
	    $self->error($error);
	    return;
	} else {
	    print STDERR $response->request->as_string=~/Action=(\w+)/,': ',$response->status_line,"\n";
	    return;
	}
    }
    $self->error(undef);
    my @obj = MyAWS::Object->response2objects($response,$self);

    # slight trick here so that we return one object in response to
    # describe_images(-image_id=>'foo'), rather than the number "1"
    if (!wantarray) { # scalar context
	return $obj[0] if @obj == 1;
	return         if @obj == 0;
    } else {
	return @obj;
    }
}

sub make_request {
    my $self    = shift;
    my ($action,@args) = @_;
    my $request = $self->_sign(Action=>$action,@args);
    return $self->ua->request($request);
}

# adapted from Jeff Kim's Net::Amazon::EC2 module
sub _sign {
    my $self    = shift;
    my @args    = @_;

    my $action = 'POST';
    my $host   = lc URI->new($self->endpoint)->host;
    my $path   = '/';

    my %sign_hash                = @args;
    $sign_hash{AWSAccessKeyId}   = $self->id;
    $sign_hash{Timestamp}        = $self->timestamp;
    $sign_hash{Version}          = $self->version;
    $sign_hash{SignatureVersion} = 2;
    $sign_hash{SignatureMethod}  = 'HmacSHA256';

    my @param;
    my @parameter_keys = sort keys %sign_hash;
    for my $p (@parameter_keys) {
	push @param,join '=',map {uri_escape($_,"^A-Za-z0-9\-_.~")} ($p,$sign_hash{$p});
    }
    my $to_sign = join("\n",
		       $action,$host,$path,join('&',@param));
    my $signature = encode_base64(hmac_sha256($to_sign,$self->secret),'');
    $sign_hash{Signature} = $signature;

    my $uri = URI->new($self->endpoint);
    $uri->query_form(\%sign_hash);

    return POST $self->endpoint,[%sign_hash];
}

1;
