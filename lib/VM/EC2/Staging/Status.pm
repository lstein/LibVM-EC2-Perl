package VM::EC2::Staging::Registry;

=head1 NAME

VM::EC2::Staging::Registry - Persistent registry of staging servers.

=head1 SYNOPSIS

This module is used internally by VM::EC2::Staging::Server.

 use VM::EC2::Staging::Registry;
 my $registry = VM::EC2::Staging::Registry->new();
 $registry->register_server($vm_ec2_staging_server,$private_key);
 $registry->unregister_server($vm_ec2_staging_server);
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
use Storable;


1;
