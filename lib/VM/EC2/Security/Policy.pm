package VM::EC2::Security::Policy;

=head1 NAME

VM::EC2::Security::Policy -- Simple IAM policy generator for EC2

=head1 SYNOPSIS

 my $policy = VM::EC2::Security::Policy->new;
 $policy->add_statement(-effect   => 'allow',
                        -actions  => 'Describe*','CreateVolume','delete_volume');
 $policy->add_statement(-effect   => 'deny',
                        -actions  => 'DescribeImages');
 print $policy->as_string;

=head1 DESCRIPTION

=head1 METHODS

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use VM::EC2;
use Carp 'croak';
use overload
    '""'     => 'as_string',
    fallback => 1;

sub new {
    my $class = shift;
    return bless {
	statements => [],
    },ref $class || $class;
}

sub allow {
    my $self = shift;
    my @actions = @_ ? @_ : '*';
    return $self->_add_statement(-effect=>'allow',
				-actions=>\@actions);
}
sub deny {
    my $self = shift;
    my @actions = @_ ? @_ : '*';
    return $self->_add_statement(-effect=>'deny',
				 -actions=>\@actions);
}

sub _add_statement {
    my $self = shift;
    my %args = @_;
    my $effect  = $args{-effect} || 'allow';
    my $actions = $args{-action} || $args{-actions} || [];
    $actions    = [$actions] unless ref $actions && ref $actions eq 'ARRAY';
    $effect     =~ /^allow|deny$/i or croak '-effect must be "allow" or "deny"';
    push @{$self->{statements}},{effect  => $effect,
				 actions => $actions};
    return $self;
}

sub as_string {
    my $self = shift;
    my @statements = @{$self->{statements}};
    my $result =<<END;
\{
   "Statement": \[
END
;
    $result .= join ",\n",map {$self->_format_statement($_)} @statements;
    $result .= <<END;

   ]
}
END
    chomp($result);
    return $result;
}

sub _format_statement {
    my $self = shift;
    my $s    = shift;
    my $action_list = join ',',map {$self->_format_action($_)} @{$s->{actions}};
    my $effect  = $s->{effect} =~ /allow/i ? 'Allow' 
                 :$s->{effect} =~ /deny/i  ? 'Deny'
		 :'Allow';
    my $result =<<END;
      {
	  "Action":   [ $action_list ],
          "Effect":   "$effect",
          "Resource": "*"
      }
END
    chomp($result);
    return $result;
}

sub _format_action {
    my $self = shift;
    my $a    = shift;
    $a      =~ s/^ec2://;  # temporarily remove leading ec2
    my $mixed = ucfirst VM::EC2->uncanonicalize($a);
    return qq("ec2:$mixed");
}

1;
