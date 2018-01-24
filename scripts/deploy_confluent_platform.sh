#!/usr/bin/env bash

# This file:
#
#  - Deploys Confluent Platform using the new beta packages with dedicated Zookeeper
#
#
# Usage:
#
#  ./deploy-cp install | uninstall

# Exit on error. Append "|| true" if you expect an error.
#set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
set -o xtrace

packages=("beta-confluent-kafka-zookeeper")
platform_packages=( "beta-confluent-kafka" "confluent-rest-proxy" "confluent-connect" "confluent-schema-registry" )
ssh_user="core" # Change accordingly
APP_COUNT=2


function cp_uninstall () {
    package=confluent-kafka
    for (( app=1; app<=${APP_COUNT}; app+=1 ))
    do
	for package in "${platform_packages[@]}"
    	do
        	dcos package uninstall ${package} --app-id=/${package}-app${app} --yes
		mpkg=`/bin/echo -n ${package} | sed -e 's/confluent-//'`
		dcos marathon app remove --force /${mpkg}-app${app}
    	done
    done
    dcos package uninstall confluent-control-center --yes
    dcos package uninstall beta-confluent-kafka-zookeeper --yes
    watch dcos service # Watch this until all packages removed, then ctrl+c
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


function build_cp_json () {
zkhosts=$(dcos beta-confluent-kafka-zookeeper --name=beta-confluent-kafka-zookeeper endpoint clientport | jq -r .dns[] | paste -sd, -)

# write the control center json first since it won't change
tee confluent-control-center.json << EOF
{
  "control-center": {
    "name": "confluent-control-center",
    "instances": 1,
    "cpus": 2,
    "mem": 4096,
    "role": "*",
    "kafka-service": "beta-confluent-kafka-app1",
    "connect-service": "connect-app1",
    "confluent-controlcenter-internal-topics-partitions": 3,
    "confluent-controlcenter-internal-topics-replication": 2,
    "confluent-monitoring-interceptor-topic-partitions": 3,
    "confluent-monitoring-interceptor-topic-replication": 2,
    "zookeeper-connect": "${zkhosts}/app1"
  }
}
EOF

for (( app=1; app<=${APP_COUNT}; app+=1 ))
do
	kafka_service="beta-confluent-kafka-app${app}"
	zk="${zkhosts}/app${app}"

	tee beta-confluent-kafka-app${app}.json << EOF
{
  "service": {
    "name": "${kafka_service}"
  },
  "kafka": {
    "kafka_zookeeper_uri": "${zk}",
    "auto_create_topics_enable": true,
    "delete_topic_enable": true,
    "confluent_support_metrics_enable": true
  }
}
EOF

	tee confluent-rest-proxy-app${app}.json << EOF
{
  "proxy": {
    "name": "rest-proxy-app${app}",
    "instances": 1,
    "cpus": 2,
    "mem": 1024,
    "heap": 768,
    "role": "*",
    "kafka-service": "${kafka_service}",
    "zookeeper-connect": "${zk}",
    "schema-registry-service": "schema-registry-app${app}"
  }
}
EOF

	tee confluent-schema-registry-app${app}.json << EOF
{
  "registry": {
    "name": "schema-registry-app${app}",
    "instances": 1,
    "cpus": 2,
    "mem": 1024,
    "heap": 768,
    "role": "*",
    "zookeeper-master": "${zkhosts}",
    "kafkastore": "app${app}"
  }
}
EOF

	tee confluent-connect-app${app}.json << EOF
{
  "connect": {
    "name": "connect-app${app}",
    "instances": 1,
    "cpus": 2,
    "mem": 1024,
    "heap": 768,
    "role": "*",
    "kafka-service": "${kafka_service}",
    "zookeeper-connect": "${zk}",
    "schema-registry-service": "schema-registry-app${app}"
  }
}
EOF

	tee confluent-replicator-app${app}.json << EOF
{
  "connect": {
    "name": "replicator-app${app}",
    "instances": 1,
    "cpus": 2,
    "mem": 1024,
    "heap": 768,
    "role": "*",
    "kafka-service": "${kafka_service}",
    "zookeeper-connect": "${zk}",
    "schema-registry-service": "schema-registry-app${app}"
  }
}
EOF

done # end app for loop

}


function control_center () {
    c3_host=$(dcos marathon app show confluent-control-center | jq -r .tasks[0].host)
    echo ${c3_host}
    c3_port=$(dcos marathon app show confluent-control-center | jq -r .tasks[0].ports[0])
    echo   ${c3_port}
    master=$(dcos cluster list --attached | tail -1 |  awk {'print $4'} | sed 's~http[s]*://~~g') # Don't judge me.
    ssh -N -L 9021:${c3_host}:${c3_port} ${ssh_user}@${master}
    echo "Open your browser on 127.0.0.1:9021 to access Confluent Control Center"
}


function clean () {
    echo "Cleaning up the options.json files..."
    rm -f *.json
}

function cp_install () {
    build_zookeeper_json
    # install ZK
    package="beta-confluent-kafka-zookeeper"
    dcos package install ${package} --options=${package}.json --yes
    sleep 30; # Give the scheduler time to fire up and build a deployment plan

    while [[ "$(dcos ${package} --name=${package} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
    do
    	sleep 5
    	echo "Waiting for the installation of ${package} to complete..."
    	dcos ${package} --name=${package} plan status deploy
    done
    build_cp_json # One time run to add the zk endpoints to the other options.json files

    package="beta-confluent-kafka"
    for (( app=1; app<=${APP_COUNT}; app+=1 ))
    do
        dcos package install ${package} --options=${package}-app${app}.json --yes
        sleep 30; # Give the scheduler time to fire up and build a deployment plan

        while [[ "$(dcos ${package} --name=${package}-app${app} plan status deploy | head -n1 | grep -c -v COMPLETE)" -eq 1 ]]
        do
        	sleep 5
                echo "Waiting for the installation of ${package}-app${app} to complete..."
                dcos ${package} --name=${package}-app${app} plan status deploy
        done

	# handle the rest of the packages
	for subpackage in "${platform_packages[@]}"
	do
		dcos package install ${subpackage} --options=${subpackage}-app${app}.json --yes
	done

	# let things settle a little now
	echo "sleeping for 30 seconds to let things settle..."
	sleep 30 
    done

    # finally install the control center
    package="confluent-control-center"
    dcos package install ${package} --options=${package}.json --yes
}

case "$@" in
  install)          cp_install ;;
  uninstall)        cp_uninstall  ;;
  build_zk_json)    build_zk_json ;;
  build_cp_json)    build_cp_json ;;
  control_center)   control_center ;;
  clean)	    clean ;;
  *) exit 1 ;;
esac
