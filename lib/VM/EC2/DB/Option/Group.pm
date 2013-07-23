package VM::EC2::DB::Option::Group;

=head1 NAME

VM::EC2::DB::Option::Group - An RDS Database Option Group

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
use VM::EC2::DB::Option;

sub primary_id { shift->OptionGroupName }

sub valid_fields {
    my $self = shift;
    return qw(AllowsVpcAndNonVpcInstanceMemberships
              EngineName
              MajorEngineVersion
              OptionGroupDescription
              OptionGroupName
              Options
              VpcId);
}

sub AllowsVpcAndNonVpcInstanceMemberships {
    my $self = shift;
    my $allows = $self->SUPER::AllowsVpcAndNonVpcInstanceMemberships;
    return $allows eq 'true';
}

sub Options {
    my $self = shift;
    my $options = $self->SUPER::Options;
    return unless $options;
    $options = $options->{Option};
    return ref $options eq 'HASH' ?
        (VM::EC2::DB::Option->new($options,$self->aws)) :
        map { VM::EC2::DB::Option->new($_,$self->aws) } @$options;
}

1;
