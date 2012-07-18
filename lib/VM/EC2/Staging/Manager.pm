package VM::EC2::Staging::Manager;

=head1 NAME

VM::EC2::Staging::Manager - Automated VM for moving data in and out of cloud.

=head1 SYNOPSIS

 use VM::EC2::Staging::Manager;

 my $ec2     = VM::EC2->new;
 my $staging = $ec2->staging_manager(-on_exit     => 'stop', # default, stop servers when process exists
                                     -quiet       => 0,      # default, verbose progress messages
                                     -scan        => 1,      # default, scan region for existing staging servers and volumes
                                     -image_name  => 'ubuntu-maverick-10.10', # default server image
                                     -user_name   => 'ubuntu',                # default server login name
                                     );

 # provision a new server, using defaults. Name will be assigned automatically
 my $server = $staging->provision_server(-availability_zone => 'us-east-1a');

 # retrieve a new server named "my_server", if one exists. If not, it creates one
 # using the specified options
 my $server = $staging->get_server(-name              => 'my_server',
                                   -availability_zone => 'us-east-1a',
                                   -instance_type     => 't1.micro');

 # open up an ssh session in an xterm
 $server->shell;

 # run a command over ssh on the server. See VM::EC2::Staging::Server
 $server->ssh('whoami');

 # run a command over ssh on the server, returning the result as an array of lines or a
 # scalar string, similar to backticks (``)
 my @password_lines = $server->scmd('cat /etc/passwd');

 # run a command on the server and read from it using a filehandle
 my $fh  = $server->scmd_read('ls -R /usr/lib');
 while (<$fh>) { # do something }

 # run a command on the server and write to it using a filehandle
 my $fh  = $server->scmd_write('sudo -s "cat >>/etc/fstab"');
 print $fh "/dev/sdf3 /mnt/demo ext3 0 2\n";
 close $fh;

 # Provision a new volume named "Pictures". Will automatically be mounted to a staging server in
 # the specified zone. Server will be created if needed.
 my $volume = $staging->provision_volume(-name              => 'Pictures',
                                         -fstype            => 'ext4',
                                         -availability_zone => 'us-east-1a',
                                         -size              => 2) or die $staging->error_str;

 # gets an existing volume named "Pictures" if it exists. Otherwise provisions a new volume;
 my $volume = $staging->get_volume(-name              => 'Pictures',
                                   -fstype            => 'ext4',
                                   -availability_zone => 'us-east-1a',
                                   -size              => 2) or die $staging->error_str;

 # copy contents of local directory /opt/test to remote volume $volume using rsync
 # See VM::EC2::Staging::Volume
 $volume->put('/opt/test/');

 # same thing, but first creating a subdirectory on the remote volume
 $volume->put('/opt/test/' => './mirrors/');

 # copy contents of remote volume $volume to local directory /tmp/test using rsync
 $volume->get('/tmp/test');

 # same thing, but from a subdirectory of the remote volume
 $volume->get('./mirrors/' => '/tmp/test');

 # server to server transfer (works both within and between availability regions)
 my $south_america = VM::EC2->new(-region=>'sa-east-1')->staging_manager;    # create a staging manager in Sao Paolo
 my $volume2 = $south_america->provision_volume(-name              => 'Videos',
                                                -availability_zone => 'sa-east-1a',
                                                -size              => 2);
 $staging->rsync("$volume/mirrors" => "$volume2/us-east");

 $staging->stop_all_servers();
 $staging->start_all_servers();
 $staging->terminate_all_servers();

 # Assuming an EBS image named ami-12345 is located in the US, copy it into 
 # the South American region, returning the AMI ID in South America
 my $new_image = $staging->copy_image('ami-12345','sa-east-1');

=head1 DESCRIPTION

VM::EC2::Staging::Manager manages a set of EC2 volumes and servers
in a single AWS region. It was primarily designed to simplify the
process of provisioning and populating volumes, but it also provides a
handy set of ssh commands that allow you to run remote commands
programmatically.

The manager also allows you to copy AMIs from one region to another,
something that is otherwise hard to do right.

The main classes are:

 VM::EC2::Staging::Manager -- A set of volume and server resources in
                              a single AWS region.

 VM::EC2::Staging::Server -- A named server running somewhere in the
                             region. It is a VM::EC2::Instance
                             extended to provide remote command and
                             copy facilities.

 VM::EC2::Staging::Volume -- A named disk volume running somewhere in the
                             region. It is a VM::EC2::Volume
                             extended to provide remote copy
                             facilities.

See the perldoc for more information on Server and Volume
    capabilities.

=head1 Constructors

The following methods allow you to create new
VM::EC2::Staging::Manager instances. Be aware that only one manager is
allowed per EC2 region; attempting to create additional managers in
the same region will return the same one each time.

=cut

use strict;
use VM::EC2;
use VM::EC2::Staging::Volume;
use VM::EC2::Staging::Server;
use Carp 'croak';
use File::Spec;
use File::Path 'make_path','remove_tree';
use File::Basename 'dirname';
use Scalar::Util 'weaken';

use constant                     GB => 1_073_741_824;
use constant SERVER_STARTUP_TIMEOUT => 120;

my (%Zones,%Instances,%Volumes,%Managers);

=head2 $manager = $ec2->staging_manager(@args)

This is a simplified way to create a staging manager. First create the
EC2 object in the desired region, and then call its staging_manager()
method:

 $manager = VM::EC2->new(-region=>'us-west-2')->staging_manager()

=over 4

=item Required Arguments

None.

=item Optional Arguments

The optional arguments change the way that the manager creates new
servers and volumes.

 -on_exit       What to do with running servers when the manager goes 
                out of scope or the script exits. One of 'run', 
                'stop' (default), or 'terminate'. "run" keeps all
                created instances running, so beware!

 -architecture  Architecture for newly-created server
                instances (default "i386"). Can be overridden in calls to get_server()
                and provision_server().

 -instance_type Type of newly-created servers (default "m1.small"). Can be overridden
                in calls to get_server() and provision_server().

 -root_type     Root type for newly-created servers (default depends
                on the -on_exit behavior; "ebs" for exit behavior of 
                "stop" and "instance-store" for exit behavior of "run"
                or "terminate".

 -image_name    Name or ami ID of the AMI to use for creating the
                instances of new servers. Defaults to 'ubuntu-maverick-10.10'.
                If the image name begins with "ami-", then it is 
                treated as an AMI ID. Otherwise it is treated as
                a name pattern and will be used to search the AMI
                name field using the wildcard search "*$name*".
                Names work better than AMI ids here, because the
                latter change from one region to another. If multiple
                matching image candidates are found, then an alpha
                sort on the name is used to find the image with the
                highest alpha sort value, which happens to work with
                Ubuntu images to find the latest release.

 -availability_zone Availability zone for newly-created
                servers. Default is undef, in which case a random
                zone is selected.

 -username      Username to use for ssh connections. Defaults to 
                "ubuntu". Note that this user must be able to use
                sudo on the instance without providing a password,
                or functionality of this module will be limited.
  
 -quiet         Boolean, default false. If true, turns off most informational
                messages.

 -scan          Boolean, default true. If true, scans region for
                volumes and servers created by earlier manager
                instances.

 -reuse_key     Boolean, default true. If true, creates a single
                ssh keypair for each region and reuses it. Note that
                the private key is kept on the local computer in the
                directory ~/.vm-ec2-staging, and so additional
                keypairs may be created if you use this module on
                multiple local machines. If this option is false,
                then a new keypair will be created for every server
                you partition.

 -reuse_volumes Boolean, default true. If this flag is true, then
                calls to provision_volume() will return existing
                volumes if they share the same name as the requested
                volume. If no suitable existing volume exists, then
                the most recent snapshot of this volume is used to 
                create it in the specified availability zone. Only
                if no volume or snapshot exist will a new volume be
                created from scratch.

 -dotdir        Path to the directory that contains keyfiles and other
                stable configuration information for this module.
                Defaults to ~/.vm_ec2_staging. You may wish to change
                this to, say, a private dropbox directory or an NFS-mount
                in order to share keyfiles among machines. Be aware of
                the security implications of sharing private key files.

=back

=head2 $manager = VM::EC2::Staging::Manager(-ec2 => $ec2,@args)

This is a more traditional constructur for the staging manager.

=over 4

=item Required Arguments
 
  -ec2     A VM::EC2 object.

=item Optional Arguments

All of the arguments listed in the description of
VM::EC2->staging_manager().

=back

=cut

sub VM::EC2::staging_manager {
    my $self = shift;
    return VM::EC2::Staging::Manager->new(@_,-ec2=>$self)
}


sub new {
    my $self = shift;
    my %args  = @_;
    $args{-ec2}               ||= VM::EC2->new();

    if (my $manager = $self->find_manager($args{-ec2}->endpoint)) {
	return $manager;
    }

    $args{-on_exit}           ||= $self->default_exit_behavior;
    $args{-reuse_key}         ||= $self->default_reuse_keys;
    $args{-username}          ||= $self->default_user_name;
    $args{-architecture}      ||= $self->default_architecture;
    $args{-root_type}         ||= $self->default_root_type;
    $args{-instance_type}     ||= $self->default_instance_type;
    $args{-reuse_volumes}     ||= $self->default_reuse_volumes;
    $args{-image_name}        ||= $self->default_image_name;
    $args{-availability_zone} ||= undef;
    $args{-quiet}             ||= undef;
    $args{-scan}                = 1 unless exists $args{-scan};
    $args{-pid}                 = $$;
    $args{-dotdir}            ||= $self->default_dot_directory_path;

    # create accessors
    my $class = ref $self || $self;
    foreach (keys %args) {
	(my $func_name = $_) =~ s/^-//;
	next if $self->can($func_name);
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

    my $obj = bless \%args,$class;
    weaken($Managers{$obj->ec2->endpoint} = $obj);
    if ($args{-scan}) {
	$obj->info("scanning for existing staging servers and volumes\n");
	$obj->scan_region;
    }
    return $obj;
}


# class method
# the point of this somewhat odd way of storing managers is to ensure that there is only one
# manager per endpoint, and to avoid circular references in the Server and Volume objects.
sub find_manager {
    my $class    = shift;
    my $endpoint = shift;
    return $Managers{$endpoint};
}

=head2 $name = $manager->default_exit_behavior

Return the default exit behavior ("stop") when the manager terminates.
Intended to be overridden in subclasses.

=cut

sub default_exit_behavior { 'stop'        }

=head2 $name = $manager->default_image_name

Return the default image name ('ubuntu-maverick-10.10') for use in
creating new instances. Intended to be overridden in subclasses.

=cut

sub default_image_name    { 'ubuntu-maverick-10.10' };  # launches faster than precise

=head2 $name = $manager->default_user_name

Return the default user name ('ubuntu') for use in creating new
instances. Intended to be overridden in subclasses.

=cut

sub default_user_name     { 'ubuntu'      }

=head2 $name = $manager->default_architecture

Return the default instance architecture ('i386') for use in creating
new instances. Intended to be overridden in subclasses.

=cut

sub default_architecture  { 'i386'        }

=head2 $name = $manager->default_root_type

Return the default instance root type ('instance-store') for use in
creating new instances. Intended to be overridden in subclasses. Note
that this value is ignored if the exit behavior is "stop", in which case an
ebs-backed instance will be used. Also, the m1.micro instance type
does not come in an instance-store form, so ebs will be used in this
case as well.

=cut

sub default_root_type     { 'instance-store'}

=head2 $name = $manager->default_instance_type

Return the default instance type ('m1.small') for use in
creating new instances. Intended to be overridden in subclasses. We default
to m1.small rather than a micro instance because the I/O in m1.small
is far faster than in t1.micro.

=cut

sub default_instance_type { 'm1.small'      }

=head2 $name = $manager->default_reuse_keys

Return the default value of the -reuse_keys argument ('true'). This
value allows the manager to create an ssh keypair once, and use the
same one for all servers it creates over time. If false, then a new
keypair is created for each server and then discarded when the server
terminates.

=cut

sub default_reuse_keys    { 1               }

=head2 $name = $manager->default_reuse_volumes

Return the default value of the -reuse_volumes argument ('true'). This
value instructs the manager to use the symbolic name of the volume to
return an existing volume whenever a request is made to provision a
new one of the same name.

=cut

sub default_reuse_volumes { 1               }

=head2 $name = $manager->default_dot_directory_path

Return the default value of the -dotdir argument
("$ENV{HOME}/.vm_ec2_staging"). This value instructs the manager to
use the symbolic name of the volume to return an existing volume
whenever a request is made to provision a new one of the same name.

=cut

sub default_dot_directory_path {
    my $class = shift;
    my $dir = File::Spec->catfile($ENV{HOME},'.vm_ec2_staging');
    return $dir;
}

sub dot_directory {
    my $self = shift;
    my $dir  = $self->dotdir;
    unless (-e $dir && -d $dir) {
	mkdir $dir       or croak "mkdir $dir: $!";
	chmod 0700,$dir  or croak "chmod 0700 $dir: $!";
    }
    return $dir;
}

# scan for staging instances in current region and cache them
# into memory
# status should be...
# -on_exit => {'terminate','stop','run'}
sub scan_region {
    my $self = shift;
    my $ec2  = shift || $self->ec2;
    $self->_scan_instances($ec2);
    $self->_scan_volumes($ec2);
}

sub _scan_instances {
    my $self = shift;
    my $ec2  = shift;
    my @instances = $ec2->describe_instances({'tag:Role'            => 'StagingInstance',
					      'instance-state-name' => ['running','stopped']});
    for my $instance (@instances) {
	my $keyname  = $instance->keyName                   or next;
	my $keyfile  = $self->_check_keyfile($keyname)      or next;
	my $username = $instance->tags->{'StagingUsername'} or next;
	my $name     = $instance->tags->{StagingName} || $self->new_server_name;
	my $server   = VM::EC2::Staging::Server->new(
	    -name     => $name,
	    -keyfile  => $keyfile,
	    -username => $username,
	    -instance => $instance,
	    -endpoint => $self->ec2->endpoint,
	    );
	$self->register_server($server);
    }
}

sub _scan_volumes {
    my $self = shift;
    my $ec2  = shift;

    # now the volumes
    my @volumes = $ec2->describe_volumes(-filter=>{'tag:Role'          => 'StagingVolume',
						   'status'            => ['available','in-use']});
    for my $volume (@volumes) {
	my $status = $volume->status;
	my $zone   = $volume->availabilityZone;

	my %args;
	$args{-endpoint} = $self->ec2->endpoint;
	$args{-volume}   = $volume;
	$args{-name}     = $volume->tags->{StagingName};

	if (my $attachment = $volume->attachment) {
	    $args{-server} = $self->find_server_by_instance($attachment->instance);
	    $args{-mtpt}   = undef; # leave blank - volume will fill in when server is up
	}

	my $vol = VM::EC2::Staging::Volume->new(%args);
	$self->register_volume($vol);
    }
}

sub get_server_in_zone {
    my $self = shift;
    my $zone = shift;
    if (my $servers = $Zones{$zone}{Servers}) {
	return (values %{$servers})[0];
    }
    else {
	return $self->provision_server(-availability_zone => $zone);
    }
}

sub get_server {
    my $self = shift;
    my %args = @_;
    $args{-name}              ||= $self->new_server_name;

    # find servers of same name
    my %servers = map {$_->name => $_} $self->servers;
    my $server = $servers{$args{-name}} || $self->provision_server(%args);
    $server->start unless $server->is_up;
    return $server;
}

sub provision_server {
    my $self    = shift;
    my @args    = @_;

    # let subroutine arguments override manager's args
    my %args    = ($self->_run_instance_args,@args);

    # fix possible gotcha -- instance store is not allowed for micro instances.
    $args{-root_type} = 'ebs' if $args{-instance_type} eq 't1.micro';
    $args{-name}    ||= $self->new_server_name;

    my ($keyname,$keyfile) = $self->_security_key;
    my $security_group     = $self->_security_group;
    my $image              = $self->_search_for_image(%args) or croak "No suitable image found";
    my ($instance)         = $self->ec2->run_instances(
	-image_id          => $image,
	-security_group_id => $security_group,
	-key_name          => $keyname,
	%args,
	);
    $instance or croak $self->ec2->error_str;
    $instance->add_tags(Role            => 'StagingInstance',
			Name            => "Staging server $args{-name} created by ".__PACKAGE__,
			StagingUsername => $self->username,
			StagingName     => $args{-name});
			
    my $server = VM::EC2::Staging::Server->new(
	-keyfile  => $keyfile,
	-username => $self->username,
	-instance => $instance,
	-endpoint => $self->ec2->endpoint,
	);
    eval {
	local $SIG{ALRM} = sub {die 'timeout'};
	alarm(SERVER_STARTUP_TIMEOUT);
	$self->wait_for_instances($server);
    };
    alarm(0);
    croak "server did not start after ",SERVER_STARTUP_TIMEOUT," seconds"
	if $@ =~ /timeout/;
    $self->register_server($server);
    return $server;
}

sub _run_instance_args {
    my $self = shift;
    my @args;
    for my $arg (qw(instance_type availability_zone architecture image_name root_type)) {
	push @args,("-${arg}" => $self->$arg);
    }
    return @args;
}

sub find_server_by_instance {
    my $self  = shift;
    my $server = shift;
    return $Instances{$server};
}

sub find_volume_by_volid {
    my $self   = shift;
    my $volid = shift;
    return $Volumes{$volid};
}

sub find_volume_by_name {
    my $self =  shift;
    my $name = shift;
    my %volumes = map {$_->name => $_} $self->volumes;
    return $volumes{$name};
}

sub _select_server_by_zone {
    my $self = shift;
    my $zone = shift;
    my @servers = values %{$Zones{$zone}{Servers}};
    return $servers[0];
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
    my $zone   = eval{$server->placement} or return; # avoids problems at global destruction
    delete $Zones{$zone}{Servers}{$server};
    delete $Instances{$server->instance};
}

sub servers {
    my $self = shift;
    return grep {$_->ec2->endpoint eq $self->ec2->endpoint} values %Instances;
}

sub register_volume {
    my $self = shift;
    my $vol  = shift;
    $Zones{$vol->availabilityZone}{Volumes}{$vol} = $vol;
    $Volumes{$vol->volumeId} = $vol;
}

sub unregister_volume {
    my $self = shift;
    my $vol  = shift;
    my $zone = $vol->availabilityZone;
    delete $Zones{$zone}{$vol};
    delete $Volumes{$vol->volumeId};
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
    # my @servers = keys %Instances;  # allows this to run correctly during global destruct
    my $ec2 = $self->ec2;
    my @servers  = grep {$_->ec2 eq $ec2} $self->servers;
    @servers or return;
    $self->info("Stopping servers @servers.\n");
    $self->ec2->stop_instances(@servers);
    $self->ec2->wait_for_instances(@servers);
    $self->unregister_server($_) foreach @servers;
}

sub terminate_all_servers {
    my $self = shift;
    my $ec2 = $self->ec2 or return;
    my @servers  = grep {$_->ec2 eq $ec2} $self->servers;
    @servers or return;
    
    $self->info("Terminating servers @servers.\n");
    $ec2->terminate_instances(@servers) or warn $self->ec2->error_str;
    $ec2->wait_for_instances(@servers);
    unless ($self->reuse_key) {
	$ec2->delete_key_pair($_) foreach $ec2->describe_key_pairs(-filter=>{'key-name' => 'staging-key-*'});
    }
    $self->unregister_server($_) foreach @servers;
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
    $self->info("waiting for ssh daemon on @instances.\n") if %pending;
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

sub get_volume {
    my $self = shift;
    my %args = @_;
    $args{-name}              ||= $self->new_volume_name;

    # find volume of same name
    my %vols = map {$_->name => $_} $self->volumes;
    return $vols{$args{-name}} || $self->provision_volume(%args);
}

sub provision_volume {
    my $self = shift;
    my %args = @_;

    $args{-name}              ||= $self->new_volume_name;
    $args{-size}              ||= 1 unless $args{-snapshot_id} || $args{-volume_id};
    $args{-volume_id}         ||= undef;
    $args{-snapshot_id}       ||= undef;
    $args{-reuse}               = $self->reuse_volumes unless defined $args{-reuse};
    $args{-mount}             ||= '/mnt/DataTransfer/'.$args{-name};
    $args{-fstype}            ||= 'ext4';
    $args{-availability_zone} ||= $self->_select_used_zone;
    $args{-label}             ||= $args{-name};

    $self->find_volume_by_name($args{-name}) && 
	croak "There is already a volume named $args{-name} in this region";
    
    if ($args{-snapshot_id}) {
	$self->info("Provisioning volume from snapshot $args{-snapshot_id}\n");
    } elsif ($args{-volume_id}) {
	$self->info("Provisioning volume from volume $args{-volume_id}\n");
	my $v = $self->ec2->describe_volumes($args{-volume_id});
	$args{-availability_zone} = $v->availabilityZone if $v;
	$args{-size}              = $v->size             if $v;
    } else {
	$self->info("Provisioning a new $args{-size} GB $args{-fstype} volume\n");
    }

    my $server = $self->get_server_in_zone($args{-availability_zone});
    $server->start unless $server->ping;
    my $volume = $server->provision_volume(%args);
    $self->register_volume($volume);
    return $volume;
}

sub volumes {
    my $self = shift;
    return grep {$_->ec2->endpoint eq $self->ec2->endpoint} values %Volumes;
}

sub _search_for_image {
    my $self = shift;
    my %args = @_;
    my $name = $args{-image_name};

    $self->info("Searching for a staging image...");

    my $root_type    = $self->on_exit eq 'stop' ? 'ebs' :
    $args{-root_type};

    my @candidates = $name =~ /^ami-[0-9a-f]+/ ? $self->ec2->describe_images($name)
	                                       : $self->ec2->describe_images({'name'             => "*$args{-image_name}*",
									      'root-device-type' => $root_type,
									      'architecture'     => $args{-architecture}});
    return unless @candidates;
    # this assumes that the name has some sort of timestamp in it, which is true
    # of ubuntu images, but probably not others
    my ($most_recent) = sort {$b->name cmp $a->name} @candidates;
    $self->info("found $most_recent: ",$most_recent->name,"\n");
    return $most_recent;
}

sub security_group {
    my $self = shift;
    return $self->{security_group} ||= $self->_security_group();
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
    my $name    = $self->_token('staging-key');
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
    my $name = $self->_token('ssh');
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

sub rsync {
    my $self = shift;
    VM::EC2::Staging::Server->rsync(@_);
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
sub _find_server_in_zone {
    my $self = shift;
    my $zone = shift;
    my @servers = sort {$a->ping cmp $b->ping} values %{$Zones{$zone}{Servers}};
    return unless @servers;
    return $servers[-1];
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
    return File::Spec->catfile($self->dot_directory,"${keyname}.pem")
}

sub _check_keyfile {
    my $self = shift;
    my $keyname = shift;
    my $dotpath = $self->dot_directory;
    opendir my $d,$dotpath or die "Can't opendir $dotpath: $!";
    while (my $file = readdir($d)) {
	if ($file =~ /^$keyname.pem/) {
	    return $1,$self->key_path($keyname,$1);
	}
    }
    closedir $d;
    return;
}

sub _select_used_zone {
    my $self = shift;
    if (my @servers = $self->servers) {
	my @up     = grep {$_->ping} @servers;
	my $server = $up[0] || $servers[0];
	return $server->placement;
    } elsif (my $zone = $self->availability_zone) {
	return $zone;
    } else {
	return;
    }
}

#############################################
# copying AMIs from one zone to another
#############################################
sub copy_image {
    my $self = shift;
    my ($image,$destination) = @_;
    my $ec2 = $self->ec2;

    $image = $ec2->describe_images($image)
	unless ref $image && $image->isa('VM::EC2::Image');
    
    $image       
	or croak "Invalid image '$image'; usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";
    $image->imageType eq 'machine' 
	or croak "$image is not an AMI: usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";
    
    my $dest_manager;
    if (ref $destination && $destination->isa('VM::EC2::Staging::Manager')) {
	$dest_manager = $destination;
    } else {
	my $dest_region = ref $destination && $destination->isa('VM::EC2::Region') 
	    ? $destination
	    : $ec2->describe_regions($destination);
	$dest_region 
	    or croak "Invalid EC2 Region '$dest_region'; usage VM::EC2::Staging::Manager->copy_image(\$image,\$dest_region)";	
	my $dest_endpoint = $dest_region->regionEndpoint;
	my $dest_ec2      = VM::EC2->new(-endpoint    => $dest_endpoint,
					 -access_key  => $ec2->access_key,
					 -secret_key  => $ec2->secret) 
	    or croak "Could not create new VM::EC2 in $dest_region";
	$dest_manager = $self->new(-ec2           => $dest_ec2,
				   -scan          => 1,
				   -on_exit       => 'destroy',
				   -instance_type => $self->instance_type);
    }


    my $root_type = $image->rootDeviceType;
    if ($root_type eq 'ebs') {
	return $self->_copy_ebs_image($image,$dest_manager);
    } else {
	return $self->_copy_instance_image($image,$dest_manager);
    }
}

sub _copy_ebs_image {
    my $self = shift;
    my ($image,$dest_manager) = @_;

    # hashref with keys 'name', 'description','architecture','kernel','ramdisk','block_devices','root_device'
    $self->info("Gathering information about image $image\n");
    my $info = $self->_gather_image_info($image);

    my $name         = $info->{name};
    my $description  = $info->{description};
    my $architecture = $info->{architecture};
    my $kernel       = $self->_match_kernel($info->{kernel},$dest_manager,'kernel')
	or croak "Could not find an equivalent kernel for $info->{kernel} in region ",$dest_manager->ec2->endpoint;
    
    my $ramdisk;
    if ($info->{ramdisk}) {
	$ramdisk      = $self->_match_kernel($info->{ramdisk},$dest_manager,'ramdisk')
	    or croak "Could not find an equivalent ramdisk for $info->{ramdisk} in region ",$dest_manager->ec2->endpoint;	    }

    my $block_devices   = $info->{block_devices};  # format same as $image->blockDeviceMapping
    my $root_device     = $info->{root_device};

    $self->info("Copying EBS volumes attached to this image (this may take a long time)\n");
    my @bd              = @$block_devices;
    my @dest_snapshots  = map {$self->copy_snapshot($_->snapshotId,$dest_manager)} @bd;

    # create the new block device mapping
    my @mappings;
    for my $source_ebs (@$block_devices) {
	my $snapshot    = shift @dest_snapshots;
	my $dest        = "$source_ebs";  # interpolates into correct format
	$dest          =~ s/=[\w-]+/=$snapshot/;  # replace source snap with dest snap
	push @mappings,$dest;
    }

    return $dest_manager->ec2->register_image(-name                 => $name,
					      -root_device_name     => $root_device,
					      -block_device_mapping => \@mappings,
					      -description          => $description,
					      -architecture         => $architecture,
					      -kernel_id            => $kernel,
					      $ramdisk ? (-ramdisk_id  => $ramdisk): ()
	);
}

sub copy_snapshot {
    my $self = shift;
    my ($snapId,$dest_manager) = @_;
    my $snap   = $self->ec2->describe_snapshots($snapId) 
	or croak "Couldn't find snapshot for $snapId";
    my $description = "duplicate of $snap, created by ".__PACKAGE__." during image copying";

    my $source = $self->provision_volume(-snapshot_id=>$snapId) 
	or croak "Couldn't mount volume for $snapId";
    my $fstype  = $source->fstype;
    my $blkinfo = $source->server->scmd('sudo','blkid',$source->mtdev);
    my ($uuid)  = $blkinfo =~ /UUID="(\S+)"/;
    my ($label) = $blkinfo =~ /LABEL="(\S+)"/;
    
    my $dest   = $dest_manager->provision_volume(-fstype => $fstype,
						 -size   => $source->size,
						 -label  => $label,
						 -uuid   => $uuid,
						 -reuse  => 0,
	) or croak "Couldn't create new destination volume for $snapId";

    if ($fstype eq 'raw') {
	$self->info("Using dd for block level disk copy (will take a while)\n");
	$source->dd($dest)    or croak "dd failed";
    } else {
	# this now works?
	$source->copy($dest) or croak "rsync failed";
    }
    
    $dest->unmount; # don't want this mounted; otherwise it will be unmounted & remounted
    my $snapshot = $dest->create_snapshot($description);
    
    # we don't need these volumes now
    $source->delete;
    $dest->delete;

    return $snapshot;
}

sub _gather_image_info {
    my $self  = shift;
    my $image = shift;
    return {
	name         =>   $image->name,
	description  =>   $image->description,
	architecture =>   $image->architecture,
	kernel       =>   $image->kernelId  || undef,
	ramdisk      =>   $image->ramdiskId || undef,
	root_device  =>   $image->rootDeviceName,
	block_devices=>   [$image->blockDeviceMapping],
    };
}

sub _match_kernel {
    my $self = shift;
    my ($imageId,$dest_manager) = @_;
    my $home_ec2 = $self->ec2;
    my $dest_ec2 = $dest_manager->ec2;  # different endpoints!
    my $image    = $home_ec2->describe_images($imageId) or return;
    my $type     = $image->imageType;
    my @candidates;

    if (my $name     = $image->name) { # will sometimes have a name
	@candidates = $dest_ec2->describe_images({'name'        => $name,
						  'image-type'  => $type,
						    });
    }
    unless (@candidates) {
	my $location = $image->imageLocation; # will always have a location
	my @path     = split '/',$location;
	$location    = $path[-1];
	@candidates  = $dest_ec2->describe_images(-filter=>{'image-type'=>'kernel',
							    'manifest-location'=>"*/$location"},
						  -executable_by=>['all','self']);
    }
    return $candidates[0];
}

sub DESTROY {
    my $self = shift;
    if ($$ == $self->pid) {
	my $action = $self->on_exit;
	$self->terminate_all_servers if $action eq 'terminate';
	$self->stop_all_servers      if $action eq 'stop';
    }
    delete $Managers{$self->ec2->endpoint};
}

sub new_volume_name {
    return shift->_token('volume');
}

sub new_server_name {
    return shift->_token('server');
}

sub _token {
    my $self = shift;
    my $base = shift or croak "usage: _token(\$basename)";
    return sprintf("$base-%08x",1+int(rand(0xFFFFFFFF)));
}

1;


=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Staging::Server>
L<VM::EC2::Staging::Volume>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

