package VM::EC2::DB::Instance::StatusInfo;

=head1 NAME

VM::EC2::DB::Instance::StatusInfo - An RDS Database Status Info

=head1 SYNOPSIS

 use VM::EC2;

 $ec2 = VM::EC2->new(...);
 $db = $ec2->describe_db_instances('mydbinstance');
 my $status = $db->StatusInfos;
 print $status->Status,' : ',$status->Message,"\n";

=head1 DESCRIPTION

This object represents a DB Instance Status Info, as returned by the
VM::EC2->describe_db_instances() call.

=head1 STRING OVERLOADING

In a scalar context, this object returns the Status field.

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

use overload '""' => sub { shift->Status },
             fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(
               Message
               Normal
               Status
               StatusType
    );
}

sub Normal {
    my $self = shift;
    my $n = $self->SUPER::Normal;
    return $n eq 'true';
}

1;
