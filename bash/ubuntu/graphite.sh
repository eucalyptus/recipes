#!/bin/bash

####################################
# HOMEPAGE
# http://graphite.wikidot.com/
# BASIC REQUIREMENTS
# http://graphite.wikidot.com/installation
# http://geek.michaelgrace.org/2011/09/how-to-install-graphite-on-ubuntu/
# Last tested & updated 7/24/2012 against Ubuntu 11.10 (Oneiric Ocelot)
# After installation hit http://<public-ip> to access web frontend
####################################
cd /opt
wget http://launchpad.net/graphite/0.9/0.9.9/+download/graphite-web-0.9.9.tar.gz
wget http://launchpad.net/graphite/0.9/0.9.9/+download/carbon-0.9.9.tar.gz
wget http://launchpad.net/graphite/0.9/0.9.9/+download/whisper-0.9.9.tar.gz
tar -zxvf graphite-web-0.9.9.tar.gz
tar -zxvf carbon-0.9.9.tar.gz
tar -zxvf whisper-0.9.9.tar.gz
mv graphite-web-0.9.9 /opt/graphite
mv carbon-0.9.9 /opt/carbon
mv whisper-0.9.9 /opt/whisper
rm carbon-0.9.9.tar.gz
rm graphite-web-0.9.9.tar.gz
rm whisper-0.9.9.tar.gz
sudo apt-get install --assume-yes apache2 apache2-mpm-worker apache2-utils apache2.2-bin apache2.2-common libapr1 libaprutil1 libaprutil1-dbd-sqlite3 python3.2 libpython3.2 python3-minimal libapache2-mod-wsgi libaprutil1-ldap memcached python-cairo-dev python-django python-ldap python-memcache python-pysqlite2 sqlite3 erlang-os-mon erlang-snmp rabbitmq-server bzr expect ssh libapache2-mod-python python-setuptools
sudo easy_install django-tagging
 
####################################
# INSTALL WHISPER
####################################
 
pushd whisper
sudo python setup.py install
popd
 
####################################
# INSTALL CARBON
####################################
 
pushd carbon
sudo python setup.py install
popd

# CONFIGURE CARBON
####################
pushd /opt/graphite/conf
sudo cp carbon.conf.example carbon.conf
sudo cp storage-schemas.conf.example storage-schemas.conf
tee storage-schemas.conf <<EOF              
[stats]
priority = 110
pattern = .*
retentions = 10:2160,60:10080,600:262974            
EOF

####################################
# CONFIGURE GRAPHITE (webapp)
####################################

cd /opt/graphite
sudo python check-dependencies.py
sudo python setup.py install

###################
# CONFIGURE APACHE
###################
cd /opt/graphite/examples
sudo cp example-graphite-vhost.conf /etc/apache2/sites-available/default
sudo cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
sudo mkdir -p /etc/httpd/wsgi
sudo /etc/init.d/apache2 reload

####################################
# INITIAL DATABASE CREATION
####################################
cd /opt/graphite/webapp/graphite/
sudo python manage.py syncdb --noinput
# follow prompts to setup django admin user
sudo chown -R www-data:www-data /opt/graphite/storage/
sudo /etc/init.d/apache2 restart
cd /opt/graphite/webapp/graphite
sudo cp local_settings.py.example local_settings.py 

####################################
# START CARBON
####################################
cd /opt/graphite/
sudo ./bin/carbon-cache.py start

####################################
# SEND DATA TO GRAPHITE
####################################
cd /opt/graphite/examples
sudo chmod +x example-client.py
# [optional] edit example-client.py to report data faster
# sudo vim example-client.py
sudo ./example-client.py