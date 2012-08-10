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

# Setup the system's hostname.
FULL_HOSTNAME="myhost.mydomain"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`
hostname ${FULL_HOSTNAME}
sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts
echo -n ${FULL_HOSTNAME} >> /etc/sysconfig/network

# Write this into a script to be forked separately.  This is to work around
# the systemd timeout issue.  Future versions of cloud-init should perhaps
# handle this case.
cat >> /root/boot-script.bash <<EOF
# First, update all packages.
yum -y update 1>/tmp/01.out 2>/tmp/01.err

# Next, install mock and sudo to allow package building.
yum -y install mock 1>/tmp/02.out 2>/tmp/02.err
yum -y install sudo 1>/tmp/03.out 2>/tmp/03.err

# Next, create user for building packages and put that 
# user in the right groups. 
useradd mock -g mock 1>/tmp/04a.out 2>/tmp/04a.err 
useradd builder 1>/tmp/04.out 2>/tmp/04.err
usermod -a -G mock builder 1>/tmp/05.out 2>/tmp/05.err

# A hack to move builder's homedir into the bigger mount directory.
# mv /home/builder /mnt/home-builder 1>/tmp/04a.out 2>/tmp/04a.err
# ln -s /mnt/home-builder /home/builder 1>/tmp/04b.out 2>/tmp/04b.err

# Install rake and other goodness.
yum -y install git rubygem-rake ntp 1>/tmp/06.out 2>/tmp/06.err

# Get the latest crankcase repo.
su builder -c "cd /home/builder ; git clone git://github.com/openshift/crankcase.git /home/builder/crankcase" 1>/tmp/07.out 2>/tmp/07.err

# A hack to fix an issue in the Rakefile
perl -pi -e 's/.*getlogin.*//;' /home/builder/crankcase/build/Rakefile

# Start building!
su builder -c "cd /home/builder/crankcase" 1>/tmp/08.out 2>/tmp/08.err
cd /home/builder/crankcase/build ; rake build_setup 1>/tmp/09.out 2>/tmp/09.err
cd /home/builder/crankcase/build ; rake devbroker 1>/tmp/10.out 2>/tmp/10.err
EOF

/bin/bash /root/boot-script.bash &

