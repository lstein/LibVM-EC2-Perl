package VM::EC2::ParmParser;

use strict;
use VM::EC2 '';

=head1 NAME

VM::EC2::ParmParser - Format parameters for passing to the API

=head1 SYNOPSIS

=head1 METHODS

=cut

use Carp 'croak';

sub new { return bless {},ref $_[0] || $_[0] }

sub format_parms {
    my $self = shift;
    my ($args,$spec) = @_;

    my @param;
    for my $format (keys %$spec) {
	my ($prefix,$parser);

	if ((my ($p,$f) = split(/\./,$format))==2) {
	    $parser = $f;
	    $prefix = $p;
	} else {
	    $parser = $format;
	}

	croak "Invalid parameter formatting method '$parser'" unless $self->can($parser);
	my @argkeys = ref $spec->{$format} eq 'ARRAY' ? @{$spec->{$format}} : $spec->{$format};
	my @p       = map {my $exists =  exists   $args->{$_} || exists $args->{VM::EC2->canonicalize($_)};
			   my $val    = $exists ? $args->{$_} ||        $args->{VM::EC2->canonicalize($_)} : undef;
			   $exists ? $self->$parser($_,$val) : ()
	                  } @argkeys;
	if ($prefix) {
	    for (my $i=0;$i<@p;$i+=2) { $p[$i] = "$prefix.$p[$i]" }
	}
	push @param,@p;
    }
    return $args->{-cb},@param;
}

sub args {
    my $self = shift;
    my $default_param_name = shift;
    return unless @_;
    return @_ if $_[0] =~ /^-/;
    return (-filter=>shift) if @_==1 && ref $_[0] && ref $_[0] eq 'HASH';
    return ($default_param_name => \@_);
}

sub filter_parm {
    my $self = shift;
    my ($parameter_name,$values) = @_;
    return $self->name_value_parm($parameter_name,$values);
}

sub name_value_parm {
    my $self = shift;
    my ($parameter_name,$values,$skip_undef_values) = @_;
    
    my @params;
    my $c = 1;
    if (ref $values && ref $values eq 'HASH') {
	while (my ($name,$value) = each %$values) {
	    push @params,("$parameter_name.$c.Name"   => $name);
	    if (ref $value && ref $value eq 'ARRAY') {
		for (my $m=1;$m<=@$value;$m++) {
		    push @params,("$parameter_name.$c.Value.$m" => $value->[$m-1])
		}
	    } else {
		push @params,("$parameter_name.$c.Value" => $value)
		    unless !defined $value && $skip_undef_values;
	    }
	    $c++;
	}
    } else {
	for (ref $values ? @$values : $values) {
	    my ($name,$value) = /([^=]+)\s*=\s*(.+)/;
	    push @params,("$parameter_name.$c.Name"   => $name);
	    push @params,("$parameter_name.$c.Value"  => $value)
		unless !defined $value && $skip_undef_values;
	    $c++;
	}
    }

    return @params;
}

sub single_parm {
    my $self = shift;
    my ($argname,$val) = @_;
    my $v = ref $val  && ref $val eq 'ARRAY' ? $val->[0] : $val;
    return ($argname=>$v);
}

sub list_parm {
    my $self = shift;
    my ($argname,$val) = @_;

    my @params;
    my $c = 1;
    for (ref $val && ref $val eq 'ARRAY' ? @$val : $val) {
	push @params,("$argname.".$c++ => $_);
    }
    return @params;
}

sub block_device_parm {
    my $self     = shift;
    my ($argname,$devlist) = @_;
    my @dev     = ref $devlist && ref $devlist eq 'ARRAY' ? @$devlist : $devlist;

    my @p;
    my $c = 1;
    for my $d (@dev) {
	next unless $d;
	$d =~ /^([^=]+)=([^=]+)$/ or croak "block device mapping must be in format /dev/sdXX=device-name";

	my ($devicename,$blockdevice) = ($1,$2);
	push @p,("$argname.$c.DeviceName"=>$devicename);

	if ($blockdevice =~ /^vol-/) {  # this is a volume, and not a snapshot
	    my ($volume,$delete_on_term) = split ':',$blockdevice;
	    push @p,("$argname.$c.Ebs.VolumeId" => $volume);
	    push @p,("$argname.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if defined $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/
	}
	elsif ($blockdevice eq 'none') {
	    push @p,("$argname.$c.NoDevice" => '');
	} elsif ($blockdevice =~ /^ephemeral\d$/) {
	    push @p,("$argname.$c.VirtualName"=>$blockdevice);
	} else {
	    my ($snapshot,$size,$delete_on_term,$vtype,$iops) = split ':',$blockdevice;

	    # Workaround for apparent bug in 2012-12-01 API; instances will crash without volume size
	    # even if a snapshot ID is provided
	    if ($snapshot) {
		$size ||= eval{$self->describe_snapshots($snapshot)->volumeSize};
		push @p,("$argname.$c.Ebs.SnapshotId" =>$snapshot);
	    }

	    push @p,("$argname.$c.Ebs.VolumeSize" =>$size)                    if $size;
	    push @p,("$argname.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if defined $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/;
	    push @p,("$argname.$c.Ebs.VolumeType"=>$vtype)                    if $vtype;
	    push @p,("$argname.$c.Ebs.Iops"=>$iops)                           if $iops;
	}
	$c++;
    }
    return @p;
}

# ['eth0=eni-123456','eth1=192.168.2.1,192.168.3.1,192.168.4.1:subnet-12345:sg-12345:true:My Weird Network']
# form 1: ethX=network device id
# form 2: ethX=primary_address,secondary_address1,secondary_address2...:subnetId:securityGroupId:deleteOnTermination:description
# form 3: ethX=primary_address,secondary_address_count:subnetId:securityGroupId:deleteOnTermination:description
sub network_interface_parm {
    my $self = shift;
    my ($argname,$devlist) = @_;
    my @dev     = ref $devlist && ref $devlist eq 'ARRAY' ? @$devlist : $devlist;

    my @p;
    my $c = 0;
    for my $d (@dev) {
	$d =~ /^eth(\d+)\s*=\s*([^=]+)$/ or croak "network device mapping must be in format ethX=option-string";

	my ($device_index,$device_options) = ($1,$2);
	push @p,("$argname.$c.DeviceIndex" => $device_index);
	my @options = split ':',$device_options;
	if (@options == 1) {
	    push @p,("$argname.$c.NetworkDeviceId" => $options[0]);
	} 
	else {
	    my ($ip_addresses,$subnet_id,$security_group_id,$delete_on_termination,$description) = @options;
	    my @addresses = split /\s*,\s*/,$ip_addresses;
	    for (my $a = 0; $a < @addresses; $a++) {
		if ($addresses[$a] =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
		    push @p,("$argname.$c.PrivateIpAddresses.$a.PrivateIpAddress" => $addresses[$a]);
		    push @p,("$argname.$c.PrivateIpAddresses.$a.Primary"          => $a == 0 ? 'true' : 'false');
		}
		elsif ($addresses[$a] =~ /^\d+$/ && $a > 0) {
		    push @p,("$argname.$c.SecondaryPrivateIpAddressCount"        => $addresses[$a]);
		}
	    }
	    my @sgs = split ',',$security_group_id;
	    for (my $i=0;$i<@sgs;$i++) {
		push @p,("$argname.$c.SecurityGroupId.$i" => $sgs[$i]);
	    }

	    push @p,("$argname.$c.SubnetId"              => $subnet_id)             if length $subnet_id;
	    push @p,("$argname.$c.DeleteOnTermination"   => $delete_on_termination) if length $delete_on_termination;
	    push @p,("$argname.$c.Description"           => $description)           if length $description;
	}
	$c++;
    }
    return @p;
}

sub boolean_parm {
    my $self = shift;
    my ($argname,$val) = @_;
    return ($argname => $val ? 'true' : 'false');
}

1;

=head1 SEE ALSO

L<VM::EC2>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2013 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

