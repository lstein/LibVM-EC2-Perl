package VM::EC2::Staging::Volume;

=head1 NAME

VM::EC2::Staging::Volume - High level functions for provisioning and populating EC2 volumes

=head1 SYNOPSIS

 use VM::EC2::Staging::Volume;

 my $ec2 = VM::EC2->new;
 my $vol1 = $ec2->staging_volume(-name => 'Backup',
                                 -fstype => 'ext4',
                                 -size   => 11,
                                 -zone   => 'us-east-1a');
 $vol1->mkdir('pictures');
 $vol1->mkdir('videos');
 $vol1->put('/usr/local/my_pictures/' =>'pictures/');
 $vol1->put('/usr/local/my_videos/'   =>'videos/');
 mkdir('/tmp/jpegs');
 $vol1->get('pictures/*.jpg','/tmp/jpegs');

 # note that these commands are executed on the remote server as root!
 @listing = $vol1->ls('-r','pictures');
 $vol1->chown('fred','pictures');
 $vol1->chgrp('nobody','pictures');
 $vol1->chmod('0700','pictures');
 $vol1->rm('-rf','pictures/*');
 $vol1->rmdir('pictures');

 my $path = $vol1->mtpt;

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

# can be called as class method
sub provision_volume {
    my $self = shift;
    my $ec2   = shift or croak "Usage: $self->new(\$ec2,\@args)";

    my %args  = @_;

    $args{-availability_zone}  = $self->_get_vol_zone($ec2,$args{-volume_id}) if $args{-volume_id};
    $args{-name}             ||= $args{-volume_id} || $args{-snapshot_id} || sprintf("Volume%02d",$Volume++);
    $args{-fstype}           ||= 'ext4';
    $args{-availability_zone}||= $self->_select_zone($ec2);
    my $server = $self->_get_server_in_zone($args{-availability_zone}) or croak "Can't launch a server to provision volume";
    my $vol    = $server->provision_volume(%args) or croak "Can't provision volume";
    return $vol;
}

# look up our filesystem type
sub get_fstype {
    my $self = shift;
    $self->_spin_up;
    my $dev    = $self->mtdev;
    my @mounts = $self->server->scmd('cat /etc/mtab');
    for my $m (@mounts) {
	my ($mtdev,undef,$type) = split /\s+/,$m;
	return $type if $mtdev eq $dev;
    }
    return;
}

# $stagingvolume->new({-server => $server,  -volume => $volume,
#                      -mtdev => $device,   -mtpt   => $mtpt,
#                      -name => $name})
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
foreach (qw(-server -volume -name -endpoint -mtpt -mtdev)) {
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

sub mounted {
    my $self = shift;
    my $m    = $self->{mounted};
    $self->{mounted} = shift if @_;
    return $m;
}

sub _spin_up {
    my $self = shift;
    unless ($self->server) {
	$self->manager->info("provisioning server to mount $self\n");
	my $server = $self->manager->get_server_in_zone($self->availabilityZone);
	$self->server($server);
    }
    unless ($self->server->status eq 'running') {
	$self->manager->info("starting server to mount $self\n");
	$self->server->start;
    }
    $self->server->mount_volume($self) unless $self->mounted();
}

#sub as_string {
#    my $self = shift;
#    return $self->server.':'.$self->mtpt;
#}

sub create_snapshot {
    my $self = shift;
    my $description = shift;
    if ($self->mounted && (my $server = $self->server)) {
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

sub copy {
    my $self = shift;
    $self->mounted or croak "Volume is not currently mounted";
    $self->server->rsync(@_);
}

sub ls    { shift->_cmd('sudo ls',@_)    }
sub df    { shift->_cmd('df',@_)    }

sub mkdir { shift->_ssh('sudo mkdir',@_) }
sub chown { shift->_ssh('sudo chown',@_) }
sub chgrp { shift->_ssh('sudo chgrp',@_) }
sub chmod { shift->_ssh('sudo chmod',@_) }
sub rm    { shift->_ssh('sudo rm',@_)    }
sub rmdir { shift->_ssh('sudo rmdir',@_) }

# unmount volume from wherever it is
sub unmount {
    my $self = shift;
    my $server = $self->server or return;
    $self->_spin_up; # guarantees that server is running
    $server->unmount_volume($self);
}

sub detach {
    my $self = shift;
    my $server = $self->server or return;
    $self->current_status eq 'in-use' or return;
    $self->unmount;  # make sure we are not mounted; this might involve starting a server
    $server->info("detaching $self\n");
    $self->volume->detach;
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
    if (my @servers = VM::EC2::Staging::Server->active_servers($ec2)) {
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

sub VM::EC2::staging_volume {
    my $self = shift;
    return VM::EC2::Staging::Volume->provision_volume($self,@_)
}

1;
