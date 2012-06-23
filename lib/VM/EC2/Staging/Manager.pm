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
 $staging->scan();  # populate with preexisting servers & volumes
 
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

 $staging->stop_all();
 $staging->start_all();
 $staging->terminate_all();

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

use constant                     GB => 1_073_741_824;
use constant SERVER_STARTUP_TIMEOUT => 120;

my %Servers;
my %Zones;
my %Volumes;
my $LastHost;

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-ec2}               ||= VM::EC2->new();
    $args{-on_exit}           ||= $class->default_exit_behavior;
    $args{-reuse_key}         ||= $class->default_reuse_key;
    $args{-username}          ||= $class->default_user_name;
    $args{-architecture}      ||= $class->default_architecture;
    $args{-root_type}         ||= $class->default_root_type;
    $args{-instance_type}     ||= $class->default_instance_type;
    $args{-availability_zone} ||= undef;
    $args{-quiet}             ||= undef;

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
END
    }

    return bless \%args,ref $class || $class;
}

sub default_image_name    { 'ubuntu-maverick-10.10' };  # launches faster than precise
sub default_exit_behavior { 'terminate'   }
sub default_user_name     { 'ubuntu'      }
sub default_architecture  { 'i386'        }
sub default_root_type     { 'instance-store'}
sub default_instance_type { 'm1.small'      }

# scan for staging instances in current region and cache them
# into memory
# status should be...
# -on_exit => {'terminate','stop','run'}
sub scan {
    my $self = shift;
    my $ec2  = shift;
    $self->_scan_instances($ec2);
    $self->_scan_volumes($ec2);
}

sub _scan_instances {
    my $self = shift;
    my $ec2  = shift;
    my @instances = $ec2->describe_instances(-filter=>{'tag:Role'=>'StagingInstance'});
    for my $instance (@instances) {
	my $keyname  = $instance->keyName                   or next;
	my $keyfile  = $self->_check_keyfile($keyname)      or next;
	my $username = $instance->tags->{'StagingUsername'} or next;
	my $server   = VM::EC2::Staging::Server->new(
	    -keyfile  => $keyfile,
	    -username => $username,
	    -instance => $instance
	    );
	$self->register_server($server);
    }
}

sub _scan_volumes {
    my $self = shift;
    my $ec2  = shift;

    # now the volumes
    my @volumes = $ec2->describe_volumes(-filter=>{'tag:Role'=>'StagingVolume'});
    for my $volume (@volumes) {
	my $status = $volume->status;
	next unless $status eq 'in-use';
	
	# the server should have been found by _scan_instances() in the earlier step
	# Must run _scan_instances before _scan_volumes.
	my $server     = $self->find_server_by_instance($instance) or next;

	my $zone       = $volume->availabilityZone;
	my $attachment = $volume->attachment;
	my $ebs_device = $attachment->device;
	my $instance   = $attachment->instance;
	my $vol = VM::EC2::Staging::Volume->new(
	    -volume => $volume,
	    -name   => $name,
	    # note - leave mtpt and device empty to avoid
	    # starting up a server at this stage. The volume
	    # will have to determine this info at use time.
	    );
	$self->register_volume($vol);
    }
}

sub provision_server {
    my $self    = shift;
    my ($keyname,$keyfile) = $self->_security_key;
    my $security_group     = $self->_security_group;
    my $image              = $self->_search_for_image() or croak "No suitable image found";
    my ($instance)         = $self->ec2->run_instances(
	-image_id          => $image,
	-instance_type     => $self->instance_type,
	-security_group_id => $security_group,
	-key_name          => $keyname,
	-availability_zone => $self->availability_zone
	);
    $instance->add_tag(Role            => 'StagingInstance');
    $instance->add_tag(StagingUsername => $self->username  );
    $instance->add_tag(Name            => "Staging server created by ".__PACKAGE__);
    my $server = VM::EC2::Staging::Server->new(
	-keyfile  => $keyfile,
	-username => $self->username,
	-instance => $instance);
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(SERVER_STARTUP_TIMEOUT);
	$self->_wait_for_instances($server);
    };
    alarm(0);
    croak "some servers did not start after ",SERVER_STARTUP_TIMEOUT," seconds"
	if $@ =~ /timeout/;
    return $server;
}

sub find_server_by_instance {
    my $self = shift;
    my $instance = shift;
    return $self->{Instances}{$instance};
}

sub register_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = $server->availability_zone;
    $self->{Zones}{$zone}{Servers}{$server} = $server;
    $self->{Instances}{$server->instance}   = $server;
}

sub unregister_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = $server->availability_zone;
    delete $self->{Zones}{$zone}{Servers}{$server};
    delete $self->{Instances}{$server->instance};
}

sub servers {
    my $self = shift;
    return values %{$self->{Instances}};
}

sub register_volume {
    my $self = shift;
    my $vol  = shift;
    $self->{Volumes}{$vol->volumeId} = $vol;
}

sub unregister_volume {
    my $self = shift;
    my $vol  = shift;
    delete $self->{Volumes}{$vol->volumeId};
}

sub volumes {
    my $self = shift;
    return values %{$self->{Volumes}};
}

sub start_all {
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

sub _start_instances {
    my $self = shift;
    my @need_starting = @_;
    $self->info("starting instances: @need_starting.\n");
    $self->ec2->start_instances(@need_starting);
    $self->_wait_for_instances(@need_starting);
}

sub _wait_for_instances {
    my $self = shift;
    my @instances = @_;
    $self->ec2->wait_for_instances(@instances);
    $self->info("waiting for ssh daemons on @instances.\n");
    my %pending = map {$_=>$_} @instances;
    while (%pending) {
	for my $s (values %pending) {
	    continue unless $s->ping;
	    delete $pending{$s};
	} continue {
	    sleep 5;
	}
    }
}

sub provision_volume {
    my $self = shift;
    my %args = @_;

    my $name   = $args{-name};
    my $size   = $args{-size};
    my $volid  = $args{-volume_id};
    my $snapid = $args{-snapshot_id};
    my $reuse  = $args{-reuse};

    if ($volid || $snapid) {
	$name  ||= $volid || $snapid;
	$size  ||= -1;
    } else {
	$name        =~ /^[a-zA-Z0-9_.,&-]+$/
	    or croak "Volume name must contain only characters [a-zA-Z0-9_.,&-]; you asked for '$name'";
    }

    my $ec2      = $self->ec2;
    my $mtpt     = $args{-mount}  || '/mnt/DataTransfer/'.$name;
    my $fstype   = $args{-fstype} || 'ext4';
    my $username = $self->username;
    
    $size = int($size) < $size ? int($size)+1 : $size;  # dirty ceil() function

    
    my $instance = $self->instance;
    my $zone     = $instance->placement;
    my ($vol,$needs_mkfs,$needs_resize) = $self->_create_volume($name,$size,$zone,$volid,$snapid,$reuse);
    
    my ($ebs_device,$mt_device) = eval{$self->unused_block_device()}           
                      or die "Couldn't find suitable device to attach this volume to";
    my $s = $instance->attach_volume($vol=>$ebs_device)  
	              or die "Couldn't attach $vol to $instance via $ebs_device";
    $ec2->wait_for_attachments($s)                   or croak "Couldn't attach $vol to $instance via $ebs_device";
    $s->current_status eq 'attached'                 or croak "Couldn't attach $vol to $instance via $ebs_device";

    if ($needs_resize) {
	$self->scmd("sudo file -s $mt_device") =~ /ext[234]/   or croak "Sorry, but can only resize ext volumes ";
	$self->info("Checking filesystem...\n");
	$self->ssh("sudo /sbin/e2fsck -fy $mt_device")          or croak "Couldn't check $mt_device";
	$self->info("Resizing previously-used volume to $size GB...\n");
	$self->ssh("sudo /sbin/resize2fs $mt_device ${size}G") or croak "Couldn't resize $mt_device";
    } elsif ($needs_mkfs) {
	$self->info("Making $fstype filesystem on staging volume...\n");
	$self->ssh("sudo /sbin/mkfs.$fstype -L '$name' $mt_device") or croak "Couldn't make filesystem on $mt_device";
    }

    my $vol = VM::EC2::Staging::Volume->new({
	volume    => $vol,
	device    => $mt_device,
	mtpt      => $mtpt,
	server    => $self,
	symbolic_name => $name});

    $self->mount_volume($vol);
    $self->register_volume($vol);
    return $vol;
}

sub register_volume {
    my $self = shift;
    my $vol  = shift;
    weaken($Volumes{$vol->volumeId} = $vol);
}

sub unregister_volume {
    my $self = shift;
    my $vol  = shift;
    delete $Volumes{$vol->volumeId};
}

sub mount_volume {
    my $self = shift;
    my $vol  = shift;
    my $mtpt      = $vol->mtpt;
    my $mt_device = $vol->device;
    $self->info("Mounting staging volume.\n");
    $self->ssh("sudo mkdir -p $mtpt; sudo mount $mt_device $mtpt");
    $vol->mounted(1);
}

sub unmount_volume {
    my $self = shift;
    my $vol  = shift;
    my $mtpt = $vol->mtpt;
    $self->info("unmounting $vol...\n");
    $self->ssh('sudo','umount',$mtpt) or croak "Could not umount $mtpt";
    $vol->mounted(0);
}

sub remount_volume {
    my $self = shift;
    my $vol  = shift;
    my $mtpt = $vol->mtpt;
    my $device = $vol->device;
    $self->info("remounting $vol\n");
    $self->ssh('sudo','mount',$device,$mtpt) or croak "Could not remount $mtpt";
    $vol->mounted(1);
}

sub delete_volume {
   my $self = shift;
   my $vol  = shift;
   my $ec2 = $self->ec2;
   $self->unmount_volume($vol);
   $ec2->wait_for_attachments( $vol->detach() );
   $self->info("deleting $vol...\n");
   $ec2->delete_volume($vol->volumeId);
   $vol->mounted(0);
}

# take real or symbolic name and turn it into a two element
# list consisting of server object and mount point
# possible forms:
#            /local/path
#            vol-12345/relative/path
#            vol-12345:/relative/path
#            vol-12345:relative/path
#            $server:/absolute/path
#            $server:relative/path
# 
# treat path as symbolic if it does not start with a slash
# or dot characters
sub resolve_path {
    my $self  = shift;
    my $vpath = shift;

    my ($servername,$pathname);
    if ($vpath =~ m!^(vol-[0-9a-f]+):?(.*)! && $Volumes{$1}) {
	my $vol  = $Volumes{$1};
	my $path = $2;
	$path       = "/$path" if $path && $path !~ m!^/!;
	$servername = $LastHost = $vol->server;
	my $mtpt    = $vol->mtpt;
	$pathname   = $mtpt;
	$pathname  .= $path if $path;
    } elsif ($vpath =~ /^([^:]+):(.+)$/) {
	$servername = $LastHost = $1;
	$pathname   = $2;
    } elsif ($vpath =~ /^:(.+)$/) {
	$servername = $LastHost;
	$pathname   = $2;
    } else {
	return [undef,$vpath];   # localhost
    }

    my $server = $Servers{$servername} || $servername;
    unless (ref $server && $server->isa('VM::EC2::Staging::Server')) {
	return [$server,$pathname];
    }

    return [$server,$pathname];
}

# most general form
# 
sub rsync {
    my $self = shift;
    undef $LastHost;
    my @paths = map {$self->resolve_path($_)} @_;

    my $dest   = pop @paths;
    my @source = @paths;

    my %hosts;
    foreach (@source) {
	$hosts{$_->[0]} = $_->[0];
    }
    croak "More than one source host specified" if keys %hosts > 1;
    my ($source_host) = values %hosts;
    my $dest_host     = $dest->[0];

    my @source_paths      = map {$_->[1]} @source;
    my $dest_path         = $dest->[1];

    # localhost           => DataTransferServer
    if (!$source_host && UNIVERSAL::isa($dest_host,__PACKAGE__)) {
	return $dest_host->_rsync_put(@source_paths,$dest_path);
    }

    # DataTransferServer  => localhost
    if (UNIVERSAL::isa($source_host,__PACKAGE__) && !$dest_host) {
	return $source_host->_rsync_get(@source_paths,$dest_path);
    }

    if ($source_host eq $dest_host) {
	return $source_host->ssh('sudo','rsync','-avz',@source_paths,$dest_path);
    }

    # DataTransferServer1 => DataTransferServer2
    # this one is slightly more difficult because datatransferserver1 has to
    # ssh authenticate against datatransferserver2.
    my $keyname = "/tmp/${source_host}_to_${dest_host}";
    unless ($source_host->has_key($keyname)) {
	$source_host->info('creating ssh key for server to server data transfer');
	$source_host->ssh("ssh-keygen -t dsa -q -f $keyname</dev/null 2>/dev/null");
	$source_host->has_key($keyname=>1);
    }
    unless ($dest_host->accepts_key($keyname)) {
	my $key_stuff = $source_host->scmd("cat ${keyname}.pub");
	chomp($key_stuff);
	$dest_host->ssh("mkdir -p .ssh; chmod 0700 .ssh; echo '$key_stuff' >> .ssh/authorized_keys");
	$dest_host->accepts_key($keyname=>1);
    }

    my $username = $dest_host->username;
    return $source_host->ssh('sudo','rsync','-avz',
			     '-e',"'ssh -o \"StrictHostKeyChecking no\" -i $keyname -l $username'",
			     "--rsync-path='sudo rsync'",
			     @source_paths,"$dest_host:$dest_path");


    # localhost           => localhost (local cp)
    return system('rsync',@source_paths,$dest_path) == 0;
}

sub _rsync_put {
    my $self   = shift;
    my @source = @_;
    my $dest   = pop @source;
    # resolve symbolic name of $dest
    $dest        =~ s/^.+://;  # get rid of hostname, if it is there
    my $host     = $self->instance->dnsName;
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    $self->info("Beginning rsync...\n");
    system("rsync -avz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' --rsync-path='sudo rsync' @source $host:$dest") == 0;
}

sub _rsync_get {
    my $self = shift;
    my @source = @_;
    my $dest   = pop @source;

    # resolve symbolic names of src
    my $host     = $self->instance->dnsName;
    foreach (@source) {
	(my $path = $_) =~ s/^.+://;  # get rid of host part, if it is there
	$_ = "$host:$path";
    }
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    
    $self->info("Beginning rsync...\n");
    system("rsync -avz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' --rsync-path='sudo rsync' @source $dest")==0;
}

sub _create_instance {
    my $self = shift;
    my $args = shift;
    my $image = $args->{-image};

    # search for a matching instance
    $image ||= $self->search_for_image($args) or croak "No suitable image found";
    my $sg   = $self->_security_group();
    my $kp   = $self->_keypair();
    my $zone = $args->{-availability_zone};
    $self->info("Creating staging server from $image in $zone.\n");
    my $instance = $self->ec2->run_instances(-image_id          => $image,
					     -instance_type     => $args->{-instance_type},
					     -security_group_id => $sg,
					     -key_name          => $kp,
					     -availability_zone => $zone) 
	or die "Can't create instance: ",$self->ec2->error_str;
    $instance->add_tag(Name=>"Staging server created by VM::EC2::Staging::Server");
    return $instance;
}

sub search_for_image {
    my $self = shift;
    my $args = shift;
    $self->info("Searching for a staging image...");
    my @candidates = $self->ec2->describe_images({'name'             => "*$args->{-image_name}*",
						  'root-device-type' => $args->{-root_type},
						  'architecture'     => $args->{-architecture}});
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
    $self->info("Creating temporary security group $name.\n");
    my $sg =  $ec2->create_security_group(-name  => $name,
				       -description => "Temporary security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    return $sg;
}

sub _keypair {
    my $self = shift;
    my $ec2     = $self->ec2;
    if ($self->reuse_key) {
	my @candidates = $ec2->describe_key_pairs(-filter=>{'tag:Role' => 'StagingKeyPair'});
	for my $c (@candidates) {
	    my $name    = $c->keyName;
	    my $keyfile = $self->key_path($name);
	    return $c if -e $keyfile;
	}
    }
    my $name    = $ec2->token;
    $self->info("Creating keypair $name.\n");
    my $kp      = $ec2->create_key_pair($name);
    my $keyfile = $self->key_path($name);
    my $private_key = $kp->privateKey;
    open my $k,'>',$keyfile or die "Couldn't create $keyfile: $!";
    chmod 0600,$keyfile     or die "Couldn't chmod  $keyfile: $!";
    print $k $private_key;
    close $k;
    $kp->add_tag(Role => 'StagingKeyPair');
    return $kp;
}

sub _security_group {
    my $self = shift;
    my $ec2  = $self->ec2;
    my @groups = $ec2->describe_security_groups(-filter=>{'tag:Role' => 'StagingGroup'});
    return $groups[0] if @groups;
    my $name = $ec2->token;
    $self->info("Creating staging security group $name.\n");
    my $sg =  $ec2->create_security_group(-name  => $name,
					  -description => "Temporary security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    $sg->add_tag(Role  => 'StagingGroup');
    return $sg;

}

sub _create_volume {
    my $self = shift;
    my ($name,$size,$zone,$volid,$snapid,$reuse_staging_volume) = @_;
    my $ec2 = $self->ec2;

    my (@vols,@snaps);

    if ($volid) {
	my $vol = $ec2->describe_volumes($volid) or croak "Unknown volume $volid";
	croak "$volid is not in server availability zone $zone. Create staging volumes with VM::EC2->staging_volume() to avoid this."
	    unless $vol->availabilityZone eq $zone;
	croak "$vol is unavailable for use, status ",$vol->status
	    unless $vol->status eq 'available';
	@vols = $volid;
    }

    elsif ($snapid) {
	my $snap = $ec2->describe_snapshots($snapid) or croak "Unknown snapshot $snapid";
	@snaps   = $snap;
    }

    elsif ($reuse_staging_volume) {
	@vols = sort {$b->createTime cmp $a->createTime} $ec2->describe_volumes({status              => 'available',
										 'availability-zone' => $zone,
										 'tag:StagingName'   => $name});
	@snaps = sort {$b->startTime cmp $a->startTime} $ec2->describe_snapshots(-owner  => $ec2->account_id,
										 -filter => {'tag:StagingName' => $name})
	    unless @vols;
    }

    my ($vol,$needs_mkfs,$needs_resize);

    if (@vols) {
	$vol = $vols[0];
	$size   = $vol->size unless $size > 0;
	$self->info("Reusing existing volume $vol...\n");
	$vol->size == $size or croak "Cannot (yet) resize live volumes. Please snapshot first and restore from the snapshot"
    }

    elsif (@snaps) {
	my $snap = $snaps[0];
	$size    = $snap->volumeSize unless $size > 0;
	$self->info("Reusing existing snapshot $snap...\n");
	$snap->volumeSize <= $size or croak "Cannot (yet) shrink volumes derived from snapshots. Please choose a size >= snapshot size";
	$vol = $snap->create_volume(-availability_zone=>$zone,
				    -size             => $size);
	$needs_resize = $snap->volumeSize < $size;
    }

    else {
	unless ($size > 0) {
	    $self->info("No size provided. Defaulting to 10 GB.\n");
	    $size = 10;
	}
	$self->info("Provisioning a new $size GB volume...\n");
	$vol = $ec2->create_volume(-availability_zone=>$zone,
				   -size             =>$size);
	$needs_mkfs++;
    }

    return unless $vol;

    $vol->add_tag(Name => $self->volume_description($name)) unless exists $vol->tags->{Name};
    $vol->add_tag(StagingName => $name);
    return ($vol,$needs_mkfs,$needs_resize);
}

sub volume_description {
    my $self = shift;
    my $vol  = shift;
    my $name = ref $vol ? $vol->name : $vol;
    return "Staging volume for $name created by ".__PACKAGE__;
}

sub ssh {
    my $self = shift;
    my @cmd   = @_;
    my $Instance = $self->instance or die "Remote instance not set up correctly";
    my $username = $self->username;
    my $keyfile  = $self->keyfile;
    my $host     = $Instance->dnsName;
    system('/usr/bin/ssh','-o','CheckHostIP no','-o','StrictHostKeyChecking no','-i',$keyfile,'-l',$username,$host,@cmd)==0;
}

sub scmd {
    my $self = shift;
    my @cmd   = @_;
    my $Instance = $self->instance or die "Remote instance not set up correctly";
    my $username = $self->username;
    my $keyfile  = $self->keyfile;
    my $host     = $Instance->dnsName;

    my $pid = open my $kid,"-|"; #this does a fork
    die "Couldn't fork: $!" unless defined $pid;
    if ($pid) {
	my @results;
	while (<$kid>) {
	    push @results,$_;
	}
	close $kid;
#	croak "ssh failed with status ",$?>>8 unless $?==0;
	if (wantarray) {
	    chomp(@results);
	    return @results;
	} else {
	    return join '',@results;
	}
    }

    # in child
    exec '/usr/bin/ssh','-o','CheckHostIP no','-o','StrictHostKeyChecking no','-i',$keyfile,'-l',$username,$host,@cmd;
}

sub shell {
    my $self = shift;
    fork() && return;
    setsid(); # so that we are independent of parent signals
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    my $host     = $self->instance->dnsName;
    exec 'xterm',
    '-e',"/usr/bin/ssh -o 'CheckHostIP no' -o 'StrictHostKeyChecking no' -i $keyfile -l $username $host";
}

# find an unused block device
sub unused_block_device {
    my $self        = shift;
    my $major_start = shift || 'f';

    my @devices = $self->scmd('ls -1 /dev/sd?* /dev/xvd?* 2>/dev/null');
    return unless @devices;
    my %used = map {$_ => 1} @devices;
    
    my $major_start = shift || 'f';

    my $base =   $used{'/dev/sda1'}   ? "/dev/sd"
               : $used{'/dev/xvda1'}  ? "/dev/xvd"
               : '';
    die "Device list contains neither /dev/sda1 nor /dev/xvda1; don't know how blocks are named on this system"
	unless $base;

    my $ebs = '/dev/sd';
    for my $major ($major_start..'p') {
        for my $minor (1..15) {
            my $local_device = "${base}${major}${minor}";
            next if $used{$local_device}++;
            my $ebs_device = "/dev/sd${major}${minor}";
            return ($ebs_device,$local_device);
        }
    }
    return;
}

sub info {
    my $self = shift;
    return if $self->quiet;
    print STDERR @_;
}

sub cleanup {
    my $self = shift;
    if (-e $self->keyfile) {
	$self->info('Deleting private key file...');
	my $dir = dirname($self->keyfile);
	remove_tree($dir);
    }
    if (my $i = $self->instance) {
	$self->info('Terminating staging instance...');
	$i->terminate();
	$self->ec2->wait_for_instances($i);
    }
    if (my $kp = $self->{keypair}) {
	$self->info('Removing key pair...');
	$self->ec2->delete_key_pair($kp);
    }
    if (my $sg = $self->{security_group}) {
	$self->info('Removing security group...');
	$self->ec2->delete_security_group($sg);
    }
}

sub has_key {
    my $self = shift;
    my $keyname = shift;
    $self->{_has_key}{$keyname} = shift if @_;
    return $self->{_has_key}{$keyname};
}

sub accepts_key {
    my $self = shift;
    my $keyname = shift;
    $self->{_accepts_key}{$keyname} = shift if @_;
    return $self->{_accepts_key}{$keyname};
}

sub DESTROY {
    my $self = shift;
#    return if $self->keep;
#    undef $Servers{$self->as_string};
#    undef $Zones{$self->instance->placement};
#    $self->cleanup;
}

# can be called as a class method
sub find_server_in_zone {
    my $self = shift;
    my $zone = shift;
    return $Zones{$zone};
}

sub active_servers {
    my $self = shift;
    my $ec2  = shift; # optional
    my @servers = values %Servers;
    return @servers unless $ec2;
    return grep {$_->ec2 eq $ec2} @servers;
}

sub key_path {
    my $self    = shift;
    my ($keyname,$username)  = @_;
    $username ||= $self->username;
    return File::Spec->catfile($self->dot_directory_path,"${username}-${keyname}.pem")
}

sub dot_directory_path {
    my $class = shift;
    my $dir = File::Spec->catfile($HOME,'.vm_ec2_staging');
    unless (-e $dir && -d $dir) {
	mkdir $dir       or croak "mkdir $dir: $!";
	chmod 0700 $dir  or croak "chmod 0700 $dir: $!";
    }
    return $dir;
}

sub _check_keyfile {
    my $self = shift;
    my $keyname = shift;
    my $dotpath = $self->dot_directory_path;
    opendir my $d,$dotpath or die "Can't opendir $dotpath: $!";
    while (my $file = readdir($d)) {
	if ($file =~ /^(.+)-$keyname.pem/) {
	    return $1,$self->key_path($keyname,$1);
	}
    }
    closedir $d;
    return;
}

sub VM::EC2::new_data_transfer_server {
    my $self = shift;
    return VM::EC2::Staging::Server->new($self,@_)
}

1;

