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
# Description:
# This recipe bootstraps a puppetmaster for use within a cloud instance 
# or physical system. It uses puppet to bootstrap itself as a server and 
# is based on the original puppet bootstrap recipe.
# It uses apache as the webserver with passenger to help puppet scale.
# It also sets up pluginsync and storedconfigs with a mysql backend.
#
# Credits:
# Tom Ellis <tom.ellis@eucalyptus.com>

MYSQL_PASSWD="t3mp0rary"
PUPPET_MYSQL_PASSWD="t3mppupp3t"
FULL_HOSTNAME="puppet.example.com"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
YUM=`which yum`
RPM=`which rpm`
EPEL_PACKAGE="epel-release-6-7.noarch.rpm"
EPEL_URL="http://dl.fedoraproject.org/pub/epel/6/i386/"
PUPPETLABS_PACKAGE="puppetlabs-release-6-1.noarch.rpm"
PUPPETLABS_URL="http://yum.puppetlabs.com/el/6/products/x86_64/"
PASSENGER_PACKAGE="passenger-release.noarch.rpm"
PASSENGER_URL="http://passenger.stealthymonkeys.com/rhel/6/"
MODULE_PATH="/root/puppet/modules"

###########
# Setup the hostname for the system. Puppet really relies on 
# the hostname so this must be done.
###########
hostname ${FULL_HOSTNAME}

sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts

sed -i -e "s/HOSTNAME.*/HOSTNAME=${FULL_HOSTNAME}/g" /etc/sysconfig/network

###########
# Download and install EPEL repo which contains lots of useful pacakges.
###########
curl -o /root/${EPEL_PACKAGE} ${EPEL_URL}/${EPEL_PACKAGE}
${RPM} -Uhv /root/${EPEL_PACKAGE}

###########
# Download and install the puppetlabs repo which has new offical releases of puppet
###########
# EPEL contains Puppet 2.6. There are some cool features in 2.7 though, ymmv.
curl -o /root/${PUPPETLABS_PACKAGE} ${PUPPETLABS_URL}/${PUPPETLABS_PACKAGE} 
${RPM} -Uhv /root/${PUPPETLABS_PACKAGE}

###########
# Download and install the passenger repo to allow puppet to scale
###########
# Passenger is not part of EPEL
curl -o /root/${PASSENGER_PACKAGE} ${PASSENGER_URL}/${PASSENGER_PACKAGE}
${RPM} -Uvh /root/${PASSENGER_PACKAGE}

###########
# Update the instance and install the puppet agent
###########
${YUM} -y update
${YUM} -y install puppet

##########
# Configure puppet a puppetmaster using puppet
##########
PUPPET=`which puppet`

##########
# Setup the puppet manifest in /root/puppetmaster.pp
##########
mkdir -p ${MODULE_PATH}/puppetmaster/{files,manifests}
cat >> ${MODULE_PATH}/puppetmaster/manifests/init.pp <<EOF
class puppetmaster {
 package {
     'puppet-server': ensure => installed
 }
 
 package {
     'rubygem-activerecord': ensure => installed
 }

 package {
     'rubygem-sqlite3-ruby': ensure => installed
 }

 package {
     'httpd': ensure => installed
 }

 package {
     'mod_passenger': ensure => installed
 }

 package {
     'mod_ssl': ensure => installed
 }
 package {
     'mysql-server': ensure => installed
 }
 package {
     'ruby-mysql': ensure => installed
 }

 file {'puppet.conf':
     owner   => 'root',
     group   => 'root',
     mode    => '0644',
     path    => '/etc/puppet/puppet.conf',
     source  => 'puppet:///modules/puppetmaster/puppet.conf',
     require => Package['puppet-server'],
 }

 file {'puppetmaster.conf':
     owner   => 'root',
     group   => 'root',
     mode    => '0644',
     path    => '/etc/httpd/conf.d/puppetmaster.conf',
     source  => 'puppet:///modules/puppetmaster/puppetmaster.conf',
     require => Package['mod_passenger'],
 }
 
 file {'autosign.conf':
     owner   => 'root',
     group   => 'root',
     mode    => '0644',
     path    => '/etc/puppet/autosign.conf',
     source  => 'puppet:///modules/puppetmaster/autosign.conf',
     require => Package['puppet-server'],
 }

 file {'site.pp':
     owner   => 'root',
     group   => 'root',
     mode    => '0644',
     path    => '/etc/puppet/manifests/site.pp',
     source  => 'puppet:///modules/puppetmaster/site.pp',
     require => Package['puppet-server'],
 }

 file {'nodes.pp':
     owner   => 'root',
     group   => 'root',
     mode    => '0644',
     path    => '/etc/puppet/manifests/nodes.pp',
     source  => 'puppet:///modules/puppetmaster/nodes.pp',
     require => Package['puppet-server'],
 }
    
 service {
    'puppetmaster':
        ensure => stopped,
        enable => false,
        require => [ Package['puppet-server'], File['puppet.conf'], File['autosign.conf'], File['site.pp'], File['nodes.pp'] ],
 }
 
 service {
    'mysqld':
        ensure => running,
        enable => true,
        require => [ Package['mysql-server'] ],
 }

 service {
    'httpd':
 	ensure => stopped,
 	enable => true,
        require => [ Package['httpd'], Package['mod_passenger'], Package['ruby-mysql'], File['puppetmaster.conf'] ],
 }

  exec {'rack-config':
      command => "/bin/cp -f /usr/share/puppet/ext/rack/files/config.ru /etc/puppet/rack/",
      creates => "/etc/puppet/rack/config.ru",
      require => File['/etc/puppet/rack/public'],
  }

  file {'/etc/puppet/rack/config.ru':
    owner   => puppet,
    group   => puppet,
    mode    => 0644,
    require => Exec['rack-config'],
  }

  file {'/etc/puppet/rack':
    owner   => puppet,
    group   => puppet,
    mode    => 0644,
    ensure  => directory,
    require => Package['puppet-server'],
  }

  file {'/etc/puppet/rack/public':
    owner   => puppet,
    group   => puppet,
    mode    => 0644,
    ensure  => directory,
    require => File['/etc/puppet/rack'],
  }


}
EOF

cat >> ${MODULE_PATH}/puppetmaster/files/puppet.conf << EOF
[main]
    # The Puppet log directory.
    # The default value is '\$vardir/log'.
    logdir = /var/log/puppet

    # Where Puppet PID files are kept.
    # The default value is '\$vardir/run'.
    rundir = /var/run/puppet

    # Where SSL certificates are kept.
    # The default value is '\$confdir/ssl'.
    ssldir = \$vardir/ssl

    # Pluginsync
    pluginsync = true

[agent]
    # The file in which puppetd stores a list of the classes
    # associated with the retrieved configuratiion.  Can be loaded in
    # the separate ``puppet`` executable using the ``--loadclasses``
    # option.
    # The default value is '\$confdir/classes.txt'.
    classfile = \$vardir/classes.txt

    # Where puppetd caches the local configuration.  An
    # extension indicating the cache format is added automatically.
    # The default value is '\$confdir/localconfig'.
    localconfig = \$vardir/localconfig

    server = ${FULL_HOSTNAME}

[master]

    certname = ${FULL_HOSTNAME}

    # Stored configs
    storeconfigs = true
    thin_storeconfigs = true
    dbname = puppet
    dbuser = puppet
    dbpassword = ${PUPPET_MYSQL_PASSWD}
    dbserver = localhost
    dbsocket = /var/run/mysqld/mysqld.sock

[production]
    # Production environment configuration
    modulepath=/etc/puppet/modules
    templatedir=/var/lib/puppet/templates
    manifest=/etc/puppet/manifests/site.pp
EOF

cat >> ${MODULE_PATH}/puppetmaster/files/autosign.conf <<EOF
# Change this to whitelist your DNS address e.g. *.example.com
EOF

cat >> ${MODULE_PATH}/puppetmaster/files/site.pp <<EOF
# Main Puppet site.pp

# Import our node definitions from a separate file
import 'nodes.pp'
EOF

cat >> ${MODULE_PATH}/puppetmaster/files/nodes.pp <<EOF
node default {
}
EOF

cat >> ${MODULE_PATH}/puppetmaster/files/puppetmaster.conf <<EOF
# you probably want to tune these settings
PassengerHighPerformance on
PassengerMaxPoolSize 12
PassengerPoolIdleTime 1500
# PassengerMaxRequests 1000
PassengerStatThrottleRate 120
RackAutoDetect Off
RailsAutoDetect Off

Listen 8140

<VirtualHost *:8140>
        SSLEngine on
        SSLProtocol -ALL +SSLv3 +TLSv1
        SSLCipherSuite ALL:!ADH:RC4+RSA:+HIGH:+MEDIUM:-LOW:-SSLv2:-EXP

        SSLCertificateFile      /var/lib/puppet/ssl/certs/${FULL_HOSTNAME}.pem
        SSLCertificateKeyFile   /var/lib/puppet/ssl/private_keys/${FULL_HOSTNAME}.pem
        SSLCertificateChainFile /var/lib/puppet/ssl/ca/ca_crt.pem
        SSLCACertificateFile    /var/lib/puppet/ssl/ca/ca_crt.pem
        # If Apache complains about invalid signatures on the CRL, you can try disabling
        # CRL checking by commenting the next line, but this is not recommended.
        SSLCARevocationFile     /var/lib/puppet/ssl/ca/ca_crl.pem
        SSLVerifyClient optional
        SSLVerifyDepth  1
        SSLOptions +StdEnvVars

        # This header needs to be set if using a loadbalancer or proxy
        RequestHeader unset X-Forwarded-For

        RequestHeader set X-SSL-Subject %{SSL_CLIENT_S_DN}e
        RequestHeader set X-Client-DN %{SSL_CLIENT_S_DN}e
        RequestHeader set X-Client-Verify %{SSL_CLIENT_VERIFY}e

        DocumentRoot /etc/puppet/rack/public/
        RackBaseURI /
        <Directory /etc/puppet/rack/>
                Options None
                AllowOverride None
                Order allow,deny
                allow from all
        </Directory>
</VirtualHost>
EOF

############
# Apply the puppet manifest
############
$PUPPET apply --modulepath=${MODULE_PATH} -e "include puppetmaster" 

# Set mysql root passwd
/usr/bin/mysqladmin -u root password '${MYSQL_PASSWD}'
#/usr/bin/mysqladmin -u root -h ${FULL_HOSTNAME} password '${MYSQL_PASSWD}'

# Create puppetdb
mysql -u root --password=${MYSQL_PASSWD} -e "create database puppet; grant all privileges on puppet.* to puppet@localhost identified by '${PUPPET_MYSQL_PASSWD}';"

# We need to generate the puppet ssl certs before we can start apache 
# perhaps there is a better way than doing this
/sbin/service puppetmaster start
/sbin/service puppetmaster stop

# Let's go!
/sbin/service httpd start
