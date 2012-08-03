#!/bin/bash
#
# Simple script to setup planet (feed aggregator)
#

# where is the configuration stored
WALRUS_URL="http://173.205.188.8:8773/services/Walrus/euca-planet/"

# USER to own the planet's files (ubuntu for Ubuntu, and www-data for
# Debian)
PLANET_USER="www-data"
PLANET_GROUP="www-data"

# where is planet
WHERE="/mnt"

# update the instance
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# install planet-venus
apt-get install --force-yes -y planet-venus nginx

# create planet's structure
mkdir -pv ${WHERE}/cache ${WHERE}/output ${WHERE}/output/images ${WHERE}/theme ${WHERE}/theme/images
echo "<html></html>" >${WHERE}/output/index.html
cp -pv /usr/share/planet-venus/theme/common/* ${WHERE}/theme
cp -pvr /usr/share/planet-venus/theme/default/* ${WHERE}/theme
cp -pv /usr/share/planet-venus/theme/common/images/* ${WHERE}/output/images

# let's create a script to update the skinning of the planet
cat >${WHERE}/execute <<EOF
#!/bin/sh
curl -s -f -o ${WHERE}/planet.ini --url ${WALRUS_URL}/planet.ini
curl -s -f -o ${WHERE}/theme/index.html.tmpl --url ${WALRUS_URL}/index.html.tmpl
curl -s -f -o ${WHERE}/output/favicon.ico --url ${WALRUS_URL}/favicon.ico
curl -s -f -o ${WHERE}/output/images/logo.png --url ${WALRUS_URL}/logo.png
curl -s -f -o ${WHERE}/output/planet.css --url ${WALRUS_URL}/planet.css
cd ${WHERE} && planet --verbose planet.ini
EOF

# change execut permission
chmod +x ${WHERE}/execute

# and turn it into a cronjob
cat >${WHERE}/crontab <<EOF
2,17,32,47 * * * * ${WHERE}/execute
EOF

# change the ownership of all planet stuff
chown -R ${PLANET_USER}.${PLANET_GROUP} ${WHERE}
su -c "${WHERE}/execute" - ${PLANET_USER}

# and start the cronjob
crontab -u ${PLANET_USER} ${WHERE}/crontab

# let's remove the link to the default website
rm /etc/nginx/sites-enabled/default

# let's create our own simple configuration
cat >/etc/nginx/sites-available/eucalyptus <<EOF
server {
	listen   80; ## listen for ipv4
	listen   [::]:80 default ipv6only=on; ## listen for ipv6
	access_log /var/log/nginx/access.log;
	location / {
		root	${WHERE}/output;
		index	index.html;
	}
}
EOF

# and make it available
ln -s /etc/nginx/sites-available/eucalyptus /etc/nginx/sites-enabled/eucalyptus

# start the service
/etc/init.d/nginx restart

