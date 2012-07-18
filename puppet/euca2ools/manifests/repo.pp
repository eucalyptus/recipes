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
# author: Andrew Hamilton (ahamilton@eucalyptus.com)
#

class euca2ools::repo {
  if $operatingsystem == "Ubuntu" {
    file { "/etc/apt/sources.list.d/euca2ools.list":
      ensure => present,
      owner => root,
      group => root,
      mode => 0600,
      content => template("euca2ools/euca2ools.list.erb"),
    }

    file { "/root/c1240596-eucalyptus-release-key.pub":
      ensure => present,
      owner => root,
      group => root,
      mode => 0600,
      source => "puppet:///modules/euca2ools/c1240596-eucalyptus-release-key.pub",
      require => File["/etc/apt/sources.list.d/euca2ools.list"],
    }
     
    exec { "add-repo-key":
      command => "/usr/bin/apt-key add /root/c1240596-eucalyptus-release-key.pub",
      require => File["/root/c1240596-eucalyptus-release-key.pub"],
    }

    # Run apt-get update when anything beneath /etc/apt/ changes
    # Found @ https://blog.kumina.nl/2010/11/puppet-tipstricks-running-apt-get-update-only-when-needed/
    exec { "apt-get update":
      command => "/usr/bin/apt-get update",
      onlyif => "/bin/sh -c '[ ! -f /var/cache/apt/pkgcache.bin ] || /usr/bin/find /etc/apt/* -cnewer /var/cache/apt/pkgcache.bin | /bin/grep . > /dev/null'",
      require => Exec["add-repo-key"],
    }
  } elsif $operatingsystem == "CentOS" or $operatingsystem == "RedHat" {
    file { "/etc/yum.repos.d/euca2ools.repo":
      ensure => present,
      owner => root,
      group => root,
      mode => 0644,
      source => "puppet:///modules/euca2ools/euca2ools.repo",
    }

    file { "/etc/pki/rpm-gpg/RPM-GPG-KEY-eucalyptus-release":
      ensure => present,
      owner => root,
      group => root,
      mode => 0600,
      source => "puppet:///modules/euca2ools/RPM-GPG-KEY-eucalyptus-release",
    }
  }
}
