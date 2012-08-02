#!/bin/bash
#
# Script to install mailman

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="community"                 # arbitrary name 
WALRUS_IP="173.205.188.8"               # IP of the walrus to use
WALRUS_ID="xxxxxxxxxxxxxxxxxxxxx"       # EC2_ACCESS_KEY
WALRUS_KEY="xxxxxxxxxxxxxxxxxxx"        # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/mailman"	# conf bucket
WALRUS_MASTER="mailman-archive.tgz"	# master copy of the database

# mailman related configuration
MAILNAME="lists.eucalyptus.com"         # the public hostname
POSTMASTER="community@eucalyptus.com"   # email to receive exim errors
MOUNT_POINT="/mailman"                  # archives and data are on ephemeral

# do backup on walrus?
WALRUS_BACKUP="Y"

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

# update the instance
echo "Upgrading and installing packages"
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# make sure the mailname is correct
echo "Setting hostname and mailname to ${MAILNAME}"
echo "${MAILNAME}" > /etc/mailname
echo "${MAILNAME}" > /etc/hostname
hostname ${MAILNAME}
LOCALIP="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/local-ipv4`"
echo "${LOCALIP}      ${MAILNAME}" >> /etc/hosts

# mailman and exim requires some preseed to prevent questions
echo "Preseeding debconf for mailman and exim"
cat >/root/preseed.cfg <<EOF
exim4-config    exim4/dc_other_hostnames        string  
exim4-config    exim4/dc_eximconfig_configtype  select  internet site; mail is sent and received directly using SMTP
exim4-config    exim4/no_config boolean true
exim4-config    exim4/hide_mailname     boolean 
exim4-config    exim4/dc_postmaster     string  ${POSTMASTER}
exim4-config    exim4/dc_smarthost      string  
exim4-config    exim4/dc_relay_domains  string  
exim4-config    exim4/dc_relay_nets     string  
exim4-base      exim4/purge_spool       boolean false
exim4-config    exim4/mailname  string  ${MAILNAME}
exim4-config    exim4/dc_readhost       string  
# Reconfigure exim4-config instead of this package
exim4-config    exim4/use_split_config  boolean false
exim4-config    exim4/dc_localdelivery  select  mbox format in /var/mail/
exim4-config    exim4/dc_local_interfaces       string  
exim4-config    exim4/dc_minimaldns     boolean false

mailman mailman/gate_news       boolean false
mailman mailman/site_languages  multiselect     en
mailman mailman/queue_files_present     select  abort installation
mailman mailman/used_languages  string  
mailman mailman/default_server_language select  en
mailman mailman/create_site_list        note    
EOF
debconf-set-selections /root/preseed.cfg
rm -f /root/preseed.cfg

# install mailman
echo "Installing mailman"
apt-get install --force-yes -y mailman ntp ntpdate

# just sync the date first
ntpdate -s

# let's make sure we have the mountpoint
echo "Creating and prepping ${MOUNT_POINT}"
mkdir -p ${MOUNT_POINT}

# don't mount ${MOUNT_POINT} more than once (mainly for debugging)
if ! mount |grep ${MOUNT_POINT}; then
        # let's see where ephemeral is mounted, and either mount
        # it in the final place (${MOUNT_POINT}) or mount -o bind
        EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
        if [ -z "${EPHEMERAL}" ]; then
                # workaround for a bug in EEE 2
                EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
        fi
        if [ -z "${EPHEMERAL}" ]; then
                echo "Cannot find ephemeral partition!"
                exit 1
        else
                # let's see if it is mounted
                if ! mount | grep ${EPHEMERAL} ; then
                        mount /dev/${EPHEMERAL} ${MOUNT_POINT}
                else
                        mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` ${MOUNT_POINT}
                fi
        fi
fi

# now let's get the exim configured
echo "Creating exim4 configuration"
cat >/etc/exim4/update-exim4.conf.conf <<EOF
# This is a Debian specific file

dc_eximconfig_configtype='internet'
dc_other_hostnames=''
dc_local_interfaces=''
dc_readhost=''
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost=''
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname=''
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF
cat >/etc/exim4/exim4.conf.localmacros <<EOF
SYSTEM_ALIASES_USER = list
SYSTEM_ALIASES_PIPE_TRANSPORT = address_pipe
EOF

# regenerate config and restart service
service exim4 stop
# there seems to be a bug for which exim is not properly stopped
killall exim4
rm /var/log/exim4/paniclog
update-exim4.conf
service exim4 start

# let's setup apache's configuration
echo "Configuring apache"
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/lists > /etc/apache2/sites-available/lists
if [ "`head -c 4 /etc/apache2/sites-available/lists`" = "<Err" -o "`head -c 4 /etc/apache2/sites-available/lists`" = "Fail" ]; then
        echo "Couldn't get apache configuration!"
        exit 1
fi
a2dissite default
a2ensite lists
a2enmod rewrite
service apache2 restart

# now let's get the archives from the walrus bucket
service mailman stop
echo "Retrieving mailman archives and configuration"
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > /${MOUNT_POINT}/master_copy.tgz
mkdir /${MOUNT_POINT}/mailman
if [ "`head -c 4 /${MOUNT_POINT}/master_copy.tgz`" = "<Err" -o "`head -c 4 /${MOUNT_POINT}/master_copy.tgz`" = "Fail"  ]; then
        echo "Couldn't get archives!"
        exit 1
else
        tar -C /${MOUNT_POINT}/mailman -xzf /${MOUNT_POINT}/master_copy.tgz
        mv /var/lib/mailman /var/lib/mailman.orig
        ln -s /${MOUNT_POINT}/mailman /var/lib/mailman
fi

# and the aliases
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/aliases > /${MOUNT_POINT}/aliases
if [ "`head -c 4 /${MOUNT_POINT}/aliases`" = "<Err" -o "`head -c 4 /${MOUNT_POINT}/aliases`" = "Fail" ]; then
        echo "Couldn't get aliases!"
        exit 1
else
        mv /etc/aliases /etc/aliases.orig
        cp /${MOUNT_POINT}/aliases /etc/aliases
        newaliases
fi
service mailman start

# set up a cron-job to save the archives and config to a bucket: it will
# run as root
echo "Preparing local script to push backups to walrus"
cat >/usr/local/bin/mailman_backup.sh <<EOF
#!/bin/sh
tar -C /var/lib/mailman -czf /${MOUNT_POINT}/archive.tgz . 
# check the bucket exists
if ${S3CURL} --id ${WALRUS_NAME} -- ${WALRUS_URL}/${WALRUS_MASTER}|grep NoSuchBucket ; then
        echo
        echo "${WALRUS_URL}/${WALRUS_MASTER} does not exist: you need to"
        echo "create it to have backups."
        echo
        exit 1
fi
# keep one copy per day of the month
if ${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month | grep -v ETag ; then
        echo 
        echo "Failed to upload to walrus!"
        exit 1
fi
# and push it to be the latest backup too for easy recovery
if ${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER} |grep -v ETag; then 
        echo 
        echo "Failed to upload to walrus!"
        exit 1
fi
# and save the aliases too
if ${S3CURL} --id ${WALRUS_NAME} --put /etc/aliases -- -s ${WALRUS_URL}/aliases |grep -v ETag; then
        echo 
        echo "Failed to upload to walrus!"
        exit 1
fi
# finally the apache config file
if ${S3CURL} --id ${WALRUS_NAME} --put /etc/apache2/sites-available/lists -- -s ${WALRUS_URL}/lists |grep -v ETag; then
        echo 
        echo "Failed to upload to walrus!"
        exit 1
fi
rm /${MOUNT_POINT}/archive.tgz
EOF
# substitute to get the day of month
sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/mailman_backup.sh

# change execute permissions and ownership
chmod +x /usr/local/bin/mailman_backup.sh

if [ "$WALRUS_BACKUP" != "Y" ]; then
	# we are done here
	exit 0
fi

# and turn it into a cronjob to run every hour
echo "Setting up cron-job"
cat >/tmp/crontab <<EOF
30 * * * * /usr/local/bin/mailman_backup.sh
EOF
crontab /tmp/crontab

