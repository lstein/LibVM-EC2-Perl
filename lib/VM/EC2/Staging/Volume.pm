package VM::EC2::Staging::Volume;

=head1 NAME

VM::EC2::Staging::Volume - High level functions for provisioning and populating EC2 volumes

=head1 SYNOPSIS

 use VM::EC2::Staging::manager;

 # get a new staging manager
 my $ec2     = VM::EC2->new;
 my $staging = $ec2->staging_manager();                                         );

 my $vol1 = $staging->get_volume(-name => 'Backup',
                                 -fstype => 'ext4',
                                 -size   => 11,
                                 -zone   => 'us-east-1a');

 # make a couple of directories in new volume
 $vol1->mkdir('pictures');
 $vol1->mkdir('videos');

 # use rsync to copy local files onto a subdirectory of this volume
 $vol1->put('/usr/local/my_pictures/' =>'pictures');
 $vol1->put('/usr/local/my_videos/'   =>'videos');

 # use rsync to to copy a set of files on the volume to a local directory 
 mkdir('/tmp/jpegs');
 $vol1->get('pictures/*.jpg','/tmp/jpegs');

 # note that these commands are executed on the remote server as root!
 @listing = $vol1->ls('-r','pictures');
 $vol1->chown('fred','pictures');
 $vol1->chgrp('nobody','pictures');
 $vol1->chmod('0700','pictures');
 $vol1->rm('-rf','pictures/*');
 $vol1->rmdir('pictures');

 # get some information about the volume
 my $mtpt     = $vol->mtpt;
 my $mtdev    = $vol->mtdev;
 my $mounted  = $vol->mounted;
 my $server   = $vol->server;

 # detach the volume
 $vol->detach;

 # delete the volume entirely
 $vol->delete;

=head1 DESCRIPTION

This is a high-level interface to EBS volumes which is used in
conjunction with VM::EC2::Staging::Manager and
VM::EC2::Staging::Server. It is intended to ease the process of
allocating and managing EBS volumes, and provides for completely
automated filesystem creation, directory management, and data transfer
to and from the volume.

You can use staging volumes without having to manually create and
manage the instances needed to manipulate the volumes. As needed, the
staging manager will create the server(s) needed to execute the
desired actions on the volumes.

Staging volumes are wrappers around VM::EC2::Volume, and have all the
methods associated with those objects. In addition to the standard EC2
volume characteristics, each staging volume in an EC2 region has a
symbolic name, which can be used to retrieve previously-created
volumes without remembering their volume ID. This symbolic name is
stored in the tag StagingName. Volumes also have a filesystem type
(stored in the tag StagingFsType). When a volume is mounted on a
staging server, it will also have a mount point on the file system,
and a mounting device (e.g. /dev/sdf1).

=cut

use strict;
use VM::EC2;
use Carp 'croak';
use VM::EC2::Staging::Server;
use File::Spec;

use overload
    '""'     => sub {my $self = shift;
 		     return $self->short_name;  # "inherited" from VM::EC2::Volume
},
    fallback => 1;

my $Volume = 1;  # for anonymously-named volumes
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my $vol = eval {$self->ebs} or croak overload::StrVal($self)," no longer connected to an Amazon EBS object, so can't execute $func_name()";
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

=head1 Staging Volume Creation

Staging volumes are created via a staging manager's get_volume() or
provision_volume() methods. See L<VM::EC2::Staging::Manager>. One
typical invocation is:

 my $ec2     = VM::EC2->new;
 my $manager = $ec2->staging_manager();                                         );
 my $vol = $manager->get_volume(-name => 'Backup',
                                -fstype => 'ext4',
                                -size   => 5,
                                -zone   => 'us-east-1a');

This will either retrieve an existing volume named "Backup", or, if
none exists, create a new one using the provided specification. Behind
the scenes, a staging server will be allocated to mount the
volume. The manager tries to conserve resources, and so will reuse a
suitable running staging server if one is available.

The other typical invocation is:

 my $vol = $manager->provision_volume(-name => 'Backup',
                                      -fstype => 'ext4',
                                      -size   => 5,
                                      -zone   => 'us-east-1a');

This forces creation of a new volume with the indicated
characteristics. If a volume of the same name already exists, this
method will die with a fatal error (to avoid this, either wrap in an
eval, or leave off the -name argument and let the manager pick a
unique name for you).

=cut

=head1 Volume Information

The methods in this section return status information about the staging volume.

=head2 $name = $vol->name([$newname])

Get/set the symbolic name associated with this volume.

=head2 $mounted = $vol->mounted

Returns true if the volume is currently mounted on a server.

=head2 $type = $vol->fstype

Return the filesystem type requested at volume creation time.

=head2 $server = $vol->server

Get the server associated with this volume, if any.

=head2 $device = $vol->mtdev

Get the device that the volume is attached to, e.g. /dev/sdf1. If the
volume is not attached to a server, returns undef.

=head2 $device = $vol->mtpt

Get the mount point for this volume on the attached server. If the
volume is not mounted, returns undef.

=head2 $ebs_vol = $vol->ebs

Get the underlying EBS volume associated with the staging volume object.

=head2 $manager = $vol->manager

Return the VM::EC2::Staging::Manager which manages this volume.

=cut

# $stagingvolume->new({-server => $server,  -volume => $volume,
#                      -mtdev => $device,   -mtpt   => $mtpt,
#                      -name => $name,      -fstype => $fstype})
#
sub new {
    my $self = shift;
    my $args;
    if (ref $_[0]) {
	$args = shift;
    } else {
	my %args = @_;
	$args    = \%args;
    }
    return bless $args,ref $self || $self;
}

# accessors:
# sub volume
# sub mtpt
# sub name
# sub manager
foreach (qw(-server -volume -name -endpoint -mtpt -mtdev -fstype)) {
    (my $function = $_) =~ s/^-//;
    eval <<END;
    sub $function {
	my \$self = shift;
	my \$d    = \$self->{$_};
	\$self->{$_} = shift if \@_;
	return \$d;
    }
END
}

sub ebs  {shift->volume(@_)}
sub manager {
    my $self = shift;
    my $ep   = $self->endpoint;
    return VM::EC2::Staging::Manager->find_manager($ep);
}

=head2 $type = $vol->get_fstype

Return the volume's actual filesystem type. This can be different from
the requested type if it was later altered by running mkfs on the
volume, or the contents of the disk were overwritten by a block-level
dd command. As a side effect, this method sets fstype() to the current
correct value.

=cut

# look up our filesystem type
sub get_fstype {
    my $self = shift;
    return $self->fstype if $self->fstype;
    return 'raw'         if $self->mtpt eq 'none';

    $self->_spin_up;
    my $dev    = $self->mtdev;
    my $blkid  = $self->server->scmd("sudo blkid $dev");
    my ($type) = $blkid =~ /TYPE="([^"]+)"/;
    $self->fstype($type);
    return $type || 'raw';
}

sub mount {
    my $self = shift;
    $self->_spin_up;
    $self->fstype($self->get_fstype) unless $self->fstype;
}

sub mounted {
    my $self = shift;
    my $m    = $self->{mounted};
    $self->{mounted} = shift if @_;
    return $m;
}

sub _spin_up {
    my $self = shift;
    my $nomount = shift;
    unless ($self->server) {
	$self->manager->info("provisioning server to mount $self\n");
	my $server = $self->manager->get_server_in_zone($self->availabilityZone);
	$self->server($server);
    }
    unless ($self->server->status eq 'running') {
	$self->manager->info("starting server to mount $self\n");
	$self->server->start;
    }
    $self->server->mount_volume($self) unless $nomount || $self->mounted();
}

#sub as_string {
#    my $self = shift;
#    return $self->server.':'.$self->mtpt;
#}

sub snapshot {shift->create_snapshot(@_)}

sub create_snapshot {
    my $self = shift;
    my $description = shift;
    if (my $server = $self->server) {
	my ($snap) = $server->create_snapshot($self => $description);
	return $snap;
    } else {
	$self->ebs->create_snapshot($description);
    }
}

#
# $vol->get($source1,$source2,$source3....,$dest)
# If $source not in format hostname:/path then 
# volume will be appended to it.
sub get {
    my $self = shift;
    croak 'usage: ',ref($self),'->get($source1,$source2,$source3....,$dest_path)'
	unless @_;
    unshift @_,'./' if @_ < 2;
    
    my $dest   = pop;
    my $server = $self->server or croak "no staging server available";

    $self->mounted or croak "Volume is not currently mounted";
    my @source = $self->_rel2abs(@_);
    $server->rsync(@source,$dest);
}

# $vol->put($source1,$source2,$source3....,$dest)
# If $dest not in format hostname:/path then 
# volume will be appended to it.
sub put {
    my $self = shift;
    croak 'usage: ',ref($self),'->put($source1,$source2,$source3....,$dest_path)'
	unless @_;
    push @_,'.' if @_ < 2;

    my $dest = pop;
    my @source = @_;

    $self->_spin_up;
    my $server = $self->server or croak "no staging server available";
    ($dest)    = $self->_rel2abs($dest);
    $server->rsync(@source,$dest);
}

sub rsync {
    my $self = shift;
    $self->mounted or croak "Volume is not currently mounted";
    unshift @_,"$self/" if @_ <= 1;
    $self->server->rsync(@_);
}

sub copy { shift->rsync(@_)      }
sub dd   { 
    my $self = shift;
    unshift @_,$self if @_ < 2;
    $self->server->dd(@_);
}

sub ls    { shift->_cmd('sudo ls',@_)    }
sub df    { shift->_cmd('df',@_)    }

sub mkdir { shift->_ssh('sudo mkdir',@_) }
sub chown { shift->_ssh('sudo chown',@_) }
sub chgrp { shift->_ssh('sudo chgrp',@_) }
sub chmod { shift->_ssh('sudo chmod',@_) }
sub rm    { shift->_ssh('sudo rm',@_)    }
sub rmdir { shift->_ssh('sudo rmdir',@_) }

sub fstab_line {
    my $self = shift;
    return join "\t",$self->mtdev,$self->mtpt,$self->fstype,'defaults,nobootwait',0,2;
}

# unmount volume from wherever it is
sub unmount {
    my $self = shift;
    my $server = $self->server or return;
    # guarantees that server is running, but avoids mounting the disk
    # prior to unmounting it again.
    $self->_spin_up('nomount'); 
    $server->unmount_volume($self);
}

sub detach {
    my $self = shift;
    my $server = $self->server or return;
    $self->current_status eq 'in-use' or return;
    $self->unmount;  # make sure we are not mounted; this might involve starting a server
    $server->info("detaching $self\n");
    my $status = $self->volume->detach;
    $self->mtpt(undef);
    $self->mtdev(undef);
    $self->server(undef);
    return $status;
}

# remove volume entirely
sub delete {
    my $self = shift;
    my $status = $self->current_status;
    if ($status eq 'in-use') {
	my $server = $self->server;
	$server->delete_volume($self);
    } elsif ($status eq 'available') {
	$self->ec2->delete_volume($self);
    } else {
	croak "Cannot delete volume, status is $status";
    }
    $self->mounted(0);
    $self->mtpt(undef);
    $self->mtdev(undef);
    $self->fstype(undef);
}

sub _cmd {
    my $self = shift;
    my $cmd          = shift;
    my @args         = map {quotemeta} @_;
    $self->mounted or croak "Volume is not currently mounted";
    my $mtpt         = $self->mtpt;
    $self->server->scmd("cd '$mtpt'; $cmd @args");
}

sub _ssh {
    my $self = shift;
    my $cmd          = shift;
    my @args         = map {quotemeta} @_;
    $self->mounted or croak "Volume is not currently mounted";
    my $mtpt         = $self->mtpt;
    $self->server->ssh("cd '$mtpt'; $cmd @args");
}


sub _rel2abs {
    my $self  = shift;
    my @paths = @_;

    my $server = $self->server or croak "no server";

    my @result;
    foreach (@paths) {
	if (/^([^:]+):(.+)$/) {
	    push @result,$_;
	}
	elsif (m!^/!) { # absolute path
	    push @result,"$server:".$_;
	} 
	else {
	    my $p = "$server:".File::Spec->rel2abs($_,$self->mtpt);
	    $p   .= '/' if m!/$!;
	    push @result,$p;
	}
    }
    return @result;
}

sub _select_zone {
    my $self = shift;
    my $ec2  = shift;
    if (my @servers = VM::EC2::Staging::Server->_servers($ec2->endpoint)) {
	return $servers[0]->instance->placement;
    } else {
	my @zones = $ec2->describe_availability_zones;
	return $zones[rand @zones];
    }
}

sub _get_vol_zone {
    my $self = shift;
    my ($ec2,$volid) = @_;
    my $volume = $ec2->describe_volumes($volid) or croak "unknown volumeid $volid";
    return $volume->availabilityZone;
}

sub DESTROY {
    my $self    = shift;
    my $manager = $self->manager or return;
    my $ebs     = $self->ebs     or return;
    $manager->unregister_volume($self);
}

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Staging::Manager>
L<VM::EC2::Staging::Server>
L<VM::EC2::Instance>
L<VM::EC2::Volume>
L<VM::EC2::Snapshot>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;
