package VM::EC2::DB::PendingMaintenanceAction;

=head1 NAME

VM::EC2::DB::PendingMaintenanceAction - An RDS Database Pending Maintenance Action object

=head1 SYNOPSIS

 use VM::EC2;

 $ec2 = VM::EC2->new(...);
 $action = $ec2->apply_pending_maintenance_action(...);
 foreach $p ($pending->valid_fields) {
    print $p,' ',$action->$p,"\n" if $action->$p;
 }

=head1 DESCRIPTION

Provides information about a pending maintenance action for a resource.

=head1 STRING OVERLOADING

In string context, this object returns the Action field.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::DB::Instance>

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.comE<gt>.

Copyright (c) 2015 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';

use overload '""' => sub { shift->Action },
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(
        Action
        AutoAppliedAfterDate
        CurrentApplyDate
        ForcedApplyDate
        OptInStatus
    );
}

1;
