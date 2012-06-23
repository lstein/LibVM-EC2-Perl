package VM::EC2::Staging::Registry;

=head1 NAME

VM::EC2::Staging::Registry - Persistent registry of staging servers.

=head1 SYNOPSIS

This module is used internally by VM::EC2::Staging::Server.

 use VM::EC2::Staging::Registry;
 my $registry = VM::EC2::Staging::Registry->new();
 $registry->register_server($vm_ec2_staging_server);
 $registry->unregister_server($vm_ec2_staging_server);
 $registry->add_key($vm_ec2_staging_server=>$keyname);
 $registry->synchronize($ec2);  # synchronize with an endpoint

 $path    = $registry->private_key_path($vm_ec2_staging_server);
 $server  = $registry->instance_to_server($instance_id);
 $server  = $registry->volume_to_server($volume_id);
 @servers = $registry->servers();
 @servers = $registry->servers('us-west-1a');

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
use VM::EC2::Staging::Volume;
use File::Spec;
use Carp 'croak';
use Storable qw(lock_store lock_retrieve);

sub new {
    my $class = shift;
    my $reg   = $class->read_configuration();
    return bless $reg,ref $class || $class;
}

sub read_configuration {
    my $self = shift;
    my $conf_file = $self->conf_file_path;
    my $conf;
    if (-e $conf_file) {
	$conf = lock_retrieve($conf_file);
    } else {
	$conf = {
	    servers => {},
	    zones   => {},
	    volumes => {},
	};
	lock_store($conf,$conf_file);
    }
    return $conf;
}

sub write_configuration {
    my $self = shift;
    my $conf_file = $self->conf_file_path;
    lock_store($self,$conf_file);
}

sub register_server {
    my $self = shift;
    my $server      = shift;
    my $endpoint    = $server->ec2->endpoint;
    my $zone        = $server->instance->placement;
    my $instance_id = $server->instance->instanceId;
    my $private_key = $server->private_key;
    my $accept_keys = $server->accept_keys;
    my $keyname     = $server->instance->keyName;

    my $keyfile     = $self->key_path($keyname);
    open my $k,'>',$keyfile or die "Couldn't create $keyfile: $!";
    chmod 0600,$keyfile     or die "Couldn't chmod  $keyfile: $!";
    print $k $private_key;
    close $k;

    $self->{servers}{$instance_id} = {
	endpoint    => $endpoint,
	zone        => $zone,
	instance_id => $instance_id,
	keyname     => $keyname,
	accept_keys => $accept_keys,
    };
    $self->write_configuration;
}

sub unregister_server {
    my $self    = shift;
    my $server  = shift;
    my $d       = $self->{servers}{$server->instance->instanceId} or return;
    my $keyfile = $self->key_path($d->{keyname});
    delete $self->{servers}{$server->instance->instanceId};
    unlink $keyfile;
}

sub key_path {
    my $class = shift;
    my $keyname = shift;
    return File::Spec->catfile($self->dot_directory_path,"$keyname.pem")
}

sub dot_directory_path {
    my $class = shift;
    my $dir = File::Spec->catfile($HOME,'.vm_ec2_registry');
    unless (-e $dir && -d $dir) {
	mkdir $dir       or croak "mkdir $dir: $!";
	chmod 0700 $dir  or croak "chmod 0700 $dir: $!";
    }
    return $dir;
}

sub conf_file_name {
    my $class = shift;
    return 'staging_registry';
}

sub conf_file_path {
    my $class = shift;
    return File::Spec->catfile($class->dot_directory_path,$class->conf_file_name);
}


1;
