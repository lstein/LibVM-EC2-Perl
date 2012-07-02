package VM::EC2::Staging::Server;

# high level interface for transferring data, and managing data snapshots
# via a series of DataTransfer VMs.

=head1 NAME

VM::EC2::Staging::Server - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 #SYNOPSIS IS OF DATE

 use VM::EC2::Staging::Manager;

 my $ec2     = VM::EC2->new;
 my $staging = VM::EC2::Staging::Manager->new(-ec2     => $ec2,
                                              -on_exit => 'stop', # default, choose root volume type based on behavior
                                              -quiet   => 0,      # default
                                              -scan    => 1,      # default
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
use Carp 'croak';
use Scalar::Util 'weaken';
use File::Spec;
use File::Path 'make_path','remove_tree';
use File::Basename 'dirname';
use POSIX 'setsid';
use overload
    '""'     => sub {my $self = shift;
 		     return $self->short_name;  # "inherited" from VM::EC2::Volume
},
    fallback => 1;

use constant GB => 1_073_741_824;
my $LastHost;

our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my $vol = eval {$self->instance} or croak "Can't locate object method \"$func_name\" via package \"$pack\"";;
    return $vol->$func_name(@_);
}

sub can {
    my $self = shift;
    my $method = shift;

    my $can  = $self->SUPER::can($method);
    return $can if $can;

    my $ebs  = $self->ebs or return;
    return $ebs->can($method);
}

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-keyfile}        or croak 'need keyfile path';
    $args{-username}       or croak 'need username';
    $args{-instance}       or croak 'need a VM::EC2::Instance';
    $args{-manager}        or croak 'need a VM::EC2::Staging::Manager object';

    my $self = bless {
	manager  => $args{-manager},
	instance => $args{-instance},
	username => $args{-username},
	keyfile  => $args{-keyfile},
    },ref $class || $class;
    return $self;
}

sub ec2      { shift->manager->ec2    }
sub manager  { shift->{manager}  }
sub instance { shift->{instance} }
sub keyfile  { shift->{keyfile}  }
sub username { shift->{username} }

sub is_up {
    my $self = shift;
    my $d    = $self->{_is_up};
    $self->{_is_up} = shift if @_;
    $d;
}

sub start {
    my $self = shift;
    return if $self->ping;
    $self->manager->info("Starting staging server\n");
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(VM::EC2::Staging::Manager::SERVER_STARTUP_TIMEOUT());
	$self->ec2->start_instances($self);
	$self->manager->wait_for_instances($self);
    };
    alarm(0);
    if ($@) {
	$self->manager->info('could not start $self');
	return;
    }
    $self->is_up(1);
}

sub stop {
    my $self = shift;
    return unless $self->instance->status eq 'running';
    $self->instance->stop;
    $self->manager->wait_for_instances($self);
}

sub ping {
    my $self = shift;
    return unless $self->instance->status eq 'running';
    return 1 if $self->is_up;
    return unless $self->ssh('pwd >/dev/null 2>&1');
    $self->is_up(1);
    return 1;
}

# probably not working
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

    $vol->add_tag(Name        => $self->volume_description($name)) unless exists $vol->tags->{Name};
    $vol->add_tags(StagingName => $name,
		   StagingMtPt => $mtpt,
		   Role        => 'StagingVolume');
    
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
	-volume    => $vol,
	-mtdev     => $mt_device,
	-mtpt      => $mtpt,
	-server    => $self,
	-name      => $name});

    $self->mount_volume($vol);
    return $vol;
}

sub _find_or_create_mount {
    my $self = shift;
    my $vol  = shift;

    my ($ebs_device,$mt_device,$mtpt);
    
    # handle the case of the volme already being attached
    if (my $attachment = $vol->attachment) {
	if ($attachment->status eq 'attached') {
	    $attachment->instanceId eq $self->instanceId or
		die "$vol is attached to wrong server";
	    ($mt_device,$mtpt) = $self->_find_mount($attachment->device);
	    unless ($mtpt) {
		$mtpt = $vol->tags->{StagingMtPt} || '/mnt/DataTransfer/'.$vol->name;
		$self->_mount($mt_device,$mtpt);
	    }

	    #oops, device is in a semi-attached state. Let it settle then reattach.
	} else {
	    $self->info("$vol was recently used. Waiting for attachment state to settle...\n");
	    $self->ec2->wait_for_attachments($attachment);
	}
    }

    unless ($mt_device && $mtpt) {
	($ebs_device,$mt_device) = $self->unused_block_device;
	$self->info("attaching $vol to $self via $mt_device\n");
	my $s = $vol->attach($self->instanceId,$mt_device);
	$self->ec2->wait_for_attachments($s);
	$s->current_status eq 'attached' or croak "Can't attach $vol to $self";
	$mtpt = $vol->tags->{StagingMtPt} || '/mnt/DataTransfer/'.$vol->name;
	$self->_mount($mt_device,$mtpt);
    }

    $vol->mtpt($mtpt);
    $vol->mtdev($mt_device);
}

# this gets called to find a device that is already mounted
sub _find_mount {
    my $self       = shift;
    my $device     = shift;
    my @mounts = $self->scmd('cat /proc/mounts');
    my (%mounts,$xvd);
    for my $m (@mounts) {
	my ($dev,$mtpt) = split /\s+/,$m;
	$xvd++ if $dev =~ m!^/dev/xvd!;
	$mounts{$dev} = $mtpt;
    }
    $device =~ s!^/dev/sd!/dev/xvd! if $xvd;
    return ($device,$mounts{$device});
}

sub mount_volume {
    my $self = shift;
    my $vol  = shift;
    if ($vol->mtpt) {
	$self->_mount($vol->mtdev,$vol->mtpt);
    } else {
	$self->_find_or_create_mount($vol);
    }
    $vol->mounted(1);
}

sub _mount {
    my $self = shift;
    my ($mt_device,$mtpt) = @_;
    $self->info("Mounting staging volume.\n");
    $self->ssh("sudo mkdir -p $mtpt; sudo mount $mt_device $mtpt") or croak "mount failed";
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
    my $device = $vol->mtdev;
    $self->info("remounting $vol\n");
    $self->ssh('sudo','mount',$device,$mtpt) or croak "Could not remount $mtpt";
    $vol->mounted(1);
}

sub delete_volume {
   my $self = shift;
   my $vol  = shift;
   my $ec2 = $self->ec2;
   $self->unregister_volume($vol);
   $self->unmount_volume($vol);
   $ec2->wait_for_attachments( $vol->instance->detach() );
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

    my $mgr = $self->manager;
    my ($servername,$pathname);
    if ($vpath =~ m!^(vol-[0-9a-f]+):?(.*)! && (my $vol = $mgr->find_volume_by_name($1))) {
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

    my $server = $self->manager->find_server_by_instance($servername)|| $servername;
    unless (ref $server && $server->isa('VM::EC2::Staging::Server')) {
	return [$server,$pathname];
    }

    $server->start unless $server->is_up;

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
    my $dest_ip  = $dest_host->instance->dnsName;
    return $source_host->ssh('sudo','rsync','-avz',
			     '-e',"'ssh -o \"StrictHostKeyChecking no\" -i $keyname -l $username'",
			     "--rsync-path='sudo rsync'",
			     @source_paths,"$dest_ip:$dest_path");
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

sub create_snapshot {
    my $self = shift;
    my ($vol,$description) = @_;
    my @snaps;
    my $device = $vol->mtdev;
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

    return ($vol,$needs_mkfs,$needs_resize);
}

sub volume_description {
    my $self = shift;
    my $vol  = shift;
    my $name = ref $vol ? $vol->name : $vol;
    return "Staging volume for $name created by ".__PACKAGE__;
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
    $self->manager->info(@_);
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

1;

