#!/bin/bash

# Script installs varnishd, and attachs a volume for the storage of the cache
# for varnishd.  The configuration files of varnish are stored in Walrus.
# Additionally, we log progress of everything in root.  The assumption is to 
# have a Debian installation, thus we'll look for Debian's style configuration 
# and modify it accordingly.

# export Cloud Controller IP Address
export CLC_IP="<ip-address>"

# export Walrus IP
export WALRUS_IP="<ip-address>"

# variables for euca2ools
# Define EC2 variables for volume creation
export EC2_URL="http://${CLC_IP}:8773/services/Eucalyptus"
export EC2_ACCESS_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxx'
export EC2_SECRET_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxx'

# location where configs will be downloaded
export INSTALL_PATH="/root"

# bucket location and file name for varnish configs
export VARNISH_BUCKET=""
export VARNISH_CONFIG_FILENAME=""

# Activate ec2-consistent-snapshot repo
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

# Add euca2ools repo
echo "deb http://eucalyptussoftware.com/downloads/repo/euca2ools/1.3.1/debian squeeze main" > /etc/apt/sources.list.d/euca2ools.list

# Update repositories and packages
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# Install euca2ools, sudo, python-boto, less, ntpdate, and mlocate
apt-get --force-yes -y install sudo euca2ools python-boto less ntpdate mlocate

# install varnish - HTTP Accelerator
apt-get --force-yes -y install varnish

# set date
ntpdate pool.ntp.org

# set up information for s3cmd
# get s3cmd script
cd /root
wget http://173.205.188.8:8773/services/Walrus/s3-tools/s3cmd-0.9.8.3-patched.tgz
tar -zxf s3cmd-0.9.8.3-patched.tgz

# create s3curl config file 
echo "Creating s3cmd config file...."
cat >${INSTALL_PATH}/s3cfg <<EOF
[default]
access_key = ${EC2_ACCESS_KEY}
acl_public = False
bucket_location = US
debug_syncmatch = False
default_mime_type = binary/octet-stream
delete_removed = False
dry_run = False
encrypt = False
force = False
gpg_command = /usr/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase = 
guess_mime_type = False
host_base = ${WALRUS_IP}:8773 
host_bucket = ${WALRUS_IP}:8773
human_readable_sizes = False
preserve_attrs = True
proxy_host = 
proxy_port = 0
recv_chunk = 4096
secret_key = ${EC2_SECRET_KEY}
send_chunk = 4096
use_https = False
verbosity = WARNING
EOF
chmod 600 ${INSTALL_PATH}/s3cfg

# create volume used for EMI cache, then attach to instance

INSTANCEID=`curl http://169.254.169.254/latest/meta-data/instance-id`
VOLID=`euca-create-volume -s 15 -z production | awk '{print $2}'`

printf "%s\n" "Volume ${VOLID} created successfully for ${INSTANCEID}." >> /root/volume-attach-status.txt

if [ -n "${VOLID}" ] ; then
	STATUS=`euca-describe-volumes ${VOLID} | awk '{print $5}'`
	printf "%s\n" "Volume $VOLID has status of $STATUS." >> /root/volume-attach-status.txt

	until [ "${STATUS}" = "available" ] ; do
		sleep 10
		printf "%s\n" "Volume ${VOLID} has status of ${STATUS}." >> /root/volume-attach-status.txt
		STATUS=`euca-describe-volumes ${VOLID} | awk '{print $5}'`
	done

	euca-attach-volume --instance ${INSTANCEID} --device /dev/sdb ${VOLID}
	while [ ! -e /dev/sdb ] ; do
		echo "Waiting for volume to mount."
		sleep 5
	done
	echo "Volume mounted."
	
fi

# if mounting was successful, then format the block device and mount it for varnish to use.
if [ -e /dev/sdb ] ; then
	# format device to xfs, and mount for varnish cache
	printf "%s\n" "Formatting block device and mounting cache directory for varnish." >> /root/varnish-download-status.txt

	mkfs.xfs /dev/sdb
	sleep 10
	echo "/dev/sdb /mnt/web-cache xfs noatime,nobarrier 0 0" | tee -a /etc/fstab	
	mkdir -p /mnt/web-cache
	mount /mnt/web-cache
	mkdir /mnt/web-cache/debian
	chown -R varnish:varnish /mnt/web-cache/debian

	printf "%s\n" "Done formatting and mounting /mnt/web-cache." >> /root/varnish-download-status.txt
fi

# if web cache is created successful, then grab varnish configs, then start varnish
if [ -d /mnt/web-cache ] ; then

	printf "%s\n" "Using s3cmd to download varnish configs..." >> /root/varnish-download-status.txt
	./s3cmd-0.9.8.3-patched/s3cmd --config=s3cfg get s3://starter-emis-config/varnish-configs.tgz ${INSTALL_PATH}/varnish-configs.tgz

	if [ -e ${INSTALL_PATH}/varnish-configs.tgz ] ; then
		echo "Untarring varnish config..."
	        printf "%s\n" "Untarring varnish config..." >> /root/varnish-download-status.txt
		tar -zxf /root/varnish-configs.tgz
	fi

	if [ -e ${INSTALL_PATH}/default.vcl ] && [ -e ${INSTALL_PATH}/varnish ] ; then
		/bin/cp /root/default.vcl /etc/varnish/default.vcl
		/bin/cp /root/varnish /etc/default/varnish
		/etc/init.d/varnish restart
	fi

fi
