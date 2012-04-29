Usage
===========

These scripts have been created to be passed to the metadata service of any EC2 complient cloud but may also be run directly from the command line. To use with euca2ools first download the script to your local machine and then use ''euca-run-instances'' as shown below:

    euca-run-instances -k <my_key> -t <instance_size> -f <location_of_bootstrap_script> <emi>

A properly setup instance will then automatically download the script and install the configuration management assistant specified by the script.


