package VM::EC2::Staging::Manager;

=head1 NAME

VM::EC2::Staging::Manager - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 use VM::EC2::Staging::Manager;

 my $ec2     = VM::EC2->new;
 my $staging = VM::EC2::Staging::Manager->new(-ec2         => $ec2,
                                              -on_exit     => 'stop', # default, choose root volume type based on behavior
                                              -quiet       => 0,      # default
                                              -scan        => 1,      # default
                                              -image_name  => 'ubuntu-maverick-10.10', # default
                                              -user_name   => 'ubuntu',                # default
                                         );


 
 # reuse or provision new server as needed
 my $server = $staging->provision_server(-architecture      => 'i386',
                                         -availability_zone => 'us-east-1a');

 my $volume = $staging->provision_volume(-name    => 'Pictures',
                                         -fstype  => 'ext4',
                                         -size    => 2) or die $staging->error_str;

 # localhost to remote transfer using symbolic names of volumes
 $server->put('/usr/local/pictures/'   => 'Pictures');

 # remote to local transfer
 $server->get('Pictures' => '/tmp/pictures');

 # remote to remote transfer - useful for interzone transfers
 $server->rsync('Pictures' => "$server2:/home/ubuntu/pictures");

 $server->create_snapshot($vol1 => 'snapshot of pictures');
 $server->terminate;  # automatically terminates when goes out of scope

 $staging->stop_all_servers();
 $staging->start_all_servers();
 $staging->terminate_all_servers();

 # cross-region copying of EBS images.
 my $new_image = $staging->copy_image('ami-12345',$new_region);

=head1 DESCRIPTION

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Instance>
L<VM::EC2::Volume>
L<VM::EC2::Snapshot>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use VM::EC2;
use VM::EC2::Staging::Volume;
use VM::EC2::Staging::Server;
use Carp 'croak';
use File::Spec;
use File::Path 'make_path','remove_tree';
use File::Basename 'dirname';
use Scalar::Util 'weaken';

use constant                     GB => 1_073_741_824;
use constant SERVER_STARTUP_TIMEOUT => 120;

my $VolumeName = 'StagingVolume000';
my $ServerName = 'StagingServer000';
my (%Zones,%Instances,%Volumes,%Managers);

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-ec2}               ||= VM::EC2->new();

    if (my $manager = $class->find_manager($args{-ec2}->endpoint)) {
	return $manager;
    }

    $args{-on_exit}           ||= $class->default_exit_behavior;
    $args{-reuse_key}         ||= $class->default_reuse_keys;
    $args{-username}          ||= $class->default_user_name;
    $args{-architecture}      ||= $class->default_architecture;
    $args{-root_type}         ||= $class->default_root_type;
    $args{-instance_type}     ||= $class->default_instance_type;
    $args{-reuse_volumes}     ||= $class->default_reuse_volumes;
    $args{-image_name}        ||= $class->default_image_name;
    $args{-availability_zone} ||= undef;
    $args{-quiet}             ||= undef;
    $args{-scan}                = 1 unless exists $args{-scan};

    # create accessors
    foreach (keys %args) {
	next unless /^-\w+$/;
	(my $func_name = $_) =~ s/^-//;
	eval <<END;
sub ${class}::${func_name} {
    my \$self = shift;
    my \$d    = \$self->{$_};
    \$self->{$_} = shift if \@_;
    return \$d;
}
END
    die $@ if $@;
    }

    my $self = bless \%args,ref $class || $class;
    weaken($Managers{$self->ec2->endpoint} = $self);
    if ($args{-scan}) {
	$self->info("scanning for existing staging servers and volumes\n");
	$self->scan_region;
    }
    return $self;
}

# class method
# the point of this somewhat odd way of storing managers is to ensure that there is only one
# manager per endpoint, and to avoid circular references in the Server and Volume objects.
sub find_manager {
    my $class    = shift;
    my $endpoint = shift;
    return $Managers{$endpoint};
}

sub default_image_name    { 'ubuntu-maverick-10.10' };  # launches faster than precise
sub default_exit_behavior { 'terminate'   }
sub default_user_name     { 'ubuntu'      }
sub default_architecture  { 'i386'        }
sub default_root_type     { 'instance-store'}
sub default_instance_type { 'm1.small'      }
sub default_reuse_keys    { 1               }
sub default_reuse_volumes { 1               }

# scan for staging instances in current region and cache them
# into memory
# status should be...
# -on_exit => {'terminate','stop','run'}
sub scan_region {
    my $self = shift;
    my $ec2  = shift || $self->ec2;
    $self->_scan_instances($ec2);
    $self->_scan_volumes($ec2);
}

sub _scan_instances {
    my $self = shift;
    my $ec2  = shift;
    my @instances = $ec2->describe_instances({'tag:Role'            => 'StagingInstance',
					      'instance-state-name' => ['running','stopped']});
    for my $instance (@instances) {
	my $keyname  = $instance->keyName                   or next;
	my $keyfile  = $self->_check_keyfile($keyname)      or next;
	my $username = $instance->tags->{'StagingUsername'} or next;
	my $server   = VM::EC2::Staging::Server->new(
	    -keyfile  => $keyfile,
	    -username => $username,
	    -instance => $instance,
	    -endpoint => $self->ec2->endpoint,
	    );
	$self->register_server($server);
    }
}

sub _scan_volumes {
    my $self = shift;
    my $ec2  = shift;

    # now the volumes
    my @volumes = $ec2->describe_volumes(-filter=>{'tag:Role'          => 'StagingVolume',
						   'status'            => ['available','in-use']});
    for my $volume (@volumes) {
	my $status = $volume->status;
	my $zone   = $volume->availabilityZone;

	my %args;
	$args{-endpoint} = $self->ec2->endpoint;
	$args{-volume}   = $volume;
	$args{-name}     = $volume->tags->{StagingName};

	if (my $attachment = $volume->attachment) {
	    $args{-server} = $self->find_server_by_instance($attachment->instance);
	    $args{-mtpt}   = undef; # leave blank - volume will fill in when server is up
	}

	my $vol = VM::EC2::Staging::Volume->new(%args);
	$self->register_volume($vol);
    }
}

sub get_server_in_zone {
    my $self = shift;
    my $zone = shift;
    if (my $servers = $Zones{$zone}{Servers}) {
	return (values %{$servers})[0];
    }
    else {
	return $self->provision_server(-availability_zone => $zone);
    }
}

sub provision_server {
    my $self    = shift;
    my @args    = @_;

    # let subroutine arguments override manager's args
    my %args    = ($self->_run_instance_args,@args);

    # fix possible gotcha -- instance store is not allowed for micro instances.
    $args{-root_type} = 'ebs' if $args{-instance_type} eq 't1.micro';

    my ($keyname,$keyfile) = $self->_security_key;
    my $security_group     = $self->_security_group;
    my $image              = $self->_search_for_image(%args) or croak "No suitable image found";
    my ($instance)         = $self->ec2->run_instances(
	-image_id          => $image,
	-security_group_id => $security_group,
	-key_name          => $keyname,
	%args,
	);
    $instance or croak $self->ec2->error_str;
    $instance->add_tag(Role            => 'StagingInstance');
    $instance->add_tag(StagingUsername => $self->username  );
    $instance->add_tag(Name            => "Staging server created by ".__PACKAGE__);
    my $server = VM::EC2::Staging::Server->new(
	-keyfile  => $keyfile,
	-username => $self->username,
	-instance => $instance,
	-endpoint => $self->ec2->endpoint,
	);
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(SERVER_STARTUP_TIMEOUT);
	$self->wait_for_instances($server);
    };
    alarm(0);
    croak "server did not start after ",SERVER_STARTUP_TIMEOUT," seconds"
	if $@ =~ /timeout/;
    $self->register_server($server);
    return $server;
}

sub _run_instance_args {
    my $self = shift;
    my @args;
    for my $arg (qw(instance_type availability_zone architecture image_name root_type)) {
	push @args,("-${arg}" => $self->$arg);
    }
    return @args;
}

sub find_server_by_instance {
    my $self  = shift;
    my $server = shift;
    return $Instances{$server};
}

sub find_volume_by_name {
    my $self   = shift;
    my $volume = shift;
    return $Volumes{$volume};
}

sub _select_server_by_zone {
    my $self = shift;
    my $zone = shift;
    my @servers = values %{$Zones{$zone}{Servers}};
    return $servers[0];
}

sub register_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = $server->placement;
    $Zones{$zone}{Servers}{$server} = $server;
    $Instances{$server->instance}   = $server;
}

sub unregister_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = eval{$server->availability_zone} or return; # avoids problems at global destruction
    delete $Zones{$zone}{Servers}{$server};
    delete $Instances{$server->instance};
}

sub servers {
    my $self = shift;
    return values %Instances;
}

sub register_volume {
    my $self = shift;
    my $vol  = shift;
    $Zones{$vol->availabilityZone}{Volumes}{$vol} = $vol;
    $Volumes{$vol->volumeId} = $vol;
}

sub unregister_volume {
    my $self = shift;
    my $vol  = shift;
    my $zone = $vol->availabilityZone;
    delete $Zones{$zone}{$vol};
    delete $Volumes{$vol->volumeId};
}

sub start_all_servers {
    my $self = shift;
    my @servers = $self->servers;
    my @need_starting = grep {$_->current_status eq 'stopped'} @servers;
    return unless @need_starting;
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(SERVER_STARTUP_TIMEOUT);
	$self->_start_instances(@need_starting);
    };
    alarm(0);
    croak "some servers did not start after ",SERVER_STARTUP_TIMEOUT," seconds"
	if $@ =~ /timeout/;
}

sub stop_all_servers {
    my $self = shift;
    # my @servers = keys %Instances;  # allows this to run correctly during global destruct
    my $ec2 = $self->ec2;
    my @servers  = grep {$_->ec2 eq $ec2} $self->servers;
    @servers or return;
    $self->info("Stopping servers @servers.\n");
    $self->ec2->stop_instances(@servers);
    $self->ec2->wait_for_instances(@servers);
    $self->unregister_server($_) foreach @servers;
}

sub terminate_all_servers {
    my $self = shift;
    my $ec2 = $self->ec2 or return;
#    my @servers = keys %Instances; # allows this to run correctly during global destruct
    my @servers  = grep {$_->ec2 eq $ec2} $self->servers;
    @servers or return;
    
    $self->info("Terminating servers @servers.\n");
    $ec2->terminate_instances(@servers) or warn $self->ec2->error_str;
    $ec2->wait_for_instances(@servers);
    unless ($self->reuse_key) {
	$ec2->delete_key_pair($_) foreach $ec2->describe_key_pairs(-filter=>{'key-name' => 'staging-key-*'});
    }
    $self->unregister_server($_) foreach @servers;
}

sub _start_instances {
    my $self = shift;
    my @need_starting = @_;
    $self->info("starting instances: @need_starting.\n");
    $self->ec2->start_instances(@need_starting);
    $self->wait_for_instances(@need_starting);
}

sub wait_for_instances {
    my $self = shift;
    my @instances = @_;
    $self->ec2->wait_for_instances(@instances);
    my %pending = map {$_=>$_} grep {$_->current_status eq 'running'} @instances;
    $self->info("waiting for ssh daemon on @instances.\n") if %pending;
    while (%pending) {
	for my $s (values %pending) {
	    unless ($s->ping) {
		sleep 5;
		next;
	    }
	    delete $pending{$s};
	}
    }
}

sub get_volume {
    my $self = shift;
    my %args = @_;
    $args{-name}              ||= ++$VolumeName;

    # find volume of same name
    my %vols = map {$_->name => $_} $self->volumes;
    return $vols{$args{-name}} || $self->provision_volume(%args);
}

sub provision_volume {
    my $self = shift;
    my %args = @_;

    $args{-name}              ||= ++$VolumeName;
    $args{-size}              ||= 1;
    $args{-volume_id}         ||= undef;
    $args{-snapshot_id}       ||= undef;
    $args{-reuse}               = $self->reuse_volumes unless defined $args{-reuse};
    $args{-mount}             ||= '/mnt/DataTransfer/'.$args{-name};
    $args{-fstype}            ||= 'ext4';
    $args{-availability_zone} ||= $self->_select_used_zone;
    
    $self->info("provisioning a $args{-size} GB $args{-fstype} volume in $args{-availability_zone}\n");

    my $server = $self->get_server_in_zone($args{-availability_zone});
    $server->start unless $server->ping;
    my $volume = $server->provision_volume(%args);
    $self->register_volume($volume);
    return $volume;
}

sub volumes {
    my $self = shift;
    return values %Volumes;
}

sub _search_for_image {
    my $self = shift;
    my %args = @_;

    $self->info("Searching for a staging image...");

    my $root_type    = $self->on_exit eq 'stop' ? 'ebs' : $args{-root_type};

    my @candidates = $self->ec2->describe_images({'name'             => "*$args{-image_name}*",
						  'root-device-type' => $root_type,
						  'architecture'     => $args{-architecture}});
    return unless @candidates;
    # this assumes that the name has some sort of timestamp in it, which is true
    # of ubuntu images, but probably not others
    my ($most_recent) = sort {$b->name cmp $a->name} @candidates;
    $self->info("found $most_recent: ",$most_recent->name,"\n");
    return $most_recent;
}

sub security_group {
    my $self = shift;
    return $self->{security_group} ||= $self->_new_security_group();
}

sub keypair {
    my $self = shift;
    return $self->{keypair} ||= $self->_new_keypair();
}

sub create_snapshot {
    my $self = shift;
    my ($vol,$description) = @_;
    my @snaps;
    my $device = $vol->device;
    my $mtpt   = $vol->mtpt;
    my $volume = $vol->ebs;
    $self->unmount_volume($vol);
    my $d = $self->volume_description($vol);
    $self->info("snapshotting $vol\n");
    my $snap = $volume->create_snapshot($description) or croak "Could not snapshot $vol: ",$vol->ec2->error_str;
    $snap->add_tag(StagingName => $vol->name);
    $snap->add_tag(Name => "Staging volume ".$vol->name);
    $self->remount_volume($vol);
    return $snap;
}

sub _new_security_group {
    my $self = shift;
    my $ec2  = $self->ec2;
    my $name = $ec2->token;
    $self->info("Creating ssh security group $name.\n");
    my $sg =  $ec2->create_security_group(-name     => $name,
				       -description => "SSH security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    return $sg;
}

sub _security_key {
    my $self = shift;
    my $ec2     = $self->ec2;
    if ($self->reuse_key) {
	my @candidates = $ec2->describe_key_pairs(-filter=>{'key-name' => 'staging-key-*'});
	for my $c (@candidates) {
	    my $name    = $c->keyName;
	    my $keyfile = $self->key_path($name);
	    return ($c,$keyfile) if -e $keyfile;
	}
    }
    my $name    = 'staging-key-'.$ec2->token;
    $self->info("Creating keypair $name.\n");
    my $kp          = $ec2->create_key_pair($name) or die $ec2->error_str;
    my $keyfile     = $self->key_path($name);
    my $private_key = $kp->privateKey;
    open my $k,'>',$keyfile or die "Couldn't create $keyfile: $!";
    chmod 0600,$keyfile     or die "Couldn't chmod  $keyfile: $!";
    print $k $private_key;
    close $k;
    return ($kp,$keyfile);
}

sub _security_group {
    my $self = shift;
    my $ec2  = $self->ec2;
    my @groups = $ec2->describe_security_groups(-filter=>{'tag:Role' => 'StagingGroup'});
    return $groups[0] if @groups;
    my $name = $ec2->token;
    $self->info("Creating staging security group $name.\n");
    my $sg =  $ec2->create_security_group(-name  => $name,
					  -description => "SSH security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    $sg->add_tag(Role  => 'StagingGroup');
    return $sg;

}

sub rsync {
    my $self = shift;
    VM::EC2::Staging::Server->rsync(@_);
}

sub volume_description {
    my $self = shift;
    my $vol  = shift;
    my $name = ref $vol ? $vol->name : $vol;
    return "Staging volume for $name created by ".__PACKAGE__;
}

sub info {
    my $self = shift;
    return if $self->quiet;
    print STDERR @_;
}

# can be called as a class method
sub _find_server_in_zone {
    my $self = shift;
    my $zone = shift;
    my @servers = sort {$a->ping cmp $b->ping} values %{$Zones{$zone}{Servers}};
    return unless @servers;
    return $servers[-1];
}

sub active_servers {
    my $self = shift;
    my $ec2  = shift; # optional
    my @servers = values %Instances;
    return @servers unless $ec2;
    return grep {$_->ec2 eq $ec2} @servers;
}

sub key_path {
    my $self    = shift;
    my $keyname = shift;
    return File::Spec->catfile($self->dot_directory_path,"${keyname}.pem")
}

sub dot_directory_path {
    my $class = shift;
    my $dir = File::Spec->catfile($ENV{HOME},'.vm_ec2_staging');
    unless (-e $dir && -d $dir) {
	mkdir $dir       or croak "mkdir $dir: $!";
	chmod 0700,$dir  or croak "chmod 0700 $dir: $!";
    }
    return $dir;
}

sub _check_keyfile {
    my $self = shift;
    my $keyname = shift;
    my $dotpath = $self->dot_directory_path;
    opendir my $d,$dotpath or die "Can't opendir $dotpath: $!";
    while (my $file = readdir($d)) {
	if ($file =~ /^$keyname.pem/) {
	    return $1,$self->key_path($keyname,$1);
	}
    }
    closedir $d;
    return;
}

sub _select_used_zone {
    my $self = shift;
    if (my @servers = $self->servers) {
	my @up     = grep {$_->ping} @servers;
	my $server = $up[0] || $servers[0];
	return $server->placement;
    } elsif (my $zone = $self->availability_zone) {
	return $zone;
    } else {
	my @zones = $self->ec2->describe_availability_zones;
	return $zones[rand @zones];
    }
}

#############################################
# copying AMIs from one zone to another
#############################################
sub copy_image {
    my $self = shift;
    my ($image,$dest_region) = @_;
    my $ec2 = $self->ec2;

    $image = $ec2->describe_images($image)
	unless ref $image && $image->isa('VM::EC2::Image');
    
    $dest_region = $ec2->describe_regions($dest_region)
	unless ref $dest_region && $dest_region->isa('VM::EC2::Region');

    $image       or croak "Invalid image '$image'; usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";
    $dest_region or croak "Invalid EC2 Region '$dest_region'; usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";

    $image->imageType eq 'machine' or croak "$image is not an AMI: usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";
    
    my $dest_endpoint = $dest_region->regionEndpoint;
    my $dest_ec2      = VM::EC2->new(-endpoint    => $dest_endpoint,
				     -access_key  => $ec2->access_key,
				     -secret_key  => $ec2->secret)
	or croak "Could not create new VM::EC2 in $dest_region";
    my $dest_manager = $self->new(-ec2     => $dest_ec2,
				  -scan    => 1,
				  -on_exit => 'destroy');

    my $root_type = $image->rootDeviceType;
    if ($root_type eq 'ebs') {
	return $self->_copy_ebs_image($image,$dest_manager);
    } else {
	return $self->_copy_instance_image($image,$dest_manager);
    }
}

sub _copy_ebs_image {
    my $self = shift;
    my ($image,$dest_manager) = @_;

    # hashref with keys 'name', 'description','architecture','kernel','ramdisk','block_devices','root_device'
    $self->info("Gathering information about image $image\n");
    my $info = $self->_gather_image_info($image);

    my $name         = $info->{name};
    my $description  = $info->{description};
    my $architecture = $info->{architecture};
    my $kernel       = $self->_match_kernel($info->{kernel},$dest_manager->ec2,'kernel')
	or croak "Could not find an equivalent kernel for $info->{kernel} in region ",$dest_manager->ec2->endpoint;
    
    my $ramdisk;
    if ($info->{ramdisk}) {
	$ramdisk      = $self->_match_kernel($info->{ramdisk},$dest_manager->ec2,'ramdisk')
	    or croak "Could not find an equivalent ramdisk for $info->{ramdisk} in region ",$dest_manager->ec2->endpoint;	
    }

    my $block_devices   = $info->{block_devices};  # format same as $image->blockDeviceMapping
    my $root_device     = $info->{root_device};

    $self->info("Copying EBS volumes attached to this image (this may take a long time)\n");
    my @dest_snapshots  = map {$self->copy_snapshot($_->snapshotId,$dest_manager)} @$block_devices;

    # create the new block device mapping
    my @mappings;
    for my $source_ebs (@$block_devices) {
	my $snapshot    = shift @dest_snapshots;
	my $dest        = "$source_ebs";  # interpolates into correct format
	$dest          =~ s/=[\w-]+/$snapshot/;  # replace source snap with dest snap
	push @mappings,$dest;
    }

    return $dest_manager->ec2->register_image(-name                 => $name,
					      -root_device_name     => $root_device,
					      -block_device_mapping => \@mappings,
					      -description          => $description,
					      -architecture         => $architecture,
					      -kernel_id            => $kernel,
					      $ramdisk ? (-ramdisk_id  => $ramdisk): ()
	);
}

sub copy_snapshot {
    my $self = shift;
    my ($snapId,$dest_manager) = @_;
    my $snap   = $self->ec2->describe_snapshots($snapId) 
	or croak "Couldn't find snapshot for $snapId";
    my $description = $snap->description;

    my $source = $self->provision_volume(-snapshot_id=>$snapId) 
	or croak "Couldn't mount volume for $snapId";
    my $fstype = $source->fstype;
    my $dest   = $dest_manager->provision_volume(-fstype => $fstype,
						 -size   => $source->size) 
	or croak "Couldn't create new destination volume for $snapId";

    if ($fstype eq 'raw') {
	$source->dd($dest)    or croak "dd failed";
    } else {
	$source->rsync($dest) or croak "rsync failed";
    }
    
    my $snap = $dest->create_snapshot($description);
    
    # we don't need these volumes now
    $source->delete;
    $dest->delete;

    return $snap;
}

sub _gather_image_info {
    my $self  = shift;
    my $image = shift;
    return {
	name         =>   $image->name,
	description  =>   $image->description,
	architecture =>   $image->architecture,
	kernel       =>   $image->kernelId  || undef,
	ramdisk      =>   $image->ramdiskId || undef,
	root_device  =>   $image->rootDeviceName,
	block_devices=>   [$image->blockDeviceMapping],
    };
}

sub _match_kernel {
    my $self = shift;
    my ($imageId,$dest_manager) = @_;
    my $home_ec2 = $self->ec2;
    my $dest_ec2 = $dest_manager->ec2;  # different endpoints!
    my $image    = $home_ec2->describe_images($imageId) or return;
    my $name     = $image->name;
    my $type     = $image->imageType;
    my @candidates = $dest_ec2->describe_images({'name'        => $name,
						 'image-type'  => $type,
						});
    return $candidates[0];
}

sub copy_snapshot {
    my $self = shift;
    my ($snapId,$dest_manager) = @_;
    $self->info("staging snapshotshot $snapId\n");
    my $vol = $self->provision_volume(-snapshot_id=>$snapId);
}

sub DESTROY {
    my $self = shift;
    my $action = $self->on_exit;
    $self->terminate_all_servers if $action eq 'terminate';
    $self->stop_all_servers      if $action eq 'stop';
    delete $Managers{$self->ec2->endpoint};
}

sub VM::EC2::staging_manager {
    my $self = shift;
    return VM::EC2::Staging::Manager->new(@_,-ec2=>$self)
}

1;

