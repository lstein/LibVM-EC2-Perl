package VM::EC2::Staging::Server;

# high level interface for transferring data, and managing data snapshots
# via a series of DataTransfer VMs.

=head1 NAME

VM::EC2::Staging::Server - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 use VM::EC2::Staging::Server;

 my $ec2    = VM::EC2->new;
 my $server = $ec2->staging_server(-architecture => 'i386',
                                   -availability_zone => 'us-east-1a');

 # provision volume either creates volumes from scratch or initializes them
 # using similarly-named EBS snapshots, adjusting the size as necessary.
 my $vol1 = $server->provision_volume(-name    => 'Pictures',
                                      -fstype  => 'ext4',
                                      -size    => 2) or die $server->error_str;
 my $vol2 = $server->provision_volume(-name      => 'Videos',
                                      -volume_id => 'vol-12345',
                                      -size      => 200) or die $server->error_str;
 my $vol3 = $server->provision_volume(-name    => 'Music',
                                      -size    => 10,
                                      -mount   => '/mnt/volume3'  # specify mount point explicitly
                                      ) or die $server->error_str;

 # localhost to remote transfer using symbolic names of volumes
 $server->put('/usr/local/pictures'                        => 'Pictures');
 $server->put('/usr/local/my_videos'                       => 'Videos');
 $server->put('/home/fred/music','/home/jessica/music'     => 'Music');

 # localhost to remote transfer using directory paths
 $server->put('/usr/local/my_videos'  => '/home/ubuntu/videos');

 # remote to local transfer
 $server->get('Music' => '/tmp/music');
 $server->get('Music','Videos' => '/tmp/music');

 # remote to remote transfer - useful for interzone transfers
 $server->rsync('Music' => "$server2:/home/ubuntu/music");
 $server->rsync('Music' => "$server2:Music");

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
		     return $self->as_string;
                  },
    fallback => 1;

use constant GB => 1_073_741_824;

my %Servers;
my %Zones;
my $LastHost;

sub new {
    my $class = shift;
    my $ec2   = shift or croak "Usage: $class->new(\$ec2,\@args)";
    my %args  = @_;
    $args{-image_name}        ||= $class->default_image_name;
    $args{-username}          ||= $class->default_user_name;
    $args{-architecture}      ||= $class->default_architecture;
    $args{-root_type}         ||= $class->default_root_type;
    $args{-instance_type}     ||= $class->default_instance_type;
    $args{-availability_zone} ||= undef;
    $args{-quiet}             ||= undef;
    $args{-image}             ||= '';

    my $self = bless {
	ec2      => $ec2,
	instance => undef,
	username => $args{-username},
	quiet    => $args{-quiet},
    },ref $class || $class;
    $self->new_instance(\%args);
    weaken($Servers{$self->as_string}         = $self);
    weaken($Zones{$self->instance->placement} = $self);
    return $self;
}

sub ec2      { shift->{ec2}      }
sub instance { shift->{instance} }
sub volumes  { shift->{volumes}  }
sub keyfile  { shift->{keyfile}  }
sub username { shift->{username} }
sub quiet    { shift->{quiet}    }

sub default_image_name {
    return 'ubuntu-maverick-10.10';  # launches faster
#    return 'ubuntu-precise-12.04';  # LTS, but launches more slowly
}

sub default_user_name {
    return 'ubuntu';
}

sub default_architecture {
    return 'i386';
}

sub default_root_type {
    return 'instance-store';
}

sub default_instance_type {
    return 'm1.small';
}

sub as_string {
    my $self = shift;
    my $ip   = eval {$self->instance->dnsName} || '1.2.3.4';
    return $ip;
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

    $self->info("Mounting staging volume.\n");
    $self->ssh("sudo mkdir -p $mtpt; sudo mount $mt_device $mtpt; sudo chown $username $mtpt");

    return VM::EC2::Staging::Volume->new({
	volume    => $vol,
	device    => $mt_device,
	mtpt      => $mtpt,
	server    => $self,
	symbolic_name => $name});
}

sub delete_volume {
   my $self = shift;
   my $vol  = shift;
   my $mtpt = $vol->mtpt;
   my $volume = $vol->ebs;
   $self->info("unmounting $vol...");
   $self->ssh('sudo','umount',$mtpt) or croak "Could not umount $mtpt";
   $self->info("detaching $vol...");
   $self->wait_for_attachments( $volume->detach() );
   $self->info("deleting $vol...");
   $self->ec2->delete_volume($volume);
}

# take real or symbolic name and turn it into a two element
# list consisting of server object and mount point
# possible forms:
#            /local/path
#            Symbolic_path
#            $server:/remote/path
#            $server:./remote/path
#            $server:../remote/path
#            $server:Symbolic_path
#            $server:Symbolic_path/additional/directories
# 
# treat path as symbolic if it does not start with a slash
# or dot characters
sub resolve_path {
    my $self  = shift;
    my $vpath = shift;

    my ($servername,$pathname);
    if ($vpath =~ /^([^:]+):(.+)$/) {
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

sub new_instance {
    my $self = shift;
    my $args = shift;
    unless ($self->{instance}) {
	my $instance = $self->_create_instance($args)
	    or croak "Could not create an instance that satisfies requested criteria";
	$self->ec2->wait_for_instances($instance)
	    or croak "Instance did not come up in a reasonable time";
	$self->{instance} = $instance;
    }
    do {
	$self->info("Waiting for ssh daemon to become ready on staging server...");    
	sleep 5;
    } until eval{$self->scmd('pwd')};
    return $self->{instance};
}

sub _create_instance {
    my $self = shift;
    my $args = shift;
    my $image = $args->{-image};

    # search for a matching instance
    $image ||= $self->search_for_image($args) or croak "No suitable image found";
    my $sg   = $self->security_group();
    my $kp   = $self->keypair();
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
    $self->info("unmounting $vol\n");
    $self->ssh('sudo','umount',$mtpt) or croak "Could not umount $mtpt";
    my $d = $self->volume_description($vol);
    $self->info("snapshotting $vol\n");
    my $snap = $volume->create_snapshot($description) or croak "Could not snapshot $vol: ",$vol->ec2->error_str;
    $snap->add_tag(StagingName => $vol->name);
    $snap->add_tag(Name => "Staging volume ".$vol->name);
    $self->info("remounting $vol\n");
    $self->ssh('sudo','mount',$device,$mtpt) or croak "Could not remount $mtpt";
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

sub _new_keypair {
    my $self = shift;
    my $ec2  = $self->ec2;
    my $name = $ec2->token;
    $self->info("Creating temporary keypair $name.\n");
    my $kp   = $ec2->create_key_pair($name);
    my $tmpdir      = File::Spec->catfile(File::Spec->tmpdir,__PACKAGE__);
    make_path($tmpdir);
    chmod 0700,$tmpdir;
    my $keyfile     = File::Spec->catfile($tmpdir,"$name.pem");
    my $private_key = $kp->privateKey;
    open my $k,'>',$keyfile or die "Couldn't create $keyfile: $!";
    chmod 0600,$keyfile     or die "Couldn't chmod  $keyfile: $!";
    print $k $private_key;
    close $k;
    $self->{keyfile} = $keyfile;
    return $kp;
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
	    $self->info("No size provided. Defaulting to 10 GB.");
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
    undef $Servers{$self->as_string};
    undef $Zones{$self->instance->placement};
    $self->cleanup;
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

sub VM::EC2::new_data_transfer_server {
    my $self = shift;
    return VM::EC2::Staging::Server->new($self,@_)
}

1;

