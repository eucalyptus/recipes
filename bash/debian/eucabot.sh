#!/bin/bash -x
#
# Script to install eucabot

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="community"                 # arbitrary name
WALRUS_IP="FIXME"                       # IP of the walrus to use
WALRUS_ID="FIXME"                       # EC2_ACCESS_KEY
WALRUS_KEY="FIXME"                      # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/eucabot"  # conf bucket
ARCHIVE_TARBALL="eucabot-archive.tgz"   # master copy of the database

MOUNT_POINT="/srv/supybot"              # archives and data are on ephemeral
MOUNT_MOUNT_POINT="N"                   # whether to mount something there or
                                        # just make a directory on the rootfs

# do backup on walrus?
RESTORE_FROM_WALRUS="Y"

# Modification below this point are needed only to customize the behavior
# of the script.

# just sync the date first
apt-get install --force-yes -y ntpdate
ntpdate pool.ntp.org
apt-get install --force-yes -y ntp
sleep 60

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
echo "Getting ${S3CURL}"
curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
chmod 755 ${S3CURL}

# now let's setup the id for accessing walrus
echo "Setting credentials for ${S3CURL}"
cat > /root/.s3curl <<EOF
%awsSecretAccessKeys = (
    ${WALRUS_NAME} => {
        url => '${WALRUS_IP}',
        id  => '${WALRUS_ID}',
        key => '${WALRUS_KEY}',
    },
);
EOF
chmod 600 /root/.s3curl

# update the instance
echo "Upgrading and installing packages"
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

hostname meetbot.eucalyptus.com

grep -q meetbot /etc/hosts || echo '173.205.188.126 meetbot.eucalyptus.com meetbot' >> /etc/hosts

# install deps
echo "Installing dependencies"
apt-get install --force-yes -y apache2 darcs git python-twisted-names

wget http://www.eucalyptus.com/favicon.ico -O /var/www/favicon.ico

# let's make sure we have the mountpoint
echo "Creating and prepping ${MOUNT_POINT}"
mkdir -p ${MOUNT_POINT}

# don't mount ${MOUNT_POINT} more than once (mainly for debugging)
if [[ "${MOUNT_MOUNT_POINT}" = Y ]] && ! mount | grep ${MOUNT_POINT}; then
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

useradd -g www-data -M -N -r -s /usr/sbin/nologin supybot1
useradd -g www-data -M -N -r -s /usr/sbin/nologin supybot2

# now let's get the archives from the walrus bucket
if [[ "$RESTORE_FROM_WALRUS" = Y ]]; then
    echo "Retrieving eucabot archives and configuration"
    ${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${ARCHIVE_TARBALL} > /${MOUNT_POINT}/archive.tgz
    if [ "`head -c 4 /${MOUNT_POINT}/archive.tgz`" = "<Err" ]; then
        echo 'Failed to get archives!'
        exit 1
    else
        tar -C ${MOUNT_POINT} -xzpf ${MOUNT_POINT}/archive.tgz
    fi
else
    # Don't forget to write data/*/supybot.conf and data/*/conf/users.conf

    # Supybot instances' data go in subdirectories of this
    install -d -m 0710 ${MOUNT_POINT}/data         -g www-data
    install -d -m 0710 ${MOUNT_POINT}/meeting-logs -g www-data

    # Plugins go here
    install -d -m 0775 ${MOUNT_POINT}/plugins      -g www-data

    # Instance 1 lives on Freenode
    install -d -m 0710 ${MOUNT_POINT}/data/1         -o supybot1
    install -d -m 0750 ${MOUNT_POINT}/meeting-logs/1 -o supybot1 -g www-data
    mkdir -p ${MOUNT_POINT}/data/1/conf
    chown -R supybot1:www-data ${MOUNT_POINT}/data/1 ${MOUNT_POINT}/meeting-logs/1

    # Instance 2 lives in Eucalyptus HQ
    install -d -m 0710 ${MOUNT_POINT}/data/2         -o supybot2 -g www-data
    install -d -m 0750 ${MOUNT_POINT}/meeting-logs/2 -o supybot2 -g www-data
    mkdir -p ${MOUNT_POINT}/data/2/conf
    chown -R supybot2:www-data ${MOUNT_POINT}/data/2 ${MOUNT_POINT}/meeting-logs/2
fi

# Install supybot
tempdir=`mktemp -d`
git clone --depth 1 git://github.com/ProgVal/Limnoria.git $tempdir/supybot
pushd $tempdir/supybot
python setup.py install
popd
rm -rf $tempdir

# Install the MeetBot plugin
darcs get http://anonscm.debian.org/darcs/collab-maint/MeetBot/ ${MOUNT_POINT}/plugins/MeetBot

# Install remaining plugins
tempdir=`mktemp -d`
git clone --depth 1 git://github.com/gholms/supybot-plugins.git $tempdir/supybot-plugins-gholms
mv -n $tempdir/supybot-plugins-gholms/* ${MOUNT_POINT}/plugins/
git clone --depth 1 git://github.com/ProgVal/Supybot-plugins.git $tempdir/supybot-plugins-progval
mv -nT $tempdir/supybot-plugins-progval/AttackProtector ${MOUNT_POINT}/plugins/AttackProtector
rm -rf $tempdir

chgrp -R www-data ${MOUNT_POINT}/plugins
chmod -R g+rwX    ${MOUNT_POINT}/plugins

[[ "$RESTORE_FROM_WALRUS" != Y ]] && exit 0

# let's setup apache's configuration
echo "Configuring apache"
cat >> /etc/ldap/ldap.conf << EOF
BASE FIXME
URI FIXME
TLS_CACERT /etc/ssl/certs/gd_bundle.crt
TLS_REQCERT demand
EOF

${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/supybot-apache-config > /etc/apache2/sites-available/supybot
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/gd_bundle.crt      > /etc/ssl/certs/gd_bundle.crt
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/eucalyptus.com.crt > /etc/ssl/certs/eucalyptus.com.crt
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/eucalyptus.com.key > /etc/ssl/private/eucalyptus.com.key
if [ "`head -c 4 /etc/apache2/sites-available/supybot`" = "<Err" ]; then
        echo "Couldn't get apache configuration!"
        exit 1
fi
a2dissite default
a2ensite supybot
a2enmod authnz_ldap
a2enmod ssl
service apache2 restart

# Fetch /etc/init.d/supybot
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/supybot.init > /etc/init.d/supybot
if [ "`head -c 4 /etc/init.d/supybot`" = "<Err" ]; then
        echo "Couldn't get init script!"
        exit 1
fi
chmod +x /etc/init.d/supybot
update-rc.d supybot defaults

# Set up a cron-job to save the archives and config to a bucket. It will
# run as root
echo "Preparing local script to push backups to walrus"
cat >/etc/cron.hourly/eucabot-backup <<EOF
#!/bin/sh
chmod -R g+rwX ${MOUNT_POINT}/plugins
tar -C ${MOUNT_POINT} -czpf ${MOUNT_POINT}/archive.tgz .
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${ARCHIVE_TARBALL}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${ARCHIVE_TARBALL}
# save the init script
${S3CURL} --id ${WALRUS_NAME} --put /etc/init.d/supybot -- -s ${WALRUS_URL}/supybot.init
# and save the aliases too
${S3CURL} --id ${WALRUS_NAME} --put /etc/aliases -- -s ${WALRUS_URL}/aliases
# finally the apache config file
${S3CURL} --id ${WALRUS_NAME} --put /etc/apache2/sites-available/supybot -- -s ${WALRUS_URL}/supybot-apache-config
rm ${MOUNT_POINT}/archive.tgz
EOF
# substitute to get the day of month
sed -i 's/-day_of_month/-$(date +%d)/' /etc/cron.hourly/eucabot-backup

# change execute permissions and ownership
chmod +x /etc/cron.hourly/eucabot-backup

# Start the bot(s)
service supybot start
