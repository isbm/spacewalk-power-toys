#!/bin/sh
#
# Make your SUSE Manager cry
#

NCC_CREDS="/etc/zypp/credentials.d/NCCcredentials"
SYS_ID="/etc/sysconfig/rhn/systemid"

if [ -z "$3" ]; then
  echo "Usage: <host> <activation-key> <times>"
  echo
  echo "Example: $0 foo.bar.com 1-foo 10"
  echo

  exit 1;
fi

for ((i=1;i<=$3;i++));
  do
    if [ -e $NCC_CREDS ]; then
      rm $NCC_CREDS
    fi

    if [ -e $SYS_ID ]; then
      rm $SYS_ID
    fi

    rhnreg_ks --serverUrl=http://$1/XMLRPC --activationkey=$2
    echo "Registered $i servers"
done
