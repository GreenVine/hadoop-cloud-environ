#!/bin/bash

ZOOKEEPER_CONF_DIR=/etc/zookeeper/conf
ZOOKEEPER_DATA_DIR=/var/lib/zookeeper
ZOOKEEPER_CTRL_DIR=/usr/share/zookeeper/bin
ZOOKEEPER_MYID=$(echo "$INSTANCE_CONFIG" | jq -r '.server_id')

configure_file() {
  # Cluster nodes list
  jq -r '.config.cluster | .common * (.nodes[]) | "server." + .server_id + "=" + .server_name + ".'"$DNS_SUFFIX"'" + ":" + (.zookeeper_comm_port|tostring) + ":" + (.zookeeper_election_port|tostring)' "$DEPLOY_SPEC" >> $ZOOKEEPER_CONF_DIR/zoo.cfg

  if [ "$ZOOKEEPER_MYID" -ge 1 ]; then
    echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_CONF_DIR/myid
    echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_DATA_DIR/myid
  fi
}

configure_service() {
  # Start ZooKeeper automatically on boot
  systemctl enable zookeeper

  # TODO: Start ZooKeeper simultaneously may cause cluster to fail
  systemctl stop zookeeper
}

case "$1" in
  install)
    set -e
    configure_file
    configure_service
    set +e
    ;;
  *)
    echo "Usage: $0 {install}" >&2
    exit 1
    ;;
esac
