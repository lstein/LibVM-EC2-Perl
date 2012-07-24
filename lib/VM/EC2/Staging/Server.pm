package VM::EC2::Staging::Server;

# high level interface for transferring data, and managing data snapshots
# via a series of Staging VMs.

=head1 NAME

VM::EC2::Staging::Server - High level interface to EC2-based servers

=head1 SYNOPSIS


 use VM::EC2::Staging::Manager;

 # get a new staging manager
 my $ec2     = VM::EC2->new;
 my $staging = $ec2->staging_manager();                                         );
 

 # Fetch a server named 'my_server'. Create it if it does not already exist.
 my $server1 = $staging->get_server(-name              => 'my_server',
                                   -availability_zone  => 'us-east-1a',
                                   -architecture       => 'i386',
                                   -instance_type      => 't1.micro');

 # As above, but force a new server to be provisioned.
 my $server2 = $staging->provision_server(-name              => 'my_server',
                                          -availability_zone => 'us-east-1a',
                                          -architecture      => 'i386',
                                          -instance_type     => 't1.micro');

 # open up a terminal emulator in a separate window
 $server1->shell;
 
 # Run a command over ssh on the server. Standard in and out will be connected to
 # STDIN/OUT
 $server1->ssh('whoami');

 # run a command over ssh on the server, returning standard output as an array of lines or a
 # scalar string, similar to backticks (``)
 my @password_lines = $server1->scmd('cat /etc/passwd');

 # run a command on the server and read from it using a filehandle
 my $fh  = $server1->scmd_read('ls -R /usr/lib');
 while (<$fh>) { # do something }

 # run a command on the server and write to it using a filehandle
 my $fh  = $server1->scmd_write('sudo -s "cat >>/etc/fstab"');
 print $fh "/dev/sdf3 /mnt/demo ext3 0 2\n";
 close $fh;

 # provision and mount a 5 gig ext3 volume mounted on /opt, returning
 # VM::EC2::Staging::Volume object
 my $opt = $server1->provision_volume(-mtpt   => '/opt',
                                      -fstype => 'ext3',
                                      -size   => 5);

 # copy some data from the local filesystem onto the opt volume
 $server1->rsync("$ENV{HOME}/local_staging_volume/" => $opt);

 # provision a volume attached to another server, and let the
 # system choose the filesystem and mount point for us
 my $backups = $server2->provision_volume(-name => 'Backup',
                                         -size => 10);

 # copy some data from opt to the new volume using rsync
 $server1->rsync($opt => "$backups/opt");
 
 # Do a block-level copy between disks - warning, the filesystem must be unmounted
 # before you attempt this.
 $backups->unmount;
 $server1->dd($opt => $backups);

=head1 DESCRIPTION

VM::EC2::Staging::Server objects are an extension of VM::EC2::Instance
to allow for higher-level access, including easy management of ssh
keys, remote copying of data from one server to another, and executing
of remote commands on the server from within Perl. See
L<VM::EC2::Staging::Manager> for an overview of staging servers and
volumes.

Note that proper functioning of this module is heavily dependent on
running on a host system that has access to ssh, rsync and terminal
emulator command-line tools. It will most likely fail when run on a
Windows host.

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
my ($LastHost,$LastMt);

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

=head1 Staging Server Creation

Staging servers are usually created via a staging manager's
get_server() or provision_server() methods. See L<VM::EC2::Staging::Manager>.

There is also a new() class method that is intended to be used
internally in most cases. It is called like this:

=head2 $server = VM::EC2::Staging::Server->new(%args)

With the arguments:

 -keyfile    path to the ssh public/private keyfile for this instance
 -username   username for remote login on this instance
 -instance   VM::EC2::Instance to attach this server to
 -manager    VM::EC2::Staging::Manager in same zone as the instance

Note that you will have to launch a staging manager, start an
instance, and appropriate provision the SSH credentials for that
instance before invoking new() directly.

=cut

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-keyfile}        or croak 'need -keyfile path';
    $args{-username}       or croak 'need -username';
    $args{-instance}       or croak 'need a -instance VM::EC2::Instance argument';
    $args{-manager}        or croak 'need a -manager argument';

    my $endpoint = $args{-manager}->ec2->endpoint;
    my $self = bless {
	endpoint => $endpoint,
	instance => $args{-instance},
	username => $args{-username},
	keyfile  => $args{-keyfile},
	name     => $args{-name} || undef,
    },ref $class || $class;
    return $self;
}

=head1 Information about the Server

VM::EC2::Staging::Server objects have all the methods of
VM::EC2::Instance, such as dnsName(), but add several new methods. The
new methods involving getting basic information about the server are
listed in this section.

=head2 $name = $server->name

This method returns the server's symbolic name, if any.

Servers can optionally be assigned a symbolic name at the time they
are created by the manager's get_server() or provision_server()
methods. The name persists as long as the underlying instance exists
(including in stopped state for EBS-backed instances). Calling
$manager->get_server() with this name returns the server object.

=cut

sub name     { shift->{name}     }

=head2 $ec2 = $server->ec2

Return the VM::EC2 object associated with the server.

=cut

sub ec2      { shift->manager->ec2    }

=head2 $ec2 = $server->endpoint

Return the endpoint URL associated with this server.

=cut

sub endpoint { shift->{endpoint}  }

=head2 $instance = $server->instance

Return the VM::EC2::Instance associated with this server.

=cut

sub instance { shift->{instance} }

=head2 $file = $server->keyfile

Return the full path to the SSH PEM keyfile used to log into this
server.

=cut

sub keyfile  { shift->{keyfile}  }

=head2 $user = $server->username

Return the name of the user (e.g. 'ubuntu') used to ssh into this
server.

=cut

sub username { shift->{username} }

=head2 $manager = $server->manager

Returns the VM::EC2::Staging::Manager that manages this server.

=cut

sub manager {
    my $self = shift;
    my $ep   = $self->endpoint;
    return VM::EC2::Staging::Manager->find_manager($ep);
}

=head1 Lifecycle Methods

The methods in this section manage the lifecycle of a server.

=head2 $flag = $server->ping

The ping() method returns true if the server is running and is
reachable via ssh. It is different from checking that the underlying
instance is "running" via a call to current_status, because it also
checks the usability of the ssh daemon, the provided ssh key and
username, firewall rules, and the network connectivity.

The result of ping is cached so that subsequent invocations return
quickly.

=cut

sub ping {
    my $self = shift;
    return unless $self->instance->status eq 'running';
    return 1 if $self->is_up;
    return unless $self->ssh('pwd >/dev/null 2>&1');
    $self->is_up(1);
    return 1;
}

=head2 $result = $server->start

Attempt to start a stopped server. The method will wait until a ping()
is successful, or until a timeout of 120 seconds. The result code will
be true if the server was successfully started and is reachable.

If you wish to start a set of servers without waiting for each one
individually, then you may call the underling instance's start()
method:

 $server->instance->start;

You may then wish to call the staging manager's wait_for_instances()
method to wait on all of the servers to start:

 $manager->wait_for_servers(@servers);

Also check out $manager->start_all_servers().

=cut


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
    1;
}

=head2 $result = $server->stop

Attempt to stop a running server. The method will wait until the
server has entered the "stopped" state before returning. It will
return a true result if the underlying instance stopped successfully.

If you wish to stop a set of servers without waiting for each one
individually, then you may call the underling instance's start()
method:

 $server->instance->stop;

You may then wish to call the staging manager's wait_for_instances()
method to wait on all of the servers to start:

 $status = $manager->wait_for_servers(@servers);

Also check out $manager->stop_all_servers().

=cut

sub stop {
    my $self = shift;
    return unless $self->instance->status eq 'running';
    $self->instance->stop;
    $self->is_up(0);
    my $status = $self->manager->wait_for_instances($self);
    return $status->{$self->instance} eq 'stopped';
}

=head2 $result = $server->terminate

Terminate a server and unregister it from the manager. This method
will stop and wait until the server is terminated.

If you wish to stop a set of servers without waiting for each one
individually, then you may call the underling instance's start()
method:

 $server->instance->terminate;

=cut

sub terminate {
    my $self = shift;
    $self->manager->_terminate_servers($self);
    $self->is_up(0);
    1;
}

=head1 Volume Management Methods

The methods in this section allow you to create and manage volumes
attached to the server. These supplement the EC2 facilities for
creating and attaching EBS volumes with the ability to format the
volumes with a variety of filesystems, and mount them at a desired
location.

=head2 $volume = $server->provision_volume(%args)

Provision and mount a new volume. If successful, the volume is
returned as a VM::EC2::Staging::Volume object.

Arguments:

 -name         Symbolic name for the desired volume.
 -fstype       Filesystem type for desired volume
 -size         Size for the desired volume in GB
 -mtpt         Mountpoint for this volume
 -mount        Alias for -mtpt
 -volume_id    ID of existing volume to attach & mount
 -snapshot_id  ID of existing snapshot to use to create this volume
 -reuse        Reuse an existing managed volume of same name.
 -label        Disk label to assign during formatting
 -uuid         UUID to assign during formatting

*Explain default behavior
*Explain -fstype types
*Explain -volume_id and _snapshot_id
*Explain -reuse
*Explain UUID

=cut

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

sub add_volume {
    shift->provision_volume(@_)
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
    return unless $mtpt;
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
    if ($vpath =~ /^(vol-[0-9a-f]+):?(.*)/ &&
	      (my $vol = VM::EC2::Staging::Manager->find_volume_by_volid($1))) {
	my $path    = $2 || '/';
	$path       = "/$path" if $path && $path !~ m!^/!;
	$vol->_spin_up;
	$servername = $LastHost = $vol->server;
	my $mtpt    = $LastMt   = $vol->mtpt;
	$pathname   = $mtpt;
	$pathname  .= $path if $path;
    } elsif ($vpath =~ /^(i-[0-9a-f]{8}):(.+)$/ && 
	     (my $server = VM::EC2::Staging::Manager->find_server_by_instance($1))) {
	$servername = $LastHost = $server;
	$pathname   = $2;
    } elsif ($vpath =~ /^:(.+)$/) {
	$servername = $LastHost if $LastHost;
	$pathname   = $LastHost && $LastMt ? "$LastMt/$2" : $2;
    } else {
	return [undef,$vpath];   # localhost
    }

    $servername->start    if $servername && !$servername->is_up;
    return [$servername,$pathname];
}

=head1 Data Copying Methods

=cut

# most general form
# 
sub rsync {
    my $self = shift;
    croak "usage: VM::EC2::Staging::Server->rsync(\$source_path1,\$source_path2\...,\$dest_path)"
	unless @_ >= 2;

    my @p    = @_;
    undef $LastHost;
    undef $LastMt;
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

    my $src_is_server    = $source_host && UNIVERSAL::isa($source_host,__PACKAGE__);
    my $dest_is_server   = $dest_host   && UNIVERSAL::isa($dest_host,__PACKAGE__);

    # this is true when one of the paths contains a ":", indicating an rsync
    # path that contains a hostname, but not a managed server
    my $remote_path      = "@source_paths $dest_path" =~ /:/;

    # remote rsync on either src or dest server
    if ($remote_path && ($src_is_server || $dest_is_server)) {
	my $server = $source_host || $dest_host;
	return $server->ssh(['-t','-A'],"sudo -E rsync -e 'ssh -o \"CheckHostIP no\" -o \"StrictHostKeyChecking no\"' $rsync_args @source_paths $dest_path");
    }

    # localhost => localhost
    if (!($source_host || $dest_host)) {
	return system("rsync @source $dest") == 0;
    }

    # localhost           => DataTransferServer
    if ($dest_is_server && !$src_is_server) {
	return $dest_host->_rsync_put(@source_paths,$dest_path);
    }

    # DataTransferServer  => localhost
    if ($src_is_server && !$dest_is_server) {
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

=head1 Remote Shell Methods

=cut

sub ssh {
    my $self = shift;

    my @extra_args;
    if (ref($_[0]) && ref($_[0]) eq 'ARRAY') {
	my $extra      = shift;
	@extra_args = @$extra;
    }
    my @cmd   = @_;
    my $Instance = $self->instance or die "Remote instance not set up correctly";
    my $host     = $Instance->dnsName;
    system('ssh',$self->_ssh_args,@extra_args,$host,@cmd)==0;
}

sub scmd {
    my $self = shift;
    my @extra_args;
    if (ref($_[0]) && ref($_[0]) eq 'ARRAY') {
	my $extra      = shift;
	@extra_args = @$extra;
    }
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
    exec 'ssh',$self->_ssh_args,@extra_args,$host,@cmd;
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
    my @extra_args;
    if (ref($cmd[0]) && ref($cmd[0]) eq 'ARRAY') {
	my $extra      = shift @cmd;
	@extra_args = @$extra;
    }
    my $operation = $op eq 'write' ? '|-' : '-|';
    my $host = $self->dnsName;
    my $pid = open(my $fh,$operation); # this does a fork
    defined $pid or croak "piped open failed: $!" ;
    return $fh if $pid;         # writing to the filehandle writes to an ssh session
    exec 'ssh',$self->_ssh_args,@extra_args,$host,@cmd;
    exit 0;
}


sub shell {
    my $self = shift;
    $self->start unless $self->is_up;
    fork() && return;
    setsid(); # so that we are independent of parent signals
    my $host     = $self->instance->dnsName;
    my $ssh_args = $self->_ssh_escaped_args;
    my $emulator = $ENV{COLORTERM} || $ENV{TERM} || 'xterm';
    exec $emulator,'-e',"ssh $ssh_args $host";
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
	$args[$i] = qq("$args[$i]") if $args[$i];
    }
    my $args = join ' ',@args;
    return $args;
}

sub _rsync_args {
    my $self = shift;
    my $quiet = eval{$self->manager->quiet};
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

=head1 Internal methods

The methods in this section are intended primarily for internal use.

=cut

sub is_up {
    my $self = shift;
    my $d    = $self->{_is_up};
    $self->{_is_up} = shift if @_;
    $d;
}


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

1;

