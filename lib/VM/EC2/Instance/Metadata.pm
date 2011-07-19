package VM::EC2::Instance::Metadata;

use strict;
use LWP::Simple 'get';
use Carp 'croak';

my $global_cache = {};

sub new {
    my $pack = shift;
    return bless { cache => {} },ref $pack || $pack;
}

sub imageId          { shift->fetch('ami-id') }
sub imageLaunchIndex { shift->fetch('ami-launch-index') }
sub amiManifestPath  { shift->fetch('ami-manifest-path')}
sub imageLocation    { shift->amiManifestPath            }
sub ancestorAmiIds   { shift->fetch('ancestor-ami-ids')  }
sub imageAncestorIds { shift->ancestorAmiIds             }  
sub instanceAction   { shift->fetch('instance-action')   }
sub instanceId       { shift->fetch('instance-id')       }
sub instanceType     { shift->fetch('instance-type')     }
sub localHostname    { shift->fetch('local-hostname')    }
sub privateDnsName   { shift->localHostname              }
sub localIpv4        { shift->fetch('local-ipv4')        }
sub privateIpAddress { shift->localIpv4                  }
sub kernelId         { shift->fetch('kernel-id')         }
sub mac              { shift->fetch('mac')               }
sub availabilityZone { shift->fetch('placement/availability-zone') }
sub productCodes     { split /\s+/,shift->fetch('product-codes')   }
sub publicHostname   { shift->fetch('public-hostname')   }
sub dnsName          { shift->publicHostname             }
sub publicIpv4       { shift->fetch('public-ipv4')       }
sub ipAddress        { shift->publicIpv4                 }
sub ramdiskId        { shift->fetch('ramdisk-id')        }
sub reservationId    { shift->fetch('reservation-id')    }
sub securityGroups   { split /\s+/,shift->fetch('security-groups')   }
sub profile          { shift->fetch('profile')           }
sub userData         { shift->fetch('../user-data')      }

sub blockDeviceMapping {
    my $self = shift;
    my @devices = split /\s+/,$self->fetch('block-device-mapping');
    my %map     = map {$self->fetch("block-device-mapping/$_") => $_} @devices;
    return \%map;
}
sub interfaces {
    my $self = shift;
    my @macs   = split /\s+/,$self->fetch('network/interfaces/macs');
    my %result;
    for my $m (@macs) {
	$m =~ s/^\/$//; # get rid of hanging slash
	for my $pair ([localHostname     => 'local-hostname',
		       localIpv4s        => 'local-ipv4s',
		       mac               => 'mac',
		       publicIpv4s       => 'public-ipv4s',
		       securityGroupIds  => 'security-groupids',
		       subnetId          => 'subnet-id',
		       subnetIpv4CidrBlock => 'subnet-ipv4-cidr-block',
		       vpcId             => 'vpc-id',
		       vpcIpv4CidrBlock  => 'vpc-ipv4-cidr-block']) {
	    my ($tag,$attribute) = @$pair;
	    my $value = $self->fetch("network/interfaces/macs/$m/$attribute");
	    my @value = split /\s+/,$value;
	    $result{$m}{$tag} = $attribute =~ /s$/ ? \@value : $value;
	}
    }
    return \%result;
}

sub publicKeys {
    my $self = shift;
    my @keys = split /\s+/,$self->fetch('public-keys');
    return map {/^\d+=(.+)/ && $1} @keys;
}

sub fetch {
    my $self = shift;
    my $attribute = shift or croak "Usage: VM::EC2::Instance::Metadata->get('attribute')";
    my $cache = $self->{cache} || $global_cache;  # protect against class invocation
    return $cache->{$attribute} if exists $cache->{$attribute};
    chomp (my $v = get("http://169.254.169.254/latest/meta-data/$attribute"));
    return $cache->{$attribute} = $v;
}

1;

