#!/bin/bash
#
# Script to install freeradius2 server configured for PEAP/MSCHAPv2/OpenLDAP.  Intended to be used with CentOS 5.x instances.

# Basic variables that should be used with this script
HOST="radius.mydomain.com"
SHORT_HOST=`echo ${HOSTNAME} | cut -d'.' -f1`

# Do basic setup on the instance.
hostname $HOST
sed -ie 's/localhost.localdomain/${HOST} ${SHORT_HOST} localhost.localdomain/g' /etc/hosts

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="radiuss3id" # arbitrary name
WALRUS_IP="10.1.2.3" # IP of the walrus to use
WALRUS_ID="abcdefghijklmnopqrstuvwxyz1234567890ABCD" # EC2_ACCESS_KEY
WALRUS_KEY="abcdefghijklmnopqrstuvwxyz1234567890ABCD" # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/radius" # conf bucket
WALRUS_MASTER="archive.tgz" # backup copy of all radius data

# installation log file location
LOGFILE="/var/log/radius-install.log"

# yum related configuration
# if you have internal mirrors for your cloud, enter them below, otherwise
# leave these commented to use the stock yum configuration for your instance
YUM_CENTOS_BASE_URL='http://10.1.2.3/centos/$releasever/os/$basearch/'
YUM_CENTOS_UPDATES_URL='http://10.1.2.3/centos/$releasever/updates/$basearch/'
YUM_CENTOS_EXTRAS_URL='http://10.1.2.3/centos/$releasever/extras/$basearch/'
YUM_CENTOS_CENTOSPLUS_URL='http://10.1.2.3/centos/$releasever/centosplus/$basearch/'
YUM_CENTOS_CONTRIB_URL='http://10.1.2.3/centos/$releasever/contrib/$basearch/'
EPEL_PACKAGE_URL='http://10.1.2.3/epel/5/x86_64/epel-release-5-4.noarch.rpm'
YUM_EPEL_URL='http://10.1.2.3/epel/5/$basearch'
YUM_EPEL_DEBUGINFO_URL='http://10.1.2.3/epel/5/$basearch/debug'
YUM_EPEL_SOURCE_URL='http://10.1.2.3/epel/5/SRPMS'

# radius related configuration
MOUNT_POINT="/srv/radius" # archives and data are on ephemeral

# do backup on walrus?
WALRUS_BACKUP="Y"

# Modifications below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
if [ ! -f ${S3CURL} ] ; then
  echo "$(date) - Getting ${S3CURL}" | tee -a $LOGFILE
  curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
  chmod 755 ${S3CURL}
else
  echo "$(date) - ${S3CURL} already present" | tee -a $LOGFILE
fi

# now let's setup the id for accessing walrus
if [ "$HOME" = "/" ] ; then
  HOME="/root"
  echo "$(date) - Set HOME to ${HOME}" | tee -a $LOGFILE
fi
if [ ! -f ${HOME}/.s3curl ] ; then
  echo "$(date) - Setting credentials for ${S3CURL}" | tee -a $LOGFILE
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
else
  echo "$(date) - Credentials already set for ${S3CURL}" | tee -a $LOGFILE
fi

# customize yum configuration if applicable
echo "$(date) - Customizing yum repositories" | tee -a $LOGFILE
if [ $YUM_CENTOS_BASE_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/os/\$basearch/%baseurl=$YUM_CENTOS_BASE_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ $YUM_CENTOS_UPDATES_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/updates/\$basearch/%baseurl=$YUM_CENTOS_UPDATES_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ $YUM_CENTOS_EXTRAS_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/extras/\$basearch/%baseurl=$YUM_CENTOS_EXTRAS_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ $YUM_CENTOS_CENTOSPLUS_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/centosplus/\$basearch/%baseurl=$YUM_CENTOS_CENTOSPLUS_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ $YUM_CENTOS_CONTRIB_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=contrib%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/contrib/\$basearch/%baseurl=$YUM_CENTOS_CONTRIB_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi

# install/customize EPEL repository
rpm -q epel-release > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing EPEL package" | tee -a $LOGFILE
  if [ ! $EPEL_PACKAGE_URL ] ; then
    EPEL_PACKAGE_URL='http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm'
  fi
  wget $EPEL_PACKAGE_URL
  rpm -Uvh epel-release-*.noarch.rpm
else
  echo "$(date) - EPEL package already installed" | tee -a $LOGFILE
fi

if [ $YUM_EPEL_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-debug-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e "s%#baseurl=http://download.fedoraproject.org/pub/epel/5/\$basearch%baseurl=$YUM_EPEL_URL%g" /etc/yum.repos.d/epel.repo
fi

if [ $YUM_EPEL_SOURCE_URL ] ; then
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-source-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e "s%#baseurl=http://download.fedoraproject.org/pub/epel/5/SRPMS%baseurl=$YUM_EPEL_SOURCE_URL%g" /etc/yum.repos.d/epel.repo
fi

# update the instance
yum check-update > /dev/null
if [ $? -eq 100 ] ; then
  echo "$(date) - Upgrading and installing packages" | tee -a $LOGFILE
  yum -y update
  echo "$(date) - Packages updated.  Rebooting" | tee -a $LOGFILE
  shutdown -r now
  exit 0
else
  echo "$(date) - No package updates" | tee -a $LOGFILE
fi

# install NTP, set the time, and enable the service
rpm -q ntp > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing and configuring NTP" | tee -a $LOGFILE
  yum -y install ntp
  /sbin/ntpd -q -g
  chkconfig ntpd on
  service ntpd start
else
  echo "$(date) - NTP package already installed" | tee -a $LOGFILE
fi

# let's make sure we have the mountpoint
echo "$(date) - Creating and prepping ${MOUNT_POINT}" | tee -a $LOGFILE
mkdir -p ${MOUNT_POINT}

# don't mount ${MOUNT_POINT} more than once (mainly for debugging)
if ! mount |grep ${MOUNT_POINT} > /dev/null ; then
  # let's see where ephemeral is mounted, and either mount
  # it in the final place (${MOUNT_POINT}) or mount -o bind
  EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
  if [ -z "${EPHEMERAL}" ]; then
    # workaround for a bug in EEE 2
    EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
  fi
  if [ -z "${EPHEMERAL}" ]; then
    echo "$(date) - Cannot find ephemeral partition!" | tee -a $LOGFILE
    exit 1
  else
    echo "$(date) - Ephemeral partition located at ${EPHEMERAL}" | tee -a $LOGFILE
    # let's see if it is mounted
    if ! mount | grep ${EPHEMERAL} ; then
      mount /dev/${EPHEMERAL} ${MOUNT_POINT}
      echo "$(date) - Mounted /dev/${EPHEMERAL} at ${MOUNT_POINT}" | tee -a $LOGFILE
    else
      mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` ${MOUNT_POINT}
      echo "$(date) - Bound ${EPHEMERAL} mount to ${MOUNT_POINT}" | tee -a $LOGFILE
    fi
  fi
else
  echo "$(date) - ${MOUNT_POINT} already mounted" | tee -a $LOGFILE
fi

# install freeradius2, freeradius2-ldap, freeradius2-utils, vixie-cron and other dependencies
rpm -q freeradius2 > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing freeradius2, freeradius2-ldap, freeradius2-utils and other dependencies" | tee -a $LOGFILE
  yum -y install freeradius2 freeradius2-ldap freeradius2-utils vixie-cron perl-Digest-HMAC
fi

# now let's get the archives from the walrus bucket
echo "$(date) - Retrieving radius archives" | tee -a $LOGFILE
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > ${MOUNT_POINT}/archive.tgz
if [ "`head -c 4 ${MOUNT_POINT}/archive.tgz`" = "<Err" ]; then
  echo "$(date) - Couldn't get archives!" | tee -a $LOGFILE
  echo "$(date) - Will start with default radius configuration." | tee -a $LOGFILE
  rm -f ${MOUNT_POINT}/archive.tgz
else
  mkdir -p ${MOUNT_POINT}/archive
  tar -C ${MOUNT_POINT}/archive/ -xzf ${MOUNT_POINT}/archive.tgz
  echo "$(date) - Extracted archive.tgz" | tee -a $LOGFILE
fi
if [ -d ${MOUNT_POINT}/archive/raddb ] ; then
  rm -rf /etc/raddb
  cp -a ${MOUNT_POINT}/archive/raddb /etc/
  echo "$(date) - Restored /etc/raddb" | tee -a $LOGFILE
fi

# start radiusd for the first time to generate certificates if they don't exist
if [ ! -f /etc/raddb/certs/server.crt ] ; then
  radiusd -X 2>&1 >> $LOGFILE &
  grep 'Ready to process requests' $LOGFILE
  while [ $? -ne 0 ]
  do
    echo "Waiting for radius server to finish starting" | tee -a $LOGFILE
    sleep 5
    grep 'Ready to process requests' $LOGFILE
  done
  RADIUSPID=`ps -ef | grep [r]adiusd | awk '{print $2}'`
  echo "Killing radiusd process $RADIUSPID" | tee -a $LOGFILE
  kill $RADIUSPID
  sleep 5
  ps -efl | grep [r]adius | tee -a $LOGFILE
fi

# enable the radiusd and crond service and start them
chkconfig radiusd on
chkconfig crond on
if [ ! -f /var/run/radiusd/radiusd.pid ] ; then
  service radiusd start
else
  service radiusd restart
fi
if [ ! -f /var/run/crond.pid ] ; then
  service crond start
else
  service crond restart
fi

# clean out the accounting records regularly
cat > /etc/cron.daily/radiusacctcleanup <<EOF
#!/bin/bash
find /var/log/radius/radacct -type f -mtime +7 | xargs rm -f {}
EOF
chmod +x /etc/cron.daily/radiusacctcleanup

if [ "$WALRUS_BACKUP" != "Y" ]; then
# we are done here
exit 0
fi

# set up a cron-job to save the configuration files in a bucket
if [ ! -f /usr/local/bin/radius_backup.sh ] ; then
  echo "$(date) - Preparing local script to push backups to walrus" | tee -a $LOGFILE
  cat >/usr/local/bin/radius_backup.sh <<EOF
#!/bin/sh
if [ ! -d ${MOUNT_POINT}/archive ] ; then
  mkdir -p ${MOUNT_POINT}/archive
fi
cp -a /etc/raddb ${MOUNT_POINT}/archive/
if [ -f ${MOUNT_POINT}/archive.tgz ] ; then
  rm -f ${MOUNT_POINT}/archive.tgz
fi
tar -C ${MOUNT_POINT}/archive/ -czf ${MOUNT_POINT}/archive.tgz .
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put ${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put ${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}
rm -f ${MOUNT_POINT}/archive.tgz
EOF
  # substitute to get the day of month
  sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/radius_backup.sh
  # change execute permissions
  chmod +x /usr/local/bin/radius_backup.sh
fi

if [ "$WALRUS_BACKUP" != "Y" ]; then
# we are done here
exit 0
fi

# and turn it into a cronjob to run every hour
if ! crontab -l | grep radius_backup.sh > /dev/null ; then
  echo "$(date) - Setting up cron-job" | tee -a $LOGFILE
  cat >/tmp/crontab <<EOF
40 * * * * /usr/local/bin/radius_backup.sh
EOF
  crontab /tmp/crontab
  if [ ! -f /var/run/crond.pid ] ; then
    service crond start
  else
    service crond restart
  fi
fi
