package VM::EC2::DB::LogFilesDetails;

=head1 NAME

VM::EC2::DB::LogFilesDetails - An RDS Database Log Files Details object

=head1 SYNOPSIS

 use VM::EC2;
 $ec2 = VM::EC2->new(...);
 my @logs = $ec2->describe_db_log_files(-db_instance_identifier => 'mydbinstance');;
 print $_->LogFileName,"\n" foreach grep { $_->Size > 1024 } @logs;

=head1 DESCRIPTION

DB instance log file details.

=head1 STRING OVERLOADING

In string context, this object returns a string with the log file date,
log file name, and log file size in bytes.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

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

use overload '""' => sub { shift->as_string },
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(LastWritten LogFileName Size);
}

sub as_string {
    my $self = shift;
    return $self->LastWritten . '  ' . $self->LogFileName . '  ' . $self->Size . ' Bytes';
}

1;
