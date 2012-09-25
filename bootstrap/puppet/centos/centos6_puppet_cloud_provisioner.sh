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
# This recipe bootstraps a puppet client with the latest version of puppet and
# sets it up to run Puppet's cloud_provisioner module.  Tested with:
#   * Amazon Linux 2012.03 (ami-94cd60fd)
#
# Credits:
# Tom Ellis <tom.ellis@eucalyptus.com>
# Greg DeKoenigsberg <greg.dekoenigsberg@eucalyptus.com>

CURL=`which curl`
YUM=`which yum`
RPM=`which rpm`

# Pull the public hostname from the metadata server.
FULL_HOSTNAME=`${CURL} http://169.254.169.254/latest/meta-data/public-hostname`
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
EPEL_PACKAGE="epel-release-6-7.noarch.rpm"
EPEL_URL="http://dl.fedoraproject.org/pub/epel/6/i386/"
PUPPETLABS_PACKAGE="puppetlabs-release-6-5.noarch.rpm"
PUPPETLABS_URL="http://yum.puppetlabs.com/el/6/products/x86_64/"
MODULE_PATH="/root/puppet/modules"

# Setup the hostname for the system. Puppet really relies on 
# the hostname so this must be done.
hostname ${FULL_HOSTNAME}
sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts
sed -i -e "s/HOSTNAME.*/HOSTNAME=${FULL_HOSTNAME}/g" /etc/sysconfig/network

# Install NTP with default config - it's crucial for ssl based apps
yum -y install ntp 1>/tmp/010.out 2>/tmp/010.err
service ntpd start 1>/tmp/020.out 2>/tmp/020.err
chkconfig ntpd on 1>/tmp/030.out 2>/tmp/030.err

# Hey, running Amazon Linux?  Guess what?  They set their repos to have top priority
# by default!  We can't have that.  Tell yum not to check repo priorities.
rm /etc/yum/pluginconf.d/priorities.conf 

# Download and install EPEL repo which contains lots of useful pacakges.
curl -o /root/${EPEL_PACKAGE} ${EPEL_URL}/${EPEL_PACKAGE} 1>/tmp/040.out 2>/tmp/040.err
${RPM} -Uhv /root/${EPEL_PACKAGE} 1>/tmp/050.out 2>/tmp/050.err
rm /root/${EPEL_PACKAGE} 1>/tmp/060.out 2>/tmp/060.err

# Download and install the puppetlabs repo which has new offical releases of puppet
curl -o /root/${PUPPETLABS_PACKAGE} ${PUPPETLABS_URL}/${PUPPETLABS_PACKAGE} 1>/tmp/070.out 2>/tmp/070.err
${RPM} -Uhv /root/${PUPPETLABS_PACKAGE} 1>/tmp/080.out 2>/tmp/080.err
rm /root/${PUPPETLABS_PACKAGE} 1>/tmp/090.out 2>/tmp/090.err

# Update the node and install the puppet agent
${YUM} -y update 1>/tmp/100.out 2>/tmp/100.err
${YUM} -y install puppet 1>/tmp/110.out 2>/tmp/110.err

# Fog requires a ton of stuff, so install lots of tools. :)
${YUM} -y groupinstall 'Development Tools' 1>/tmp/115.out 2>/tmp/115.err
${YUM} -y install rubygems ruby-devel libxml2 libxml2-devel libxslt libxslt-devel 1>/tmp/120.out 2>/tmp/120.err

PUPPET=`which puppet`
GEM=`which gem`

# OK, with rubygems installed, install Fog, which is Ruby's cloud library.
# We also need guid.
${GEM} install fog -v 0.7.2 1>/tmp/130.out 2>/tmp/130.err
${GEM} install guid 1>/tmp/140.out 2>/tmp/140.err

# Now install puppet-module so we can install modules directly from
# the Puppet module repository.
${GEM} install puppet-module 1>/tmp/150.out 2>/tmp/150.err

# Go to the directory where Puppet modules are kept.
cd $(${PUPPET} --configprint confdir)/modules

# Now install the cloud_provisioner module!
puppet-module install puppetlabs/cloud_provisioner 1>/tmp/160.out 2>/tmp/160.err

# After this, you still need to configure the system to actually provision some
# cloud instances, which means setting up your EC2/Euca credentials.  To go on
# from here, check out:
#
# http://docs.puppetlabs.com/guides/cloud_pack_getting_started.html
# http://forge.puppetlabs.com/puppetlabs/cloud_provisioner
#
# Here's what I did to get the client working:
# 
# export RUBYLIB=/etc/puppet/modules/cloud_provisioner/lib/:$RUBYLIB
#   (to get the path working)
# puppet help node_aws
#   (to ensure that it installed correctly, should get useful help)
# edit the .fog file to add key info
#   (follow instructions at http://docs.puppetlabs.com/guides/cloud_pack_getting_started.html)
# FIXME: more here
# 
# TODO:
#   * Add this module to global ruby load path
