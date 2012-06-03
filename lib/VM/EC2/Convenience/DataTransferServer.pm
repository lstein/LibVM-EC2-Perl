package VM::EC2::Convenience::DataTransferServer;

# high level interface for transferring data, and managing data snapshots
# via a series of DataTransfer VMs.

=head1 NAME

VM::EC2::Convenience::DataTransferServer - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 my $server = VM::EC2::Convenience->DataTransferServer->new(-access_key    => 'access key id',
                                                            -secret_key    => 'aws_secret_key',
                                                            -name          => 'ubuntu-maverick-10.10'
    );

 # provision volume either creates volumes from scratch or initializes them
 # using similarly-named EBS snapshots, adjusting the size as necessary.
 $server->provision_volume(-name    => 'Pictures',
                           -fstype  => 'ext4',
                           -size    => 20) or die $server->error_str;
 $server->provision_volume(-name    => 'Videos',
                           -size    => 20) or die $server->error_str;
 $server->provision_volume(-name    => 'Music',
                           -size    => 200,
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
 $server->copy('Music' => "$server2:/home/ubuntu/music");
 $server->copy('Music' => "$server2:Music");

 $server->snapshot('Music','Videos','Pictures');
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
use Carp 'croak';
use Scalar::Util 'weaken';
use File::Spec;
use File::Path 'make_path','remove_tree';
use File::Basename 'dirname';
use overload
    '""'     => sub {my $self = shift;
		     return $self->as_string;
                  },
    fallback => 1;

use constant GB => 1_073_741_824;

my %Servers;

sub new {
    my $class = shift;
    my $ec2   = shift or croak "Usage: $class->new(\$ec2,\@args)";
    my %args  = @_;
    $args{-quiet}           ||= undef;
    $args{-preserve_volume} ||= undef;
    $args{-image}           ||= '';
    $args{-image_name}      ||= 'ubuntu-maverick-10.10';
    $args{-username}        ||= 'ubuntu';
    $args{-architecture}    ||= 'i386';
    $args{-root_type}       ||= 'instance-store';
    $args{-instance_type}   ||= $args{-architecture} eq 'i386' ? 'm1.small' : 'm1.large';

    my $self = bless {
	ec2      => $ec2,
	instance => undef,
	username => $args{-username},
	volumes  => {},           # {Symbolic_name => {snapshot=>$snap,volume=>$volume,mount=>'mnt/pt'}}
	quiet    => $args{-quiet},
	preserve => $args{-preserve_volume},
    },ref $class || $class;
    weaken($Servers{$self->as_string}=$self);

    $self->new_instance(\%args);
    return $self;
}

sub ec2      { shift->{ec2}      }
sub instance { shift->{instance} }
sub volumes  { shift->{volumes}  }
sub keyfile  { shift->{keyfile}  }
sub username { shift->{username} }
sub preserve { shift->{preserve} }
sub quiet    { shift->{quiet}    }

sub as_string {
    my $self = shift;
    my $ip   = eval {$self->instance->dnsName} || '1.2.3.4';
    return $ip;
}

sub provision_volume {
    my $self = shift;
    my %args = @_;
    my $name = $args{-name};
    my $size = $args{-size};
    $name && $size or croak "Usage: provision_volume(-name=>'name',-size=>$size)";
    $name        =~ /^[a-zA-Z0-9_.,&-]+$/
	or croak "Volume name must contain only characters [a-zA-Z0-9_.,&-]; you asked for '$name'";
    my $ec2      = $self->ec2;
    my $mtpt     = $args{-mount}  || '/mnt/DataTransfer/'.$name;
    my $fstype   = $args{-fstype} || 'ext4';
    my $username = $self->username;
    
    $size = int($size) < $size ? int($size)+1 : $size;  # dirty ceil() function
    $self->info("Provisioning a $size GB volume...\n");
    my $instance = $self->instance;
    my $zone     = $instance->placement;
    my ($vol,$needs_mkfs,$needs_resize) = $self->_create_volume($name,$size,$zone);
    
    my ($ebs_device,$mt_device) = eval{$self->unused_block_device()}           
                      or die "Couldn't find suitable device to attach this volume to";
    my $s = $instance->attach_volume($vol=>$ebs_device)  
	              or die "Couldn't attach $vol to $instance via $ebs_device";
    $ec2->wait_for_attachments($s)                   or die "Couldn't attach $vol to $instance via $ebs_device";
    $s->current_status eq 'attached'                 or die "Couldn't attach $vol to $instance via $ebs_device";

    if ($needs_resize) {
	die "Sorry, but can only resize ext volumes " unless $fstype =~ /^ext/;
	$self->info("Resizing previously-snapshotted volume to $size GB...\n");
	$self->ssh("sudo /sbin/resize2fs $mt_device");
    } elsif ($needs_mkfs) {
	$self->info("Making $fstype filesystem on staging volume...\n");
	$self->ssh("sudo /sbin/mkfs.$fstype $mt_device");
    }

    $self->info("Mounting staging volume...\n");
    $self->ssh("sudo mkdir -p $mtpt; sudo mount $mt_device $mtpt; sudo chown $username $mtpt");

    $self->{volumes}{$name} = {volume=>$vol,mtpt=>$mtpt};
    return $self->as_string .':'.$name;
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
    if ($vpath =~ /^([^:])+:(.+)$/) {
	$servername = $self->{_last_host} = $1;
	$pathname   = $2;
    } elsif ($vpath =~ /^:(.+)$/) {
	$servername = $self->{_last_host};
	$pathname   = $2;
    } else {
	return [undef,$vpath];   # localhost
    }

    my $server = $Servers{$servername} || $servername;
    unless (ref $server && $server->isa('VM::EC2::Convenience::DataTransferServer')) {
	return [$server,$pathname];
    }

    my $path;
    if ($pathname !~ m!^[/.]!) { # symbolic name
	my ($base,@rest) = split('/',$pathname);
	my $mtpt = $server->mntpt($base) or croak "$server: no mountpoint for $base";
	$path    = join ('/',$mtpt,@rest);
    } else {
	$path = $pathname;
    }

    return [$server,$path];
}

# most general form
# 
sub copy {
    my $self = shift;
    delete $self->{_last_host};
    my @paths = map {$self->resolve_path($_)} @_;

    my $dest   = pop @paths;
    my @source = @paths;

    my %hosts;
    foreach (@source) {
	$hosts{$_[0]} = $_->[0];
    }
    croak "More than one source host specified" if keys %hosts > 1;
    my ($source_host) = values %hosts;
    my $dest_host     = $dest->[0];

    my @source_paths      = map {$_->[1]} @source;
    my $dest_path         = $dest->[1];

    # localhost           => DataTransferServer
    if (!$source_host && UNIVERSAL::isa($dest_host,__PACKAGE__)) {
	return $dest_host->put(@source_paths,$dest_path);
    }

    # DataTransferServer  => localhost
    if (UNIVERSAL::isa($source_host,__PACKAGE__) && !$dest_host) {
	return $source_host->get(@source_paths,$dest_path);
    }

    # DataTransferServer1 => DataTransferServer2
    # this one is slightly more difficult because datatransferserver1 has to
    # ssh authenticate against datatransferserver2.
    my $keyname = "/tmp/${source_host}_to_${dest_host}";
    unless ($source_host->has_key($keyname)) {
	$source_host->ssh("ssh-keygen -t dsa -q -f $keyname</dev/null 2>/dev/null");
	$source_host->has_key($keyname=>1);
    }
    unless ($dest_host->accepts_key($keyname)) {
	my $key_stuff = $source_host->ssh("cat ${keyname}.pub");
	chomp($key_stuff);
	$dest_host->ssh('mkdir -p .ssh; chmod 0700 .ssh; echo $key_stuff >> .ssh/authorized_keys');
	$dest_host->accepts_key($keyname);
    }

    my $username = $dest_host->username;
    return $source_host->ssh("rsync -Ravz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyname -l $username' @source_paths $dest_host:$dest_path");

    # localhost           => localhost (local cp)
    return system("rsync @source_paths $dest_path") == 0;

    # DataTransferServer  => DataTransferServer (remote cp)
    return $source_host->ssh("rsync @source_paths $dest_path");
}

sub put {
    my $self   = shift;
    my @source = @_;
    my $dest   = pop @source;
    # resolve symbolic name of $dest
    $dest        =~ s/^.+://;  # get rid of hostname, if it is there
    my $target   = $self->_symbolic_to_real_mtpt($dest);
    my $host     = $self->instance->dnsName;
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    $self->info("Beginning rsync...\n");
    system "rsync -avz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' @source $host:$target";
}

sub get {
    my $self = shift;
    my @source = @_;
    my $target   = pop @source;

    # resolve symbolic names of src
    my $host     = $self->instance->dnsName;
    my @from;
    foreach (@source) {
	(my $path = $_) =~ s/^.+://;  # get rid of host part, if it is there
	$path = $self->_symbolic_to_real_mtpt($path);
	push @from,"$host:$path";
    }
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    
    $self->info("Beginning rsync...\n");
    system "rsync -avz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' @from $target";
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
    while (!eval{$self->ssh('pwd')}) {
	$self->info("Waiting for ssh daemon to become ready on remote instance...");
	sleep 5;
    }
    return $self->{instance};
}

sub _create_instance {
    my $self = shift;
    my $args = shift;
    # search for a matching instance
    my $image = $args->{-image};
    $image ||= $self->search_for_image($args);
    my $sg   = $self->security_group();
    my $kp   = $self->keypair();
    $self->info("Creating staging server from $image...\n");
    my $instance = $self->ec2->run_instances(-image_id          => $image,
					     -instance_type     => $args->{-instance_type},
					     -security_group_id => $sg,
					     -key_name          => $kp);
    $instance->add_tag(Name=>"Staging server created by VM::EC2::Convenience::DataTransferServer");
    return $instance;
}

sub search_for_image {
    my $self = shift;
    my $args = shift;
    $self->info("Searching for a suitable image matching $args->{-image_name}...\n");
    my @candidates = $self->ec2->describe_images({'name'             => "*$args->{-image_name}*",
						  'root-device-type' => $args->{-root_type},
						  'architecture'     => $args->{-architecture}});
    return unless @candidates;
    # this assumes that the name has some sort of timestamp in it, which is true
    # of ubuntu images, but probably not others
    my ($most_recent) = sort {$b->name cmp $a->name} @candidates;
    $self->info("Found $most_recent: ",$most_recent->name,"\n");
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
    $self->info("Creating temporary keypair $name\n");
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
    my ($name,$size,$zone) = @_;
    my $ec2 = $self->ec2;
    
    my @snaps = sort {$b->startTime cmp $a->startTime} $ec2->describe_snapshots(-owner  => $ec2->account_id,
										-filter => {description=>$name});
    my ($vol,$needs_mkfs,$needs_resize);
    if (@snaps) {
	my $snap = $snaps[0];
	print STDERR "Reusing existing snapshot $snap...\n";
	my $s    = $size > $snap->volumeSize ? $size : $snap->volumeSize;
	$vol = $snap->create_volume(-availability_zone=>$zone,
				    -size             => $s);
	$needs_resize = $snap->volumeSize < $s;
    } else {
	$vol = $ec2->create_volume(-availability_zone=>$zone,
				   -size             =>$size);
	$needs_mkfs++;
    }
    return unless $vol;
    $vol->add_tag(Name=>"Staging volume for $name created by ".__PACKAGE__);
    $vol->add_tag(Role=>"Staging volume for $name created by ".__PACKAGE__);
    return ($vol,$needs_mkfs,$needs_resize);
}

sub _symbolic_to_real_mtpt {
    my $self = shift;
    my $path = shift;
    my @dirs = split '/',$path;
    @dirs         = map {$self->{volumes}{$_}{mtpt} || $_} @dirs;
    my $realpath  = join '/',@dirs;
    $realpath    .= '/' if $path =~ m!/$!;
    return $realpath;
}

sub ssh {
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
	die "ssh failed with status ",$?>>8 unless $?==0;
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

# find an unused block device
sub unused_block_device {
    my $self        = shift;
    my $major_start = shift || 'f';

    my @devices = $self->ssh('ls -1 /dev/sd?*');
    unless (@devices) {
	@devices = $self->ssh('ls -1 /dev/xvd?*');
    }
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
            return ($local_device,$ebs_device);
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
    unless ($self->preserve) {
	$self->info('Deleting staging volumes...');
	for my $v (keys %{$self->volumes}) {
	    my $volume = $self->volumes->{$v}{volume};
	    warn "deleting volume... we probably don't want to do this...";
	    $self->ec2->delete_volume($volume); # do we really want to do this?
	}
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
    $self->cleanup;
}

sub VM::EC2::new_data_transfer_server {
    my $self = shift;
    return VM::EC2::Convenience::DataTransferServer->new($self,@_)
}

1;

