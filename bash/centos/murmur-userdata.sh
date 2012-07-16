#!/bin/bash
#
# Script to install murmur server.  Intended to be used with CentOS 5.x instances.

# Basic variables that should be used with this script
HOST="murmur.mydomain.com"
SHORT_HOST=`echo ${HOST} | cut -d'.' -f1`

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="murmurs3id" # arbitrary name
WALRUS_IP="10.1.2.3" # IP of the walrus to use
WALRUS_ID="abcdefghijklmnopqrstuvwxyz1234567890ABCD" # EC2_ACCESS_KEY
WALRUS_KEY="abcdefghijklmnopqrstuvwxyz1234567890ABCD" # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/murmur" # conf bucket
WALRUS_MASTER="archive.tgz" # backup copy of all murmur data

# installation log file location
LOGFILE="/var/log/murmur-install.log"

# yum related configuration
# if you have internal mirrors for your cloud, enter them below, otherwise
# leave these commented to use the stock yum configuration for your instance
#YUM_CENTOS_BASE_URL='http://10.1.2.3/centos/$releasever/os/$basearch/'
#YUM_CENTOS_UPDATES_URL='http://10.1.2.3/centos/$releasever/updates/$basearch/'
#YUM_CENTOS_EXTRAS_URL='http://10.1.2.3/centos/$releasever/extras/$basearch/'
#YUM_CENTOS_CENTOSPLUS_URL='http://10.1.2.3/centos/$releasever/centosplus/$basearch/'
#YUM_CENTOS_CONTRIB_URL='http://10.1.2.3/centos/$releasever/contrib/$basearch/'
#EPEL_PACKAGE_URL='http://10.1.2.3/epel/5/x86_64/epel-release-5-4.noarch.rpm'
#YUM_EPEL_URL='http://10.1.2.3/epel/5/$basearch'
#YUM_EPEL_DEBUGINFO_URL='http://10.1.2.3/epel/5/$basearch/debug'
#YUM_EPEL_SOURCE_URL='http://10.1.2.3/epel/5/SRPMS'

# murmur related configuration
MOUNT_POINT="/srv/murmur" # archives and data are on ephemeral
MURMURSUPW="password" # murmur superuser password

# do backup on walrus?
WALRUS_BACKUP="Y"

# Modifications below this point are needed only to customize the behavior
# of the script.

# Do basic setup on the instance.
hostname $HOST
if grep ${HOST} /etc/hosts ; then
  echo "$(date) - ${HOST} already in /etc/hosts" | tee -a $LOGFILE
else
  sed -ie "s/localhost.localdomain/${HOST} ${SHORT_HOST} localhost.localdomain/g" /etc/hosts
  echo "$(date) - Added ${HOST} and ${SHORT_HOST} to /etc/hosts" | tee -a $LOGFILE
fi

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

# install perl-Digest-HMAC
rpm -q perl-Digest-HMAC > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing perl-Digest-HMAC package" | tee -a $LOGFILE
  yum -y install perl-Digest-HMAC
else
  echo "$(date) - perl-Digest-HMAC package already installed" | tee -a $LOGFILE
fi

# now let's get the archives from the walrus bucket
echo "$(date) - Retrieving murmur archives" | tee -a $LOGFILE
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > ${MOUNT_POINT}/archive.tgz
if [ "`head -c 4 ${MOUNT_POINT}/archive.tgz`" = "<Err" ]; then
  echo "$(date) - Couldn't get archives." | tee -a $LOGFILE
  echo "$(date) - Will start with default murmur configuration." | tee -a $LOGFILE
  rm -f ${MOUNT_POINT}/archive.tgz
elif [ "`ls -s ${MOUNT_POINT}/archive.tgz | awk '{print $1}'`" = "0" ]; then
  echo "$(date) - Couldn't get archives." | tee -a $LOGFILE
  echo "$(date) - Will start with default murmur configuration." | tee -a $LOGFILE
  rm -f ${MOUNT_POINT}/archive.tgz
else
  mkdir -p ${MOUNT_POINT}/archive
  tar -C ${MOUNT_POINT}/archive/ -xzf ${MOUNT_POINT}/archive.tgz
  echo "$(date) - Extracted archive.tgz" | tee -a $LOGFILE
fi
if [ -d ${MOUNT_POINT}/archive/murmur ] ; then
  if [ ! -d ${MOUNT_POINT}/murmur ] ; then
    cp -a ${MOUNT_POINT}/archive/murmur* ${MOUNT_POINT}/
    echo "$(date) - Restored ${MOUNT_POINT}/murmur" | tee -a $LOGFILE
  fi
fi

# install murmur if it wasn't restored from backups
if [ ! -f ${MOUNT_POINT}/murmur/murmur.x86 ] ; then
  echo "$(date) - Downloading and extracting murmur-static_x86-1.2.3.tar.bz" | tee -a $LOGFILE
  cd /root/
  wget http://downloads.sourceforge.net/project/mumble/Mumble/1.2.3/murmur-static_x86-1.2.3.tar.bz2
  cd ${MOUNT_POINT}
  tar -xjvf /root/murmur-static_x86-1.2.3.tar.bz2
  ln -s murmur-static_x86-1.2.3 murmur
else
  echo "$(date) - Murmur already installed" | tee -a $LOGFILE
fi

# add the murmur user if it doesn't already exist
id murmur
if [ ! $? -eq 0 ] ; then
  echo "$(date) - Creating murmur user" | tee -a $LOGFILE
  useradd murmur -d ${MOUNT_POINT}/murmur
  cp /etc/skel/.bash* ${MOUNT_POINT}/murmur/
  chown -R murmur:murmur ${MOUNT_POINT}/murmur*
else
  echo "$(date) - murmur user already exists" | tee -a $LOGFILE
fi

# set the murmur superuser password
echo "$(date) - Setting murmur superuser password" | tee -a $LOGFILE
su murmur -c "${MOUNT_POINT}/murmur/murmur.x86 -supw $MURMURSUPW"

# set the murmur server to start in rc.local
if ! grep murmur /etc/rc.d/rc.local ; then
  echo "$(date) - Adding ${MOUNT_POINT}/murmur/murmur.x86 to /etc/rc.d/rc.local" | tee -a $LOGFILE
  echo "su murmur -c \"${MOUNT_POINT}/murmur/murmur.x86\"" >> /etc/rc.d/rc.local
else
  echo "$(date) - ${MOUNT_POINT}/murmur/murmur.x86 already in /etc/rc.d/rc.local" | tee -a $LOGFILE
fi

# start the murmur server if it isn't running already
ps -ef | grep  [m]urmur.x86
if [ ! $? -eq 0 ] ; then
  echo "$(date) - Starting murmur server" | tee -a $LOGFILE
  su murmur -c "${MOUNT_POINT}/murmur/murmur.x86"
else
  echo "$(date) - Murmur server already started" | tee -a $LOGFILE
fi

# install cron daemon
rpm -q vixie-cron > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing vixie-cron" | tee -a $LOGFILE
  yum -y install vixie-cron
else
  echo "$(date) - vixie-cron already installed" | tee -a $LOGFILE
fi

# set up a cron-job to save in a bucket
if [ ! -f /usr/local/bin/murmur_backup.sh ] ; then
  echo "$(date) - Preparing local script to push backups to walrus" | tee -a $LOGFILE
  cat >/usr/local/bin/murmur_backup.sh <<EOF
#!/bin/sh
if [ ! -d ${MOUNT_POINT}/archive ] ; then
  mkdir -p ${MOUNT_POINT}/archive
fi
if [ -d ${MOUNT_POINT}/archive/murmur ] ; then
  rm -rf ${MOUNT_POINT}/archive/murmur
fi
cp -a ${MOUNT_POINT}/murmur* ${MOUNT_POINT}/archive/
tar -C ${MOUNT_POINT}/archive/ -czf ${MOUNT_POINT}/archive.tgz .
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put ${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put ${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}
rm -f ${MOUNT_POINT}/archive.tgz
EOF
  # substitute to get the day of month
  sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/murmur_backup.sh
  # change execute permissions
  chmod +x /usr/local/bin/murmur_backup.sh
fi

if [ "$WALRUS_BACKUP" != "Y" ]; then
# we are done here
exit 0
fi

# and turn it into a cronjob to run every day
if ! crontab -l | grep murmur_backup.sh > /dev/null ; then
  echo "$(date) - Setting up cron-job" | tee -a $LOGFILE
  cat >/tmp/crontab <<EOF
40 22 * * * /usr/local/bin/murmur_backup.sh
EOF
  crontab /tmp/crontab
  if [ ! -f /var/run/crond.pid ] ; then
    service crond start
  else
    service crond restart
  fi
fi

echo "$(date) - Done" | tee -a $LOGFILE
