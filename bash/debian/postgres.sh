#!/bin/bash
#
# Script to install postgres, and make it point to a volume (sdb) where
# the database resides. The assumption is to have a Debian installation,
# thus we'll look for Debian's style configuration and modify it
# accordingly. 

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="my_walrus"                 # arbitrary name 
WALRUS_IP="173.205.188.8"               # IP of the walrus to use
WALRUS_ID="xxxxxxxxxxxxxxxxxxxxx"       # EC2_ACCESS_KEY
WALRUS_KEY="xxxxxxxxxxxxxxxxxxx"        # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/postgres"	# conf bucket
WALRUS_MASTER="backup"			# master copy of the database

# do backup on walrus?
WALRUS_BACKUP="Y"

# use MOUNT_DEV to wait for an EBS volume, otherwise we'll be using
# ephemeral: WARNING when using ephemeral you may be loosing data uping
# instance termination
#MOUNT_DEV="/dev/sdb"		# EBS device
MOUNT_DEV=""			# use ephemeral
PG_VERSION="8.4"

# where are the important directory/data
CONF_DIR="/etc/postgresql/$PG_VERSION/main/"
DATA_DIR="/var/lib/postgresql/$PG_VERSION/"
MOUNT_POINT="/postgres"

# user to use when working with the database
USER="postgres"

# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
echo "Getting ${S3CURL}"
curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
chmod 755 ${S3CURL}

# now let's setup the id for accessing walrus
echo "Setting credentials for ${S3CURL}"
cat >${HOME}/.s3curl <<EOF
%awsSecretAccessKeys = (
	${WALRUS_NAME} => {
		url => '${WALRUS_IP}',
		id => '${WALRUS_ID}',
		key => '${WALRUS_KEY}',
	},
);
EOF
chmod 600 ${HOME}/.s3curl

# let's make sure we have the mountpoint
echo "Creating and prepping $MOUNT_POINT"
mkdir -p $MOUNT_POINT

# are we using ephemeral or EBS?
if [ -z "$MOUNT_DEV" ]; then
	# don't mount $MOUNT_POINT more than once (mainly for debugging)
	if ! mount |grep $MOUNT_POINT; then
		# let's see where ephemeral is mounted, and either mount
		# it in the final place ($MOUNT_POINT) or mount -o bind
		EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
		if [ -z "${EPHEMERAL}" ]; then
			# workaround for a bug in EEE 2
			EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
		fi
		if [ -z "${EPHEMERAL}" ]; then
			echo "Cannot find ephemeral partition!"
			exit 1
		else
			# let's see if it is mounted
			if ! mount | grep ${EPHEMERAL} ; then
				mount /dev/${EPHEMERAL} $MOUNT_POINT
			else
				mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` $MOUNT_POINT
			fi
		fi
	fi
else
	# wait for the EBS volume and mount it
	while ! mount $MOUNT_DEV $MOUNT_POINT ; do
		echo "waiting for EBS volume ($MOUNT_DEV) ..."
		sleep 10
	done

	# if there is already a database ($MOUNT_POINT/main) in the volume
	# we'll use it, otherwise we will recover from walrus
fi

# update the instance
echo "Upgrading and installing packages"
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# install postgres
apt-get install --force-yes -y postgresql libdigest-hmac-perl

# stop the database
echo "Setting up postgres"
/etc/init.d/postgresql stop

# change where the data directory is and listen to all interfaces
sed -i "1,$ s;^\(data_directory\).*;\1 = '$MOUNT_POINT/main';" $CONF_DIR/postgresql.conf
sed -i "1,$ s;^#\(listen_addresses\).*;\1 = '*';" $CONF_DIR/postgresql.conf

# we need to set postgres to trust access from the network: euca-authorize
# will do the rest
cat >>$CONF_DIR/pg_hba.conf <<EOF
# trust everyone: the user will set the firewall via ec2-authorize
hostssl all         all         0.0.0.0/0             md5
EOF

# let's make sure $USER can write in the right place
chown ${USER} $MOUNT_POINT

# now let's see if we have an already existing database on the target
# directory
if [ ! -d $MOUNT_POINT/main ]; then
	# nope: let's recover from the bucket: let's get the default
	# structure in
	(cd $DATA_DIR; tar czf - *)|(cd $MOUNT_POINT; tar xzf -)

	# start the database
	/etc/init.d/postgresql start

	# and recover from bucket
	${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > $MOUNT_POINT/$WALRUS_MASTER
	# check for error
	if [ "`head -c 6 $MOUNT_POINT/$WALRUS_MASTER`" = "<Error" ]; then
		echo "Cannot get backup!"
		echo "Database is empty: disabling auto-backup."
		WALRUS_BACKUP="N"
	else 
		chown ${USER} $MOUNT_POINT/$WALRUS_MASTER
		chmod 600 $MOUNT_POINT/$WALRUS_MASTER
		su - -c "psql -f $MOUNT_POINT/$WALRUS_MASTER postgres" postgres
		rm $MOUNT_POINT/$WALRUS_MASTER
	fi
else
	# database is in place: just start 
	/etc/init.d/postgresql start
fi

# set up a cron-job to save the database to a bucket: it will run as root
cat >/usr/local/bin/pg_backup.sh <<EOF
#!/bin/sh
su - -c "pg_dumpall > $MOUNT_POINT/$WALRUS_MASTER" ${USER}
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put $MOUNT_POINT/$WALRUS_MASTER -- -s ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put $MOUNT_POINT/$WALRUS_MASTER -- -s ${WALRUS_URL}/${WALRUS_MASTER}
rm $MOUNT_POINT/$WALRUS_MASTER
EOF
# substitute to get the day of month
sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/pg_backup.sh

# change execute permissions and ownership
chmod +x /usr/local/bin/pg_backup.sh

if [ "$WALRUS_BACKUP" != "Y" ]; then
	# we are done here
	exit 0
fi

# and turn it into a cronjob to run every hour
cat >/tmp/crontab <<EOF
30 * * * * /usr/local/bin/pg_backup.sh
EOF
crontab /tmp/crontab

