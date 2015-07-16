#!/usr/bin/env bash

VIRTENV="$HOME/work/virtualenv"
SRC="$VIRTENV/src/"

function am_user() {
    if [ "$(whoami)" == "root" ]; then
	echo "Thou shouldst becometh user!"
	exit 1
    fi
}

function require() {
    echo $(which $1)
}


function setup_virtualenv() {
    if [ -z $(require "virtualenv") ]; then
	echo "Please install python-virtualenv"
	exit 1
    fi
    virtualenv $VIRTENV
    source $VIRTENV/bin/activate
}


function setup_salt_git() {
    if [ -z $(require "git") ]; then
	echo "Please install Git"
	exit 1
    fi

    mkdir -p $SRC
    cd $SRC
    echo "Changed to $(pwd)"

    git clone https://github.com/saltstack/salt
    cd $SRC/salt
    git remote add upstream https://github.com/saltstack/salt
    git fetch --tags upstream

    cd $1
    echo "Changed to $(pwd)"
}

function setup_salt_deps() {
    pip install pyzmq PyYAML pycrypto msgpack-python jinja2 psutil tornado
    cd $SRC
    echo "Changed to $(pwd)"
    pip install -e ./salt
    cd $1
    echo "Changed to $(pwd)"
}

function setup_system_deps() {
    sudo apt-get install python-m2crypto python-dev python-pip libzmq-dev
}

S_DIR=$(pwd)

am_user
setup_system_deps
setup_virtualenv
setup_salt_git $S_DIR
setup_salt_deps $S_DIR

echo
echo "----"
echo "Done"
