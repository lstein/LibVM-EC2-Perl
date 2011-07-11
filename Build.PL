#!/usr/bin/perl

use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name       => 'MyAWS',
    license           => 'perl',
    dist_version_from => 'lib/MyAWS.pm',
    dist_author       => 'Lincoln Stein <lincoln.stein@oicr.on.ca>',
    requires          => {
    },
    recommends        => {
    },
    create_makefile_pl => 'passthrough',
    build_class        => 'Module::Build',
    );


$build->create_build_script;
exit 0;
