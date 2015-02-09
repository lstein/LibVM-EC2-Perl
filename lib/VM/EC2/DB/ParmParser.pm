package VM::EC2::DB::ParmParser;

=head1 NAME

VM::EC2::DB::ParmParser - Format parameters for passing to the RDS API

Inherits from and augments VM::EC2::ParmParser with RDS specific parameter
building functions

=cut

use base 'VM::EC2::ParmParser';

sub member_list_key_value_parm {
    my $self = shift;

    my ($argname,$args) = @_;
    return unless ref $args eq 'HASH';

    my @params;
    $argname .= ".member";
    my $c = 1;
    foreach my $key (keys %$args) {
        push @params,("$argname.$c.Key" => $key);
        push @params,("$argname.".$c++.".Value" => $args->{$key});
    }

    return @params;
}

1;
