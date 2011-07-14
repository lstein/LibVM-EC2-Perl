package MyAWS::Object::SecurityGroup::IpPermission;

use strict;
use base 'MyAWS::Object::Base';
use MyAWS::Object::SecurityGroup::UserIdGroup;

sub valid_fields {
    qw(ipProtocol fromPort toPort groups ipRanges);
}

sub short_name {
    my $s = shift;
    sprintf("%s(%s:%s)%s",$s->ipProtocol,$s->fromPort,$s->toPort,$s->ipRanges ? ' FROM '.join(',',$s->ipRanges):'');
}

sub groups {
    my $self = shift;
    my $g    = $self->SUPER::groups or return;
    return map { MyAWS::Object::SecurityGroup::UserIdGroup->new($_->$self->aws) } @{$g->{item}};
}

sub ipRanges {
    my $self = shift;
    my $r    = $self->SUPER::ipRanges or return;
    return map {$_->{cidrIp}} @{$r->{item}};
}


1;

