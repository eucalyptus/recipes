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
# author: Andrew Hamilton
#

FULL_HOSTNAME="myhost.mydomain"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
YUM=`which yum`
RPM=`which rpm`
EPEL_PACKAGE="epel-release-6-7.noarch.rpm"
EPEL_URL="http://dl.fedoraproject.org/pub/epel/6/i386/"

###########
# Setup the hostname for the system. Puppet really relies on 
# the hostname so this must be done.
###########
hostname ${FULL_HOSTNAME}

sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts

echo -n ${FULL_HOSTNAME} >> /etc/sysconfig/network

###########
# Download and install EPEL repo which contains the puppet agent.
###########
curl -o /root/${EPEL_PACKAGE} ${EPEL_URL}/${EPEL_PACKAGE}

${RPM} -Uhv /root/${EPEL_PACKAGE}

###########
# Update the instance and install the puppet agent
###########
${YUM} -y update
${YUM} -y install puppet

###########
# **** NOTE ****
#
# Puppet is now installed. Below is a proof of concept that will use the puppet
# agent to install httpd and vim on this instance. You may remove this if you 
# only wanted the puppet agent installed.
##########

##########
# Install httpd using puppet
##########

PUPPET=`which puppet`

##########
# Setup the puppet manifest in /root/my_manifest
##########
cat >>/root/my_manifest.pp <<EOF
package {
    'httpd': ensure => installed
}

service {
    'httpd':
        ensure => true,
        enable => true,
        require => Package['httpd']
}

package {
    'vim-enhanced': ensure => installed
}
EOF

############
# Apply the puppet manifest
############
$PUPPET apply /root/my_manifest.pp

