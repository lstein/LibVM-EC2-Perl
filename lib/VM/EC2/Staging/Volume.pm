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
		     return $self->as_string;
                  },
    fallback => 1;

my $Volume = 1;  # for anonymously-named volumes
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my $vol = eval {$self->ebs} or croak "Can't locate object method \"$func_name\" via package \"$pack\"";;
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

    $args{-zone}       = $self->_get_vol_zone($ec2,$args{-volume_id}) if $args{-volume_id};
    $args{-name}     ||= $args{-volume_id} || $args{-snapshot_id} || sprintf("Volume%02d",$Volume++);
    $args{-fstype}   ||= 'ext4';
    $args{-size}     ||= 10;
    $args{-zone}     ||= $self->_select_zone($ec2);
    my $server = $self->_get_server($ec2,$args{-zone}) or croak "Can't launch a server to provision volume";
    my $vol    = $server->provision_volume(%args) or croak "Can't provision volume";
    return $vol;
}

# $stagingvolume->new({server => $server,  volume => $volume,
#                      device => $device,  mtpt   => $mtpt,
#                      symbolic_name => $name})
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

sub server { shift->{server} }
sub device { shift->{device} }
sub ebs    { shift->{volume} }
sub mtpt   { shift->{mtpt}   }
sub name   { shift->{symbolic_name}   }

sub as_string {
    my $self = shift;
    return $self->server.':'.$self->mtpt;
}

sub create_snapshot {
    my $self = shift;
    my $description = shift;
    if (my $server = $self->server) {
	my ($snap) = $server->snapshot($self => $description);
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
    my $dest   = pop;
    my $server = $self->server or croak "no staging server available";

    my @source = $self->_rel2abs(@_);
    $server->rsync(@source,$dest);
}

# $vol->put($source1,$source2,$source3....,$dest)
# If $dest not in format hostname:/path then 
# volume will be appended to it.
sub put {
    my $self = shift;
    my $dest = pop;
    my @source = @_;

    my $server = $self->server or croak "no staging server available";
    ($dest)    = $self->_rel2abs($dest);
    $server->rsync(@source,$dest);
}

sub copy {
    my $self = shift;
    $self->server->rsync(@_);
}

sub ls    { shift->_cmd('ls',@_)    }
sub df    { shift->_cmd('df',@_)    }

sub mkdir { shift->_ssh('mkdir',@_) }
sub chown { shift->_ssh('sudo chown',@_) }
sub chgrp { shift->_ssh('sudo chgrp',@_) }
sub chmod { shift->_ssh('sudo chmod',@_) }
sub rm    { shift->_ssh('rm',@_)    }
sub rmdir { shift->_ssh('rmdir',@_) }

sub _cmd {
    my $self = shift;
    my $cmd          = shift;
    my @args         = map {quotemeta} @_;
    my $mtpt         = $self->mtpt;
    $self->server->scmd("cd '$mtpt'; $cmd @args");
}

sub _ssh {
    my $self = shift;
    my $cmd          = shift;
    my @args         = map {quotemeta} @_;
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
	    push @result,"$server:".File::Spec->rel2abs($_,$self->mtpt);
	}
    }
    return @result;
}

sub _select_zone {
    my $self = shift;
    my $ec2  = shift;
    if (my @servers = VM::EC2::Staging::Server->active_servers) {
	return $servers[0]->instance->placement;
    } else {
	my @zones = $ec2->describe_availability_zones;
	return $zones[rand @zones];
    }
}

sub _get_server {
    my $self = shift;
    my ($ec2,$zone) = @_;
    return VM::EC2::Staging::Server->find_server_in_zone($zone)
	||
	$ec2->new_data_transfer_server(-availability_zone=>$zone); # caches
}

sub _get_vol_zone {
    my $self = shift;
    my ($ec2,$volid) = @_;
    my $volume = $ec2->describe_volumes($volid) or croak "unknown volumeid $volid";
    return $volume->availabilityZone;
}

sub VM::EC2::staging_volume {
    my $self = shift;
    return VM::EC2::Staging::Volume->provision_volume($self,@_)
}

1;
