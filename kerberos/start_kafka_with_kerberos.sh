#!/usr/bin/env bash

# This file:
#
#  - Deploys Confluent Kafka with a dedicated Zookeeper and a Kerberos KDC server
#
#
# Usage:
#
#  ./start_kafka_with_kerberos.sh install | uninstall | clean
#
# Version:
#   0.1 - 29-Jan-18 - [Eric Lubow] - Dedicated ZK, Kafka authenticated against Kerberos

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

function clean () {
	echo "Cleaning up the local files..."
	rm -rf dcos-commons kafka-principals.txt *.json
	echo "done."
}


function setup () {
	echo ""
	echo "NOTE: You should already be auth'd into a cluster."
	echo ""
	echo "Shallow cloning the dcos-commons git repo"
	git clone --depth 1 git@github.com:mesosphere/dcos-commons.git
	echo "Installing Python eggs"
	cd dcos-commons && pip3 install -r test_requirements.txt && cd ..

	echo "Example:"
	echo 'kafka/kafka-0-broker.beta-confluent-kafka.autoip.dcos.thisdcos.directory@LOCAL
kafka/kafka-1-broker.beta-confluent-kafka.autoip.dcos.thisdcos.directory@LOCAL
kafka/kafka-2-broker.beta-confluent-kafka.autoip.dcos.thisdcos.directory@LOCAL
client@LOCAL' 
	echo -n "Enter the kafka principals (CTRL-d to finish): "
	kp_file=kafka-principals.txt
	cat > "$kp_file"

	echo "Creating the kerberos server..."
	cd dcos-commons && PYTHONPATH=testing ./tools/kdc/kdc.py deploy ../kafka-principals.txt
	cd ../
	echo "Setup complete."
}

function install () {
	setup
	echo -n "Testing for Kerberos KDC..."
	if [ "$(dcos marathon app list | grep -c -v kdc)" -eq 1 ]
	then
		echo "found."
	else
		echo "not found.."
		echo "Please ensure the Kerberos KDC server was properly created."
		echo "This can be accomplished by following the setup instructions below:"
		setup
		exit 1
	fi	

	echo -n "Testing for secret..."
	if [ "$(dcos security secrets list / | grep -c -v __dcos_base64___keytab)" -eq 1 ]
	then
		echo "found."
	else
		echo "not found.."
		echo "Please ensure the secret for the Kerberos principals was properly created."
		echo "This can be accomplished by following the setup instructions below:"
		setup
		exit 1
	fi	
	
	echo "Starting up dedicated zookeeper without kerberos..."

	build_zookeeper_json
	package="beta-confluent-kafka-zookeeper"
	dcos package install ${package} --options=${package}.json --yes
	sleep 30; # Give the scheduler time to fire up and build a deployment plan

	while [[ "$(dcos ${package} --name=${package} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
	do
        	sleep 5
        	echo "Waiting for the installation of ${package} to complete..."
        	dcos ${package} --name=${package} plan status deploy
	done

	echo "Starting up the kerberos server"
	build_kafka_json
	package="beta-confluent-kafka"
	dcos package install ${package} --options=${package}.json --yes
        sleep 30; # Give the scheduler time to fire up and build a deployment plan

        while [[ "$(dcos ${package} --name=${package} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
        do
                sleep 5
                echo "Waiting for the installation of ${package} to complete..."
                dcos ${package} --name=${package} plan status deploy
        done
}

function uninstall () {
	echo "Uninstalling"
	echo "Removing Kerberos KDC..."
	dcos marathon app remove kdc --force
	echo "Removing created secret.."
	dcos security secrets delete __dcos_base64___keytab
	echo "Removing Kafka..."
    	dcos package uninstall beta-confluent-kafka --yes
	echo "Removing Zookeeper..."
    	dcos package uninstall beta-confluent-kafka-zookeeper --yes
	echo "Cleaning up local files..."
	rm -rf dcos-commons kafka-principals.txt *.json
	echo "done."
}

function build_zookeeper_json () {
tee beta-confluent-kafka-zookeeper.json << EOF
{
  "service": {
    "name": "beta-confluent-kafka-zookeeper"
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
	    "enabled": true,
            "kdc": {
                "hostname": "kdc.marathon.autoip.dcos.thisdcos.directory",
                "port": 2500
            },
            "keytab_secret": "__dcos_base64___keytab"
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
