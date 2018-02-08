# Scripts
This is a list of scripts that have been put together for one reason or another.

## create_keytabs_for_ad_kafka_zk.sh
Creates a keytab from an Active Directory Kerberos server using utilities on a Linux machine. It is expected that the Linux server can access Kerberos utilities and the Active Directory server.

## deploy_confluent_platform.sh
Launches a single zookeeper with multiple Confluent Kafka platforms. The Confluent Kafka platform includes the Schema Registry, Connect, Rest Proxy, Replicator and core Kafka. It will also install the Confluent Control Center (C3) separately.

## start_kafka_with_kerberos.sh
Launches a Kerberos KDC server, dedicated ZK without Kerberos and Confluent kafka that authenticates against the Kerberos KDC.

## template.sh
Template script to use as a starter for new scripts.
