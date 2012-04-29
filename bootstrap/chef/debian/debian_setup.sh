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

#######
# Install the Chef client and then install nginx using chef-solo.
#######
APT_KEY=`which apt-key`
APTITUDE=`which aptitude`
HOSTNAME=`which hostname`

SYSTEM_NAME="chef.mydomain.int"
SHORT_SYSTEM_NAME=`echo ${SYSTEM_NAME} | cut -d'.' -f1`

COOKBOOK_REPO="https://nodeload.github.com/opscode/cookbooks/tarball/master"
CHEF_DIR="/var/chef-solo/"
CHEF=""

DEFAULT_DIR="/root/"

#######
# Setup the hostname on the system
#######
${HOSTNAME} ${SYSTEM_NAME}
echo ${SYSTEM_NAME} > /etc/hostname
sed -i -e "s/\(localhost.localdomain\)/${SYSTEM_NAME} ${SHORT_SYSTEM_NAME} \1/" /etc/hosts

#######
# Make aptitude stop asking questions
#######
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

#######
# Make sure that lsb_release is installed
#######
if [ -z `which lsb_release` ]; then 
    ${APTITIDUE} -y install lsb-release
fi

#######
# Setup the OpsCode APT repo
#######
echo "deb http://apt.opscode.com/ `lsb_release -cs`-0.10 main" | tee /etc/apt/sources.list.d/opscode.list

${APT_KEY} adv --keyserver keyserver.ubuntu.com --recv-keys 83EF826A

#######
# Install the ec2-consistent shapshot PPA key for easier updating of ECC images
#######
${APT_KEY} adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

#######
# Update the system
#######
${APTITUDE} update
${APTITUDE} -y safe-upgrade

#######
# Install chef-solo
#######
${APTITUDE} -y install chef

########
# **** NOTE ****
#
# The chef client is now installed. You can remove the rest of this script if you
# do not wish to install nginx. This is a proof of concept part of the script
# and is not needed.
########

########
# Now use chef-solo to install nginx
########

CHEF=`which chef-solo`

#######
# Create the needed config files for chef-solo
#
# solo.rb   -- Basic configuration for chef-solo
# node.json -- Information we want to give to chef-solo about the what
#              to install.
########
cat >>${DEFAULT_DIR}/solo.rb <<EOF
file_cache_path "${CHEF_DIR}"
cookbook_path ["${CHEF_DIR}/cookbooks"]
EOF

cat >>${DEFAULT_DIR}/node.json <<EOF
{
    "run_list": [ "recipe[nginx]" ]
}
EOF

########
# Create the chef-solo cookbooks directory
########
mkdir -p ${CHEF_DIR}/cookbooks

########
# Download the OpsCode GitHub cookbook repo. Move the nginx cookbook to 
# the chef-solo cookbooks directory created above.
########
curl -o ${DEFAULT_DIR}/cookbooks.tgz ${COOKBOOK_REPO}
tar xzvf ${DEFAULT_DIR}/cookbooks.tgz -C ${DEFAULT_DIR}
cp -R ${DEFAULT_DIR}/opscode-cookbooks-*/nginx/ ${CHEF_DIR}/cookbooks/

########
# Run chef-solo to install the cookbooks refrenced in node.json above
########
${CHEF} -c ${DEFAULT_DIR}/solo.rb -j ${DEFAULT_DIR}/node.json 

########
# Create the basic directory structure for nginx and a basic index.html
########
mkdir -p /var/www/nginx-default

cat >>/var/www/nginx-default/index.html <<EOF
<html>
  <head><title>Testing nginx Installation</title></head>
  <body>
    <h1>My temporary site after installing nginx with Chef!</h1>
  </body>
</html>
EOF

############
# End of script cleanup.
############
export DEBIAN_FRONTEND=dialog
export DEBIAN_PRIORITY=high
