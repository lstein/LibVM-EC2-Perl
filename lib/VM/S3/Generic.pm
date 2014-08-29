package VM::S3::Generic;

use strict;
use base 'VM::EC2::Generic';

sub s3 { shift->ec2 }

sub _normalize_args {
    my $self = shift;
    my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;
    my %normalized;

    while (my ($key,$value) = each %args) {
	$key =~ s/([a-z])([A-Z])/$1_$2/;
	$key = lc($key);
	$key =~ s/^-//;
	$normalized{$key} = $value;
    }
    return %normalized;
}
1;

