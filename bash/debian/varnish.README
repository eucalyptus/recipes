Varnish Recipe
---------------

This recipe is for deploying a varnish cache web server for information stored in a Walrus bucket. It has been developed to be used with our starter images (debian-based). This is what we use for deploying tar-gzipped EMIs though emis.eucalyptus.com.  

Details
--------

The variables that need to be set in the script are as follows:

CLC_IP 					=>	IP address of the Cloud Controller
WALRUS_IP				=>	IP address of the Walrus
EC2_ACCESS_KEY	=>	EC2 Access Key (located in eucarc file)
EC2_SECRET_KEY	=>	EC2 Secret Key (located in eucarc file)
INSTALL_PATH		=>	Location where configs will be placed when downloading from Walrus

The script will do the following:
	
		* update the packages and repos on the instance (debian based)
		* downloads the patched version of s3cmd that works with Eucalyptus Walrus
		* installs varnish
		* creates and attaches an EBS volume (used for varnish cache)
		* downloads varnish configuration files from Walrus bucket, and updates varnish config (for more information about configuring varnish, please see https://www.varnish-cache.org/docs)
		
After the EBS volume is created, it is formatted with an XFS filesystem, and mounted under /mnt/web-cache. 

Usage
------

Make sure you have a security group which allows the following ports to be open:

 	* the port you configure varnish to use for clients to access varnish web cache
 	* port 80 so that varnish can access Walrus
 	* ssh for instance access via ssh

For example:

	euca-add-group -d "varnish security group" varnish
	euca-authorize -p <varnish port> -P tcp -s 0.0.0.0/0 varnish
	euca-authorize -p 80 -P tcp -s <ip of walrus>/31 varnish
	euca-authorize -p 22 -P tcp -s 0.0.0.0/0 varnish
	
When starting with one of our debian-based images you can do something like

		euca-run-instance -g varnish -k XXXX emi-XXXXXX -f varnish.sh
