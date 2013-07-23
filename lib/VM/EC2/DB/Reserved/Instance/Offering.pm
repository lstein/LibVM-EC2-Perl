package VM::EC2::DB::Reserved::Instance::Offering;

=head1 NAME

VM::EC2::DB::Reserved::Instance::Offering - An RDS Database Reserved Instance Offering

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
use VM::EC2::DB::Reserved::RecurringCharge;

sub primary_id { shift->ReservedDBInstanceId }

sub valid_fields {
    my $self = shift;
    return qw(
        CurrencyCode
        DBInstanceClass
        DBInstanceCount
        Duration
        FixedPrice
        MultiAZ
        OfferingType
        ProductDescription
        RecurringCharges
        ReservedDBInstanceId
        ReservedDBInstancesOfferingId
        UsagePrice
    );
}

sub MultiAZ {
    my $self = shift;
    my $maz = $self->SUPER::MultiAZ;
    return $maz eq 'true';
}

sub RecurringCharges {
    my $self = shift;
    my $rc = $self->SUPER::RecurringCharges;
    return unless $rc;
    $rc = $rc->{RecurringCharge};
    return ref $rc eq 'HASH' ?
       (VM::EC2::DB::Reserved::RecurringCharge->new($rc,$self->aws)) :
       map { VM::EC2::DB::Reserved::RecurringCharge->new($_,$self->aws) } @$rc;
}

1;
