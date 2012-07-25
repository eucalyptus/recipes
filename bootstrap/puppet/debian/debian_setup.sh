#!/usr/bin/env bash
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
# author: Andrew Hamilton
#

FULL_HOSTNAME="myhost.mydomain"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
APTITUDE=`which aptitude`
APT_KEY=`which apt-key`
USE_PUPPET_REPO=1

###########
# Setup the hostname for the system. Puppet really relies on 
# the hostname so this must be done.
###########
hostname ${FULL_HOSTNAME}

sed -i -e "s/\(localhost\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts

###########
# Need to add in the aptitude workarounds for instances.
# * First disable dialog boxes for dpkg
# * Add the PPA for ec2-consistent-snapshot or else the update will hang.
###########
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

${APT_KEY} adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

##########
# Puppet APT Repository
# If $USE_PUPPET_REPO is non-zero then the Puppet APT repository will be used
# to install the puppet agent. Else the Ubuntu/Debian repo will be used.
##########
if [[ ${USE_PUPPET_REPO} ]]; then
    CODENAME=`lsb_release -c | awk '{print $2}'`
    echo -e "deb http://apt.puppetlabs.com/ ${CODENAME} main\ndeb-src http://apt.puppetlabs.com/ ${CODENAME} main" >> /etc/apt/sources.list.d/puppet.list
    apt-key  adv --keyserver keyserver.ubuntu.com --recv 4BD6EC30
fi

##########
# Update the instance and install the puppet agent
##########
${APTITUDE} update
${APTITUDE} -y safe-upgrade
${APTITUDE} -y install puppet

##########
# **** NOTE ****
# 
# Puppet is now installed. Below is a proof of concept that will use the puppet
# agent to install apache2 and vim on this instance. You may remove this if you
# only wanted the puppet agent installed.
##########

##########
# Install apache2 and vim using puppet
##########
PUPPET=`which puppet`

##########
# Setup the puppet manifest in /root/my_manifest
##########
cat >>/root/my_manifest.pp <<EOF
package {
    'apache2': ensure => installed
}

service {
    'apache2':
        ensure => true,
        enable => true,
        require => Package['apache2']
}

package {
    'vim': ensure => installed
}
EOF

############
# Apply the puppet manifest
############
$PUPPET apply /root/my_manifest.pp

############
# End of script cleanup.
############
export DEBIAN_FRONTEND=dialog
export DEBIAN_PRIORITY=high
