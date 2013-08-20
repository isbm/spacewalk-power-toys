#!/bin/sh

HOST=$1
KEY=$2

function usage() {
    echo "Usage: centos6-client <spacewalk-host> <activation-key>"
    exit;
}

if [ -z $HOST ]; then
    usage;
fi

if [ -z $KEY ]; then
    usage;
fi

rpm -Uvh http://yum.spacewalkproject.org/2.0-client/RHEL/6/x86_64/spacewalk-client-repo-2.0-3.el6.noarch.rpm
rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/$BASEARCH/epel-release-6-8.noarch.rpm
yum install -y wget rssh rhn-client-tools rhn-check rhn-setup rhnsd m2crypto yum-rhn-plugin

# Register
rhnreg_ks --serverUrl=http://$1/XMLRPC --activationkey=$2

