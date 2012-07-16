#!/bin/bash
#
# Script to install cacti.  Intended to be used with CentOS 5.x instances.

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="cactis3id" # arbitrary name
WALRUS_IP="10.1.2.3" # IP of the walrus to use
WALRUS_ID="XXXXXXXXXXXXXXXXXXXXX" # EC2_ACCESS_KEY
WALRUS_KEY="abcdefghijklmnopqrstuvwxyz1234567890ABCD" # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/cacti" # conf bucket
WALRUS_MASTER="archive.tgz" # backup copy of all cacti data

# installation log file location
LOGFILE="/var/log/cacti-install.log"

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

# mysql configuration
MYSQLROOTPASSWORD="mysqlrootpassword"
CACTIDBUSERNAME="cactidbuser"
CACTIDBUSERPASSWORD="cactidbpassword"

# cacti related configuration
MOUNT_POINT="/srv/cacti" # archives and data are on ephemeral

# do backup on walrus?
WALRUS_BACKUP="Y"

# if you would like to further customize your cacti instance with custom cacti
# modules, a local SNMP service, or anything else, create a shell script and 
# place it, and any required data files in the $MOUNT_POINT/archive/addons 
# directory.
# 
# Any shell script ending in .sh in this directory after the Walrus archive is
# extracted will be automatically executed.  Make sure all your scripts are 
# idempotent, so that multiple runs of the script will produce consistent 
# results.

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

# install cacti and other dependencies
rpm -q cacti > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing Cacti and other dependencies" | tee -a $LOGFILE
  yum -y install cacti mysql-server net-snmp-utils vixie-cron perl-Digest-HMAC php-ldap
fi

# now let's get the archives from the walrus bucket
echo "$(date) - Retrieving cacti archives" | tee -a $LOGFILE
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > ${MOUNT_POINT}/archive.tgz
if [ "`head -c 4 ${MOUNT_POINT}/archive.tgz`" = "<Err" ]; then
  echo "$(date) - Couldn't get archives!" | tee -a $LOGFILE
  echo "$(date) - Will start with default Cacti configuration." | tee -a $LOGFILE
  rm -f ${MOUNT_POINT}/archive.tgz
else
  mkdir -p ${MOUNT_POINT}/archive
  tar -C ${MOUNT_POINT}/archive/ -xzf ${MOUNT_POINT}/archive.tgz
fi

# move/link mysql and cacti data to ephemeral storage
if [ ! -d ${MOUNT_POINT}/var/lib ] ; then
  mkdir -p ${MOUNT_POINT}/var/lib
fi 
if [ ! -d ${MOUNT_POINT}/var/lib/mysql ] ; then
  echo "$(date) - Moving MySQL data location" | tee -a $LOGFILE
  mv /var/lib/mysql ${MOUNT_POINT}/var/lib/
  ln -s ${MOUNT_POINT}/var/lib/mysql /var/lib/mysql
else
  echo "$(date) - MySQL data already at ${MOUNT_POINT}/var/lib/mysql" | tee -a $LOGFILE
fi
if [ ! -d ${MOUNT_POINT}/var/lib/cacti ] ; then
  echo "$(date) - Moving Cacti data location" | tee -a $LOGFILE
  mv /var/lib/cacti ${MOUNT_POINT}/var/lib/
  ln -s ${MOUNT_POINT}/var/lib/cacti /var/lib/cacti
else
  echo "$(date) - Cacti data already at ${MOUNT_POINT}/var/lib/cacti" | tee -a $LOGFILE
fi

# restore cacti archives, if they exist, and the rrd directory is empty
if [ -f ${MOUNT_POINT}/archive/cactiarchive.tgz ] ; then
  RRACOUNT=`ls ${MOUNT_POINT}/var/lib/cacti/rra/ | wc -l`
  if [ $RRACOUNT -eq 0 ] ; then
    echo "$(date) - Restoring Cacti data" | tee -a $LOGFILE
    tar -C ${MOUNT_POINT}/var/lib/cacti/ -xzf ${MOUNT_POINT}/archive/cactiarchive.tgz .
  fi
fi

# change the cacti apache configuration to allow access
if grep -E 'Allow from 127.0.0.1$' /etc/httpd/conf.d/cacti.conf ; then
  echo "$(date) - Modifying Apache configuration to allow remote access to Cacti web interface" | tee -a $LOGFILE
  sed -i -e 's/Allow from 127.0.0.1$/Allow from all/g' /etc/httpd/conf.d/cacti.conf
fi

# change the cacti db username and password
sed -i -e "s/\$database_username = \"cactiuser\";/\$database_username = \"$CACTIDBUSERNAME\";/g" /etc/cacti/db.php
sed -i -e "s/\$database_password = \"cactiuser\";/\$database_password = \"$CACTIDBUSERPASSWORD\";/g" /etc/cacti/db.php

# enable the crond, httpd, and mysqld services and start them
echo "$(date) - Enabling and starting services" | tee -a $LOGFILE
chkconfig crond on
chkconfig httpd on
chkconfig mysqld on
if [ ! -f /var/run/mysqld/mysqld.pid ] ; then
  service mysqld start
else
  service mysqld restart
fi
if [ ! -f /var/run/httpd.pid ] ; then
  service httpd start
else
  service httpd restart
fi
if [ ! -f /var/run/crond.pid ] ; then
  service crond start
else
  service crond restart
fi

# if the test db still exists, run the mysql_secure_installation and set the
# mysql root password
if [ -d /var/lib/mysql/test ] ; then
  echo "$(date) - Configuring MySQL service" | tee -a $LOGFILE
  cat << EOF | /usr/bin/mysql_secure_installation

Y
$MYSQLROOTPASSWORD
$MYSQLROOTPASSWORD
Y
Y
Y
Y
EOF
fi

# create/restore the cacti database if it doesn't exist
if [ ! -d /var/lib/mysql/cacti ] ; then
  echo "$(date) - Creating empty cacti database" | tee -a $LOGFILE
  cat << EOF > cactidbuser.sql
create database cacti;
CREATE USER "$CACTIDBUSERNAME"@"localhost" IDENTIFIED BY "$CACTIDBUSERPASSWORD";
GRANT ALL ON cacti.* TO "$CACTIDBUSERNAME"@"localhost";
EOF
  mysql -u root -p${MYSQLROOTPASSWORD} < cactidbuser.sql
  if [ -f ${MOUNT_POINT}/archive/cactidb.tgz ] ; then
    echo "$(date) - Restoring cacti database from archives" | tee -a $LOGFILE
    gunzip < ${MOUNT_POINT}/archive/cactidb.tgz | mysql -uroot -p${MYSQLROOTPASSWORD} cacti
  else
    echo "$(date) - Populating default cacti database" | tee -a $LOGFILE
    mysql -u $CACTIDBUSERNAME -p${CACTIDBUSERPASSWORD} cacti < /usr/share/doc/cacti-0.8.7i/cacti.sql
  fi
fi

# create the addons directory and run any scripts located there
if [ ! -d $MOUNT_POINT/archive/addons ] ; then
  echo "$(date) - Creating addons directory" | tee -a $LOGFILE
  mkdir -p $MOUNT_POINT/archive/addons
else
  echo "$(date) - Addons directory already present" | tee -a $LOGFILE
fi
for script in `ls ${MOUNT_POINT}/archive/addons/*.sh` ; do
  echo "$(date) - Executing ${script}" | tee -a $LOGFILE
  if [ ! -x ${script} ] ; then
    chmod +x ${script}
  fi
  ${script}
done

# enable the cacti cron job
if grep -E '^#' /etc/cron.d/cacti ; then
  echo "$(date) - Enabling Cacti cron job" | tee -a $LOGFILE
  sed -i -e 's/^#\*/\*/g' /etc/cron.d/cacti
fi

# set up a cron-job to save the archives and database to a bucket
if [ ! -f /usr/local/bin/cacti_backup.sh ] ; then
  echo "$(date) - Preparing local script to push backups to walrus" | tee -a $LOGFILE
  cat >/usr/local/bin/cacti_backup.sh <<EOF
#!/bin/sh
if [ ! -d ${MOUNT_POINT}/archive ] ; then
  mkdir -p ${MOUNT_POINT}/archive
fi
if [ -f ${MOUNT_POINT}/archive/cactidb.tgz ] ; then
  rm -f ${MOUNT_POINT}/archive/cactidb.tgz
fi
mysqldump --single-transaction -uroot -p${MYSQLROOTPASSWORD} cacti | gzip > ${MOUNT_POINT}/archive/cactidb.tgz
if [ -f ${MOUNT_POINT}/archive/cactiarchive.tgz ] ; then
  rm -f ${MOUNT_POINT}/archive/cactiarchive.tgz
fi
tar -C ${MOUNT_POINT}/var/lib/cacti/ -czf ${MOUNT_POINT}/archive/cactiarchive.tgz .
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
  sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/cacti_backup.sh
  # change execute permissions
  chmod +x /usr/local/bin/cacti_backup.sh
fi

if [ "$WALRUS_BACKUP" != "Y" ]; then
# we are done here
exit 0
fi

# and turn it into a cronjob to run every hour
if ! crontab -l | grep cacti_backup.sh > /dev/null ; then
  echo "$(date) - Setting up cron-job" | tee -a $LOGFILE
  cat >/tmp/crontab <<EOF
40 * * * * /usr/local/bin/cacti_backup.sh
EOF
  crontab /tmp/crontab
  if [ ! -f /var/run/crond.pid ] ; then
    service crond start
  else
    service crond restart
  fi
fi
