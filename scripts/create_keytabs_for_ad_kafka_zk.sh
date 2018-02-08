#!/usr/bin/env bash

# This file:
#
# - Creates a keytab file on linux that has access to a Windows AD master

# Constants
ENCRYPTION_TYPES=("arcfour-hmac-md5" "des-cbc-crc" "des-cbc-md5" "arcfour-hmac")
PASSWORD="DeleteM3!"

# Zookeeper
echo -n "Enter Zookeeper keytab filename: "
read ZK_KEYTAB

if [[ -f ${ZK_KEYTAB} ]]
then
        rm -f ${ZK_KEYTAB}
fi

kvno=1
for instance_no in 1 2 3
do
   for etype in ${ENCRYPTION_TYPES[@]}
   do
        printf "%b" "addent -password -p zookeeper/zookeeper-${instance_no}-server-confluent-kafka-zookeeper.autoip.dcos.thisdcos.directory -k $kvno -e ${etype}\n${PASSWORD}\nwrite_kt ${ZK_KEYTAB}" |ktutil
    ((kvno++))
   done
done

echo "Created Zookeeper keytab file: ${ZK_KEYTAB}"
base64 -w 0 ${ZK_KEYTAB} > ${ZK_KEYTAB}.base64
echo "Created base64 encoded ZK keytab: ${ZK_KEYTAB}.base64"


# Kafka
echo -n "Enter Kafka keytab filename: "
read KAFKA_KEYTAB

if [[ -f ${KAFKA_KEYTAB} ]]
then
        rm -f ${KAFKA_KEYTAB}
fi

kvno=1
for instance_no in 1 2 3
do
   for etype in ${ENCRYPTION_TYPES[@]}
   do
        printf "%b" "addent -password -p kafka/kafka-${instance_no}-broker.beta-confluent-kafka.autoip.dcos.thisdcos.directory -k $kvno -e ${etype}\n${PASSWORD}\nwrite_kt ${KAFKA_KEYTAB}" |ktutil
    ((kvno++))
   done
done

echo "Created Kafka keytab file: ${KAFKA_KEYTAB}"
base64 -w 0 ${KAFKA_KEYTAB} > ${KAFKA_KEYTAB}.base64
echo "Created base64 encoded KAFKA keytab: ${KAFKA_KEYTAB}.base64"

