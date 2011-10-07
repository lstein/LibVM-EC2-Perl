package VM::EC2::Convenience::DataTransferServer;

# high level interface for transferring data, and managing data snapshots
# via a series of DataTransfer VMs.

=head1 NAME

VM::EC2::Convenience::DataTransferServer - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 my $factory = VM::EC2::Convenience->new(-access_key    => 'access key id',
                                         -secret_key    => 'aws_secret_key',
                                         -endpoint      => 'http://ec2.amazonaws.com');

 my $server = $factory->new_server(-name => 'ubuntu-maverick-10.10') or die $factory->error_str; # optional arguments

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
 $server->sync('Music' => "$server2:/home/ubuntu/music");
 $server->sync('Music' => "$server2:Music");

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
    $args{-architecture}    ||= 'i386';
    $args{-root_type}       ||= 'instance-store';
    $args{-instance_type}   ||= $args{-architecture} eq 'i386' ? 'm1.small' : 'm1.large';

    my $self = bless {
	ec2      => $ec2,
	instance => undef,
	username => $username,
	volumes  => {},           # {Symbolic_name => {snapshot=>$snap,volume=>$volume,mount=>'mnt/pt'}}
	quiet    => $args{-quiet},
	preserve => $args{-preserve_volume},
    },ref $class || $class;
    weaken($Servers{$self->as_string}=$self);
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
    (my $ep   = $self->ec2->endpoint) =~ s!^http://!!;
    return "$ep-".$self->{instance}||'no instance';
}

sub provision_volume {
    my $self = shift;
    my %args = @_;
    my $name = $args{-name};
    my $size = $args{-size};
    $name && $size or croak "Usage: provision_volume(-name=>'name',-size=>$size)";
    my $mtpt   = $args{-mount}  || '/mnt/'.$self->ec2->token;
    my $fstype = $args{-fstype} || 'ext4';
    my $username = $self->username;
    
    $size = int($size) < $size ? int($size)+1 : $size;  # dirty ceil() function
    $self->info("Provisioning a $size GB volume...\n");
    my $instance = $self->instance;
    my $zone     = $instance->availabilityZone;
    my ($vol,$needs_mkfs,$needs_resize) = $self->_create_volume($name,$size,$zone);
    
    my $device = eval{$self->unused_device()}        or die "Couldn't find suitable device to attach this volume to";
    my $s = $Instance->attach_volume($vol=>$device)  or die "Couldn't attach $vol to $instance via $device";
    $ec2->wait_for_attachments($s)                   or die "Couldn't attach $vol to $instance via $device";
    $s->current_status eq 'attached'                 or die "Couldn't attach $vol to $instance via $device";

    if ($needs_resize) {
	die "Sorry, but can only resize ext volumes " unless $fstype =~ /^ext/;
	$self->info("Resizing previously-snapshotted volume to $gb GB...\n");
	$self->ssh("sudo /sbin/resize2fs $device");
    } elsif ($needs_mkfs) {
	$self->info("Making $fstype filesystem on staging volume...\n");
	$self->ssh("sudo /sbin/mkfs.$fstype $device");
    }

    $self->info("Mounting staging volume...\n");
    $self->ssh("sudo mkdir -p $mtpt; sudo mount $device $mtpt; sudo chown $username $mtpt");

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
    my ($servername,$pathname) = split ':',$vpath;

    my ($server,$path);
    if ($servername) {
	$server = $Servers{$servername} or croak "$servername is not a transfer server";
    }

    if ($pathname !~ m!^[/.]!) { # symbolic name
	my ($base,@rest) = split('/',$pathname);
	my $mtpt = $server->mntpt($base) or croak "$server: no mountpoint for $base";
	$path    = join ('/',$mtpt,@rest);
    } else {
	$path = $pathname;
    }

    return ($server,$path);
}

# most general form
sub copy {
    my $self = shift;
    my @paths = map $self->resolve_path(@_);

    my $dest   = pop @paths;
    my @source = @paths;

    my ($host,%hosts);
    foreach (@source) {
	$host        ||= $source->[0];  # looks mad
	$source->[0] ||= $host;         # but isn't
	$hosts{$source->[0]}++;
    }
    croak "More than one source host specified" if keys %hosts > 1;
}

sub put {
    my $self   = shift;
    my @source = @_;
    my $dest   = pop @source;
    # resolve symbolic name of $dest
    my $target   = $self->{volumes}{$dest}{mtpt} or croak "Staging volume $dest is unknown";
    my $host     = $self->instance->dnsName;
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    $self->info("Beginning rsync...\n");
    system "rsync -Ravz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' @source $host:$target";
}

sub sync {
    my $self   = shift;
    my @source = @_;
    my $dest   = pop @source;
    # figure out what $dest is
    my ($dhost,$dpath) = split(':',$dest);
    my ($host,$path);
    my $server2 = $Servers{$dhost} or croak "$dhost is not a DataTransferServer";
    $host = $server2->instance->dnsName;
    $path = $server2->{volumes}{$dpath}{mtpt} or croak "$dhost has no symbolic volume named $dpath";
    my $server2_private_key = $server2->keyfile;
    my $spk = basename($server2_private_key);
    $server1->put($server2_private_key => $spk);
}

sub get {
    my $self = shift;
    my @source = @_;
    my $target   = pop @source;

    # resolve symbolic names of src
    my $host     = $self->instance->dnsName;
    my @from;
    foreach (@source) {
	my $mnt = $self->{volumes}{$_}{mtpt} or croak "Staging volume $_ is unknown";
	push @from,"$host:$mnt";
    }
    my $keyfile  = $self->keyfile;
    my $username = $self->username;
    
    $self->info("Beginning rsync...\n");
    system "rsync -Ravz -e'ssh -o \"StrictHostKeyChecking no\" -i $keyfile -l $username' @from $target";
}

sub instance {
    my $self = shift;
    unless ($self->{instance}) {
	my $instance = $self->_create_instance(\%args)
	    or croak "Could not create an instance that satisfies requested criteria";
	$class->wait_till_instance_is_ready($instance)
	    or croak "Instance did not come up in a reasonable time";
	$self->{instance} = $instance;
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
    $self->info("Found $most_recent...\n");
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
    $self->info("Creating temporary security group $name...\n");
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
    $self->info("Creating temporary keypair $name...\n");
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


sub info {
    my $self = shift;
    return if $self->quiet;
    print STDERR @_;
}

sub cleanup {
    my $self = shift;
    if (-e $self->keyfile) {
	my $dir = dirname($self->keyfile);
	remove_tree($dir);
    }
    if (my $i = $self->instance) {
	$i->terminate();
	$self->ec2->wait_for_instances($i);
    }
    if (my $kp = $self->{keypair}) {
	$self->ec2->delete_key_pair($kp);
    }
    if (my $sg = $self->{security_group}) {
	$self->ec2->delete_security_group($sg);
    }
    unless ($self->preserve) {
	for my $v (keys %{$self->volumes}) {
	    my $volume = $self->volumes->{$v}{volume};
	    $self->ec2->delete_volume($volume); # do we really want to do this?
	}
    }
}

sub DESTROY {
    my $self = shift;
    undef $Servers{$self->as_string};
    $self->cleanup;
}



1;

