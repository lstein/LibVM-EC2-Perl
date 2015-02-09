#!/usr/bin/perl

=head1 NAME

 spot_launch.pl     Keep a series of spot instances running in the cheapest available zone.

=head1 SYNOPSIS

 # Create two spot instance requests in the cheapest availability region.

 % spot_launch.pl -verbose --tag=testlaunch --region=us-west-2 --image=ami-c04fc4f0 --count=2 --price=0.02 --security_group=web+ssh --key_name=my_default
 Insufficient active spot requests (1 active, 0 pending). Requesting 1 new spot instances
 Examining 30 day spot market for cheapest zone in which to run platform=Linux/UNIX, instance_type=t1.micro
 Cheapest zone is us-west-2a; 30 day pricing for t1.micro = $ 0.003000/0.003100/0.00305215946843854 (min/max/mean)
 1  new spot instance requests launched in zone us-west-2a

 # View the status of the instances

 % spot_launch.pl --status --tag=testlaunch --region=us-west-2
 sir-03dppl2h: state=active status=fulfilled bid=0.020000 instanceId=i-2e500c25 instance_status=running created=2014-08-27T03:17:46.000Z public_dns=ec2-54-190-148-127.us-west-2.compute.amazonaws.com current_price=0.003100
 sir-03dwpxa7: state=open status=pending-evaluation bid=0.020000

=head1 DESCRIPTION

This script surveys the 30 day pricing history in the EC2 region of
your preference, finds the zone with the cheapest historical price for
the instance type of your choice, and then creates the appropriate
number of spot requests. You may run this script under cron to
periodically check that your spot instances are running and launch new
ones.

The --status option prints out an easily-parsed report of the active
spot requests and the instances running under them.

To distinguish spot requests managed by this script from others,
provide the --tag option. This will tag each of the spot requests with
a distinguishing string.

=head1 COMMAND-LINE ARGUMENTS

  --access_key     <string>          Amazon access key (EC2_ACCESS_KEY environment var)
  --secret_key     <string>          Amazon secret key (EC2_SECRET_KEY environment var)
  --region         <string>          Desired region to run spot instances in (us-east-1)
  --image          <ami-xxxx>        AMI to launch (no default)
  --instance_type  <string>          Instance type to launch (t1.micro)
  --key_name       <string>          SSH keyname for instances (optional, no default)
  --security_group <string>          Security group name for instances (optional, no default)
  --count          <integer>         Number of instances to launch (1)
  --tag            <string>          Tag to attach to instances ("my_spot_instance")
  --price          <float>           Maximum bid (no default)
  --status                           Print status report on running instances
  --verbose                          Verbose reporting

You may use double-dashed long options in the form

  --option=value

single-dashed options in the form

 -option value

or abbreviate options to the smallest number of unique characters:

 -o value

Note that the --image and --price options are mandatory. You probably
want to provide the --key_name option to allow SSH logins, and the
--security_group option to control firewall rules.

=head1 ENVIRONMENT VARIABLES

The following environment variables are used if the corresponding
options are not present:

 EC2_ACCESS_KEY     your access key
 EC2_SECRET_KEY     your secret key
 EC2_URL            the desired region endpoint

=head1 SEE ALSO

L<VM::EC2>

=head1 AUTHOR

Lincoln Stein, lincoln.stein@gmail.com

Copyright (c) 2014 Ontario Institute for Cancer Research This package
and its accompanying libraries is free software; you can redistribute
it and/or modify it under the terms of the GPL (either version 1, or
at your option, any later version) or the Artistic License 2.0.  Refer
to LICENSE for the full license text. In addition, please see
DISCLAIMER.txt for disclaimers of warranty.

=cut


use strict;
use Getopt::Long;
use POSIX 'strftime';
use Carp 'croak';
use Memoize;
memoize('get_current_price');

load_module('Statistics::Descriptive');
load_module('Date::Parse');
load_module('VM::EC2');
VM::EC2->import(':standard','spot_instance');

my ($Access_key,$Secret_key,$Region,
    $Ami,$Instance_type,$Instance_count,$Tag,$Max_price,
    $Keyname,$Security_group,
    $Status_report,$Verbose);

GetOptions(
    'access_key|access-key=s'  => \$Access_key,
    'secret_key|secret-key=s'  => \$Secret_key,
    'endpoint|region=s'        => \$Region,
    'image|ami=s'              => \$Ami,
    'instance_type=s'          => \$Instance_type,
    'count=i'                  => \$Instance_count,
    'status'                   => \$Status_report,
    'tag=s'                    => \$Tag,
    'key_name=s'               => \$Keyname,
    'security_group=s'         => \$Security_group,
    'price=f'                  => \$Max_price,
    'verbose'                  => \$Verbose,
    ) or die <<USAGE;
Usage: $0 [options]
  -access_key     <string>          Amazon access key (EC2_ACCESS_KEY environment var)
  -secret_key     <string>          Amazon secret key (EC2_SECRET_KEY environment var)
  -region         <string>          Desired region to run spot instances in (us-east-1)
  -image          <ami-xxxx>        AMI to launch (no default)
  -instance_type  <m1.small>        Instance type to launch (t1.micro)
  -key_name       <string>          SSH keyname for instances (optional, no default)
  -security_group <string>          Security group name for instances (optional, no default)
  -count          <integer>         Number of instances to launch (1)
  -tag            <string>          Tag to attach to instances ("my_spot_instance")
  -price          <float>           Maximum bid (no default)
  -status                           Print status report on running instances
  -verbose                          Verbose reporting
USAGE

# defaults
$Access_key    ||= $ENV{EC2_ACCESS_KEY};
$Secret_key    ||= $ENV{EC2_SECRET_KEY};
$Region        ||= 'us-east-1';
$Ami           ||  croak 'Must specify AMI to launch using the -image option' unless $Status_report;
$Instance_type ||= 't1.micro';
$Instance_count||= 1;
$Tag           ||= 'my_spot_instance';
$Max_price     || croak 'Must specificy maximum bid using the -price option' unless $Status_report;
$Verbose       ||= 0;

# EC2 object creation
my $ec2 = VM::EC2->new(-access_key => $Access_key,
		       -secret_key => $Secret_key,
		       -region     => $Region) or croak 'Could not create VM::EC2 object';

if ($Status_report) {
    do_status_report($ec2,$Tag);
}

if ($Ami) {
    do_instance_update($ec2,{-tag   => $Tag,
			     -image => $Ami,
			     -type  => $Instance_type,
			     -count => $Instance_count,
			     -price => $Max_price,
			     -key   => $Keyname,
			     -sg    => $Security_group,
		       }) && exit 0;
}

exit 0;

sub do_status_report {
    my ($ec2,$tag) = @_;

    my @requests  = $ec2->describe_spot_instance_requests({'tag-key' => $tag});

    for my $r (@requests) {
	next if $r->instance && $r->instance->status eq 'terminated';

	print "$r:",' state=',$r->state,' status=',$r->status,' bid=',$r->spot_price;
	print ' fault=',$r->fault if $r->fault;
	
	if (my $i = $r->instance) {
    my $current_price = get_current_price($ec2,$r->launched_availability_zone,$r->productDescription,$i->instance_type);
	    print " instanceId=$i",' instance_status=',$i->status,' created=',$r->create_time," public_dns=",$i->dnsName," current_price=$current_price";
	}

	print "\n";
    }
    print "No tagged spot requests are pending.\n" unless @requests;

    1;
}

sub do_instance_update {
    my ($ec2,$opt) = @_;

    # get the spot instance requests that are e
    my @requests = $ec2->describe_spot_instance_requests({'tag-key' => $opt->{-tag},
							  'state'   => ['open','active']
							 });

    my $active  = grep {$_->state eq 'active' && $_->instance->status eq 'running'} @requests;
    my $pending = grep {$_->state eq 'open'}                                        @requests;
    $active  ||= 0;
    $pending ||= 0;

    # $count will be number of requests we need to launch
    my $count = $opt->{-count} - ($active+$pending);

    # enough instances running or potentially running
    if ($count <= 0) { 
	logit("Sufficient active spot requests: $active active, $pending pending");
	return;
    }

    logit("Insufficient active spot requests ($active active, $pending pending). Requesting $count new spot instances");
    $opt->{-count} = $count;
    do_make_request($ec2,$opt);
    1;
}

sub do_make_request {
    my ($ec2,$opt) = @_;
    my $best_zone        = find_best_zone($ec2,$opt);
    my ($zone,$min,$max,$mean) = @${best_zone}{'zone','min','max','mean'};
    logit("Cheapest zone is $zone; 30 day pricing for $opt->{-type} = \$ $min/$max/$mean (min/max/mean)");
    logit("WARNING: Because best 30 day price (\$$min) is greater than desired price (\$$opt->{-price}), it is unlikely these requests will ever run.") if $min > $opt->{-price};

    my @params  = (-spot_price     => $opt->{-price},
		   -image_id       => $opt->{-image},
		   -instance_type  => $opt->{-type},
		   -instance_count => $opt->{-count},
		   -zone           => $zone,
		   -type           => 'one-time');
    push @params,(-key_name        => $opt->{-key}) if $opt->{-key};
    push @params,(-security_group  => $opt->{-sg})  if $opt->{-sg};
    
    my @requests = $ec2->request_spot_instances(@params);
    croak $ec2->error unless @requests;

    logit(scalar(@requests)," new spot instance requests launched in zone $zone");
    if (defined $opt->{-tag}) {
	logit("tagging instances with $opt->{-tag}");
	sleep 2; # wait for requests to register
	foreach (@requests) { $_->add_tag($opt->{-tag}) }
    }
}

sub find_best_zone {
    my ($ec2,$opt) = @_;
    
    my $ami = $ec2->describe_images($opt->{-image});
    $ami || croak "AMI $opt->{-image} not found: ",$ec2->error;
    my $platform = $ami->platform =~ /Windows/ ? 'Windows' : 'Linux/UNIX';

    logit("Examining 30 day spot market for cheapest zone in which to run platform=$platform, instance_type=$opt->{-type}");

    my $start   = format_time(time()-30*60*60*24); # now minus 30 days in seconds
    my $end     = format_time(time());
    
    my @history = $ec2->describe_spot_price_history(-start_time           => $start,
						    -end_time             => $end,
						    -instance_type        => $opt->{-type},
						    -product_description  => $platform);
    @history or croak "No pricing information for $opt->{-type} ($platform) in this region. Please check availability of requested instance type";

    my (%zones,%current_price);
    for my $h (@history) {
	my $zone  = $h->availability_zone;
	my $price = $h->spot_price;
	$zones{$zone} ||= Statistics::Descriptive::Full->new();
	$zones{$zone}->add_data($price);

	my $time  = str2time($h->timestamp);
	if (!$current_price{$zone}{time} || $current_price{$zone}{time} > $time) {
	    $current_price{$zone}{price} = $price;
	    $current_price{$zone}{time}  = $time;
	}
    }

    my @sorted_zones = sort { ($zones{$a}->mean <=> $zones{$b}->mean ||
			       $current_price{$a}{price} <=> $current_price{$b}{price})
                            } keys %zones;
    
    return {
	zone   => $sorted_zones[0],
	min    => sprintf('%.4f',$zones{$sorted_zones[0]}->min),
	max    => sprintf('%.4f',$zones{$sorted_zones[0]}->max),
	mean   => sprintf('%.4f',$zones{$sorted_zones[0]}->mean),
	median => sprintf('%.4f',$zones{$sorted_zones[0]}->median),
	current=> sprintf('%.4f',$current_price{$sorted_zones[0]}{price})
    }
}

sub get_current_price {
    my ($ec2,$zone,$platform,$type) = @_;
    my @history = $ec2->describe_spot_price_history(-start_time           => format_time(time()),
						    -availability_zone    => $zone,
						    -instance_type        => $type,
						    -product_description  => $platform);
    return sprintf('%.4f',$history[0]->spot_price);
}

sub format_time {
    my $seconds = shift;
    return strftime('%Y-%m-%dT%H:%M:%S',localtime($seconds));
}

sub logit {
    my @msg = @_;
    return unless $Verbose;
    print STDERR "@msg\n";
}

sub load_module {
    my $module = shift;
    return if eval "use $module; 1";
    print STDERR "You are missing Perl module $module. Do you want to install it? [Yn]";
    chomp(my $response = <STDIN>);
    die "Aborted.\n" if $response && $response !~ /^[Yy]/;
    eval "use CPAN";
    CPAN::Shell->install($module);
    eval "use $module";
}


