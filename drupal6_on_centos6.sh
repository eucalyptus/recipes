#!/usr/bin/env bash
#
# Software License Agreement (BSD License)
#
# Copyright (c) 2009-2012, Eucalyptus Systems, Inc.
# All rights reserved.
#
# Redistribution and use of this software in source and binary forms, with or
# without modification, are permitted provided that the following conditions
# are met:
#
#   Redistributions of source code must retain the above
#   copyright notice, this list of conditions and the
#   following disclaimer.
#
#   Redistributions in binary form must reproduce the above
#   copyright notice, this list of conditions and the
#   following disclaimer in the documentation and/or other
#   materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# author: Greg DeKoenigsberg
#
# Special thanks to Fedora install instructions for Drupal:
#   http://fedoraproject.org/wiki/How_to_install_Drupal

##############################################################
# Drupal/MySQL password and config data. 
# 
# This info will be required by the next stage of your Drupal
# install, so keep it handy.
#
# CHANGE ALL PASSWORDS BEFORE RUNNING THIS SCRIPT!
##############################################################
MYSQL_PASSWORD='xkcd_teaches_us_that_passwords_are_awesome_when_they_are_long'
DRUPAL_DATABASE_NAME='drupal_db'
DRUPAL_DB_USERNAME='drupal_admin'
DRUPAL_DB_PASSWORD='a_man_a_plan_a_canal_panama'

# Setup the system's hostname.
FULL_HOSTNAME="myhost.mydomain"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
hostname ${FULL_HOSTNAME}
sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts
# echo -n ${FULL_HOSTNAME} >> /etc/sysconfig/network

# Install the EPEL repository.  This is where we get the Drupal packages from.
YUM=`which yum`
RPM=`which rpm`
EPEL_PACKAGE="epel-release-6-7.noarch.rpm"
EPEL_URL="http://dl.fedoraproject.org/pub/epel/6/i386/"
curl -o /root/${EPEL_PACKAGE} ${EPEL_URL}/${EPEL_PACKAGE}
${RPM} -Uhv /root/${EPEL_PACKAGE}

# Update the instance and install MySQL, php-mysql, and Drupal packages
${YUM} -y update
${YUM} -y groupinstall 'Web Server' 'MySQL Database server'
${YUM} -y install drupal6 php-mysql

# Now that MySQL is installed, configure it for use with Drupal.
service mysqld start
mysqladmin -u root password ${MYSQL_PASSWORD}
mysqladmin -h localhost -u root -p${MYSQL_PASSWORD} create ${DRUPAL_DATABASE_NAME}
mysql -u root -p${MYSQL_PASSWORD} -e "GRANT ALL PRIVILEGES ON ${DRUPAL_DATABASE_NAME}.* TO ${DRUPAL_DB_USERNAME}@localhost IDENTIFIED BY '${DRUPAL_DB_PASSWORD}';" 
mysql -u root -p${MYSQL_PASSWORD} -e "FLUSH PRIVILEGES;"

# Configure httpd properly for using Drupal.
perl -pi -e 's/#Allow from/Allow from/g;' /etc/httpd/conf.d/drupal6.conf 
perl -pi -e 's/Deny from/#Deny from/g;' /etc/httpd/conf.d/drupal6.conf 

perl -pi -e 's|# RewriteBase /$|  RewriteBase /|g;' /usr/share/drupal6/.htaccess 

# Copy over the default Drupal config and make it the active config.
cp /etc/drupal6/default/default.settings.php /etc/drupal6/default/settings.php
chmod 666 /etc/drupal6/default/settings.php

# Start Apache, and you're ready to go!
service httpd start

# Now go to yourhostname.com/drupal to configure your Drupal server for use.
