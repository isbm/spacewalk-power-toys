#!/bin/bash -i
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


ABOUT="Automated Spacewalk Environment Tool, version 0.2"


function check_env() {
#
# Check if all required commands are in place.
#
    WARN=$1
    EXIT=""
    for cmd in "rsync" "ant" "javac" \
               "ssh" "hostname" "awk" \
               "cat" "pwd" "curl" "sudo" \
               "sed" "yum" "grep" "basename" \
               "dialog" "md5sum"; do
	LOC=$(which $cmd 2>/dev/null)
	LOC_CMD=$(echo $LOC | grep alias | awk '{print $1}')
	if { [ "$LOC_CMD" == "alias" ] && [ ! -z $WARN ]; } then
	    echo "Warning: Command \"$cmd\" is an alias to \"$(echo $LOC | grep alias)\""
	elif [ -z "$LOC" ]; then
	    echo "Error: '$cmd' is missing."
	    EXIT="1"
	fi
    done

    if [ "$EXIT" = "1" ]; then
	echo
	echo "Hint: Hey, maybe run with --init-environment option, perhaps?"
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
    eval "cat ./.build-spacewalk 2>/dev/null | grep -v \# | sed 's/\s//g' | grep $1 | sed 's/.*=//g'"
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


function check_java_style() {
#
# Check Java code style
#
    PATTERN=$1
    ALL=""
    if [ -z $PATTERN ]; then
	PATTERN="*.java"
	ALL="1"
    else
	PATTERN="*"$(echo "$PATTERN" | sed 's/.java//g')"*.java"
    fi

    if [ -z $(which checkstyle 2>/dev/null) ]; then
	sudo yum --assumeyes install checkstyle
    fi

    if [ -z $ALL ]; then
	echo "Checking the style of certain Java sources."
    else
	echo "Checking the style of all Java sources. This may take a while..."
    fi

    export CLASSPATH="build/classes"
    export BASE_OPTIONS="-Djavadoc.method.scope=public \
-Djavadoc.type.scope=package \
-Djavadoc.var.scope=package \
-Dcheckstyle.cache.file=build/checkstyle.cache.src \
-Djavadoc.lazy=false \
-Dcheckstyle.header.file=buildconf/LICENSE.txt"
    find . -iname $PATTERN | grep -vE '(/test/|/jsp/|/playpen/)' | \
	xargs checkstyle -c buildconf/checkstyle.xml | \
	sed 's/\.\///' | \
	sed 's/\//\n\//' | \
	sed 's/:\s/\n\t/'

    if [ ! -z $ALL ]; then
	echo "Checking the stype of Java sources for testing"
	export BASE_OPTIONS="-Djavadoc.method.scope=nothing \
-Djavadoc.type.scope=nothing \
-Djavadoc.var.scope=nothing \
-Dcheckstyle.cache.file=build/checkstyle.cache.test \
-Djavadoc.lazy=false \
-Dcheckstyle.header.file=buildconf/LICENSE.txt"
	find . -name *.java | grep -E '/test/' | grep -vE '(/jsp/|/playpen/)' | \
	    xargs checkstyle -c buildconf/checkstyle.xml | \
	    sed 's/\.\///' | \
	    sed 's/\//\n\//' | \
	    sed 's/:\s/\n\t/'
    fi
}


function clean_workspace() {
#
# Remove all project-related items from the workspace. 
#
    ant clean

    ANTLIB_DIR="$HOME/.ant/lib"
    SRC_LIB="$(pwd)/lib"

    if [ ! -d "$ANTLIB_DIR" ]; then
	mkdir -p $ANTLIB_DIR
    fi

    echo "Removing symbolic links to libraries in private Ant environment..."
    for j in $(ls ./lib); do
	MJ="$(md5sum $(echo $SRC_LIB/$j) | awk '{print $1}').jar"
	if [ -f $ANTLIB_DIR/$MJ ]; then
	    rm $ANTLIB_DIR/$MJ
	    echo "    Removed: $j"
	fi
    done

    echo
    echo "Done"
    echo
}


function rebuild_all() {
#
# Rebuild everything, assuming we are in the $SPACEWALK/java directory.
#
    ANTLIB_DIR="$HOME/.ant/lib"
    SRC_LIB="$(pwd)/lib"
    ant clean
    ant resolve-ivy
    if [ ! -d "$ANTLIB_DIR" ]; then
	mkdir -p $ANTLIB_DIR
    fi

    echo "Adding symbolic links to the libraries into the private Ant environment..."
    for j in $(ls ./lib); do
	MJ="$(md5sum $(echo $SRC_LIB/$j) | awk '{print $1}').jar"
	
	if [ ! -f $ANTLIB_DIR/$MJ ]; then
	    ln -s $SRC_LIB/$j $ANTLIB_DIR/$MJ 2>/dev/null;
	    echo "    Added: $j"
	fi
    done

    echo
    echo "Done"
    echo

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


function deploy_static() {
#
# Deploy static folders for Apache server (CSS, fonts, images etc).
#
    echo "Deploying static data"
    DEST="/var/www/html"
    for ROOT in "../web/html" "../branding"; do
	for FOBJ in `ls $ROOT`; do
	    echo "Syncing $FOBJ to $DEST"
	    rsync -u -r --delete --verbose $ROOT/$FOBJ  $USER@$HOST:$DEST
	done
    done
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


function utl_is_applicable() {
#
# Check if system operations are applicable to the environment.
#
    if { [ ! -f /etc/redhat-release ] || [ -z $(which yum 2>/dev/null) ]; } then
	echo "Error: You supposed to run me on latest RHEL or its clone."
	echo

	exit;
    fi
}


function utl_open_remote_log() {
#
# Opens dialog with the remote log tail. :-)
#
    LOG_NAME=$(basename $1)
    OUT=pig.out
    nohup ssh $USER@$HOST tailf -n $LINES $1 > $OUT 2>/dev/null &
    PID="$!"

    while [ ! -f $OUT ]; do
	echo -n "."
	sleep 0.5;
    done

    let "HEIGHT = $LINES - 6"
    let "WIDTH = $COLUMNS- 4"

    dialog --backtitle "$ABOUT" --cr-wrap --clear --title "$LOG_NAME on $HOST" --tailbox $OUT $HEIGHT $WIDTH

    kill -9 $PID
    rm $OUT
    clear
}

function utl_open_remote_tail() {
#
# Opens top on the remote machine.
#
    ssh -t $USER@$HOST TERM=$TERM multitail -n 100 -i $1
}


function utl_open_remote_top() {
#
# Opens top on the remote machine.
#
    ssh -t $USER@$HOST TERM=$TERM $([ -z $(which htop) ] && echo top || echo $(which htop))
}


function utl_open_remote_dstat() {
#
# Opens dstat on the remote machine.
#
    clear
    if [ -z $(which dstat) ]; then
	echo "dstat is not found. Install first.";
	read;
    else
	ssh -t $USER@$HOST TERM=$TERM dstat -cglmnpry --tcp
    fi
}


function setup_monitor() {
#
# Remote monitoring
#
    # Install required tools, if some missing.
    for cmd in "htop" "dstat" "multitail" "tig" "checkstyle"; do
	LOC=`which $cmd 2>/dev/null`
	if [ -z $LOC ]; then
	    sudo yum --assumeyes install htop dstat multitail tig checkstyle
	fi
    done

    while :
    do
	cmd=(dialog --no-cancel --backtitle "$ABOUT" --title "Operations on $HOST" --menu "Select operations:" 0 0 0)
	options=("T" "Tomcat log"
                 "A" "Apache error log"
                 "S" "Apache SSL error log"
                 "M" "System messages"
		 "P" "Process list viewer"
		 "D" "System resource statistics"
		 "X" "Exit")

	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

	for choice in $choices
	do
	    case $choice in
		"T")
		    utl_open_remote_tail $(get_config_value "tomcatlog");
		    ;;
		"A")
		    utl_open_remote_tail $(get_config_value "apacheerrorlog");
		    ;;
		"S")
		    utl_open_remote_tail $(get_config_value "apachesslerrorlog");
		    ;;
		"M")
		    utl_open_remote_tail "/var/log/messages";
		    ;;
		"P")
		    utl_open_remote_top;
		    ;;
		"D")
		    utl_open_remote_dstat;
		    ;;
		"X")
		    clear
		    exit
		    ;;
	    esac
	done
    done
}


function setup_init_environment() {
#
# Init all the environment
#
    utl_is_applicable;

    if [ -z $(which dialog 2>/dev/null) ]; then
	echo
	echo "Wait a little, installing a missing bit..."
	echo
	sudo yum --assumeyes install dialog > /dev/null
    fi

    OUTPUT="/tmp/build-spacewalk.upgrade.$$.tmp"

    # Upgrade system
    sudo yum --assumeyes upgrade > $OUTPUT &
    dialog  --backtitle "$ABOUT" --clear --title "System Upgrade" --tailbox $OUTPUT 20 70
    while [ `pgrep yum` ]; do # Bypass "Exit" while Yum is running
	dialog  --backtitle "$ABOUT" --clear --title "System Upgrade" --tailbox $OUTPUT 20 70
    done

    # Install stuff
    sudo yum --assumeyes install openssh-clients rsync system-config-firewall > $OUTPUT &
    dialog  --backtitle "$ABOUT" --clear --title "Installing additional packages" --tailbox $OUTPUT 20 70
    while [ `pgrep yum` ]; do # Bypass "Exit" while Yum is running
	dialog  --backtitle "$ABOUT" --clear --title "Installing additional packages" --tailbox $OUTPUT 20 70
    done

    # Setup SE Linux
    clear
    if [ -z $(cat /etc/selinux/config | grep disabled) ]; then
	dialog --backtitle "$ABOUT" --title "Secure Linux" --yes-label "Got it" \
               --no-label "I am coward" --yesno "I need to disable SELinux on this machine. May I?" 5 55
	case $? in
	    0)
		SLF="/etc/selinux/config"
		SLFB="/etc/selinux/config.$$.backup"
		TSLF="/tmp/selinux-config"
		sudo mv $SLF $SLFB
		cat > $TSLF <<EOF
# Spacewalk development appliance
# Previous backup: $SLFB"
SELINUX=disabled
SELINUXTYPE=targeted
EOF
		sudo chmod 0644 $TSLF
		sudo chown root:root $TSLF
		sudo mv $TSLF $SLF
		dialog --backtitle "$ABOUT" --yesno "I've disabled SE Linux, but now I need to reboot." 5 55
		case $? in
		    0)
			clear
			echo
			echo "See you soon!"
			echo
			sudo shutdown -r now
			;;
		    1|255)
			dialog --backtitle "$ABOUT" --clear --msgbox "Please reboot your system later." 5 55
			;;
		esac
		;;
	    1|255)
		dialog --backtitle "$ABOUT" --clear --msgbox "Ah. Well, then I cannot continue." 5 55
		exit;
		;;
	esac
    fi
    rm $OUTPUT
    dialog --backtitle "$ABOUT" --msgbox "Environment has been initialized." 5 55
    clear
}


function setup_install_spacewalk() {
#
# Installs Spacewalk on the localhost.
#
 
    # Store data to $VALUES variable
    form=()
    while [ ${#form[@]} != 15 ];
    do
	echo "Again"
	exec 3>&1
	VALUES=$(dialog --ok-label "Save" \
                        --backtitle "$ABOUT" \
                        --title "Spacewalk Parameters" \
                        --form "Specify SSL and database parameters for the installation." 22 80 0 \
	"Admin e-mail:" 1 1 "root@$HOST"    1 30 40 0 \
	"Organization:" 2 1 "Spacewalk-Org" 2 30 40 0 \
	"Unit:"         3 1 "spacewalk"     3 30 40 0 \
	"City:"         4 1 "Nuernberg"     4 30 40 0 \
	"State:"        5 1 "Germany"       5 30 40 0 \
	"Country:"      6 1 "DE"            6 30 2 0 \
	"SSL password:" 7 1 "spacewalk"     7 30 40 0 \
	"SSL e-mail:"   8 1 "root@$HOST"    8 30 40 0 \
	"DB Name:"      9 1 "spaceschema"   9 30 25 0 \
	"DB User:"      10 1 "spaceuser"   10 30 25 0 \
	"DB Password:"  11 1 "spacewalk"   11 30 25 0 \
	"DB Host:"      12 1 "$HOST"       12 30 25 0 \
	"DB Port:"      13 1 "5432"        13 30 4 0 \
	"Use TFTP (Y/N):" 14 1 "Y"         14 30 1 0 \
	"Config SSL VHost (Y/N):" 15 1 "Y" 15 30 1 0 \
	    2>&1 1>&3)
	exec 3>&-

	i=1
	for v in $VALUES; do
	    form[$i]="$v"
	    (( i++ ))
	done

	if [ ${#form[@]} != 15 ]; then
	    dialog --backtitle "$ABOUT" \
                   --yes-label "Again" \
                   --no-label "Abort" \
                   --title "Wrong Parameters" \
                   --yesno "\nYou should not have empty fields or spaces in values.\n\nWant to try it again?" 10 40
	    case $? in
		0)
		    ;;
		1|255)
		    clear
		    exit
		    ;;
	    esac
	fi
    done

    ANSWER_FILE="/tmp/build-spacewalk.answer-file.$$.tmp"

    cat > $ANSWER_FILE <<EOF
admin-email = ${form[1]}
ssl-set-org = ${form[2]}
ssl-set-org_unit = ${form[3]}
ssl-set-city = ${form[4]}
ssl-set-state = ${form[5]}
ssl-set-country = ${form[6]}
ssl-password = ${form[7]}
ssl-set-email = ${form[8]}
ssl-config-sslvhost = ${form[15]}
db-backend = postgresql
db-name = ${form[9]}
db-user = ${form[10]}
db-password = ${form[11]}
db-host = ${form[12]}
db-port = ${form[13]}
enable-tftp = ${form[14]}
EOF
    dialog --backtitle "$ABOUT" --title "Spacewalk PostgreSQL Configuration" --no-collapse --msgbox "$(cat $ANSWER_FILE | sort | sed 's/ = /: /' | column -t)" 0 0
    clear

    URL="http://yum.spacewalkproject.org/nightly"
    DST=$(utl_get_distro_name)
    VER=$(utl_get_distro_version)
    PLT=$(uname -m)

    # Install repo
    echo "Looking for the Spacewalk repository RPM. Please wait..."
    RPM=$(utl_url_find_package "$URL/$DST/$VER/$PLT/" "spacewalk-repo-")
    sudo rpm -Uvh $URL/$DST/$VER/$PLT/$RPM
    sudo sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/spacewalk-nightly.repo
    sudo sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/spacewalk.repo

    # JPackage repo
    JPACK_REPO="/tmp/build-spacewalk.jpackage.$$.tmp"
    cat > $JPACK_REPO << EOF
[jpackage-generic]
name=JPackage generic
#baseurl=http://mirrors.dotsrc.org/pub/jpackage/5.0/generic/free/
mirrorlist=http://www.jpackage.org/mirrorlist.php?dist=generic&type=free&release=5.0
enabled=1
gpgcheck=1
gpgkey=http://www.jpackage.org/jpackage.asc
EOF

    sudo mv $JPACK_REPO /etc/yum.repos.d/jpackage-generic.repo

    # EPEL repo
    echo "Looking for the EPEL repository RPM. Please wait..."
    URL="http://dl.fedoraproject.org/pub/epel"
    RPM=$(utl_url_find_package "$URL/$VER/$PLT/" "epel-release-")
    echo "Found: $RPM"
    sudo rpm -Uvh $URL/$VER/$PLT/$RPM

    # Database server
    sudo yum --assumeyes install spacewalk-setup-postgresql
    sudo /etc/init.d/postgresql start

    echo "Waiting for 10 seconds to make sure PostgreSQL winding-up..."
    sleep 10

    # Install spacewalk
    sudo yum --assumeyes install spacewalk-postgresql

    # Configure firewall
    sudo system-config-firewall

    # Configure Spacewalk
    sudo spacewalk-setup --disconnected --answer-file=$ANSWER_FILE

    # Finished
    rm $ANSWER_FILE
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

# Logs
tomcat log = /var/log/tomcat6/catalina.out
apache error log = /var/log/httpd/error_log
apache ssl error log = /var/log/httpd/ssl_error_log

# Tools
# Enable or disable the remote monitor after dev operations.
remote monitor = enable

# Warnings
display warnings = yes

EOF
    echo "New config has been written: $ROOT/$CFG"
    echo

    exit;
}


function git_push() {
#
# Push to the current origin.
#
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "Pushing to $BRANCH"
    git push origin $BRANCH
}


function header() {
#
# Print header
#
  cat << LINE
$ABOUT

LINE
}


function usage() {
#
# Print usage
#
  cat << LINE
Usage: [setup] <mode> [host]

Setup:
    --init-environment    Initialize environment to install missing bits.

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

    -s    Check style. Optionally, pass case-insensitive 
          pattern that would match the file names. In this
          case only these files will be checked.
          For example, to find all Foo.java, BarFoo.java,
          FredFooBar.java, SomefooHere.java etc, simply run:

              $(basename $0) -s foo

    -m    Run monitor

    -c    Cleanup workspace. This will remove everything related
          to this project from your $HOME/.ant/lib and build/* directories. 

    -h    This help message.


Commands:

    --gp  Push to the current Git branch.


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


export ANT_HOME=/usr/share/ant
HOST=$(set_target_host $2)
USER="root"
MODE=$(set_default_operation $1)
TOMCAT_VERSION=$(set_tomcat_version)

if { [ "$MODE" = "-h" ] || [ "$MODE" = "" ]; } then
    usage;
else
    WARNINGS=""
    if [ "$(get_config_value "displaywarnings")" = "yes" ]; then
	WARNINGS="yes"
    fi

    if [ "$MODE" = "--generate-config" ]; then
	setup_generate_config $2 $3;
    elif [ "$MODE" = "--install-spacewalk" ]; then
	can_sudo;
	setup_install_spacewalk;
    elif [ "$MODE" = "--init-environment" ]; then
	can_sudo;
	check_env $WARNINGS;
	setup_init_environment;
    else
        # Checks
	can_sudo;
	check_env $WARNINGS;

	if [ "$MODE" = "-r" ]; then
	    correct_location;
	    rebuild_all;
	    deploy_webapp;
	    deploy_binary;
	    deploy_static;
	elif [ "$MODE" = "-w" ]; then
	    correct_location;
	    refresh_webapp;
	    deploy_webapp;
	elif [ "$MODE" = "-b" ]; then
	    correct_location;
	    refresh_bin;
	    deploy_binary;
	elif [ "$MODE" = "-a" ]; then
	    correct_location;
	    refresh_webapp;
	    refresh_bin;
	    deploy_webapp;
	    deploy_binary;
	elif [ "$MODE" = "-l" ]; then
	    synchronize_webinf_lib;
	elif [ "$MODE" = "-m" ]; then
	    setup_monitor;
	elif [ "$MODE" = "-s" ]; then
	    check_java_style $2;
	    exit;
	elif [ "$MODE" = "-c" ]; then
	    clean_workspace;
	    exit;
	elif [ "$MODE" = "--gp" ]; then
	    git_push;
	    exit;
	else
	    usage;
	fi

	restart_services $HOST;

	if [ $(get_config_value "remotemonitor") = "enable" ]; then
	    setup_monitor;
	fi
    fi
fi
