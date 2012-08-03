#!/bin/bash
#
# Script to install redmine and make it use a remote database. The
# database instance uses the PostgresRecipe. 
# This script uses s3curl (modified to work with Eucalyptus).

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="my_walrus"			# arbitrary name 
WALRUS_IP="173.205.188.8"		# IP of the walrus to use
WALRUS_KEY="xxxxxxxxxxxxxxxxxxxx"	# EC2_ACCESS_KEY
WALRUS_ID="xxxxxxxxxxxxxxxxxxxx"	# EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/redmine"	# conf bucket

LOCAL_SMTP="Y"				# install exim4 locally
ROOT_EMAIL="my_name@example.com"	# admin email recipient
EMAIL_NAME="projects.example.com"	# mailname

# do we want extra plugins (which live in github)? 
#PLUGINS="https://github.com/thorin/redmine_ldap_sync.git https://github.com/kulesa/redmine_better_gantt_chart.git https://github.com/thorin/redmine_ldap_sync.git git://github.com/edavis10/redmine-google-analytics-plugin.git"
PLUGINS=""

# we do use git clone and a cronjob to have source code mirrored locally
# for redmine's users consumptions
GIT_REPO="/media/ephemeral0/repos"
#REMOTE_GIT="git://github.com/EucalyptusSystems/Eucalyptus-Scripts.git git://github.com/EucalyptusSystems/s3curl.git https://github.com/LitheStoreDev/lithestore-cli.git"
REMOTE_GIT=""
REDMINE_USER="www-data"


# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
chmod 755 ${S3CURL}

# now let's setup the id for accessing walrus
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
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# preseed the answers for redmine (to avoid interactions, since we'll
# override the config files with our own): we need debconf-utils
apt-get --force-yes -y install debconf-utils
cat >/root/preseed.cfg <<EOF
redmine redmine/instances/default/dbconfig-upgrade      boolean true
redmine redmine/instances/default/dbconfig-remove       boolean
redmine redmine/instances/default/dbconfig-install      boolean false
redmine redmine/instances/default/dbconfig-reinstall    boolean false
redmine redmine/instances/default/pgsql/admin-pass      password
redmine redmine/instances/default/pgsql/app-pass        password	VLAvJOPLM8OP
redmine redmine/instances/default/pgsql/changeconf      boolean false
redmine redmine/instances/default/pgsql/method  select  unix socket
redmine redmine/instances/default/database-type select  pgsql
redmine redmine/instances/default/pgsql/manualconf      note
redmine redmine/instances/default/pgsql/authmethod-admin        select	ident
redmine redmine/instances/default/pgsql/admin-user      string  postgres
redmine redmine/instances/default/pgsql/authmethod-user select  password
EOF

# set the preseed q/a
debconf-set-selections /root/preseed.cfg
rm -f /root/preseed.cfg

# install local SMTP server is needed
if [ "${LOCAL_SMTP}" = "Y" ]; then
	# add more preseeding for exim4
	cat >/root/preseed.cfg <<EOF
exim4-daemon-light	exim4-daemon-light/drec	error	
exim4-config	exim4/dc_other_hostnames	string	
exim4-config	exim4/dc_eximconfig_configtype	select	internet site; mail is sent and received directly using SMTP
exim4-config	exim4/no_config	boolean	true
exim4-config	exim4/hide_mailname	boolean	
exim4-config	exim4/dc_postmaster	string	${ROOT_EMAIL}
exim4-config	exim4/dc_smarthost	string	
exim4-config	exim4/dc_relay_domains	string	
exim4-config	exim4/dc_relay_nets	string	
exim4-base	exim4/purge_spool	boolean	false
exim4-config	exim4/mailname	string	${MAIL_NAME}
exim4-config	exim4/dc_readhost	string	
exim4	exim4/drec	error	
exim4-base	exim4-base/drec	error	
exim4-config	exim4/use_split_config	boolean	false
exim4-config	exim4/dc_localdelivery	select	mbox format in /var/mail/
exim4-config	exim4/dc_local_interfaces	string	127.0.0.1 ; ::1
exim4-config	exim4/dc_minimaldns	boolean	false
EOF
	# set the preseed q/a
	debconf-set-selections /root/preseed.cfg
	rm -f /root/preseed.cfg

	# install exim4 now
	apt-get install --force-yes -y exim4
fi

# install redmine and supporting packages 
apt-get install --force-yes -y redmine-pgsql redmine librmagick-ruby libapache2-mod-passenger apache2 libdbd-pg-ruby libdigest-hmac-perl git libopenid-ruby

# now install plugins if we have them
for x in $PLUGINS ; do
	(cd /usr/share/redmine/vendors/plugin; git clone $x) || true
done

# now let's setup the git repo for the sources
if [ "${REMOTE_GIT}" != "" ]; then
	# create repo with the right permissions
	mkdir -p ${GIT_REPO}
	chown ${REDMINE_USER} ${GIT_REPO}
	chmod 2755 ${GIT_REPO}

	# save the ssh key of github into the redmine's user home
	REDMINE_HOME="`getent passwd ${REDMINE_USER} |cut -d ':' -f 6`"
	mkdir ${REDMINE_HOME}/.ssh
	chown ${REDMINE_USER} ${REDMINE_HOME}/.ssh
	chmod 700 ${REDMINE_HOME}/.ssh
	ssh-keyscan github.com > ${REDMINE_HOME}/.ssh/known_hosts
	chown ${REDMINE_USER} ${REDMINE_HOME}/.ssh/known_hosts
fi

# now let's clone the repos
for x in ${REMOTE_GIT} ; do 
	# get the repos
	(cd ${GIT_REPO}; su -c "git clone ${x}" ${REDMINE_USER})
done

# now let's setup the cronjob
if [ "${REMOTE_GIT}" != "" ]; then
	for x in `ls ${GIT_REPO}` ; do
		echo "*/3 * * * * cd ${GIT_REPO}/${x} && git pull >> /dev/null" >> /tmp/redmine_cronjob
	done

	chown ${REDMINE_USER} /tmp/redmine_cronjob
	crontab -u ${REDMINE_USER} /tmp/redmine_cronjob
	rm /tmp/redmine_cronjob
fi


# since we are using apache2, let's stop it, disable the default web site
# and enable the needed modules (passenger, ssl and rewrite)
service apache2 stop
a2dissite default
a2dissite default-ssl
a2enmod passenger
a2enmod ssl
a2enmod rewrite

# we need the cert and key for ssl configuration
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/ssl-cert.pem > /etc/ssl/certs/ssl-cert.pem
chmod 644 /etc/ssl/certs/ssl-cert.pem
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/ssl-cert.key > /etc/ssl/private/ssl-cert.key
chgrp ssl-cert /etc/ssl/private/ssl-cert.key
chmod 640 /etc/ssl/private/ssl-cert.key

# let's setup redmine's email access and database
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/email.yml > /etc/redmine/default/email.yml
chgrp www-data /etc/redmine/default/email.yml
chmod 640 /etc/redmine/default/email.yml
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/database.yml > /etc/redmine/default/database.yml
chgrp www-data /etc/redmine/default/database.yml
chmod 640 /etc/redmine/default/database.yml

# add a theme...
cd /usr/share/redmine/public/themes
mkdir -p martini/images
mkdir -p martini/stylesheets
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/martini/images/loading.gif > martini/images/loading.gif
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/martini/stylesheets/application.css > martini/stylesheets/application.css

# get redmine's configuration file and enable it
${S3CURL} --id ${WALRUS_NAME} --get -- -s $WALRUS_URL/redmine > /etc/apache2/sites-available/redmine
a2ensite redmine

# start apache
service apache2 start
