#!/usr/bin/env bash

# This file:
#
#  - Deploys Confluent Platform using the new beta packages with dedicated Zookeeper
#
#
# Usage:
#
#  ./deploy_confluent_platform.sh install | uninstall | clean | control_center
#
# Version:
#   0.1 - 25-Jan-18 - [Eric Lubow] - Modified to use multiple Kafka's on a single ZK

# Exit on error. Append "|| true" if you expect an error.
#set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
set -o xtrace

function clean () {
    echo "Cleaning up the options.json files..."
    rm -f *.json
}

function install () {
	echo "install"
}

function uninstall () {
	echo "uninstall"
}

case "$@" in
  install)          install ;;
  uninstall)        uninstall  ;;
  clean)	    clean ;;
  *) exit 1 ;;
esac
