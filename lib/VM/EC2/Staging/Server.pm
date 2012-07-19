package VM::EC2::Staging::Server;

# high level interface for transferring data, and managing data snapshots
# via a series of Staging VMs.

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
    $args{-endpoint}       or croak 'need an endpoint argument';

    my $self = bless {
	endpoint => $args{-endpoint},
	instance => $args{-instance},
	username => $args{-username},
	keyfile  => $args{-keyfile},
	name     => $args{-name} || undef,
    },ref $class || $class;
    return $self;
}

sub ec2      { shift->manager->ec2    }
sub endpoint { shift->{endpoint}  }
sub instance { shift->{instance} }
sub keyfile  { shift->{keyfile}  }
sub username { shift->{username} }
sub name     { shift->{name}     }
sub manager {
    my $self = shift;
    my $ep   = $self->endpoint;
    return VM::EC2::Staging::Manager->find_manager($ep);
}

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

sub add_volume {
    shift->provision_volume(@_)
}

sub provision_volume {
    my $self = shift;
    my %args = @_;

    my $name   = $args{-name} ||= VM::EC2::Staging::Manager->new_volume_name;
    my $size   = $args{-size};
    my $volid  = $args{-volume_id};
    my $snapid = $args{-snapshot_id};
    my $reuse  = $args{-reuse};
    my $label  = $args{-label} || $args{-name};
    my $uuid   = $args{-uuid};

    $self->manager->find_volume_by_name($args{-name}) && 
	croak "There is already a volume named $args{-name} in this region";

    if ($volid || $snapid) {
	$name  ||= $volid || $snapid;
	$size  ||= -1;
    } else {
	$name        =~ /^[a-zA-Z0-9_.,&-]+$/
	    or croak "Volume name must contain only characters [a-zA-Z0-9_.,&-]; you asked for '$name'";
    }

    my $ec2      = $self->ec2;
    my $fstype   = $args{-fstype} || 'ext4';
    my $mtpt     = $fstype eq 'raw' ? 'none' : ($args{-mount}  || $args{-mtpt} || '/mnt/Staging/'.$name);
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
	              or die "Couldn't attach $vol to $instance via $ebs_device: ",$ec2->error_str;
    $ec2->wait_for_attachments($s)                   or croak "Couldn't attach $vol to $instance via $ebs_device";
    $s->current_status eq 'attached'                 or croak "Couldn't attach $vol to $instance via $ebs_device";

    if ($needs_resize) {
	$self->scmd("sudo blkid -p $mt_device") =~ /"ext\d"/   or croak "Sorry, but can only resize ext volumes ";
	$self->info("Checking filesystem...\n");
	$self->ssh("sudo /sbin/e2fsck -fy $mt_device")          or croak "Couldn't check $mt_device";
	$self->info("Resizing previously-used volume to $size GB...\n");
	$self->ssh("sudo /sbin/resize2fs $mt_device ${size}G") or croak "Couldn't resize $mt_device";
    } elsif ($needs_mkfs && $fstype ne 'raw') {
	local $_ = $fstype;
	my $label = /^ext/     ? "-L '$label'"
                   :/^xfs/     ? "-L '$label'"
                   :/^reiser/  ? "-l '$label'"
                   :/^jfs/     ? "-L '$label'"
                   :/^vfat/    ? "-n '$label'"
                   :/^msdos/   ? "-n '$label'"
                   :/^ntfs/    ? "-L '$label'"
		   :/^hfs/     ? "-v '$label'"
                   :'';
	my $uu = $uuid ? ( /^ext/     ? "-U $uuid"
			  :/^xfs/     ? ''
			  :/^reiser/  ? "-u $uuid"
			  :/^jfs/     ? ''
			  :/^vfat/    ? ''
			  :/^msdos/   ? ''
			  :/^ntfs/    ? "-U $uuid"
			  :/^hfs/     ? ''
			  :'')
	          : '';
	my $quiet = $self->manager->quiet && ! /msdos|vfat|hfs/ ? "-q" : '';

	my $apt_packages = $self->_mkfs_packages();
	if (my $package = $apt_packages->{$fstype}) {
	    $self->info("checking for /sbin/mkfs.$fstype\n");
	    $self->ssh("if [ ! -e /sbin/mkfs.$fstype ]; then sudo apt-get update; sudo apt-get -y install $package; fi");
	}
	$self->info("Making $fstype filesystem on staging volume...\n");
	$self->ssh("sudo /sbin/mkfs.$fstype $quiet $label $uu $mt_device") or croak "Couldn't make filesystem on $mt_device";

	if ($uuid && !$uu) {
	    $self->info("Setting the UUID for the volume\n");
	    $self->ssh("sudo xfs_admin -U $uuid $mt_device") if $fstype =~ /^xfs/;
	    $self->ssh("sudo jfs_tune -U $uuid $mt_device")  if $fstype =~ /^jfs/;
	    # as far as I know you cannot set a uuid for FAT and VFAT volumes
	}
    }

    my $volobj = VM::EC2::Staging::Volume->new({
	-volume    => $vol,
	-mtdev     => $mt_device,
	-mtpt      => $mtpt,
	-server    => $self,
	-name      => $name});

    # make sure the guy is mountable before trying it
    if ($volid || $snapid) {
	my $isfs = $self->scmd("sudo file -s $mt_device") =~ /filesystem/i;
	$self->mount_volume($volobj) if $isfs;
	$volobj->mtpt('none')    unless $isfs;
	$fstype = $volobj->get_fstype;
	$volobj->fstype($fstype);
    } else {
	$volobj->fstype($fstype);
	$self->mount_volume($volobj);
    }

    $self->manager->register_volume($volobj);
    return $volobj;
}

sub _mkfs_packages {
    my $self = shift;
    return {
	xfs       => 'xfsprogs',
	reiserfs  => 'reiserfsprogs',
	jfs       => 'jfsutils',
	ntfs      => 'ntfsprogs',
	hfs       => 'hfsprogs',
    }
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
		$mtpt = $vol->tags->{StagingMtPt} || '/mnt/Staging/'.$vol->name;
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
	$mtpt = $vol->tags->{StagingMtPt} || '/mnt/Staging/'.$vol->name;
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
    return if $vol->mtpt eq 'none';
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
    return if $mtpt eq 'none';
    return unless $vol->mounted;
    $self->info("unmounting $vol...\n");
    $self->ssh('sudo','umount',$mtpt) or croak "Could not umount $mtpt";
    $vol->mounted(0);
}

sub remount_volume {
    my $self = shift;
    my $vol  = shift;
    my $mtpt = $vol->mtpt;
    return if $mtpt eq 'none';
    my $device = $vol->mtdev;
    $self->info("remounting $vol\n");
    $self->ssh('sudo','mount',$device,$mtpt) or croak "Could not remount $mtpt";
    $vol->mounted(1);
}

sub delete_volume {
   my $self = shift;
   my $vol  = shift;
   my $ec2 = $self->ec2;
   $self->manager->unregister_volume($vol);
   $self->unmount_volume($vol);
   # call underlying EBS function to avoid the volume trying to spin up the
   # server just to unmount itself.
   $ec2->wait_for_attachments( $vol->ebs->detach() ); 
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
    if ($vpath =~ m!^(vol-[0-9a-f]+):?(.*)! && (my $vol = VM::EC2::Staging::Manager->find_volume_by_volid($1))) {
	my $path = $2;
	$path       = "/$path" if $path && $path !~ m!^/!;
	$vol->_spin_up;
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

    my $server = VM::EC2::Staging::Manager->find_server_by_instance($servername)|| $servername;
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
    croak "usage: VM::EC2::Staging::Server->rsync(\$source_path1,\$source_path2\...,\$dest_path)"
	unless @_ >= 2;

    my @p    = @_;
    undef $LastHost;
    my @paths = map {$self->resolve_path($_)} @p;

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

    my $rsync_args        = $self->_rsync_args;

    # localhost           => DataTransferServer
    if (!$source_host && UNIVERSAL::isa($dest_host,__PACKAGE__)) {
	return $dest_host->_rsync_put(@source_paths,$dest_path);
    }

    # DataTransferServer  => localhost
    if (UNIVERSAL::isa($source_host,__PACKAGE__) && !$dest_host) {
	return $source_host->_rsync_get(@source_paths,$dest_path);
    }

    if ($source_host eq $dest_host) {
	return $source_host->ssh('sudo','rsync',$rsync_args,@source_paths,$dest_path);
    }

    # DataTransferServer1 => DataTransferServer2
    # this one is slightly more difficult because datatransferserver1 has to
    # ssh authenticate against datatransferserver2.
    my $keyname = $self->_authorize($source_host => $dest_host);

    my $dest_ip  = $dest_host->instance->dnsName;
    my $ssh_args = $self->_ssh_escaped_args;
    my $keyfile  = $self->keyfile;
    $ssh_args    =~ s/$keyfile/$keyname/;  # because keyfile is embedded among args
    return $source_host->ssh('sudo','rsync',$rsync_args,
			     '-e',"'ssh $ssh_args'",
			     "--rsync-path='sudo rsync'",
			     @source_paths,"$dest_ip:$dest_path");
}

# for this to work, we have to create the concept of a "raw" staging volume
# that is attached, but not mounted
sub dd {
    my $self = shift;

    @_==2 or croak "usage: dd(\$source_vol=>\$dest_vol)";

    my ($vol1,$vol2) = @_;
    my ($server1,$device1) = ($vol1->server,$vol1->mtdev);
    my ($server2,$device2) = ($vol2->server,$vol2->mtdev);
    my $hush     = $self->manager->quiet ? '2>/dev/null' : '';

    if ($server1 eq $server2) {
	$server1->ssh("sudo dd if=$device1 of=$device2 $hush");
    }  else {
	my $keyname  = $self->_authorize($server1,$server2);
	my $dest_ip  = $server2->instance->dnsName;
	my $ssh_args = $self->_ssh_escaped_args;
	my $keyfile  = $self->keyfile;
	$ssh_args    =~ s/$keyfile/$keyname/;  # because keyfile is embedded among args
	$server1->ssh("sudo dd if=$device1 $hush | gzip -1 - | ssh $ssh_args $dest_ip 'gunzip -1 - | sudo dd of=$device2 $hush'");
    }
}

sub _authorize {
    my $self = shift;
    my ($source_host,$dest_host) = @_;
    my $keyname = "/tmp/${source_host}_to_${dest_host}";
    unless ($source_host->has_key($keyname)) {
	$source_host->info("creating ssh key for server to server data transfer\n");
	$source_host->ssh("ssh-keygen -t dsa -q -f $keyname</dev/null 2>/dev/null");
	$source_host->has_key($keyname=>1);
    }
    unless ($dest_host->accepts_key($keyname)) {
	my $key_stuff = $source_host->scmd("cat ${keyname}.pub");
	chomp($key_stuff);
	$dest_host->ssh("mkdir -p .ssh; chmod 0700 .ssh; (echo '$key_stuff' && cat .ssh/authorized_keys) | sort | uniq > .ssh/authorized_keys.tmp; mv .ssh/authorized_keys.tmp .ssh/authorized_keys; chmod 0600 .ssh/authorized_keys");
	$dest_host->accepts_key($keyname=>1);
    }

    return $keyname;
}

sub _rsync_put {
    my $self   = shift;
    my @source = @_;
    my $dest   = pop @source;
    # resolve symbolic name of $dest
    $dest        =~ s/^.+://;  # get rid of hostname, if it is there
    my $host     = $self->instance->dnsName;
    my $ssh_args = $self->_ssh_escaped_args;
    my $rsync_args = $self->_rsync_args;
    $self->info("Beginning rsync...\n");
    system("rsync $rsync_args -e'ssh $ssh_args' --rsync-path='sudo rsync' @source $host:$dest") == 0;
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
    my $ssh_args   = $self->_ssh_escaped_args;
    my $rsync_args = $self->_rsync_args;
    
    $self->info("Beginning rsync...\n");
    system("rsync $rsync_args -e'ssh $ssh_args' --rsync-path='sudo rsync' @source $dest")==0;
}

sub ssh {
    my $self = shift;
    my @cmd   = @_;
    my $Instance = $self->instance or die "Remote instance not set up correctly";
    my $host     = $Instance->dnsName;
    system('/usr/bin/ssh',$self->_ssh_args,$host,@cmd)==0;
}

sub scmd {
    my $self = shift;
    my @cmd   = @_;
    my $Instance = $self->instance or die "Remote instance not set up correctly";
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
    exec '/usr/bin/ssh',$self->_ssh_args,$host,@cmd;
}

# return a filehandle that you can write to:
# e.g.
# my $fh = $server->scmd_write('cat >/tmp/foobar');
# print $fh, "testing\n";
# close $fh;
sub scmd_write {
    my $self = shift;
    return $self->_scmd_pipe('write',@_);
}

# same thing, but you read from it:
# my $fh = $server->scmd_read('cat /tmp/foobar');
# while (<$fh>) {
#    print $_;
#}
sub scmd_read {
    my $self = shift;
    return $self->_scmd_pipe('read',@_);
}

sub _scmd_pipe {
    my $self = shift;
    my ($op,@cmd) = @_;
    my $operation = $op eq 'write' ? '|-' : '-|';
    my $host = $self->dnsName;
    my $pid = open(my $fh,$operation); # this does a fork
    defined $pid or croak "piped open failed: $!" ;
    return $fh if $pid;         # writing to the filehandle writes to an ssh session
    exec '/usr/bin/ssh',$self->_ssh_args,$host,@cmd;
    exit 0;
}


sub shell {
    my $self = shift;
    fork() && return;
    setsid(); # so that we are independent of parent signals
    my $host     = $self->instance->dnsName;
    my $ssh_args = $self->_ssh_escaped_args;
    exec 'xterm',
    '-e',"/usr/bin/ssh $ssh_args $host";
}

sub _ssh_args {
    my $self = shift;
    return (
	'-o','CheckHostIP no',
	'-o','StrictHostKeyChecking no',
	'-o','UserKnownHostsFile /dev/null',
	'-o','LogLevel QUIET',
	'-i',$self->keyfile,
	'-l',$self->username,
	);
}

sub _ssh_escaped_args {
    my $self = shift;
    my @args = $self->_ssh_args;
    for (my $i=1;$i<@args;$i+=2) {
	$args[$i] = qq("$args[$i]");
    }
    return join ' ',@args;
}

sub _rsync_args {
    my $self = shift;
    my $quiet = $self->manager->quiet;
    return $quiet ? '-aqz' : '-avz';
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
    $snap->add_tag(StagingName => $vol->name                  );
    $snap->add_tag(Name        => "Staging volume ".$vol->name);
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
	croak "$volid is not in server availability zone $zone."
	    unless $vol->availabilityZone eq $zone;
	croak "$vol is unavailable for use, status ",$vol->status
	    unless $vol->status eq 'available';
	@vols = $vol;
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

sub volumes {
    my $self   = shift;
    my @volIds = map {$_->volumeId} $self->blockDeviceMapping;
    my @volumes = map {$self->manager->find_volume_by_volid($_)} @volIds;
    return grep {defined $_} @volumes;
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

sub has_key {
    my $self    = shift;
    my $keyname = shift;
    $self->{_has_key}{$keyname} = shift if @_;
    return $self->{_has_key}{$keyname} if exists $self->{_has_key}{$keyname};
    return $self->{_has_key}{$keyname} = $self->scmd("if [ -e $keyname ]; then echo 1; fi");
}

sub accepts_key {
    my $self = shift;
    my $keyname = shift;
    $self->{_accepts_key}{$keyname} = shift if @_;
    return $self->{_accepts_key}{$keyname};
}

1;

