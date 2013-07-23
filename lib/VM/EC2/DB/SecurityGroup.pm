package VM::EC2::DB::SecurityGroup;

=head1 NAME

VM::EC2::DB::SecurityGroup - An RDS Database Security Group

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
use VM::EC2::DB::EC2SecurityGroup;
use VM::EC2::DB::IPRange;

sub primary_id { shift->DBSecurityGroupName }

sub valid_fields {
    my $self = shift;
    return qw(DBSecurityGroupDescription DBSecurityGroupName EC2SecurityGroups IPRanges OwnerId VpcId);
}

sub EC2SecurityGroups {
    my $self = shift;
    my $groups = $self->SUPER::EC2SecurityGroups;
    return unless $groups;
    $groups = $groups->{EC2SecurityGroup};
    return ref $groups eq 'HASH' ?
        (VM::EC2::DB::EC2SecurityGroup->new($groups,$self->aws)) :
        map { VM::EC2::DB::EC2SecurityGroup->new($_,$self->aws) } @$groups;
}

sub IPRanges {
    my $self = shift;
    my $ranges = $self->SUPER::IPRanges;
    return unless $ranges;
    $ranges = $ranges->{IPRange};
    return ref $ranges eq 'HASH' ?
        (VM::EC2::DB::IPRange->new($ranges,$self->aws)) :
        map { VM::EC2::DB::IPRange->new($_,$self->aws) } @$ranges;
}

sub ec2_security_groups { shift->EC2SecurityGroups }

sub ip_ranges { shift->IPRanges }

1;
