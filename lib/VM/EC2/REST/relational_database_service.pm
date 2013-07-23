package VM::EC2::REST::relational_database_service;

use strict;
use VM::EC2 '';   # important not to import anything!
package VM::EC2;  # add methods to VM::EC2

VM::EC2::Dispatch->register(
    AddSourceIdentifierToSubscription => 'fetch_one_result,EventSubscription,VM::EC2::DB::Event::Subscription',
    AuthorizeDBSecurityGroupIngress   => 'fetch_one_result,DBSecurityGroup,VM::EC2::DB::SecurityGroup',
    CopyDBSnapshot                    => 'fetch_one_result,DBSnapshot,VM::EC2::DB::Snapshot',
    CreateDBInstance                  => 'fetch_one_result,DBInstance,VM::EC2::DB::Instance',
    CreateDBInstanceReadReplica       => 'fetch_one_result,DBInstance,VM::EC2::DB::Instance',
    CreateDBParameterGroup            => 'fetch_one_result,DBParameterGroup,VM::EC2::DB::Parameter::Group',
    CreateDBSecurityGroup             => 'fetch_one_result,DBSecurityGroup,VM::EC2::DB::SecurityGroup',
    CreateDBSnapshot                  => 'fetch_one_result,DBSnapshot,VM::EC2::DB::Snapshot',
    CreateDBSubnetGroup               => 'fetch_one_result,DBSubnetGroup,VM::EC2::DB::Subnet::Group',
    CreateEventSubscription           => 'fetch_one_result,EventSubscription,VM::EC2::DB::Event::Subscription',
    CreateOptionGroup                 => 'fetch_one_result,OptionGroup,VM::EC2::DB::Option::Group',
    DescribeDBEngineVersions          => 'fetch_rds_objects,DBEngineVersion,VM::EC2::DB::Engine::Version',
    DescribeDBInstances               => 'fetch_rds_objects,DBInstance,VM::EC2::DB::Instance',
    DescribeDBParameterGroups         => 'fetch_rds_objects,DBParameterGroup,VM::EC2::DB::Parameter::Group',
    DescribeDBParameters              => 'fetch_rds_objects,Parameter,VM::EC2::DB::Parameter',
    DescribeDBSecurityGroups          => 'fetch_rds_objects,DBSecurityGroup,VM::EC2::DB::SecurityGroup',
    DescribeDBSubnetGroups            => 'fetch_rds_objects,DBSubnetGroup,VM::EC2::DB::Subnet::Group',
    DescribeDBSnapshots               => 'fetch_rds_objects,DBSnapshot,VM::EC2::DB::Snapshot',
    DescribeEngineDefaultParameters   => 'fetch_one_result,EngineDefaults,VM::EC2::DB::Engine::Defaults',
    DescribeEventCategories           => 'fetch_rds_objects,EventCategoriesMap,VM::EC2::DB::Event::Category',
    DescribeEventSubscriptions        => 'fetch_rds_objects,EventSubscription,VM::EC2::DB::Event::Subscription',
    DescribeOptionGroupOptions        => 'fetch_rds_objects,OptionGroupOption,VM::EC2::DB::Option::Group::Option',
    DescribeOptionGroups              => 'fetch_rds_objects,OptionGroup,VM::EC2::DB::Option::Group',
    DescribeOrderableDBInstanceOptions=> 'fetch_rds_objects,OrderableDBInstanceOption,VM::EC2::DB::Instance::OrderableOption',
    DescribeReservedDBInstances       => 'fetch_rds_objects,ReservedDBInstance,VM::EC2::DB::Reserved::Instance',
    DescribeReservedDBInstancesOfferings
                                      => 'fetch_rds_objects,ReservedDBInstancesOffering,VM::EC2::DB::Reserved::Instance::Offering',
    DownloadDBLogFilePortion          => 'fetch_one_result,DBLogFilePortion,VM::EC2::DB::LogFilePortion',
    ListTagsForResource               => sub {
                                             my @tag_list = shift->{ListTagsForResourceResult}{TagList}{Tag};
                                             my %tags;
                                             foreach (@tag_list) {
                                                 $tags{$_->{Key}} = $_->{Value}
                                             }
                                             return wantarray ? %tags : \%tags;
                                         },
    ModifyDBInstance                  => 'fetch_one_result,DBInstance,VM::EC2::DB::Instance',
    ModifyDBParameterGroup            => sub { return shift->{ModifyDBParameterGroupResult}{DBParameterGroupName} },
    ModifyDBSubnetGroup               => 'fetch_one_result,DBSubnetGroup,VM::EC2::DB::Subnet::Group',
    ModifyEventSubscription           => 'fetch_one_result,EventSubscription,VM::EC2::DB::Event::Subscription',

    PromoteReadReplica                => 'fetch_one_result,DBInstance,VM::EC2::DB::Instance',
    PurchaseReservedDBInstancesOffering
                                      => 'fetch_one_result,ReservedDBInstance,VM::EC2::DB::Reserved::Instance',
    RebootDBInstance                  => 'fetch_one_result,DBInstance,VM::EC2::DB::Instance',
    );

sub rds_call {
    my $self = shift;
    (my $endpoint = $self->{endpoint}) =~ s/ec2/rds/;
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2013-02-12';
    $self->call(@_);
}

=head1 NAME VM::EC2::REST::relational_database_service

=head1 SYNOPSIS

use VM::EC2 ':rds';

=head1 METHODS

These methods give access and control over the AWS Relational Database Service.
RDS provides easy access to creating and managing an Oracle or MySQL database
in the AWS cloud.

Implemented:
AddSourceIdentifierToSubscription
AddTagsToResource
AuthorizeDBSecurityGroupIngress
CopyDBSnapshot
CreateDBInstance
CreateDBInstanceReadReplica
CreateDBParameterGroup
CreateDBSecurityGroup
CreateDBSnapshot
CreateDBSubnetGroup
CreateEventSubscription
CreateOptionGroup
DescribeDBEngineVersions
DescribeDBInstances
DescribeDBParameterGroups
DescribeDBParameters
DescribeDBSecurityGroups
DescribeDBSnapshots
DescribeDBSubnetGroups
DescribeEngineDefaultParameters
DescribeEventCategories
DescribeEventSubscriptions
DescribeEvents
DescribeOptionGroupOptions
DescribeOptionGroups
DescribeOrderableDBInstanceOptions
DescribeReservedDBInstances
DescribeReservedDBInstancesOfferings
DownloadDBLogFilePortion
ListTagsForResource
ModifyDBInstance
ModifyDBParameterGroup
ModifyDBSubnetGroup
ModifyEventSubscription
PromoteReadReplica
PurchaseReservedDBInstancesOffering

Unimplemented:
ModifyOptionGroup
RebootDBInstance
RemoveSourceIdentifierFromSubscription
RemoveTagsFromResource
ResetDBParameterGroup
RestoreDBInstanceFromDBSnapshot
RestoreDBInstanceToPointInTime
RevokeDBSecurityGroupIngress

=head1 SEE ALSO

L<VM::EC2>

=cut

=head2 $ec2->add_source_identifier_to_subscription(%args)

Adds a source identifier to an existing RDS event notification subscription.

Required arguments:

 -source_identifier         The identifier of the event source to be added.

 -subscription_name         The name of the RDS event notification subscription
                            you want to add a source identifier to.

Returns a VM::EC2::DB::Event::Subscription object.

=cut

sub add_source_identifier_to_subscription {
    my $self = shift;
    my %args = @_;
    $args{-source_identifier} && $args{-subscription_name} or
        croak "add_source_identifier_to_subscription(): -source_identifier and -subscription_name arguments required";
    my @params;
    push @params,$self->single_parm('SourceIdentifier',\%args);
    push @params,$self->single_parm('SubscriptionName',\%args);
    return $self->rds_call('AddSourceIdentifierToSubscription',@params);
}

=head2 $ec2->add_tags_to_db_resource(-resource_name => $name, -tags => \@tags)

Adds metadata tags to a DB Instance.

Required arguments:

 -resource_name     The DB Instance the tags will be added to.

 -tags              hashref or arrayref of hashrefs containing tag Key/Value pairs

=cut

sub add_tags_to_resource {
    my $self = shift;
    my %args = @_;
    $args{-tags} && $args{-resource_name} or
        croak "add_tags_to_db_resource(): -tags and -resource_name arguments required";
    my @params;
    push @params,$self->single_parm('ResourceName',\%args);
    push @params,$self->member_list_parm('Tags',\%args);
    return $self->rds_call('AddTagsToResource',@params);
}

=head2 $sg = $ec2->authorize_db_security_group_ingress(%args)

Enables ingress to a DBSecurityGroup using one of two forms of authorization:
IP based or EC2 Security Group based.

Required arguments:

 -db_security_group_name          The name of the DB Security Group to add
                                  authorization to.

Optional arguments:

 -cidrip                          The IP range to authorize.

 -ec2_security_group_id           ID of the EC2 Security Group to authorize.

 -ec2_security_group_name         Name of the EC2 Security Group to authorize.

 -ec2_security_group_owner_id     AWS Account Number of the owner of the EC2
                                  Security Group specified in the
                                  -ec2_security_group_name parameter.

Returns a VM::EC2::DB::SecurityGroup object.

=cut

sub authorize_db_security_group_ingress {
    my $self = shift;
    my %args = @_;
    $args{-db_security_group_name} &&
        ($args{-cidrip} || $args{-ec2_security_group_id} || $args{-ec2_security_group_name}) or
        croak "authorize_db_security_group_ingress(): -db_security_group_name and one of -cidrip, -ec2_security_group_id, -ec2_security_group_name arguments required";
    ($args{-ec2_security_group_id} || $args{-ec2_security_group_name}) && $args{-ec2_security_group_owner_id} or
        croak "authorize_db_security_group_ingress(): -ec2_security_group_owner_id required when -ec2_security_group_id or -ec2_security_group_name arguments specified";
    $args{-DBSecurityGroupName} = $args{-db_security_group_name};
    $args{-EC2SecurityGroupId} = $args{-ec2_security_group_id};
    $args{-EC2SecurityGroupName} = $args{-ec2_security_group_name};
    $args{-EC2SecurityGroupOwnerId} = $args{-ec2_security_group_owner_id};
    $args{-CIDRIP} = $args{-cidrip};
    my @params;
    push @params,$self->single_parm($_,\%args) foreach qw(CIDRIP DBSecurityGroupName EC2SecurityGroupId EC2SecurityGroupName EC2SecurityGroupOwnerId);
    return $self->rds_call('AuthorizeDBSecurityGroupIngress',@params);
}

=head2 $snapshot = $ec2->copy_db_snapshot(-source_db_snapshot_identifier => $db_id, -target_db_snapshot_identifier => $snap_id)

Copies the specified DBSnapshot. The source DBSnapshot must be in the "available" state.

Required arguments:

 -source_db_snapshot_identifier   The identifier for the source DB snapshot.

 -target_db_snapshot_identifier   The identifier for the copied snapshot.
                                  Constraints:
                                  * Cannot be null, empty, or blank
                                  * Must contain from 1 to 255 alphanumeric
                                    characters or hyphens
                                  * First character must be a letter
                                  * Cannot end with a hyphen or contain two
                                    consecutive hyphens

Returns a VM::EC2::DB::Snapshot object.

=cut

sub copy_db_snapshot {
    my $self = shift;
    my %args = @_;
    $args{-cidrip} && $args{-ec2_security_group_id} or
        croak "authorize_db_security_group_ingress(): -db_security_group_name and one of -cidrip, -ec2_security_group_id, -ec2_security_group_name arguments required";
    $args{-SourceDBSnapshotIdentifier} = $args{-source_db_snapshot_identifier} || $args{-source};
    $args{-TargetDBSnapshotIdentifier} = $args{-target_db_snapshot_identifier} || $args{-target};
    my @params;
    push @params,$self->single_parm($_,\%args) foreach qw(SourceDBSnapshotIdentifier TargetDBSnapshotIdentifier);
    return $self->rds_call('CopyDBSnapshot',@params);
}

=head2 $instance = $ec2->create_db_instance(%args)

Creates a new DB instance.

Required arguments:

 -allocated_storage                    MySQL:
                                        * Must be an integer from 5 to 1024.
                                       Oracle:
                                        * Must be an integer from 10 to 1024.
                                       SQL Server:
                                        * Must be an integer from 200 to 1024
                                          (Standard Edition and Enterprise Edition)
                                          or from 30 to 1024 (Express Edition and
                                          Web Edition)

 -db_instance_class                    The compute and memory capacity of the DB Instance.
                                       db.t1.micro | db.m1.small | db.m1.medium | db.m1.large |
                                       db.m1.xlarge | db.m2.xlarge |db.m2.2xlarge | db.m2.4xlarge

 -db_instance_identifier               The DB Instance identifier. This parameter is stored as a
                                       lowercase string.
                                       Constraints:
                                        * Must contain from 1 to 63 alphanumeric characters or
                                          hyphens (1 to 15 for SQL Server).
                                        * First character must be a letter.
                                        * Cannot end with a hyphen or contain two consecutive
                                          hyphens.

 -engine                               The name of the database engine to be used for this
                                       instance.
                                       Valid values:  MySQL | oracle-se1 | oracle-se | oracle-ee |
                                        sqlserver-ee | sqlserver-se | sqlserver-ex | sqlserver-web

 -master_user_password                 The password for the master database user. Can be any
                                       printable ASCII character except "/", "\", or "@".
                                       Constraints:
                                        * MySQL:  Must contain from 8 to 41 alphanumeric characters.
                                        * Oracle: Must contain from 8 to 30 alphanumeric characters.
                                        * SQL Server: Must contain from 8 to 128 alphanumeric
                                          characters.

 -master_username                      The name of master user for the client DB Instance.

                                       Constraints:
                                         * First character must be a letter.
                                         * Cannot be a reserved word for the chosen database engine.
                                        MySQL:
                                         * Must be 1 to 16 alphanumeric characters.
                                        Oracle:
                                         * Must be 1 to 30 alphanumeric characters.
                                        SQL Server:
                                         * Must be 1 to 128 alphanumeric characters.

Optional arguments:

 -auto_minor_version_upgrade           Indicates that minor engine upgrades will be applied
                                       automatically to the DB Instance during the maintenance
                                       window.  (Boolean).  Default: true

 -availability_zone                    The EC2 Availability Zone that the database instance will
                                       be created in.
                                       Default: A random, system-chosen Availability Zone in the
                                                endpoint's region.

 -backup_retention_period              The number of days for which automated backups are retained.
                                       Setting this parameter to a positive number enables backups.
                                       Setting this parameter to 0 disables automated backups.
                                       Default: 1
                                       Constraints:
                                        * Must be a value from 0 to 8
                                        * Cannot be set to 0 if the DB Instance is a master instance
                                          with read replicas

 -character_set_name                   For supported engines, indicates that the DB Instance should
                                       be associated with the specified CharacterSet.

 -db_name                              The meaning of this parameter differs according to the
                                       database engine you use.

                                       MySQL:
                                         The name of the database to create when the DB Instance
                                         is created. If this parameter is not specified, no database
                                         is created in the DB Instance.

                                         Constraints:
                                         * Must contain 1 to 64 alphanumeric characters
                                         * Cannot be a reserved word

                                       Oracle:
                                         The Oracle System ID (SID) of the created DB Instance.

                                         Constraints:
                                         * Cannot be longer than 8 characters

                                       SQL Server:
                                         Not applicable. Must be null.

 -db_parameter_group_name              The name of the DB Parameter Group to associate with this
                                       DB instance. If this argument is omitted, the default
                                       DBParameterGroup for the specified engine will be used.

                                       Constraints:
                                       * Must be 1 to 255 alphanumeric characters
                                       * First character must be a letter.
                                       * Cannot end with a hyphen or contain two consecutive
                                         hyphens

 -db_security_groups                   An arrayref of DB Security Groups to associate with the
                                       instance

 -db_subnet_group_name                 A DB Subnet Group to associate with this DB Instance.
                                       If not specified, then it is a non-VPC DB instance.

 -engine_version                       The version number of the database engine to use.

 -iops                                 The amount of Provisioned IOPS initially allocated.
                                       Integer between 100-1000

 -license_model                        License model information for this DB Instance.
                                       Valid values: license-included |
                                                     bring-your-own-license |
                                                     general-public-license

 -multi_az                             Specifies if the DB Instance is a Multi-AZ deployment.
                                       You cannot set the -availability_zone argument if the
                                       -multi_az argument is set to true.

 -option_group_name                    Indicates that the DB Instance should be associated
                                       with the specified option group.

 -port                                 The port number on which the database accepts
                                       connections.

                                       MySQL:
                                        * Default: 3306, Valid values: 1150-65535
                                       Oracle:
                                        * Default: 1521, Valid values: 1150-65535
                                       Oracle:
                                        * Default: 1433, Valid values: 1150-65535 except
                                          1434 and 3389.

 -preferred_backup_window              The daily time range during which automated backups are
                                       created if automated backups are enabled using the
                                       -backup_retention_period argument.

                                       Default: Default: A 30-minute window selected at random
                                       from an 8-hour block of time per region. The following
                                       list shows the time blocks for each region from which
                                       the default backup windows are assigned.

                                       * US-East (Northern Virginia) Region: 03:00-11:00 UTC
                                       * US-West (N. California, Oregon) Region: 06:00-14:00 UTC
                                       * EU (Ireland) Region: 22:00-06:00 UTC
                                       * Asia Pacific (Singapore) Region: 14:00-22:00 UTC
                                       * Asia Pacific (Tokyo) Region: 17:00-03:00 UTC

                                       Constraints:
                                        * Must be in the format hh24:mi-hh24:mi
                                        * Times in Universal Time Coordinated (UTC).
                                        * Must not conflict with the preferred maintenance window.
                                        * Must be at least 30 minutes.

 -preferred_maintenance_window         The weekly time range (in UTC) during which system
                                       maintenance can occur.

                                       Format: ddd:hh24:mi-ddd:hh24:mi

                                       Default: A 30-minute window selected at random from an 8-hour
                                       block of time per region, occurring on a random day of the
                                       week. The following list shows the time blocks for each
                                       region from which the default maintenance windows are
                                       assigned.

                                       * US-East (Northern Virginia) Region: 03:00-11:00 UTC
                                       * US-West (N. California, Oregon) Region: 06:00-14:00 UTC
                                       * EU (Ireland) Region: 22:00-06:00 UTC
                                       * Asia Pacific (Singapore) Region: 14:00-22:00 UTC
                                       * Asia Pacific (Tokyo) Region: 17:00-03:00 UTC

                                       Valid Days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
                                       Constraints: Minimum 30-minute window.

 -publicly_accessible                  Is the DB instance publicly accessible.

 -vpc_security_group_ids               A list of EC2 VPC Security Groups to associate with this
                                       DB Instance.

This method returns a VM::EC2::DB:Instance object.

=cut


sub create_db_instance {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-allocated_storage} or croak "create_db_instance(): -allocated_storage required argument missing";
    $args{-db_instance_class} or croak "create_db_instance(): -db_instance_class required argument missing";
    $args{-db_instance_identifier} or croak "create_db_instance(): -db_instance_identifier required argument missing";
    $args{-engine} or croak "create_db_instance(): -engine required argument missing";
    $args{-master_user_password} or croak "create_db_instance(): -master_user_password required argument missing";
    $args{-master_username} or croak "create_db_instance(): -master_username required argument missing";
    $args{-MultiAZ} = $args{-multi_az};
    $args{-DBInstanceClass} = $args{-db_instance_class};
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    $args{-DBName} = $args{-db_name};
    $args{-DBParameterGroupName} = $args{-db_parameter_group_name};
    $args{-DBSecurityGroups} = $args{-db_security_groups};
    $args{-DBSubnetGroupName} = $args{-db_subnet_group_name};
    push @params,$self->boolean_parm($_,\%args)
        foreach qw(AutoMinorVersionUpgrade MultiAZ PubliclyAccessible);
    push @params,$self->single_parm($_,\%args)
        foreach qw(AllocatedStorage AvailabilityZone BackupRetentionPeriod
                   CharacterSetName DBInstanceClass DBInstanceIdentifier
                   DBName DBParameterGroupName DBSubnetGroupName Engine
                   EngineVersion Iops LicenseModel MasterUserPassword
                   MasterUsername OptionGroupName Port PreferredBackupWindow
                   PreferredMaintenanceWindow);
    push @params,$self->member_list_parm($_,\%args)
        foreach qw(VpcSecurityGroupIds DBSecurityGroups);
    return $self->rds_call('CreateDBInstance',@params);
}

=head2 $instance = $ec2->create_db_instance_read_replica(%args)

Creates a DB Instance that acts as a Read Replica of a source DB Instance.
All Read Replica DB Instances are created as Single-AZ deployments with backups
disabled. All other DB Instance attributes (including DB Security Groups and DB
Parameter Groups) are inherited from the source DB Instance, except as
specified below.
IMPORTANT:  The source DB Instance must have backup retention enabled.

Required arguments:

 -db_instance_identifier             The DB Instance identifier of the Read
                                     Replica. This is the unique key that
                                     identifies a DB Instance. This parameter
                                     is stored as a lowercase string.

 -source_db_instance_identifier      The identifier of the DB Instance that will
                                     act as the source for the Read Replica.
                                     Each DB Instance can have up to five Read
                                     Replicas.
                                     Constraints: Must be the identifier of an
                                     existing DB Instance that is not already a
                                     Read Replica DB Instance.

Optional arguments:

 -auto_minor_version_upgrade         Indicates that minor engine upgrades will
                                     be applied automatically to the Read
                                     Replica during the maintenance window.
                                     (Boolean)

 -availability_zone                  The Amazon EC2 Availability Zone that the
                                     Read Replica will be created in.
                                     Default: A random, system-chosen
                                     Availability Zone in the endpoint's region.

 -db_instance_class                  The compute and memory capacity of the Read
                                     Replica.
                                     Valid Values: db.m1.small | db.m1.medium |
                                     db.m1.large | db.m1.xlarge | db.m2.xlarge |
                                     db.m2.2xlarge | db.m2.4xlarge

 -iops                               The amount of Provisioned IOPS to be
                                     initially allocated for the DB Instance.

 -option_group_name                  The option group the DB instance will be
                                     associated with. If omitted, the default
                                     Option Group for the engine specified will
                                     be used.

 -port                               The port number that the DB Instance uses
                                     for connections.
                                     Default: Inherits from the source instance
                                     Valid Values: 1150-65535

 -publicly_accessible                (Boolean)

Returns a L<VM::EC2::DB::Instance> object on success.

=cut

sub create_db_instance_read_replica {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_instance_identifier} or
        croak "create_db_instance_read_replica(): -db_instance_identifier required argument missing";
    $args{-source_db_instance_identifier} or
        croak "create_db_instance_read_replica(): -source_db_instance_identifier required argument missing";
    $args{-DBInstanceClass} = $args{-db_instance_class};
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    $args{-SourceDBInstanceIdentifier} = $args{-source_db_instance_identifier};
    push @params,$self->boolean_parm($_,\%args)
        foreach qw(AutoMinorVersionUpgrade PubliclyAccessible);
    push @params,$self->single_parm($_,\%args)
        foreach qw(AvailabilityZone DBInstanceClass DBInstanceIdentifier
                   Iops OptionGroupName Port SourceDBInstanceIdentifier);
    return $self->rds_call('CreateDBInstanceReadReplica',@params);
}

=head2 $group = $ec2->create_db_parameter_group(%args)

Creates a new DB Parameter Group.

A DB Parameter Group is initially created with the default parameters for the
database engine used by the DB Instance. To provide custom values for any of the
parameters, you must modify the group after creating it using
modify_parameter_group(). Once you've created a DB Parameter Group, you need to
associate it with your DB Instance using modify_db_instance().  When you
associate a new DB Parameter Group with a running DB Instance, you need to
reboot the DB Instance for the new DB Parameter Group and associated settings to
take effect.

Required arguments:

 -db_parameter_group_family      The DB Parameter Group Family name. A DB
                                 Parameter Group can be associated with one and
                                 only one DB Parameter Group Family, and can be
                                 applied only to a DB Instance running a
                                 database engine and engine version compatible
                                 with that DB Parameter Group Family.

 -db_parameter_group_name        The name of the DB Parameter Group.
                                 Constraints:
                                 * Must be 1 to 255 alphanumeric characters
                                 * First character must be a letter
                                 * Cannot end with a hyphen or contain two
                                   consecutive hyphens
                                 NOTE: This value is stored as a lower-case
                                       string.

 -description                    The description for the DB Parameter Group.

Returns a L<VM::EC2::DB::Parameter::Group> object.

=cut

sub create_db_parameter_group {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_parameter_group_family} or
        croak "create_db_parameter_group(): -db_parameter_group_family required argument missing";
    $args{-db_parameter_group_name} or
        croak "create_db_parameter_group(): -db_parameter_group_name required argument missing";
    $args{-description} or
        croak "create_db_parameter_group(): -description required argument missing";
    $args{-DBParameterGroupFamily} = $args{-db_parameter_group_family};
    $args{-DBParameterGroupName} = $args{-db_parameter_group_name};
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBParameterGroupFamily DBParameterGroupName Description);
    return $self->rds_call('CreateDBParameterGroup',@params);
}

=head2 $group = $ec2->create_db_security_group(%args)

Creates a new DB Security Group. DB Security Groups control access to a DB
Instance if not in a VPC.

Required arguments:

 -db_security_group_description      The description for the DB Security Group.

 -db_security_group_name             The name for the DB Security Group. This
                                     value is stored as a lowercase string.
                                     Constraints: Must contain no more than 255
                                     alphanumeric characters or hyphens.
                                     Must not be "Default".

 -name                               Alias for -db_security_group_name

 -description                        Alias for -db_security_group_description

Returns a L<VM::EC2::DB::SecurityGroup> object.

=cut

sub create_db_security_group {
    my $self = shift;
    my %args = @_;
    my @params;
    my $name = $args{-db_security_group_name} || $args{-name};
    my $desc = $args{-db_security_group_description} || $args{-description};
    $name or croak "create_db_security_group(): -db_security_group_name required argument missing";
    $desc or croak "create_db_security_group(): -db_security_group_description required argument missing";
    $args{-DBSecurityGroupName} = $name;
    $args{-DBSecurityGroupDescription} = $desc;
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBSecurityGroupDescription DBSecurityGroupName);
    return $self->rds_call('CreateDBSecurityGroup',@params);
}

=head2 $dbsnap = $ec2->create_db_snapshot(-db_instance_identifier => $db_id, -db_snapshot_identifier => $snap_id)

Creates a DB snapshot. The source DB instance must be in "available" state.

Required arguments:

 -db_instance_identifier          The DB instance identifier. This is the unique
                                  key that identifies a DB instance. This
                                  parameter is not case sensitive.

                                  Constraints:
                                  * Must contain from 1 to 63 alphanumeric
                                    characters or hyphens
                                  * First character must be a letter
                                  * Cannot end with a hyphen or contain two
                                    consecutive hyphens

 -db_snapshot_identifier          The identifier for the DB snapshot.

                                  Constraints:
                                  * Cannot be null, empty, or blank
                                  * Must contain from 1 to 255 alphanumeric
                                    characters or hyphens
                                  * First character must be a letter
                                  * Cannot end with a hyphen or contain two
                                    consecutive hyphens

 -db_id                           Alias for -db_instance_identifier

 -snapshot_id                     Alias for -db_snapshot_identifier

Returns a L<VM::EC2::DB::Snapshot> object on success.

=cut

sub create_db_snapshot {
    my $self = shift;
    my %args = @_;
    my @params;
    my $db_id = $args{-db_instance_identifier} || $args{-db_id};
    my $snapshot_id = $args{-db_snapshot_identifier} || $args{-snapshot_id};
    $db_id or croak "create_db_snapshot(): -db_instance_identifier required argument missing";
    $snapshot_id or croak "create_db_snapshot(): -db_snapshot_identifier required argument missing";
    $args{-DBInstanceIdentifier} = $db_id;
    $args{-DBSnapshotIdentifier} = $snapshot_id;
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBInstanceIdentifier DBSnapshotIdentifier);
    return $self->rds_call('CreateDBSnapshot',@params);
}

=head2 $subnet_group = $ec2->create_db_subnet_group(%args)

Creates a new DB subnet group. DB subnet groups must contain at least one subnet
in at least two availability zones in the region.

Required arguments:

 -db_subnet_group_description    The description for the DB subnet group.

 -db_subnet_group_name           The name for the DB Subnet Group. This value is
                                 stored as a lowercase string.

                                 Constraints:
                                 * Must contain no more than 255 alphanumeric
                                   characters or hyphens.
                                 * Must not be "Default".

 -subnet_ids                     Arrayref of subnet IDs for the subnet group.

 -description                    Alias for -db_subnet_group_description

 -name                           Alias -db_subnet_group_name

Returns a L<VM::EC2::DB::Subnet::Group> object on success.

=cut

sub create_db_subnet_group {
    my $self = shift;
    my %args = @_;
    my @params;
    my $name = $args{-db_subnet_group_name} || $args{-name};
    my $desc = $args{-db_subnet_group_description} || $args{-description};
    my $subnet_ids = $args{-subnet_ids};
    $name or croak "create_db_subnet_group(): -db_subnet_group_name required argument missing";
    $desc or croak "create_db_subnet_group(): -db_subnet_group_description required argument missing";
    $subnet_ids or croak "create_db_subnet_group(): -subnet_ids required argument missing";
    $args{-DBSubnetGroupName} = $name;
    $args{-DBSubnetGroupDescription} = $desc;
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBInstanceIdentifier DBSnapshotIdentifier);
    push @params,$self->member_list_parm('SubnetIds',\%args);
    return $self->rds_call('CreateDBSubnetGroup',@params);
}

=head2 $event_sub = $ec2->create_event_subscription(%args)

Creates an RDS event notification subscription. This action requires a topic ARN
(Amazon Resource Name) created by either the RDS console, the SNS console, or
the SNS API. To obtain an ARN with SNS, you must create a topic in Amazon SNS
and subscribe to the topic. The ARN is displayed in the SNS console.

You can specify the type of source (SourceType) you want to be notified of,
provide a list of RDS sources (SourceIds) that triggers the events, and provide
a list of event categories (EventCategories) for events you want to be notified
of. For example, you can specify SourceType = db-instance, SourceIds =
mydbinstance1, mydbinstance2 and EventCategories = Availability, Backup.

If you specify both the SourceType and SourceIds, such as SourceType =
db-instance and SourceIdentifier = myDBInstance1, you will be notified of all
the db-instance events for the specified source. If you specify a SourceType but
do not specify a SourceIdentifier, you will receive notice of the events for
that source type for all your RDS sources. If you do not specify either the
SourceType nor the SourceIdentifier, you will be notified of events generated
from all RDS sources belonging to your customer account.

Required arguments:

 -sns_topic_arn        The Amazon Resource Name (ARN) of the SNS topic created
                       for event notification. The ARN is created by Amazon SNS
                       when you create a topic and subscribe to it.

 -subscription_name    The name of the subscription.

Optional arguments:

 -enabled              Boolean; set to true to activate the subscription, set to
                       false to create the subscription but not active it.

 -event_categories     An arrayref of event categories for a -source_type that
                       you want to subscribe to.  You can see a list of the
                       categories for a given -source_type in the Events topic
                       in the Amazon RDS User Guide or by using the
                       describe_event_categories() call.

 -source_ids           An arrayref of identifiers of the event sources for which
                       events will be returned.  If not specified, then all
                       sources are included in the response. An identifier must
                       begin with a letter and must contain only ASCII letters,
                       digits, and hyphens; it cannot end with a hyphen or
                       contain two consecutive hyphens.

 -source_type          The type of source that will be generating the events.
                       For example, if you want to be notified of events
                       generated by a DB instance, you would set this parameter
                       to db-instance. if this value is not specified, all
                       events are returned.

                       Valid values: db-instance | db-parameter-group |
                                     db-security-group | db-snapshot

 -name                 Alias for -subscription_name

Returns a L<VM::EC2::DB::Event::Subscription> object on success.

=cut

sub create_event_subscription {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-subscription_name} ||= $args{-name};
    $args{-sns_topic_arn} or croak "create_event_subscription(): -sns_topic_arn required argument missing";
    $args{-subscription_name} or croak "create_event_subscription(): -subscription_name required argument missing";
    push @params,$self->single_parm($_,\%args)
        foreach qw(SnsTopicArn SourceType SubscriptionName);
    push @params,$self->member_list_parm($_,\%args)
        foreach qw(EventCategories SourceIds);
    push @params,$self->boolean_parm('Enabled',\%args);
    return $self->rds_call('CreateEventSubscription',@params);
}

=head2 $option_grp = $ec2->create_option_group(%args)

Creates a new Option Group. You can create up to 20 option groups.

Required arguments:

 -engine_name                     Specifies the name of the engine that this
                                  option group should be associated with.

 -major_engine_version            Specifies the major version of the engine
                                  that this option group should be associated
                                  with.

 -option_group_description        The description of the option group.

 -option_group_name               Specifies the name of the option group to be
                                  created.

                                  Constraints:
                                  * Must be 1 to 255 alphanumeric characters or
                                    hyphens
                                  * First character must be a letter
                                  * Cannot end with a hyphen or contain two
                                    consecutive hyphens

 -name                            Alias for -option_group_name

 -description                     Alias for -option_group_description

Returns a L<VM::EC2::DB::Option::Group> object on success.

=cut

sub create_option_group {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-option_group_name} ||= $args{-name};
    $args{-option_group_description} ||= $args{-description};
    $args{-option_group_name} or croak "create_option_group(): -option_group_name required argument missing";
    $args{-option_group_description} or croak "create_option_group(): -option_group_description required argument missing";
    push @params,$self->single_parm($_,\%args)
        foreach qw(EngineName MajorEngineVersion OptionGroupDescription OptionGroupName);
    return $self->rds_call('CreateOptionGroup',@params);
}

=head2 @versions = $ec2->describe_db_engine_versions(%args)

All arguments are optional.

 -db_parameter_group_family       The specific DB Parameter Group family to
                                  return details for.

 -default_only                    Return only the default version of the
                                  specified engine or engine and major
                                  version combination (boolean).

 -engine                          Database engine to return.

 -engine_version                  Database engine version to return.

 -list_supported_character_sets   List supported charsets (boolean)

 -marker                          An optional pagination token provided by a previous
                                  request.  If specified, the response includes only
                                  records after the marker, up to the value specified by
                                  -max_records.

 -max_records                     The maximum number of records to include in the
                                  response.  If more records than the max exist,
                                  a marker token is included in the response.

=cut

sub describe_db_engine_versions {
    my $self = shift;
    my %args = @_;
    my $db_pgf = $args{-db_parameter_group_family} || $args{-family};
    my @params;
    push @params, ('DBParameterGroupFamily'=>$db_pgf) if $db_pgf;
    push @params,$self->boolean_parm('DefaultOnly',\%args);
    push @params,$self->single_parm('Engine',\%args);
    push @params,$self->single_parm('EngineVersion',\%args);
    push @params,$self->boolean_parm('ListSupportedCharacterSets',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBEngineVersions',@params);
}

=head2 @db_instances = $ec2->describe_db_instances(-db_instance_identifier => $id, -marker => $marker, -max_records => $integer)

All arguments are optional.

 -db_instance_identifier    The user-supplied instance identifier. If this
                            parameter is specified, only information for the
                            specific DB Instance is returned.

 -marker                    An optional pagination token provided by a previous
                            request.  If specified, the response includes only
                            records after the marker, up to the value specified by
                            -max_records.

 -max_records               The maximum number of records to include in the
                            response.  If more records than the max exist,
                            a marker token is included in the response.

 -db_instance_id            alias for -db_instance_identifier

Returns an array of VM::EC2::DB::Instance objects if any exist.

=cut

sub describe_db_instances {
    my $self = shift;
    my %args = @_;
    my $db_id = $args{-db_instance_identifier} || $args{-db_instance_id};
    my @params;
    push @params, ('DBInstanceIdentifier'=>$db_id) if $db_id;
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBInstances',@params);
}

=head2 @groups = $ec2->describe_db_parameter_groups(-db_parameter_group_name => $name, -marker => $marker, -max_records => $integer)

All arguments are optional.

 -db_parameter_group_name   The name of the DB parameter group to describe.

 -marker                    An optional pagination token provided by a previous
                            request.  If specified, the response includes only
                            records after the marker, up to the value specified by
                            -max_records.

 -max_records               The maximum number of records to include in the
                            response.  If more records than the max exist,
                            a marker token is included in the response.

 -group_name                alias for -db_subnet_group_name

Returns an array of VM::EC2::DB::Parameter::Group objects if any exist.

=cut

sub describe_db_parameter_groups {
    my $self = shift;
    my %args = @_;
    my $group = $args{-db_parameter_group_name} || $args{-group_name};
    my @params;
    push @params, ('DBParameterGroupName'=>$group) if $group;
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBParameterGroups',@params);
}

=head2 @params = $ec2->describe_db_parameters(-db_parameter_group_name => $name, -source => $source, -marker => $marker, -max_records => $integer)

Required arguments:

 -db_parameter_group_name   The name of the DB parameter group.

Optional arguments:

 -source                    The parameter types to return.
                            Valid values: user | system | engine-default
                            Default is all parameter types.

 -marker                    An optional pagination token provided by a previous
                            request.  If specified, the response includes only
                            records after the marker, up to the value specified by
                            -max_records.

 -max_records               The maximum number of records to include in the
                            response.  If more records than the max exist,
                            a marker token is included in the response.

Returns an array of VM::EC2::DB::Parameter objects.

=cut

sub describe_db_parameters {
    my $self = shift;
    my %args = @_;
    my $group = $args{-db_parameter_group_name} || $args{-group_name};
    $group || croak "describe_db_parameters(): -db_parameter_group_name argument missing";
    my @params;
    push @params, ('DBParameterGroupName'=>$group);
    push @params,$self->single_parm('Source',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBParameters',@params);
}

=head2 @groups = $ec2->describe_db_security_groups(-db_security_group_name => $name, -marker => $marker, -max_records => $integer)

All arguments are optional.

 -db_security_group_name    The name of the DB security group.

 -marker                    An optional pagination token provided by a previous
                            request.  If specified, the response includes only
                            records after the marker, up to the value specified by
                            -max_records.

 -max_records               The maximum number of records to include in the
                            response.  If more records than the max exist,
                            a marker token is included in the response.

 -group_name                alias for -db_security_group_name

Returns an array of VM::EC2::DB::SecurityGroup objects if any exist.

=cut

sub describe_db_security_groups {
    my $self = shift;
    my %args = @_;
    my $group = $args{-db_security_group_name} || $args{-group_name};
    my @params;
    push @params, ('DBSecurityGroupName'=>$group) if $group;
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBSecurityGroups',@params);
}

=head2 @snapshots = $ec2->describe_db_snapshots(%args)

All arguments are optional.

 -db_instance_identifier    A DB Instance Identifier to retrieve the list of DB
                            snapshots for. Cannot be used in conjunction with
                            -db_snapshot_identifier.
                            This parameter is not case sensitive.

 -db_snapshot_identifier    A specific DB Snapshot Identifier to describe.
                            Cannot be used in conjunction with .
                            This value is stored as a lowercase string.

 -snapshot_type             An optional snapshot type for which snapshots will
                            be returned. If not specified, the returned results
                            will include snapshots of all types.

Returns an array of VM::EC2:DB::Snapshot objects if any exist.

=cut

=head2 @snapshots = $ec2->describe_db_snapshots(%args)

All arguments are optional.

 -db_instance_identifier    A DB Instance Identifier to retrieve the list of DB
                            snapshots for. Cannot be used in conjunction with
                            -db_snapshot_identifier.
                            This parameter is not case sensitive.

 -db_snapshot_identifier    A specific DB Snapshot Identifier to describe.
                            Cannot be used in conjunction with .
                            This value is stored as a lowercase string.

 -snapshot_type             An optional snapshot type for which snapshots will
                            be returned. If not specified, the returned results
                            will include snapshots of all types.

Returns an array of VM::EC2:DB::Snapshot objects if any exist.

=cut

sub describe_db_snapshots {
    my $self = shift;
    my %args = @_;
    my $db_id = $args{-db_instance_identifier} || $args{-db_instance_id};
    my $snap_id = $args{-db_snapshot_identifier} || $args{-db_snap_id};
    $db_id && $snap_id and croak "describe_db_snapshots(): Specify only one of -db_instance_identifier or -db_snapshot_identifier";
    my @params;
    push @params, ('DBInstanceIdentifier'=>$db_id) if $db_id;
    push @params, ('DBSnapshotIdentifier'=>$snap_id) if $snap_id;
    push @params,$self->single_parm('SnapshotType',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBSnapshots',@params);
}

=head2 @groups = $ec2->describe_db_subnet_groups(-db_subnet_group_name => $name, -marker => $marker, -max_records => $integer)

All arguments are optional.

 -db_subnet_group_name      The name of the DB Subnet Group to describe.

 -marker                    An optional pagination token provided by a previous
                            request.  If specified, the response includes only
                            records after the marker, up to the value specified by
                            -max_records.

 -max_records               The maximum number of records to include in the
                            response.  If more records than the max exist,
                            a marker token is included in the response.

 -group_name                alias for -db_subnet_group_name

Returns an array of VM::EC2::DB::Subnet::Group objects if any exist.

=cut

sub describe_db_subnet_groups {
    my $self = shift;
    my %args = @_;
    my $group = $args{-db_subnet_group_name} || $args{-group_name};
    my @params;
    push @params, ('DBSubnetGroupName'=>$group) if $group;
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeDBSubnetGroups',@params);
}

=head2 @params = $ec2->describe_engine_default_parameters(%args)

Required arguments:

 -db_parameter_group_family    The name of the DB Parameter Group Family.

 -family                       Alias for -db_parameter_group_family

Returns an array of VM::EC2::DB::Parameter objects.

=cut

sub describe_engine_default_parameters {
    my $self = shift;
    my %args = @_;
    my $family = $args{-db_parameter_group_family} || $args{-family};
    $family or croak "describe_engine_default_parameters(): missing argument -db_parameter_group_family";
    my @params;
    push @params, ('DBParameterGroupFamily'=>$family);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeEngineDefaultParameters',@params);
}

=head2 @categories = $ec2->describe_event_categories(-source_type => $type)

Optional argument:

 -source_type         The type of source that will be generating the events.
                      Valid values: db-instance | db-parameter-group |
                       db-security-group | db-snapshot

Returns an array of VM::EC2::DB::Event::Category objects

=cut

sub describe_event_categories {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->single_parm('SourceType',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeEventCategories',@params);
}

=head2 @subs = $ec2->describe_event_subscriptions(-subscription_name => $name)

Optional argument:

 -subscription_name       The name of the RDS event notification subscription.

Returns an array of VM::EC2::DB::Event::Subscription object.

=cut

sub describe_event_subscriptions {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->single_parm('SubscriptionName',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeEventSubscriptions',@params);
}

=head2 @events = $ec2->describe_events(%args)

All arguments are optional but some conditions apply.

 -duration                The number of minutes to retrieve events for.

 -end_time                The end of the time interval for which to retrieve
                          events, specified in ISO 8601 format.
                          For more information on ISO 8601, visit:
                          http://en.wikipedia.org/wiki/ISO_8601

 -event_categories        A string or arrayref of event categories that trigger
                          notifications for a event notification subscription.

 -source_identifier       The identifier of the event source for which events
                          will be returned. If not specified, then all sources
                          are included in the response.

 -source_type             The event source to retrieve events for. If no value
                          is specified, all events are returned.
                          REQUIRED if -source_identifier is provided.

                          If 'DBInstance', then a DBInstanceIdentifier must be
                          supplied in -source_identifier.

                          If 'DBSecurityGroup', a DBSecurityGroupName must be
                          supplied in -source_identifier.

                          If 'DBParameterGroup', a DBParameterGroupName must be
                          supplied in -source_identifier.

                          If 'DBSnapshot', a DBSnapshotIdentifier must be
                          supplied in -source_identifier.

 -start_time              The beginning of the time interval to retrieve events
                          for, specified in ISO 8601 format.
                          For more information on ISO 8601, visit:
                          http://en.wikipedia.org/wiki/ISO_8601

Returns an array of VM::EC2::DB::Event objects.

=cut

sub describe_events {
    my $self = shift;
    my %args = @_;
    my @params;
    push @params,$self->single_parm($_,\%args) foreach qw(Duration EndTime SourceIdentifier SourceType StartTime);
    push @params,$self->member_list_parm('EventCategories',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeEvents',@params);
}

=head2 @options = $ec2->describe_option_group_options(-engine_name => $name, -major_engine_version => $version)

Describes all available options for a particular database engine.

Required arguments:

 -engine_name                 Database engine to describe options for.

Optional arguments:

 -major_engine_version        If specified, filters the results to include only
                              options for the specified major engine version.

Returns an array of VM::EC2::DB::Option::Group::Option objects.

=cut

sub describe_option_group_options {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-engine_name} or croak "describe_option_group_options(): Required argument -engine_name missing";
    push @params,$self->single_parm('EngineName',\%args);
    push @params,$self->single_parm('MajorEngineVersion',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeOptionGroupOptions',@params);
}

=head2 @groups = $ec2->describe_option_groups(-engine_name => $name, -major_engine_version => $version, -option_group_name => $og_name)

Describes the available option groups.

All arguments are optional.

 -engine_name                 Database engine to describe options for.

 -major_engine_version        If specified, filters the results to include only
                              options for the specified major engine version.

 -option_group_name           The name of the option group to describe. Cannot
                              be supplied together with -engine_name or
                              -major_engine_version.

Returns an array of VM::EC2::DB::Option::Group objects.

=cut

sub describe_option_groups {
    my $self = shift;
    my %args = @_;
    $args{-engine_name} && $args{-option_group_name} and
        croak "describe_option_groups(): Cannot specify -engine_name and -option_group_name together";
    $args{-major_engine_version} && $args{-option_group_name} and
        croak "describe_option_groups(): Cannot specify -major_engine_version and -option_group_name together";
    my @params;
    push @params,$self->single_parm('EngineName',\%args);
    push @params,$self->single_parm('MajorEngineVersion',\%args);
    push @params,$self->single_parm('OptionGroupName',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeOptionGroups',@params);
}

=head2 @options = $ec2->describe_orderable_db_instance_options(%args)

Describe the different RDS instances that can be launched.

Required arguments:

 -engine                 The name of the engine to retrieve DB Instance options
                         for.

Optional arguments:

 -db_instance_class      The DB Instance class (size) filter value.

 -engine_version         The engine version filter value.

 -license_model          The license model filter value.

 -vpc                    The VPC filter value. (boolean)

Returns an array of VM::EC2::DB::Instance::OrderableOption objects.

=cut

sub describe_orderable_db_instance_options {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-engine} or croak "describe_orderable_db_instance_options(): Required argument -engine missing";
    push @params,$self->single_parm($_,\%args)
        foreach qw(Engine DBInstanceClass EngineVersion LicenseModel);
    push @params,$self->boolean_parm('Vpc',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeOrderableDBInstanceOptions',@params);
}

=head2 @instances = $ec2->describe_reserved_db_instances(%args)

Returns information about reserved DB Instances for the account, or about a
specific reserved DB Instance.

All arguments are optional:

 -db_instance_class                     The DB Instance class (size) filter.

 -duration                              The duration filter value, specified in
                                        years or seconds.
                                        Valid values: 1 | 3 | 31536000 | 94608000

 -multi_az                              The Multi-AZ filter value. (boolean)

 -offering_type                         The offering type filter value.
                                        Valid Values: "Light Utilization" |
                                         "Medium Utilization" |
                                         "Heavy Utilization"

 -product_description                   The product description filter value.

 -reserved_db_instance_id               The reserved DB Instance identifier filter value.

 -reserved_db_instances_offering_id     The offering identifier filter value.

Returns an array of VM::EC2::DB::Reserved::Instance objects.

=cut

sub describe_reserved_db_instances {
    my $self = shift;
    my %args = @_;
    $args{-MultiAZ} = $args{-multi_az};
    my @params;
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBInstanceClass Duration OfferingType ProductDescription
                   ReservedDBInstanceId ReservedDBInstancesOfferingId);
    push @params,$self->boolean_parm('MultiAZ',\%args);
    push @params,$self->single_parm('Marker',\%args);
    push @params,$self->single_parm('MaxRecords',\%args);
    return $self->rds_call('DescribeReservedDBInstances',@params);
}

=head2 @offerings = $ec2->describe_reserved_db_instances_offerings(%args)

Lists available reserved DB Instance offerings.

All arguments are optional:

 -db_instance_class                     The DB Instance class (size) filter.

 -duration                              The duration filter value, specified in
                                        years or seconds.
                                        Valid values: 1 | 3 | 31536000 | 94608000

 -multi_az                              The Multi-AZ filter value. (boolean)

 -offering_type                         The offering type filter value.
                                        Valid Values: "Light Utilization" |
                                         "Medium Utilization" |
                                         "Heavy Utilization"

 -product_description                   The product description filter value.

 -reserved_db_instance_id               The reserved DB Instance identifier filter value.

 -reserved_db_instances_offering_id     The offering identifier filter value.

Returns an array of VM::EC2::DB::Reserved::Instance objects.

=cut

sub describe_reserved_db_instances_offerings {
    my $self = shift;
    my %args = @_;
    $args{-MultiAZ} = $args{-multi_az};
    my @params;
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBInstanceClass Duration OfferingType ProductDescription
                   ReservedDBInstanceId ReservedDBInstancesOfferingId Marker
                   MaxRecords);
    push @params,$self->boolean_parm('MultiAZ',\%args);
    return $self->rds_call('DescribeReservedDBInstancesOfferings',@params);
}

=head2 $log = $ec2->download_db_log_file_portion(%args)

Downloads the last line of the specified log file.

All arguments are optional:

 -db_instance_identifier                The DB Instance class (size) filter.

 -log_file_name                         The name of the log file to be downloaded.

 -marker                                The pagination token provided in the previous
                                        request. If this parameter is specified the
                                        response includes only records beyond the marker,
                                        up to MaxRecords.

 -number_of_lines                       The number of lines remaining to be downloaded.

Returns a L<VM::EC2::DB::LogFilePortion> object.

=cut

sub download_db_log_file_portion {
    my $self = shift;
    my %args = @_;
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    my @params;
    push @params,$self->single_parm($_,\%args)
       foreach qw(DBInstanceIdentifier LogFileName Marker NumberOfLines);
    return $self->rds_call('DownloadDBLogFilePortion',@params);
}

=head2 %tags = $ec2->list_tags_for_resource(-resource_name => $name)

Lists all tags on a DB Instance or Snapshot.

Arguments:

 -resource_name         The name of the resource to list tags for.

Returns a hash or hashref of tags.

=cut

sub list_tags_for_resource {
    my $self = shift;
    my %args = @_;
    my @params = $self->single_parm('ResourceName',\%args);
    return $self->rds_call('ListTagsForResource',@params);
}

=head2 $db_instance = $ec2->modify_db_instance(%args)

Modify settings for a DB Instance. You can change one or more database configuration
parameters by specifying these parameters and the new values in the request.

Required arguments:

 -db_instance_identifier               The DB Instance identifier.

Optional arguments:

 -allocated_storage                    The new storage capacity of the RDS instance. Changing this
                                       parameter does not result in an outage and the change is
                                       applied during the next maintenance window unless the
                                       -apply_immediately parameter is set to true for this request.
                                       MySQL:
                                        * Must be an integer from 5 to 1024.
                                        * Value supplied must be at least 10% greater than the
                                          current value. Values that are not at least 10% greater
                                          than the existing value are rounded up so that they are
                                          10% greater than the current value.
                                       Oracle:
                                        * Must be an integer from 10 to 1024.
                                        * Value supplied must be at least 10% greater than the
                                          current value. Values that are not at least 10% greater
                                          than the existing value are rounded up so that they are
                                          10% greater than the current value.
                                       SQL Server:
                                        * CANNOT BE MODIFIED

 -allow_major_version_upgrade          Indicates that major version upgrades are allowed. Changing
                                       this parameter does not result in an outage and the change is
                                       asynchronously applied as soon as possible.

                                       Constraints: This parameter must be set to true when
                                       specifying a value for the -engine_version argument that is
                                       a different major version than the DB Instance's current
                                       version.

 -apply_immediately                    Specifies whether or not the modifications in this request
                                       and any pending modifications are asynchronously applied as
                                       soon as possible, regardless of the
                                       -preferred_maintenance_window setting for the DB Instance.

                                       If this parameter is passed as false, changes to the DB
                                       Instance are applied on the next reboot_db_instance() call,
                                       the next maintenance reboot, or the next failure reboot,
                                       whichever occurs first. See each parameter to determine when
                                       a change is applied.  Default is false.

 -auto_minor_version_upgrade           Indicates that minor engine upgrades will be applied
                                       automatically to the DB Instance during the maintenance
                                       window.  Changing this parameter does not result in an outage
                                       except in the following case and the change is asynchronously
                                       applied as soon as possible. An outage will result if this
                                       parameter is set to true during the maintenance window, and a
                                       newer minor version is available, and RDS has enabled auto
                                       patching for that engine version.  (Boolean)

 -backup_retention_period              The number of days for which automated backups are retained.
                                       Setting this parameter to a positive number enables backups.
                                       Setting this parameter to 0 disables automated backups.
                                       Default: Existing setting
                                       Constraints:
                                        * Must be a value from 0 to 8
                                        * Cannot be set to 0 if the DB Instance is a master instance
                                          with read replicas

 -db_instance_class                    The new compute and memory capacity of the DB Instance.
                                       To determine the available classes, use the
                                       describe_orderable_db_instance_options() call.

                                       Passing a value for this parameter causes an outage during
                                       the change and is applied during the next maintenance window,
                                       unless the -apply_immediately argument is specified as true
                                       for this request.

                                       Valid values:
                                       db.t1.micro | db.m1.small | db.m1.medium | db.m1.large |
                                       db.m1.xlarge | db.m2.xlarge |db.m2.2xlarge | db.m2.4xlarge

 -db_parameter_group_name              The name of the DB Parameter Group to apply to this DB Instance.
                                       Changing this parameter does not result in an outage and the
                                       change is applied during the next maintenance window unless the
                                       -apply_immediately argument is set to true for this request.

                                       Default: Existing setting.

                                       Constraints:
                                       * Must be 1 to 255 alphanumeric characters
                                       * First character must be a letter.
                                       * Cannot end with a hyphen or contain two consecutive
                                         hyphens

 -db_security_groups                   An arrayref of DB Security Groups to authorize on this DB
                                       Instance.  Changing this parameter does not result in an outage
                                       and the change is asynchronously applied as soon as possible.

 -engine_version                       The version number of the database engine to upgrade to.
                                       Changing this parameter results in an outage and the change is
                                       applied during the next maintenance window unless the
                                       -apply_immediately parameter is set to true for this request.

                                       For major version upgrades, if a nondefault DB Parameter Group is
                                       currently in use, a new DB Parameter Group in the DB Parameter
                                       Group Family for the new engine version must be specified. The
                                       new DB Parameter Group can be the default for that DB Parameter
                                       Group Family.

 -iops                                 The new Provisioned IOPS (I/O operations per second) value for
                                       the RDS instance. Changing this parameter does not result in an
                                       outage and the change is applied during the next maintenance
                                       window unless the -apply_immediately argument is set to true for
                                       this request.

                                       Default: Existing setting.

                                       Constraints:
                                       * Value supplied must be at least 10% greater than the current
                                         value. Values that are not at least 10% greater than the
                                         existing value are rounded up so that they are 10% greater than
                                         the current value.

 -master_user_password                 The new password for the master database user. Can be any
                                       printable ASCII character except "/", "\", or "@".

                                       Changing this parameter does not result in an outage and the
                                       change is asynchronously applied as soon as possible. Between the
                                       time of the request and the completion of the request, the
                                       MasterUserPassword element exists in the PendingModifiedValues
                                       element of the operation response.

                                       Constraints:
                                        * MySQL:  Must contain from 8 to 41 alphanumeric characters.
                                        * Oracle: Must contain from 8 to 30 alphanumeric characters.
                                        * SQL Server: Must contain from 8 to 128 alphanumeric
                                          characters.

 -multi_az                             Specifies if the DB Instance is a Multi-AZ deployment.
                                       Changing this parameter does not result in an outage and the
                                       change is applied during the next maintenance window unless
                                       the -apply_immediately argument is set to true for this request.
                                       (Boolean)

                                       Constraints:
                                       * Cannot be specified if the DB Instance is a read replica.

 -new_db_instance_identifier           The new DB Instance identifier for the DB Instance when renaming
                                       a DB Instance. This value is stored as a lowercase string.

                                       Constraints:
                                        * Must contain from 1 to 63 alphanumeric characters or
                                          hyphens (1 to 15 for SQL Server).
                                        * First character must be a letter.
                                        * Cannot end with a hyphen or contain two consecutive
                                          hyphens.

 -option_group_name                    Indicates that the DB Instance should be associated
                                       with the specified option group.  Changing this parameter does
                                       not result in an outage except in the following case and the
                                       change is applied during the next maintenance window unless the
                                       -apply_immediately argument is set to true for this request. If
                                       the parameter change results in an option group that enables OEM,
                                       this change can cause a brief (sub-second) period during which
                                       new connections are rejected but existing connections are not
                                       interrupted.

                                       Note that persistent options, such as the TDE_SQLServer option for
                                       Microsoft SQL Server, cannot be removed from an option group while
                                       DB instances are associated with the option group. Permanent options,
                                       such as the TDE option for Oracle Advanced Security TDE, cannot be
                                       removed from an option group, and that option group cannot be removed
                                       from a DB instance once it is associated with a DB instance.

 -preferred_backup_window              The daily time range during which automated backups are
                                       created if automated backups are enabled using the
                                       -backup_retention_period argument.

                                       Default: Default: A 30-minute window selected at random
                                       from an 8-hour block of time per region. The following
                                       list shows the time blocks for each region from which
                                       the default backup windows are assigned.

                                       * US-East (Northern Virginia) Region: 03:00-11:00 UTC
                                       * US-West (N. California, Oregon) Region: 06:00-14:00 UTC
                                       * EU (Ireland) Region: 22:00-06:00 UTC
                                       * Asia Pacific (Singapore) Region: 14:00-22:00 UTC
                                       * Asia Pacific (Tokyo) Region: 17:00-03:00 UTC

                                       Constraints:
                                        * Must be in the format hh24:mi-hh24:mi
                                        * Times in Universal Time Coordinated (UTC).
                                        * Must not conflict with the preferred maintenance window.
                                        * Must be at least 30 minutes.

 -preferred_maintenance_window         The weekly time range (in UTC) during which system
                                       maintenance can occur.

                                       Format: ddd:hh24:mi-ddd:hh24:mi

                                       Default: A 30-minute window selected at random from an 8-hour
                                       block of time per region, occurring on a random day of the
                                       week. The following list shows the time blocks for each
                                       region from which the default maintenance windows are
                                       assigned.

                                       * US-East (Northern Virginia) Region: 03:00-11:00 UTC
                                       * US-West (N. California, Oregon) Region: 06:00-14:00 UTC
                                       * EU (Ireland) Region: 22:00-06:00 UTC
                                       * Asia Pacific (Singapore) Region: 14:00-22:00 UTC
                                       * Asia Pacific (Tokyo) Region: 17:00-03:00 UTC

                                       Valid Days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
                                       Constraints: Minimum 30-minute window.

 -vpc_security_group_ids               A list of EC2 VPC Security Groups to associate with this
                                       DB Instance.  This change is asynchronously applied as soon
                                       as possible.

This method returns a VM::EC2::DB:Instance object.

=cut

sub modify_db_instance {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_instance_identifier} or croak "modify_db_instance(): -db_instance_identifier required argument missing";
    $args{-MultiAZ} = $args{-multi_az};
    $args{-DBInstanceClass} = $args{-db_instance_class};
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    $args{-NewDBInstanceIdentifier} = $args{-new_db_instance_identifier};
    $args{-DBParameterGroupName} = $args{-db_parameter_group_name};
    $args{-DBSecurityGroups} = $args{-db_security_groups};
    push @params,$self->boolean_parm($_,\%args)
        foreach qw(AutoMinorVersionUpgrade MultiAZ PubliclyAccessible);
    push @params,$self->single_parm($_,\%args)
        foreach qw(AllocatedStorage AvailabilityZone BackupRetentionPeriod
                   CharacterSetName DBInstanceClass DBInstanceIdentifier
                   DBName DBParameterGroupName DBSubnetGroupName Engine
                   EngineVersion Iops LicenseModel MasterUserPassword
                   MasterUsername OptionGroupName Port PreferredBackupWindow
                   PreferredMaintenanceWindow);
    push @params,$self->member_list_parm($_,\%args)
        foreach qw(VpcSecurityGroupIds DBSecurityGroups);
    return $self->rds_call('CreateDBInstance',@params);
}

=head2 $group_name = $ec2->modify_db_parameter_group(-db_parameter_group_name => $group, -parameters => \@parms)

Modifies the parameters of a DB Parameter Group.

Note: The immediate method can be used only for dynamic parameters; the pending-reboot method
can be used with MySQL and Oracle DB Instances for either dynamic or static parameters. For 
Microsoft SQL Server DB Instances, the pending-reboot method can be used only for static 
parameters.

Required arguments:

 -db_parameter_group_name             The name of the DB Parameter Group.
                                      Constraints:
                                      * Must be the name of an existing DB Parameter Group
                                      * Must be 1 to 255 alphanumeric characters
                                      * First character must be a letter
                                      * Cannot end with a hyphen or contain two consecutive hyphens

 -parameters                          An arrayref of hashes containing parameter names, values,
                                      and the apply method for the parameter update. At least one
                                      parameter name, value, and apply method must be supplied;
                                      subsequent arguments are optional. A maximum of 20 parameters
                                      may be modified in a single request.

                                      The hash keys must be: ParameterName, ParameterValue, ApplyMethod

Returns the DB Parameter Group name on success.

=cut

sub modify_db_parameter_group {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_parameter_group_name} or croak "modify_db_parameter_group(): -db_parameter_group_name required argument missing";
    $args{-parameters} or croak "modify_db_parameter_group(): -parameters required argument missing";
    $args{-DBParameterGroupName} = $args{-db_parameter_group_name};
    push @params, $self->single_parm('DBParameterGroupName',\%args);
    push @params, $self->member_hash_parms('Parameters',\%args);
    return $self->rds_call('ModifyDBParameterGroup',@params);
}

=head2 $subnet_group = $ec2->modify_db_subnet_group(%args)

Modifies an existing DB subnet group. DB subnet groups must contain at least one subnet in at 
least two AZs in the region.

Required arguments:

 -db_subnet_group_name                The name for the DB Subnet Group.

 -subnet_ids                          An arrayref of EC2 Subnet IDs for the DB Subnet Group.

Optional arguments:

 -db_subnet_group_description         The description for the DB Subnet Group.

Returns L<VM::EC2::DB::Subnet::Group> object on success.

=cut

sub modify_db_subnet_group {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_subnet_group_name} or croak "modify_db_subnet_group(): -db_subnet_group_name required argument missing";
    $args{-subnet_ids} or croak "modify_db_subnet_group(): -subnet_ids required argument missing";
    ref $args{-subnet_ids} eq 'ARRAY' or croak "modify_db_subnet_group(): -subnet_ids must be an arrayref";
    ref $args{-subnet_ids} eq 'ARRAY' or croak "modify_db_subnet_group(): -subnet_ids must be an arrayref";
    $args{-DBSubnetGroupName} = $args{-db_subnet_group_name};
    push @params, $self->single_parm('DBSubnetGroupName',\%args);
    push @params, $self->single_parm('DBSubnetGroupDescription',\%args);
    push @params, $self->member_list_parm('SubnetIds',\%args);
    return $self->rds_call('ModifyDBSubnetGroup',@params);
}

=head2 $event_sub = $ec2->modify_event_subscription(%args)

Modifies an existing RDS event notification subscription. Note that you cannot modify the source 
identifiers using this call; to change source identifiers for a subscription, use the 
add_source_identifier_to_subscription() and remove_source_identifier_from_subscription() calls.

Required arguments:

 -subscription_name                   The name of the RDS event notification subscription.

Optional arguments:

 -enabled                             Boolean value; set to true to activate the subscription.

 -event_categories                    An arrayref of event categories for a -source_type to
                                      subscribe to.  A list of the categories for a given
                                      -source_type can be seen in the Events topic in the Amazon
                                      RDS User Guide or by using the describe_event_categories()
                                      call.

 -sns_topic_arn                       The Amazon Resource Name (ARN) of the SNS topic created for 
                                      event notification. The ARN is created by Amazon SNS when 
                                      a topic is created and subscribed to.

 -source_type                         The type of source that will be generating the events.
                                      For example, to be notified of events generated by a DB
                                      instance, set this parameter to db-instance. if this value is
                                      not specified, all events are returned.

                                      Valid values: db-instance | db-parameter-group | 
                                                    db-security-group | db-snapshot

Returns a L<VM::EC2::DB::Event::Subscription> object on success.

=cut

sub modify_event_subscription {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-subscription_name} or croak "modify_event_subscription(): -subscription_name required argument missing";
    push @params, $self->boolean_parm('Enabled',\%args);
    push @params, $self->member_list_parm('EventCategories',\%args);
    push @params,$self->single_parm($_,\%args)
        foreach qw(SnsTopicArn SourceType SubscriptionName);
    return $self->rds_call('ModifyEventSubscription',@params);
 }

=head2 $option_group = $ec2->modify_option_group(%args)

Modifies an existing Option Group.

Note that persistent options, such as the TDE_SQLServer option for Microsoft SQL Server, cannot be
removed from an option group while DB instances are associated with the option group. Permanent
options, such as the TDE option for Oracle Advanced Security TDE, cannot be removed from an option
group, and that option group cannot be removed from a DB instance once it is associated with a DB
instance.

Required arguments:

 -option_group_name                   The name of the option group to be modified.

Optional arguments:

 -apply_immediately                   Indicates whether the changes should be applied immediately,
                                      or during the next maintenance window for each instance
                                      associated with the Option Group. (Boolean)

 -options_to_include                  Arrayref of options 

 -options_to_remove

=cut

sub modify_option_group {
}

=head2 $db_instance = $ec2->promote_read_replica(%args)

Promotes a Read Replica DB Instance to a standalone DB Instance.

Required arguments:

 -db_instance_identifier              The DB Instance identifier. This value is stored as a
                                      lowercase string.

                                      Constraints:
                                      * Must be the identifier for an existing Read Replica DB
                                        Instance
                                      * Must contain from 1 to 63 alphanumeric characters or
                                        hyphens
                                      * First character must be a letter
                                      * Cannot end with a hyphen or contain two consecutive hyphens

Optional arguments:

 -backup_retention_period             The daily time range during which automated backups are
                                      created if automated backups are enabled.

 -preferred_backup_window             The daily time range during which automated backups are
                                      created if automated backups are enabled using the
                                      -backup_retention_period argument.

                                      Default: Default: A 30-minute window selected at random
                                      from an 8-hour block of time per region. The following
                                      list shows the time blocks for each region from which
                                      the default backup windows are assigned.

                                      * US-East (Northern Virginia) Region: 03:00-11:00 UTC
                                      * US-West (N. California, Oregon) Region: 06:00-14:00 UTC
                                      * EU (Ireland) Region: 22:00-06:00 UTC
                                      * Asia Pacific (Singapore) Region: 14:00-22:00 UTC
                                      * Asia Pacific (Tokyo) Region: 17:00-03:00 UTC

                                      Constraints:
                                       * Must be in the format hh24:mi-hh24:mi
                                       * Times in Universal Time Coordinated (UTC).
                                       * Must not conflict with the preferred maintenance window.
                                       * Must be at least 30 minutes.


Returns a L<VM::EC2::DB::Instance> object on success.

=cut

sub promote_read_replica {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_instance_identifier} or croak "promote_read_replica(): -db_instance_identifier required argument missing";
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    push @params,$self->single_parm($_,\%args)
        foreach qw(BackupRetentionPeriod DBInstanceIdentifier PreferredBackupWindow);
    return $self->rds_call('PromoteReadReplica',@params);
}

=head2 $reserved_db = $ec2->purchase_reserved_db_instances_offering(%args)

Purchases a reserved DB Instance offering.

Required arguments:

 -reserved_db_instances_offering_id   The ID of the Reserved DB Instance offering to purchase.
                                      ie: 438012d3-4052-4cc7-b2e3-8d3372e0e706

Optional arguments:

 -db_instance_count                   The number of instances to reserve.  Default: 1

 -reserved_db_instance_id             Customer-specified identifier to track this reservation.
                                      ie: myreservationID

Returns a L<VM::EC2::DB::Reserved::Instance> object on success.

=cut

sub purchase_reserved_db_instances_offering {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-reserved_db_instances_offering_id} or
        croak "purchase_reserved_db_instances_offering(): -reserved_db_instances_offering_id required argument missing";
    $args{-ReservedDBInstancesOfferingId} = $args{-reserved_db_instances_offering_id};
    $args{-ReservedDBInstanceId} = $args{-reserved_db_instance_id};
    $args{-DBInstanceCount} = $args{-db_instance_count};
    push @params,$self->single_parm($_,\%args)
        foreach qw(DBInstanceCount ReservedDBInstanceId ReservedDBInstancesOfferingId);
    return $self->rds_call('PurchaseReservedDBInstancesOffering',@params);
}

=head2 $db_instance = $ec2->reboot_db_instance(-db_instance_identifier => $id, -force_failover => $boolean)

Reboots a previously provisioned RDS instance. This API results in the application of modified
DBParameterGroup parameters with ApplyStatus of pending-reboot to the RDS instance. This action
is taken as soon as possible, and results in a momentary outage to the RDS instance during which
the RDS instance status is set to rebooting. If the RDS instance is configured for MultiAZ, it is
possible that the reboot will be conducted through a failover. A DBInstance event is created when
the reboot is completed.

Required arguments:

 -db_instance_identifier              The DB Instance identifier. 

Optional arguments:

 -force_failover                      When true, the reboot will be conducted through a MultiAZ
                                      failover.

                                      Constraints:
                                      * You cannot specify true if the instance is not configured
                                        for MultiAZ.

Returns a L<VM::EC2::DB::Instance> object on success.

=cut

sub reboot_db_instance {
    my $self = shift;
    my %args = @_;
    my @params;
    $args{-db_instance_identifier} or
        croak "reboot_db_instance(): -db_instance_identifier required argument missing";
    $args{-DBInstanceIdentifier} = $args{-db_instance_identifier};
    push @params,$self->single_parm('DBInstanceIdentifier',\%args);
    push @params,$self->boolean_parm('ForceFailover',\%args);
    return $self->rds_call('RebootDBInstance',@params);
}

=head1 AUTHOR

Lance Kinley E<lt>lkinley@loyaltymethods.com<gt>.

Copyright (c) 2013 Loyalty Methods, Inc.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;
