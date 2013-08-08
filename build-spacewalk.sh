#!/bin/bash
#
# Copyright (c) 2013, SUSE Linux Products GmbH
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer. Redistributions in binary 
# form must reproduce the above copyright notice, this list of conditions and the
# following disclaimer in the documentation and/or other materials provided with
# the distribution.
#
# Neither the name of the SUSE Linux Products GmbH nor the names of its contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE. 
#
#
# Automated Spacewalk Environment script.
# Aimed to working with the remote Spacewalk machine.
#
# Author: Bo Maryniuk <bo@suse.de>
#
# NOTE: You can freely migrate this to Ant XML and support
#       continuous discrepancies between the branches, or you
#       can improve use this script that would be impact-less
#       to the main Spacewalk development environment.


function check_env() {
#
# Check if all required commands are in place.
#
    EXIT=""
    for cmd in "rsync" "ant" "javac" \
               "ssh" "hostname" "awk" \
               "cat" "pwd" "curl" "sudo" \
               "sed" "yum" "grep" "basename"; do
	LOC=`which $cmd 2>/dev/null`
	if [ -z $LOC ]; then
	    echo "Error: '$cmd' is missing."
	    EXIT="1"
	fi
    done

    if [ "$EXIT" = "1" ]; then
	echo
	exit;
    fi
}


function correct_location() {
#
# Check if this script is running from the correct location.
#
    if [ "$(basename $(pwd))" != "java" ]; then
	echo "Error: Please call me from SPACEWALK_SOURCES/java directory."
	echo
	exit;
    fi
}

function can_sudo() {
#
# Check if user has sudo access.
#
    if [ ! -z "$(sudo -v 2>&1)" ]; then
	echo "Error: You seems to have no sudo access to this machine."
	echo
	exit;
    fi
}

function get_config_value() {
#
# Get a configuration value
#
    eval "cat ./.build-spacewalk 2>/dev/null | awk '{if (\$1\$2 == \"$1\") print \$4}'"
}


function set_target_host() {
#
# Set default target host
#
    host="localhost";
    if [ -z "$1" ]; then
	confhost=$(get_config_value "deploytarget")
	if [ -z $confhost ]; then
	    host=`/bin/hostname`;
	else
	    host=$confhost;
	fi
    else
	host=$1
    fi

    echo $host;
}


function set_default_operation() {
#
# Set default operation on the mode
#
    echo $([ -z $1 ] && get_config_value "defaultmode" || echo $1);
}


function set_tomcat_version() {
#
# Set target tomcat version. Default is "Tomcat 6".
#
    op=$(get_config_value "tomcatversion");
    echo $([ -z $op ] && echo "6" || echo $op)
}


function rebuild_all() {
#
# Rebuild everything.
#
    ant clean
    ant init-install compile
    ant unwar-webapp
}


function refresh_webapp() {
#
# Refresh web (JSP) part of the application.
#
    ant unwar-webapp
}


function refresh_bin() {
#
# Refresh binary part of the application.
#
    ant pack-megajar
}


function deploy_webapp() {
#
# Deploy only web (JSP) part of the application.
#
    echo "Deploying webapp"
    ROOT="build/webapp/rhnjava/WEB-INF";
    DEST="/var/lib/tomcat6/webapps/rhn/WEB-INF"
    ssh $USER@$HOST mkdir -p $DEST
    for FOBJ in `ls $ROOT`; do
	if [ $FOBJ != "lib" ]; then
	    echo "Syncing $FOBJ"
	    rsync -u -r --delete --verbose $ROOT/$FOBJ  $USER@$HOST:$DEST
	fi
    done
}


function deploy_binary() {
#
# Deploy only binary part of the application.
#
    echo "Deploying binary"
    ROOT="build/run-lib/rhn.jar";
    DEST="/usr/share/rhn/lib"
    ssh $USER@$HOST mkdir -p $DEST
    for FOBJ in "build/run-lib/rhn.jar"; do
	FNAME=`basename $FOBJ`
	echo "Syncing $FNAME"
	rsync -u -r --delete --verbose $FOBJ  $USER@$HOST:$DEST/$FNAME
    done
}


function synchronize_webinf_lib() {
#
# Synchronize WEB-INF/lib
#
    cat <<EOF
    NOTE: At the moment synchronization with remote WEB-INF/lib is not supported.
          Please move the JAR files yourself manually and restart the tomcat.
          Next binary or webapp refresh will not affect this change.

EOF
    exit;
}


function restart_services() {
#
# Restart services
#
    echo "Restart services on $1"
    for service in "tomcat6" "taskomatic"; do
	echo "Requesting $service restart"
	ssh $USER@$1 nohup service $service restart
    done
}


function utl_get_distro_name() {
#
# CentOS and RHEL gets "RHEL"
#
    DISTRO=$(cat /etc/redhat-release | awk '{print tolower($1)}')
    if { [ "$DISTRO" = "centos" ] || [ "$DISTRO" = "rhel" ]; } then
	echo "RHEL"
    else
	echo "Fedora"
    fi
}


function utl_get_distro_version() {
#
# Get the version of the distribution (Fedora or RHEL or CentOS)
#
    echo $(cat /etc/redhat-release | awk 'match($0, /[0-9]+/) {print substr($0, RSTART, RLENGTH)}')
}


function utl_url_find_package() {
#
# Scrap the RPM package name from the web resource.
#
    echo $(eval "curl -s $1 | grep $2 | awk 'match(\$0,/>$2.*?rpm/){print substr(\$0,RSTART+1,RLENGTH-1)}'")
}


function setup_install_spacewalk() {
#
# Installs Spacewalk on the localhost.
#
    URL="http://yum.spacewalkproject.org/nightly"
    DST=$(utl_get_distro_name)
    VER=$(utl_get_distro_version)
    PLT=$(uname -m)

    # Install repo
    echo "Looking for the Spacewalk repository RPM. Please wait..."
    RPM=$(utl_url_find_package "$URL/$DST/$VER/$PLT/" "spacewalk-repo-")
    echo "Found: $RPM"
    sudo rpm -Uvh $URL/$DST/$VER/$PLT/$RPM

    # Enable nightly
    sudo sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/spacewalk-nightly.repo
    sudo sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/spacewalk.repo

    # JPackage repo
    sudo cat > /etc/yum.repos.d/jpackage-generic.repo << EOF
[jpackage-generic]
name=JPackage generic
#baseurl=http://mirrors.dotsrc.org/pub/jpackage/5.0/generic/free/
mirrorlist=http://www.jpackage.org/mirrorlist.php?dist=generic&type=free&release=5.0
enabled=1
gpgcheck=1
gpgkey=http://www.jpackage.org/jpackage.asc
EOF

    # EPEL repo
    echo "Looking for the EPEL repository RPM. Please wait..."
    URL="http://dl.fedoraproject.org/pub/epel"
    RPM=$(utl_url_find_package "$URL/$VER/$PLT/" "epel-release-")
    echo "Found: $RPM"
    sudo rpm -Uvh $URL/$VER/$PLT/$RPM

    # Database server
    sudo yum install spacewalk-setup-postgresql

    # Install spacewalk
    sudo yum install spacewalk-postgresql

    # Configure firewall
    sudo system-config-firewall

    # Configure Spacewalk
    sudo spacewalk-setup --disconnected

    # Finished
    exit;
}


function setup_generate_config() {
#
# Generate default configuration for this tool.
# This way you can save your command-line every time you call this.
#
    ROOT=`pwd`
    CFG=".build-spacewalk"
    MODE=$(set_default_operation $1)
    HOST=$(set_target_host $2)
    STAMP=`date`
    cat > $ROOT/$CFG <<EOF
# Configuration for the build spacewalk tool.
# Generated at $STAMP

deploy target = $HOST
default mode = $MODE
tomcat version = 6

EOF
    echo "New config has been written: $ROOT/$CFG"
    echo

    exit;
}

function header() {
#
# Print header
#
  cat << LINE
RedHat Spacewalk builder and deployment tool, v 0.1.

LINE
}


function usage() {
#
# Print usage
#
  cat << LINE
Usage: [setup] <mode> [host]

Setup:
    --generate-config     Generate default configuration.
                          NOTE: It will default to the localhost,
                                therefore please edit it.

    --install-spacewalk   Install the Spacewalk from scratch on the
                          localhost machine.

                          NOTE: It does really wipe out everything
                                Spacewalk-related on your LOCAL host!

                          NOTE: This operation does not supports remote
                                Spacewalk installation.


Modes:
    -r    Cleanup everything, rebuild all.

    -w    Refresh only Web app.

    -b    Refresh only binary part of application.
          NOTE: This does not affects WEB-INF/lib!

    -a    Refresh all, web app and the binary.

    -l    Synchronize library with remote WEB-INF/lib

    -h    This help message.

Deployment host:
        Specify a hostname to deploy on via SSH.
        All commands are done from the "root" account,
        so make sure you've deployed your keys there.

LINE
exit;
}



# +----------+
# |   Main   |
# +----------+

header;

# Checks
correct_location;
can_sudo;
check_env;

export ANT_HOME=/usr/share/ant
HOST=$(set_target_host $2)
USER="root"
MODE=$(set_default_operation $1)
TOMCAT_VERSION=$(set_tomcat_version)

if { [ "$MODE" = "-h" ] || [ "$MODE" = "" ]; } then
    usage;
else
    if [ "$MODE" = "-r" ]; then
	rebuild_all;
	deploy_webapp;
	deploy_binary;
    elif [ "$MODE" = "-w" ]; then
	refresh_webapp;
	deploy_webapp;
    elif [ "$MODE" = "-b" ]; then
	refresh_bin;
	deploy_binary;
    elif [ "$MODE" = "-a" ]; then
	refresh_webapp;
	refresh_bin;
	deploy_webapp;
	deploy_binary;
    elif [ "$MODE" = "-l" ]; then
	synchronize_webinf_lib;
    elif [ "$MODE" = "--generate-config" ]; then
	setup_generate_config $2 $3;
    elif [ "$MODE" = "--install-spacewalk" ]; then
	setup_install_spacewalk;
    else
	usage;
    fi
    restart_services $HOST
fi
