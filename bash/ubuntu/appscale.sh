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

# Write this into a script to be forked separately.  This is to work around
# potential systemd timeout issues.
cat >> /root/boot-script.bash <<EOF
apt-get -y update 1>/tmp/01.out 2>/tmp/01.err
apt-get -y install less bind9utils dnsutils mdadm git-core 1>/tmp/02.out 2>/tmp/02.err

# installs appscale on the image
cd ~
git clone git://github.com/AppScale/appscale.git 1>/tmp/03.out 2>/tmp/03.err
cd appscale/debian 1>/tmp/04.out 2>/tmp/04.err
bash appscale_build.sh 1>/tmp/05.out 2>/tmp/05.err

# installs the appscale tools on the image
cd ~
git clone git://github.com/AppScale/appscale-tools.git trunk-tools 1>/tmp/06.out 2>/tmp/06.err
cd trunk-tools/debian 1>/tmp/07.out 2>/tmp/07.err
bash appscale_build.sh 1>/tmp/08.out 2>/tmp/08.err

EOF

/bin/bash /root/boot-script.bash &





