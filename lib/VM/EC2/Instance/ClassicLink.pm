package VM::EC2::Instance::ClassicLink;

=head1 NAME

VM::EC2::Instance::ClassicLink - Object describing EC2-Classic instances that
are linked to a VPC.

=head1 SYNOPSIS

 @i = $ec2->describe_classic_link_instances();
 for my $i (@i) {
    print $i->instanceId, ' ', $i->vpcId, ' ', join(',',$i->groups),"\n";
 }

=head1 DESCRIPTION

This object represents a ClassicLinkInstance object found here:
http://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_ClassicLinkInstance.html

=head1 METHODS

 groups()      -- returns a list of L<VM::EC2::SecurityGroup> objects.

 tags()        -- returns a list of tags in a hash.

In a string context, this object interpolates with the status string.

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

sub valid_fields {
    my $self = shift;
    return qw(groupSet instanceId tagSet vpcId);
}

sub groupSet {
    my $self = shift;
    my $groups = $self->SUPER::groupSet;

    my @g = map { $_->groupId } @{$groups->{item}};
    return $self->aws->describe_security_groups(-group_id => \@g);
}

sub groups { shift->groupSet }

sub tagSet {
    my $self = shift;
    my $tags = $self->SUPER::tags;
    my $result = {};

    my $innerhash = $tags->{item} or return $result;
    for my $key (keys %$innerhash) {
        $result->{$key} = $innerhash->{$key}{value};
    }
    return $result;
}

sub tags { shift->tagSet }

1;

