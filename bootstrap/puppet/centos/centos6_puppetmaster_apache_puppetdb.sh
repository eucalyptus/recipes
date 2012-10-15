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
# It also sets up pluginsync and sets up puppetdb with a postgresql backend.
#
# Credits:
# Tom Ellis <tom.ellis@eucalyptus.com>
# Greg DeKoenigsberg <greg.dekoenigsberg@eucalyptus.com>

MYSQL_PASSWD="t3mp0rary"
PUPPET_MYSQL_PASSWD="t3mppupp3t"
YUM=`which yum`
RPM=`which rpm`
CURL=`which curl`
EPEL_PACKAGE="epel-release-6-7.noarch.rpm"
EPEL_URL="http://dl.fedoraproject.org/pub/epel/6/i386/"
PUPPETLABS_PACKAGE="puppetlabs-release-6-1.noarch.rpm"
PUPPETLABS_URL="http://yum.puppetlabs.com/el/6/products/x86_64/"
PASSENGER_PACKAGE="passenger-release.noarch.rpm"
PASSENGER_URL="http://passenger.stealthymonkeys.com/rhel/6/"
MODULE_PATH="/root/puppet/modules"
 
###########
# Setup the hostname for the system. Puppet really relies on 
# the hostname so this must be done.  The most reliable way
# is to pull it directly from the metadata service.
###########
FULL_HOSTNAME=`${CURL} http://169.254.169.254/latest/meta-data/public-hostname`
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
hostname ${FULL_HOSTNAME}

sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts
sed -i -e "s/HOSTNAME.*/HOSTNAME=${FULL_HOSTNAME}/g" /etc/sysconfig/network

###########
# Download and install EPEL repo which contains lots of useful packages.
###########
curl -o /root/${EPEL_PACKAGE} ${EPEL_URL}/${EPEL_PACKAGE}
${RPM} -Uhv /root/${EPEL_PACKAGE} 1>/tmp/01.out 2>/tmp/01.err

###########
# Download and install the puppetlabs repo which has new offical releases of puppet
###########
# EPEL contains Puppet 2.6. There are some cool features in 2.7 though, ymmv.
curl -o /root/${PUPPETLABS_PACKAGE} ${PUPPETLABS_URL}/${PUPPETLABS_PACKAGE} 1>/tmp/02.out 2>/tmp/02.err
${RPM} -Uhv /root/${PUPPETLABS_PACKAGE} 1>/tmp/03.out 2>/tmp/03.err

###########
# Download and install the passenger repo to allow puppet to scale
###########
curl -o /root/${PASSENGER_PACKAGE} ${PASSENGER_URL}/${PASSENGER_PACKAGE} 1>/tmp/04.out 2>/tmp/04.err
${RPM} -Uvh /root/${PASSENGER_PACKAGE} 1>/tmp/05.out 2>/tmp/05.err
# Note that the Passenger repo doesn't like the values for $releasever that Amazon AMIs give, 
# so we're going to cut those out and replace them with an explicit reference to Centos 6.
sed -i -e "s/\$releasever/6/" /etc/yum.repos.d/passenger.repo 

###########
# Update the instance and install the puppet agent
###########
${YUM} -y update 1>/tmp/06.out 2>/tmp/06.err
${YUM} -y install puppet 1>/tmp/07.out 2>/tmp/07.err

##########
# Configure puppet a puppetmaster using puppet
##########
PUPPET=`which puppet`

##########
# Setup the puppet manifest in /root/puppetmaster.pp
##########
mkdir -p ${MODULE_PATH}/puppetmaster/{files,manifests} 1>/tmp/08.out 2>/tmp/08.err
cat >> ${MODULE_PATH}/puppetmaster/manifests/init.pp <<EOF
class puppetmaster {
 package {
     'vim-enhanced': ensure => installed
 }

 package {
     'puppet-server': ensure => installed
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
    'httpd':
 	ensure => stopped,
 	enable => true,
        require => [ Package['httpd'], Package['mod_passenger'], File['puppetmaster.conf'] ],
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
$PUPPET apply --modulepath=${MODULE_PATH} -e "include puppetmaster" 1>/tmp/09.out 2>/tmp/09.err

# Cleanup
rm -rf /root/{$EPEL_PACKAGE,$PUPPETLABS_PACKAGE,$PASSENGER_PACKAGE,puppet} 1>/tmp/10.out 2>/tmp/10.err

# We need to generate the puppet ssl certs before we can start apache 
# perhaps there is a better way than doing this
/sbin/service puppetmaster start 1>/tmp/11.out 2>/tmp/11.err
/sbin/service puppetmaster stop 1>/tmp/12.out 2>/tmp/12.err

# Run the Puppetmaster
/sbin/service httpd start 1>/tmp/13.out 2>/tmp/13.err

############
# Install & configure puppetdb
############
# Grab the puppetdb module from puppet forge
$PUPPET module install puppetlabs-puppetdb 1>/tmp/14.out 2>/tmp/14.err

# Disable firewall modification (we use Eucalyptus security groups instead)
sed -i 's/manage_redhat_firewall = true/manage_redhat_firewall = false/g' /etc/puppet/modules/puppetdb/manifests/params.pp 1>/tmp/15.out 2>/tmp/15.err

# Install puppetdb
$PUPPET apply -e "include puppetdb" 1>/tmp/16.out 2>/tmp/16.err

# Tune puppetdb memory usage for large scale environments
sed -i 's/-Xmx192m/-Xmx1g/g' /etc/sysconfig/puppetdb 1>/tmp/17.out 2>/tmp/17.err

# Ensure puppetdb certs are setup correctly, then restart puppetdb
/usr/sbin/puppetdb-ssl-setup 1>/tmp/18.out 2>/tmp/18.err
/sbin/service puppetdb restart 1>/tmp/19.out 2>/tmp/18.err

# Configure puppetmaster to use puppetdb and restart puppetmaster
$PUPPET apply -e "include puppetdb::master::config" 1>/tmp/20.out 2>/tmp/20.err
/sbin/service httpd restart 1>/tmp/21.out 2>/tmp/21.err
