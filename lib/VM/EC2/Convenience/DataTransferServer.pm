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

 # remote to remote transfer - useful for interzone transfers
 $server->put('Music' => "$server2:/home/ubuntu/music");
 $server->put('Music' => "$server2:Music");

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

    my $instance = $class->create_instance(\%args)
	or croak "Could not create an instance that satisfies requested criteria";

    $class->wait_till_instance_is_ready($instance)
	or croak "Instance did not come up in time expected";

    my $self = bless {
	ec2      => $ec2,
	instance => $instance,
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
sub preserve { shift->{preserve} }
sub quiet    { shift->{quiet}    }

sub as_string {
    my $self = shift;
    (my $ep   = $self->ec2->endpoint) =~ s!^http://!!;
    return "$ep/".$self->instance;
}

sub create_instance {
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

