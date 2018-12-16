#!/bin/bash

MASTER_REPLICAS=$(jq -r '.config.deployment.replica.masterReplicas' $DEPLOY_SPEC)
SLAVE_REPLICAS=$(jq -r '.config.deployment.replica.slaveReplicas' $DEPLOY_SPEC)

ZOOKEEPER_CONF_DIR=/etc/zookeeper/conf
ZOOKEEPER_DATA_DIR=/var/lib/zookeeper
ZOOKEEPER_MYID=$(echo $INSTANCE_CONFIG | jq -r '.serverId')

# Cluster nodes list
jq -rc '.config.cluster | .common * (.nodes[]) | "server." + .serverId + "=" + .serverName + ".'"$DNS_SUFFIX"'" + ":" + (.firstPort|tostring) + ":" + (.secondPort|tostring)' $DEPLOY_SPEC >> $ZOOKEEPER_CONF_DIR/zoo.cfg

if [ "$ZOOKEEPER_MYID" -ge 1 ]; then
  echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_CONF_DIR/myid
  echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_DATA_DIR/myid
fi

systemctl restart zookeeper
