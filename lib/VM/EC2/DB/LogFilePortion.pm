package VM::EC2::DB::LogFilePortion;

=head1 NAME

VM::EC2::DB::LogFilePortion - An RDS Database Log File Portion

=head1 SYNOPSIS

 use VM::EC2;
 $ec2 = VM::EC2->new(...);
 my @logs = $ec2->describe_db_log_files(-db_instance_identifier => 'mydbinstance');
 foreach my $log (@logs) {
    my $data = $ec2->download_db_log_file_portion(-db_instance_identifier => 'mydbinstance', 
                                                  -log_file_name => $log->LogFileName);
    print $data->LogFileData,"\n";
 }

=head1 DESCRIPTION

DB instance log file portion.

=head1 STRING OVERLOADING

In string context, this object returns a string with the log file contents

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

use overload '""' => sub { shift->LogFileData },
    fallback => 1;

sub valid_fields {
    my $self = shift;
    return qw(AdditionalDataPending LogFileData Marker);
}

1;
