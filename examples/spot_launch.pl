#!/usr/bin/perl

use strict;
use VM::EC2 qw(:standard spot_instance);
use Statistics::Descriptive;
use Date::Parse;
use Getopt::Long;
use POSIX 'strftime';
use Carp 'croak';

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

This script requires the following Perl modules and their dependencies to be installed:
  
  1) VM::EC2
  2) Date::Parse
  3) Statistics::Descriptive

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

do_status_report($ec2,$Tag) && exit 0 if $Status_report;
do_instance_update($ec2,{-tag   => $Tag,
			 -image => $Ami,
			 -type  => $Instance_type,
			 -count => $Instance_count,
			 -price => $Max_price,
			 -key   => $Keyname,
			 -sg    => $Security_group,
		   }) && exit 0;
exit 0;

sub do_status_report {
    my ($ec2,$tag) = @_;

    my @requests  = $ec2->describe_spot_instance_requests({'tag-key' => $tag});

    for my $r (@requests) {

	print "$r:",' state=',$r->state,' status=',$r->status,' bid=',$r->spot_price,' fault=',$r->fault;
	
	if (my $i = $r->instanceId) {
	    my $current_price = get_current_price($ec2,$r->launched_availability_zone,$r->productDescription,$r->instanceType);
	    print " instanceId=$i",' created=',$r->create_time," public_dns=",$i->dnsName," current_price=$current_price";
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
							  'state'   => ['open','fulfilled']
							 });

    my $active  = grep {$_->state eq 'fulfilled'} @requests;
    my $pending = grep {$_->state eq 'open'}      @requests;
    $active  ||= 0;
    $pending ||= 0;

    # $count will be number of requests we need to launch
    my $count = $opt->{-count} - @requests;

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
    foreach (@requests) { $_->add_tag($opt->{-tag}) }
}

sub find_best_zone {
    my ($ec2,$opt) = @_;
    
    my $ami = $ec2->describe_images($opt->{-image});
    $ami || croak "AMI $ami not found in region ",$ec2->region;
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
	min    => $zones{$sorted_zones[0]}->min,
	max    => $zones{$sorted_zones[0]}->max,
	mean   => $zones{$sorted_zones[0]}->mean,
	median => $zones{$sorted_zones[0]}->median,
	current=> $current_price{$sorted_zones[0]}{price}
    }
}

sub get_current_price {
    my ($ec2,$zone,$platform,$type) = @_;
    my @history = $ec2->describe_spot_price_history(-start_time           => format_time(time()),
						    -availability_zone    => $zone,
						    -instance_type        => $type,
						    -product_description  => $platform);
    return $history[0]->spot_price;
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
