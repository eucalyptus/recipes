#!/bin/bash
#
# Script to install gnome desktop accessible via VNC

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="gnomevncdesktop" # arbitrary name
WALRUS_IP="10.1.2.3" # IP of the walrus to use
WALRUS_ID="XXXXXXXXXXXXXXXXXXXXX" # EC2_ACCESS_KEY
WALRUS_KEY="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/gnomevncdesktop" # conf bucket
WALRUS_MASTER="gnomevncdesktop-archive.tgz" # master copy of the database

# yum related configuration
# leave these commented out to use the stock yum configuration for your instance
#YUM_CENTOS_BASE_URL='http://10.1.2.4/centos/$releasever/os/$basearch/'
#YUM_CENTOS_UPDATES_URL='http://10.1.2.4/centos/$releasever/updates/$basearch/'
#YUM_CENTOS_EXTRAS_URL='http://10.1.2.4/centos/$releasever/extras/$basearch/'
#YUM_CENTOS_CENTOSPLUS_URL='http://10.1.2.4/centos/$releasever/centosplus/$basearch/'
#YUM_CENTOS_CONTRIB_URL='http://10.1.2.4/centos/$releasever/contrib/$basearch/'
#EPEL_PACKAGE_URL='http://10.1.2.4/epel/5/x86_64/epel-release-5-4.noarch.rpm'
#YUM_EPEL_URL='http://10.1.2.4/epel/5/$basearch'
#YUM_EPEL_DEBUGINFO_URL='http://10.1.2.4/epel/5/$basearch/debug'
#YUM_EPEL_SOURCE_URL='http://10.1.2.4/epel/5/SRPMS'

# VNC related configuration
DNSNAME="gnomedesktop.mydomain.com" # the public hostname
MOUNT_POINT="/srv/data" # archives and data are on ephemeral
SCREEN_SIZE="1024x768" # screen size in pixels e.g. 800x600, 1024x768, 1280x1024, 1600x1200
VNCUSERNAME="user"
VNCUSERPASSWORD="password"

# do backup on walrus?
WALRUS_BACKUP="Y"

# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
if [ ! -f ${S3CURL} ]
then
  echo "Getting ${S3CURL}"
  curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
  chmod 755 ${S3CURL}
else
  echo "${S3CURL} already present"
fi

# now let's setup the id for accessing walrus
echo "Setting credentials for ${S3CURL}"
cat >${HOME}/.s3curl <<EOF
%awsSecretAccessKeys = (
${WALRUS_NAME} => {
url => '${WALRUS_IP}',
id => '${WALRUS_ID}',
key => '${WALRUS_KEY}',
},
);
EOF
chmod 600 ${HOME}/.s3curl

# customize yum configuration if applicable
if [ -n "$YUM_CENTOS_BASE_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/os/\$basearch/%baseurl=$YUM_CENTOS_BASE_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ -n "$YUM_CENTOS_UPDATES_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/updates/\$basearch/%baseurl=$YUM_CENTOS_UPDATES_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ -n "$YUM_CENTOS_EXTRAS_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/extras/\$basearch/%baseurl=$YUM_CENTOS_EXTRAS_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ -n "$YUM_CENTOS_CENTOSPLUS_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/centosplus/\$basearch/%baseurl=$YUM_CENTOS_CENTOSPLUS_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi
if [ -n "$YUM_CENTOS_CONTRIB_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=contrib%#\0%g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/\$releasever/contrib/\$basearch/%baseurl=$YUM_CENTOS_CONTRIB_URL%g" /etc/yum.repos.d/CentOS-Base.repo
fi

# install/customize EPEL repository
rpm -qa | grep -E '(^epel-release-)'
if [ $? -eq 1 ]
then
  if [ ! -n "$EPEL_PACKAGE_URL" ]
  then
    EPEL_PACKAGE_URL='http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm'
  fi
  wget $EPEL_PACKAGE_URL
  rpm -Uvh epel-release-*.noarch.rpm
else echo "EPEL package already installed"
fi

if [ -n "$YUM_EPEL_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-debug-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e "s%#baseurl=http://download.fedoraproject.org/pub/epel/5/\$basearch%baseurl=$YUM_EPEL_URL%g" /etc/yum.repos.d/epel.repo
fi

if [ -n "$YUM_EPEL_SOURCE_URL" ]
then
  sed -i -e 's%^mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-source-5&arch=$basearch%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e "s%#baseurl=http://download.fedoraproject.org/pub/epel/5/SRPMS%baseurl=$YUM_EPEL_SOURCE_URL%g" /etc/yum.repos.d/epel.repo
fi

# update the instance
yum check-update
if [ $? -eq 100 ]
then
  echo "Upgrading and installing packages"
  yum -y update
  shutdown -r now
else
  echo "No package updates"
fi

# install the Gnome deskop and dependencies
yum -y groupinstall base-x gnome-desktop

# install xinetd and firefox
yum -y install xinetd firefox

# modify /etc/services
if ! grep ^vnc /etc/services ; then
  sed -i -e 's/^\(indy.*5963\/tcp.*\)/vnc\t\t5900\/tcp\t\t\t# VNC\n\1/' /etc/services
fi

# modify /etc/gdm/custom.conf
if ! grep ^RemoteGreeter /etc/gdm/custom.conf ; then
  sed -i -e 's/^\(\[daemon\]\)/\1\nRemoteGreeter=\/usr\/libexec\/gdmgreeter/' /etc/gdm/custom.conf
fi
if ! grep ^Enable /etc/gdm/custom.conf ; then
  sed -i -e 's/^\(\[xdmcp\]\)/\1\nEnable=true/' /etc/gdm/custom.conf
fi
if ! grep ^DisallowTCP /etc/gdm/custom.conf ; then
  sed -i -e 's/^\(\[chooser\]\)/\1\nDisallowTCP=false/' /etc/gdm/custom.conf
fi

# create VNC desktop configuration
cat > /etc/xinetd.d/vnc << "EOF"
service vnc
{
        disable = no
        socket_type = stream
        protocol = tcp
        wait = no
        user = nobody
        server = /usr/bin/Xvnc
        server_args = -inetd -once -query localhost -geometry XINETDSCREENSIZE -depth 16 -SecurityTypes None
        port = 5900
        only_from = 127.0.0.1
}
EOF
sed -i -e "s/XINETDSCREENSIZE/$SCREEN_SIZE/" /etc/xinetd.d/vnc

# add the local user
useradd -d /home/${VNCUSERNAME} -m ${VNCUSERNAME}
echo $VNCUSERPASSWORD | passwd --stdin user

# configure the xinetd service
chkconfig xinetd on
service xinetd start

# change the current and default runlevels
init 5
sed -ie 's/id:3:initdefault:/id:5:initdefault:/g' /etc/inittab

