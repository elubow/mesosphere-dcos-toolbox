#!/usr/bin/env bash

# This file:
#
#  - Deploys Confluent Kafka with a dedicated Zookeeper and expects to use
#  - an Active Directory or external Kerberos server
#
# Usage:
#
#  ./start_zk_kafka_with_ad_kerberos.sh install | uninstall | clean
#
# Version:
#   0.1 - 02-Feb-18 - [Eric Lubow] - Dedicated ZK, Kafka authenticated against Kerberos

# Exit on error. Append "|| true" if you expect an error.
#set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
#set -o xtrace

# Constants
KAFKA_KEYTAB_NAME="__dcos_base64___kafka_keytab"
ZOOKEEPER_KEYTAB_NAME="__dcos_base64___zookeeper_keytab"
WORKING_DIR="zk-kafka-work-dir"
CURRENT_DIR=`pwd`

function clean () {
	echo -n "Cleaning up the local files..."
	rm -rf ${WORKING_DIR}
	echo "done."
}

function keytab_secret_setup () {
	echo ""
	echo "NOTE: You should already be auth'd into a cluster."
	echo ""
	mkdir ${WORKING_DIR}
	cd ${WORKING_DIR}

	# Kafka Keytab
	echo -n "XXX KAFKA KEYTAB" > kafka_keytab.base64
	dcos security secrets create ${KAFKA_KEYTAB_NAME} --value-file kafka_keytab.base64

	# Zookeeper Keytab
	echo -n "XXX ZOOKEEPER KEYTAB" > zookeeper_keytab.base64
	dcos security secrets create ${ZOOKEEPER_KEYTAB_NAME} --value-file zookeeper_keytab.base64

	echo "Setup complete."
}

function install () {
	keytab_secret_setup
	echo -n "Testing for secrets..."
	if [ "$(dcos security secrets list / | grep -c ${ZOOKEEPER_KEYTAB_NAME} )" -eq 1 ]
	then
		echo -n "zookeeper "
	else
		echo "not found.."
		echo "Please ensure the secret for the Kerberos principals was properly created."
		echo "This can be accomplished by following the setup instructions below:"
		exit 1
	fi	

	if [ "$(dcos security secrets list / | grep -c ${KAFKA_KEYTAB_NAME} )" -eq 1 ]
	then
		echo -n "kafka "
	else
		echo "not found.."
		echo "Please ensure the secret for the Kerberos principals was properly created."
		echo "This can be accomplished by following the setup instructions below:"
		exit 1
	fi	
	echo "done."

	echo -n "Enter the kerberos server hostname (mesos.master): "
	read KDC
	
	echo -n "Enter the port (88 KDC, 389 LDAP, 636 LDAP/SSL): "
	read KDC_PORT
	
	echo "Starting up dedicated zookeeper with kerberos..."

	build_zookeeper_json ${KDC} ${KDC_PORT}
	package="beta-confluent-kafka-zookeeper"
	dcos package install ${package} --options=${package}.json --yes
	sleep 30; # Give the scheduler time to fire up and build a deployment plan

	while [[ "$(dcos ${package} --name=${package} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
	do
        	sleep 5
        	echo "Waiting for the installation of ${package} to complete..."
        	dcos ${package} --name=${package} plan status deploy
	done

	echo "Starting up the kafka server with kerberos"
	build_kafka_json ${KDC} ${KDC_PORT}
	package="beta-confluent-kafka"
	dcos package install ${package} --options=${package}.json --yes
        sleep 30; # Give the scheduler time to fire up and build a deployment plan

        while [[ "$(dcos ${package} --name=${package} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
        do
                sleep 5
                echo "Waiting for the installation of ${package} to complete..."
                dcos ${package} --name=${package} plan status deploy
        done

	# put us back where we started
	cd ${CURRENT_DIR}
}

function uninstall () {
	echo "Uninstalling"
	echo "Removing created secrets.."
	dcos security secrets delete ${KAFKA_KEYTAB_NAME}
	dcos security secrets delete ${ZOOKEEPER_KEYTAB_NAME}
	echo "Removing Kafka..."
    	dcos package uninstall beta-confluent-kafka --yes
	echo "Removing Zookeeper..."
    	dcos package uninstall beta-confluent-kafka-zookeeper --yes
	echo "Skipping local file clean up...run 'clean' to do that."
	echo "done."
}

function build_zookeeper_json () {
tee beta-confluent-kafka-zookeeper.json << EOF
{
  "service": {
    "name": "beta-confluent-kafka-zookeeper",
    "security": {
      "kerberos": {
        "debug": true,
	"realm": "XXX REALM",
	"primary": "zookeeper",
	"enabled": true,
        "kdc": {
            "hostname": "${1}",
            "port": ${2}
        },
        "keytab_secret": "${ZOOKEEPER_KEYTAB_NAME}"
      }
    }
  }
}
EOF
}

function build_kafka_json () {
	zkhosts=$(dcos beta-confluent-kafka-zookeeper --name=beta-confluent-kafka-zookeeper endpoint clientport | jq -r .dns[] | paste -sd, -)
	kafka_service="beta-confluent-kafka"
tee beta-confluent-kafka.json << EOF
{
  "service": {
    "name": "${kafka_service}",
    "security": {
	"kerberos": {
	    "debug": true,
	    "realm": "XXX REALM",
            "primary": "kafka",
	    "enabled": true,
            "kdc": {
                "hostname": "${1}",
                "port": ${2}
            },
            "keytab_secret": "${KAFKA_KEYTAB_NAME}"
        }
    }
  },
  "kafka": {
    "kafka_zookeeper_uri": "${zkhosts}",
    "auto_create_topics_enable": true,
    "delete_topic_enable": true,
    "confluent_support_metrics_enable": true
  }
}
EOF
}

case "$@" in
  install)          install ;;
  uninstall)        uninstall  ;;
  clean)	    clean ;;
  *) exit 1 ;;
esac
