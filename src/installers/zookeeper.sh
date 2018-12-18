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
  local ZOOKEEPER_QUORUM_PORT=$(echo "$INSTANCE_CONFIG" | jq -r '.zookeeper_quorum_port')

  # Start ZooKeeper automatically on boot
  systemctl enable zookeeper

  echo '[ZooKeeper] Sleeping to wait for other cluster nodes...'
  systemctl stop zookeeper
  sleep $(( INSTANCE_SERVER_ID * 10 ))  # compulsory sleep

  jq -r '.config.cluster.nodes[] | select(.server_id | tonumber < '"$INSTANCE_SERVER_ID"') | .server_name' "$DEPLOY_SPEC" |
    while IFS=$'\n' read -r hostname; do
      # clear DNS cache and sleep if remote host is not ready
      echo "[ZooKeeper] Waiting for cluster node: $hostname..."

      timeout "100" sh -c 'until nc -z $0 $1; do systemctl restart systemd-resolved.service; sleep 10; echo "[ZooKeeper::WARN] Retrying..."; done' "$hostname.$DNS_SUFFIX" "$ZOOKEEPER_QUORUM_PORT"

      if [ $? -eq 0 ]; then
        echo "[ZooKeeper] Cluster node $hostname is up!"
      else
        echo "[ZooKeeper::ERROR] Cluster node $hostname may be down or the remote service is not running."
      fi
    done

  systemctl start zookeeper  # start service anyway
  sleep 5
  echo stat | nc localhost 2181
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
