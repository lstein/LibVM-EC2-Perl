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

 $staging->stop_all_servers();
 $staging->start_all_servers();
 $staging->terminate_all_servers();

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

my $VolumeName = 'StagingVolume000';
my $ServerName = 'StagingServer000';
my (%Zones,%Instances,%Volumes);

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-ec2}               ||= VM::EC2->new();
    $args{-on_exit}           ||= $class->default_exit_behavior;
    $args{-reuse_key}         ||= $class->default_reuse_keys;
    $args{-username}          ||= $class->default_user_name;
    $args{-architecture}      ||= $class->default_architecture;
    $args{-root_type}         ||= $class->default_root_type;
    $args{-instance_type}     ||= $class->default_instance_type;
    $args{-reuse_volumes}     ||= $class->default_reuse_volumes;
    $args{-image_name}        ||= $class->default_image_name;
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
}
END
    die $@ if $@;
    }

    return bless \%args,ref $class || $class;
}

sub default_image_name    { 'ubuntu-maverick-10.10' };  # launches faster than precise
sub default_exit_behavior { 'terminate'   }
sub default_user_name     { 'ubuntu'      }
sub default_architecture  { 'i386'        }
sub default_root_type     { 'instance-store'}
sub default_instance_type { 'm1.small'      }
sub default_reuse_keys    { 1               }
sub default_reuse_volumes { 1               }

# scan for staging instances in current region and cache them
# into memory
# status should be...
# -on_exit => {'terminate','stop','run'}
sub scan {
    my $self = shift;
    my $ec2  = shift || $self->ec2;
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
	    -instance => $instance,
	    -manager  => $self,
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
	
	my $zone       = $volume->availabilityZone;
	my $attachment = $volume->attachment;
	my $ebs_device = $attachment->device;
	my $instance   = $attachment->instance;
	my $name       = $volume->tags->{StagingName};
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
    $instance or croak $self->ec2->error_str;
    $instance->add_tag(Role            => 'StagingInstance');
    $instance->add_tag(StagingUsername => $self->username  );
    $instance->add_tag(Name            => "Staging server created by ".__PACKAGE__);
    my $server = VM::EC2::Staging::Server->new(
	-keyfile  => $keyfile,
	-username => $self->username,
	-instance => $instance,
	-manager  => $self,
	);
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(SERVER_STARTUP_TIMEOUT);
	$self->wait_for_instances($server);
    };
    alarm(0);
    croak "some servers did not start after ",SERVER_STARTUP_TIMEOUT," seconds"
	if $@ =~ /timeout/;
    return $server;
}

sub find_server_by_name {
    my $self  = shift;
    my $server = shift;
    my $zone   = $server->placement;
    return $Zones{$zone}{Servers}{$server};
}

sub find_server_by_instance {
    my $self = shift;
    my $instance = shift;
    return $self->{Instances}{$instance};
}

sub register_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = $server->placement;
    $Zones{$zone}{Servers}{$server} = $server;
    $Instances{$server->instance}   = $server;
}

sub unregister_server {
    my $self   = shift;
    my $server = shift;
    my $zone   = $server->availability_zone;
    $Zones{$zone}{Servers}{$server};
    $Instances{$server->instance};
}

sub servers {
    my $self = shift;
    return values %Instances;
}

sub register_volume {
    my $self = shift;
    my $vol  = shift;
    $Zones{$vol->availability_zone}{Volumes}{$vol} = $vol;
    $Volumes{$vol->volumeId} = $vol;
}

sub unregister_volume {
    my $self = shift;
    my $vol  = shift;
    my $zone = $vol->availability_zone;
    $Zones{$zone}{$vol};
    $Volumes{$vol->volumeId};
}

sub volumes {
    my $self = shift;
    return values %Volumes;
}

sub start_all_servers {
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

sub stop_all_servers {
    my $self = shift;
    $self->info("Stopping all servers.\n");
    my @servers = $self->servers;
    foreach (@servers) { $_->stop }
}

sub terminate_all_servers {
    my $self = shift;
    $self->info("Terminating all servers.\n");
    my @servers = $self->servers;
    foreach (@servers) { $_->terminate }
    if ($self->reuse_keys) {
	$self->ec2->wait_for_instances(@servers);
	$self->ec2->delete_key_pair($_->keyPair) foreach @servers;
    }
}

sub _start_instances {
    my $self = shift;
    my @need_starting = @_;
    $self->info("starting instances: @need_starting.\n");
    $self->ec2->start_instances(@need_starting);
    $self->wait_for_instances(@need_starting);
}

sub wait_for_instances {
    my $self = shift;
    my @instances = @_;
    $self->ec2->wait_for_instances(@instances);
    my %pending = map {$_=>$_} grep {$_->current_status eq 'running'} @instances;
    $self->info("waiting for ssh daemons on @instances.\n") if %pending;
    while (%pending) {
	for my $s (values %pending) {
	    unless ($s->ping) {
		sleep 5;
		next;
	    }
	    delete $pending{$s};
	}
    }
}

sub provision_volume {
    my $self = shift;
    my %args = @_;

    $args{-name}              ||= ++$VolumeName;
    $args{-size}              ||= 1;
    $args{-volume_id}         ||= undef;
    $args{-snapshot_id}       ||= undef;
    $args{-reuse}               = $self->reuse_volumes unless defined $args{-reuse};
    $args{-mount}             ||= '/mnt/DataTransfer/'.$args{-name};
    $args{-fstype}            ||= 'ext4';
    $args{-availability_zone} ||= $self->_selected_used_zone;
    
    my $server = $self->_find_server_in_zone($args{-availability_zone});
    $server->start_and_wait unless $server->ping;
    my $volume = $server->provision_volume(\%args);
    $self->register_volume($volume);
    return $volume;
}

sub _search_for_image {
    my $self = shift;
    $self->info("Searching for a staging image...");

    my $image_name   = $self->image_name;
    my $root_type    = $self->on_exit eq 'stop' ? 'ebs' : $self->root_type;
    my $architecture = $self->architecture;

    my @candidates = $self->ec2->describe_images({'name'             => "*$image_name*",
						  'root-device-type' => $root_type,
						  'architecture'     => $architecture});
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
    $self->info("Creating ssh security group $name.\n");
    my $sg =  $ec2->create_security_group(-name     => $name,
				       -description => "SSH security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    return $sg;
}

sub _security_key {
    my $self = shift;
    my $ec2     = $self->ec2;
    if ($self->reuse_key) {
	my @candidates = $ec2->describe_key_pairs(-filter=>{'key-name' => 'staging-key-*'});
	for my $c (@candidates) {
	    my $name    = $c->keyName;
	    my $keyfile = $self->key_path($name);
	    return ($c,$keyfile) if -e $keyfile;
	}
    }
    my $name    = 'staging-key-'.$ec2->token;
    $self->info("Creating keypair $name.\n");
    my $kp          = $ec2->create_key_pair($name) or die $ec2->error_str;
    my $keyfile     = $self->key_path($name);
    my $private_key = $kp->privateKey;
    open my $k,'>',$keyfile or die "Couldn't create $keyfile: $!";
    chmod 0600,$keyfile     or die "Couldn't chmod  $keyfile: $!";
    print $k $private_key;
    close $k;
    return ($kp,$keyfile);
}

sub _security_group {
    my $self = shift;
    my $ec2  = $self->ec2;
    my @groups = $ec2->describe_security_groups(-filter=>{'tag:Role' => 'StagingGroup'});
    return $groups[0] if @groups;
    my $name = $ec2->token;
    $self->info("Creating staging security group $name.\n");
    my $sg =  $ec2->create_security_group(-name  => $name,
					  -description => "SSH security group created by ".__PACKAGE__
	) or die $ec2->error_str;
    $sg->authorize_incoming(-protocol   => 'tcp',
			    -port       => 'ssh');
    $sg->update or die $ec2->error_str;
    $sg->add_tag(Role  => 'StagingGroup');
    return $sg;

}

sub volume_description {
    my $self = shift;
    my $vol  = shift;
    my $name = ref $vol ? $vol->name : $vol;
    return "Staging volume for $name created by ".__PACKAGE__;
}

sub info {
    my $self = shift;
    return if $self->quiet;
    print STDERR @_;
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
    my @servers = values %Instances;
    return @servers unless $ec2;
    return grep {$_->ec2 eq $ec2} @servers;
}

sub key_path {
    my $self    = shift;
    my $keyname = shift;
    return File::Spec->catfile($self->dot_directory_path,"${keyname}.pem")
}

sub dot_directory_path {
    my $class = shift;
    my $dir = File::Spec->catfile($ENV{HOME},'.vm_ec2_staging');
    unless (-e $dir && -d $dir) {
	mkdir $dir       or croak "mkdir $dir: $!";
	chmod 0700,$dir  or croak "chmod 0700 $dir: $!";
    }
    return $dir;
}

sub _check_keyfile {
    my $self = shift;
    my $keyname = shift;
    my $dotpath = $self->dot_directory_path;
    opendir my $d,$dotpath or die "Can't opendir $dotpath: $!";
    while (my $file = readdir($d)) {
	if ($file =~ /^$keyname.pem/) {
	    return $1,$self->key_path($keyname,$1);
	}
    }
    closedir $d;
    return;
}

sub DESTROY {
    my $self = shift;
    my $action = $self->on_exit;
    $self->terminate_all_servers if $action eq 'terminate';
    $self->stop_all_servers      if $action eq 'stop';
}

1;

