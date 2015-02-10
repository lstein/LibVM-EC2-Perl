package VM::EC2::DB::ResourcePendingMaintenanceAction;

=head1 NAME

VM::EC2::DB::ResourcePendingMaintenanceAction - An RDS Database Resource Pending Maintenance Action
object

=head1 SYNOPSIS

 use VM::EC2;

 $ec2 = VM::EC2->new(...);
 @r = $ec2->describe_pending_maintenance_actions();
 foreach $r (@r) {
    print $r->ResourceIdentifier,': ',$r->PendingMaintenanceActionDetails->Action,"\n";
 }

=head1 DESCRIPTION

Provides information about a pending maintenance action for a resource.

=head1 STRING OVERLOADING

In string context, this object returns the Action field.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::DB::Instance>
L<VM::EC2::DB::PendingMaintenanceAction>

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
use VM::EC2::DB::PendingMaintenanceAction;

use overload '""' => sub { shift->Action },
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(
        PendingMaintenanceActionDetails
        ResourceIdentifier
    );
}

sub PendingMaintenanceActionDetails {
    my $self = shift;
    my $p = $self->SUPER::PendingMaintenanceActionDetails or return;
    my $p = $p->{PendingMaintenanceAction};
    my @p = ref $p eq 'ARRAY' ? 
        map { VM::EC2::DB::PendingMaintenanceAction->new($_,$self->aws) } @$p :
        (VM::EC2::DB::PendingMaintenanceAction->new($p,$self->aws));
    return wantarray ? @p : \@p;
}

sub PendingMaintenanceAction { shift->PendingMaintenanceActionDetails }

1;
