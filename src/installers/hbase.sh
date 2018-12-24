#!/bin/bash

TEMP_SUB_WORKDIR="$TEMP_WORKDIR/hbase"

HBASE_VERSION=$(jq -r '.config.version.hbase' "$DEPLOY_SPEC")
HBASE_BIN_URL="https://www.apache.org/dist/hbase/$HBASE_VERSION/hbase-$HBASE_VERSION-bin.tar.gz"
HBASE_ASC_URL="https://www.apache.org/dist/hbase/$HBASE_VERSION/hbase-$HBASE_VERSION-bin.tar.gz.asc"
HBASE_SIGN_KEY_URL="https://www.apache.org/dist/hbase/KEYS"

HBASE_ARCHIVE="$TEMP_SUB_WORKDIR/hbase.tar.gz"
HBASE_CONF_WORKDIR="$TEMP_SUB_WORKDIR/conf"

preinstall() {
  mkdir -p "$TEMP_SUB_WORKDIR" "$HBASE_CONF_WORKDIR"

  echo "[HBase] Import HBase PubKey from $HBASE_SIGN_KEY_URL..."
  curl -sf "$HBASE_SIGN_KEY_URL" | gpg --import
}

download_archive() {
  echo "[HBase] Download HBase $HBASE_VERSION from $HBASE_BIN_URL..."

  rm -f "$HBASE_ARCHIVE"
  curl -s "$HBASE_BIN_URL" -o "$HBASE_ARCHIVE"
  curl -s "$HBASE_ASC_URL" -o "$HBASE_ARCHIVE.asc"

  if [ ! -f "$HBASE_ARCHIVE" ] || [ ! -f "$HBASE_ARCHIVE.asc" ]; then
    echo >&2 '[HBase::ERROR] Failed to download HBase archive or signature file.'
    return 1
  fi

  if ! gpg --verify "$HBASE_ARCHIVE.asc" "$HBASE_ARCHIVE"; then
    echo >&2 '[HBase::ERROR] Failed to verify the signature of HBase archive.'
    return 2
  fi

  echo '[HBase] Signature verified. Extracting the archive to /opt...'
  mkdir -p /opt
  tar zxf "$HBASE_ARCHIVE" -C /opt

  if [ ! -d "$HBASE_INSTALL_DIR-$HBASE_VERSION" ]; then
    echo >&2 '[HBase::ERROR] Failed to extract the HBase archive.'
    return 3
  else
    mv "$HBASE_INSTALL_DIR-$HBASE_VERSION" "$HBASE_INSTALL_DIR"
  fi

  return 0
}

configure_env() {
  mkdir -p "$HBASE_INSTALL_DIR/pids"

  cp -rf "$HBASE_INSTALL_DIR/lib/"{hbase-client-*.jar,hbase-common-*.jar,hbase-protocol-*.jar,hbase-server-*.jar,metrics-core-*.jar} "$HADOOP_INSTALL_DIR/share/hadoop/common/"
}

configure_file() {
  local XML_SITE=hbase-site.xml

  # Download and install configurations
  echo '[HBase] Download configuration templates...'
  curl -sf "$ASSET_URL/templates/hbase/$XML_SITE.jinja2" -o "$HBASE_CONF_WORKDIR/$XML_SITE.jinja2"

  echo '[HBase] Configuring files...'
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nodes, variable: (.cluster.common * .configuration.hbase.common * .configuration.hbase.file.hbase_site.variable), static: .configuration.hbase.file.hbase_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HBASE_CONF_WORKDIR/$XML_SITE.jinja2" | xmllint --format - > "$HBASE_INSTALL_DIR/conf/$XML_SITE"

  # Configure hbase-env.sh
  {
    echo "export JAVA_HOME=$JAVA_HOME"
    echo "export HBASE_CLASSPATH=$HBASE_INSTALL_DIR/lib"
    echo "export HBASE_PID_DIR=$HBASE_INSTALL_DIR/pids"
    echo "export HBASE_MANAGES_ZK=false"
  } >> "$HBASE_INSTALL_DIR/conf/hbase-env.sh"

  # Configure regionservers
  jq -r '.config.cluster.nodes[] | select(.server_role == "slave") | .server_name + ".'"$DNS_SUFFIX"'"' "$DEPLOY_SPEC" > "$HBASE_INSTALL_DIR/conf/regionservers"

  # Configure backup masters (could be empty)
  jq -r '.config.cluster.nodes[] | select(.server_role == "master" and (.server_id | tonumber) > 1) | .server_name + ".'"$DNS_SUFFIX"'"' "$DEPLOY_SPEC" > "$HBASE_INSTALL_DIR/conf/backup-masters"
}

configure_permission() {
  chown -R hduser:hduser "$HBASE_INSTALL_DIR"
}

configure_service() {
  echo '[HBase] Starting HBase...'

  return 0 # TODO: temp

  jq -r '.config.cluster.nodes[] | select(.server_id | tonumber < '"$INSTANCE_SERVER_ID"') | .server_name' "$DEPLOY_SPEC" |
    while IFS=$'\n' read -r hostname; do
      # clear DNS cache and sleep if remote host is not ready
      echo "[HBase] Waiting for cluster node: $hostname..."
      systemctl restart systemd-resolved.service

      if port_wait "$hostname.$DNS_SUFFIX" "$ZOOKEEPER_QUORUM_PORT" 5 20; then
        echo "[HBase] Cluster node $hostname is up!"
      else
        echo >&2 "[HBase::ERROR] Cluster node $hostname may be down or the remote service is not running."
      fi
    done

  su - hduser -c 'start-hbase.sh'
}

case "$1" in
  install)
    set -e
    preinstall
    download_archive
    configure_env
    configure_file
    configure_permission
    configure_service
    set +e
    ;;
  *)
    echo "Usage: $0 {install}" >&2
    exit 1
    ;;
esac
