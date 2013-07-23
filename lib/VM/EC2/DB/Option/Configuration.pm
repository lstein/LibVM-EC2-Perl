package VM::EC2::DB::Option::Configuration;

=head1 NAME

VM::EC2::DB::Option::Configuration - An RDS Database Option Configuration

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 STRING OVERLOADING

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::DB::Instance>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>.

Copyright (c) 2013 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use VM::EC2::DB::Option::Setting;

sub primary_id { shift->OptionName }

sub valid_fields {
    my $self = shift;
    return qw(
        DBSecurityGroupMemberships
        OptionName
        OptionSettings
        Port
        VpcSecurityGroupMemberships
    );
}

sub OptionSettings {
    my $self = shift;
    my $settings = $self->SUPER::OptionSettings;
    return unless $settings;
    $options = $settings->{OptionSetting};
    return ref $settings eq 'HASH' ?
        (VM::EC2::DB::Option::Setting->new($settings,$self->aws)) :
        map { VM::EC2::DB::Option::Setting->new($_,$self->aws) } @$settings;
}

1;
