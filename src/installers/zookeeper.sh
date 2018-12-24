#!/bin/bash

ZOOKEEPER_CONF_DIR=/etc/zookeeper
ZOOKEEPER_CTRL_DIR=/usr/share/zookeeper/bin
ZOOKEEPER_MYID=$(echo "$INSTANCE_CONFIG" | jq -r '.server_id')

configure_file() {
  local ZOOKEEPER_CONF_FILE="$ZOOKEEPER_CONF_DIR/conf/zoo.cfg"
  local ZOOKEEPER_DATA_DIR=$(jq -r '.config.configuration.zookeeper.common.zookeeper_dir' "$DEPLOY_SPEC")
  local ZOOKEEPER_DEFAULT_DATA_DIR=/var/lib/zookeeper

  # Cluster nodes list
  jq -r '.config.cluster | .common * (.nodes[]) | "server." + .server_id + "=" + .server_name + ".'"$DNS_SUFFIX"'" + ":" + (.zookeeper_comm_port|tostring) + ":" + (.zookeeper_election_port|tostring)' "$DEPLOY_SPEC" >> "$ZOOKEEPER_CONF_FILE"

  # Override data directory
  if [ -z "$ZOOKEEPER_DATA_DIR" ] || [ "$ZOOKEEPER_DATA_DIR" == '/' ]; then
    ZOOKEEPER_DATA_DIR=$ZOOKEEPER_DEFAULT_DATA_DIR  # fallback directory
    echo >&2 "[ZooKeeper::WARN] ZooKeeper directory has been reset to default directory: $HADOOP_DIR"
  fi

  mkdir -p $ZOOKEEPER_DATA_DIR
  chown -R zookeeper:zookeeper $ZOOKEEPER_DATA_DIR

  # Output node ID
  if [ "$ZOOKEEPER_MYID" -ge 1 ] && [ "$ZOOKEEPER_MYID" -le 255 ]; then
    echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_CONF_DIR/conf/myid
    echo "$ZOOKEEPER_MYID" > $ZOOKEEPER_DATA_DIR/myid

    chown zookeeper:zookeeper $ZOOKEEPER_CONF_DIR/conf/myid $ZOOKEEPER_DATA_DIR/myid
  else
    echo >&2 "[ZooKeeper::ERROR] Invalid ZooKeeper node ID: $ZOOKEEPER_MYID"
    return 1
  fi

  # Move data directory
  if [ "$ZOOKEEPER_DATA_DIR" != "$ZOOKEEPER_DEFAULT_DATA_DIR" ]; then
    sed -i -- "s#dataDir=$ZOOKEEPER_DEFAULT_DATA_DIR#dataDir=$ZOOKEEPER_DATA_DIR#g" $ZOOKEEPER_CONF_FILE  # replace data dir

    if [ -d "$ZOOKEEPER_DEFAULT_DATA_DIR" ]; then
      cp -rfp "$ZOOKEEPER_DEFAULT_DATA_DIR/"* "$ZOOKEEPER_DATA_DIR"
      rm -rf "$ZOOKEEPER_DEFAULT_DATA_DIR"
    fi
  fi

  chown -R zookeeper:zookeeper "$ZOOKEEPER_DATA_DIR" "$ZOOKEEPER_CONF_DIR"
}

configure_service() {
  # Start ZooKeeper automatically on boot
  systemctl enable zookeeper

  echo '[ZooKeeper] Sleeping to wait for other cluster nodes...'
  systemctl stop zookeeper
  sleep $(( INSTANCE_SERVER_ID * 10 ))  # compulsory sleep

  jq -r '.config.cluster.nodes[] | select(.server_id | tonumber < '"$INSTANCE_SERVER_ID"') | .server_name' "$DEPLOY_SPEC" |
    while IFS=$'\n' read -r hostname; do
      # clear DNS cache and sleep if remote host is not ready
      echo "[ZooKeeper] Waiting for cluster node: $hostname..."
      systemctl restart systemd-resolved.service

      if port_wait "$hostname.$DNS_SUFFIX" "$ZOOKEEPER_QUORUM_PORT" 5 20; then
        echo "[ZooKeeper] Cluster node $hostname is up!"
      else
        echo >&2 "[ZooKeeper::ERROR] Cluster node $hostname may be down or the remote service is not running."
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
