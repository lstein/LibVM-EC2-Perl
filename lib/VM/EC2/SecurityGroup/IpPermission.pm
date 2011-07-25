package VM::EC2::SecurityGroup::IpPermission;

use strict;
use base 'VM::EC2::Generic';
use VM::EC2::SecurityGroup::UserIdGroup;

sub valid_fields {
    qw(ipProtocol fromPort toPort groups ipRanges);
}

sub short_name {
    my $s = shift;
    my $from = $s->ipRanges ? ' FROM '.join(',',sort $s->ipRanges)
              :$s->groups   ? ' FROM '.join(',',sort $s->groups)
              :''; 
    sprintf("%s(%s..%s)%s",$s->ipProtocol,$s->fromPort,$s->toPort,$from);
}

sub groups {
    my $self = shift;
    my $g    = $self->SUPER::groups or return;
    return map { VM::EC2::SecurityGroup::UserIdGroup->new($_,$self->aws) } @{$g->{item}};
}

sub ipRanges {
    my $self = shift;
    my $r    = $self->SUPER::ipRanges or return;
    return map {$_->{cidrIp}} @{$r->{item}};
}


1;

