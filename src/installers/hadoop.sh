#!/bin/bash

TEMP_SUB_WORKDIR="$TEMP_WORKDIR/hadoop"

HADOOP_VERSION=$(jq -r '.config.version.hadoop' "$DEPLOY_SPEC")
HADOOP_BIN_URL="https://www.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
HADOOP_ASC_URL="https://www.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz.asc"
HADOOP_SIGN_KEY_URL="https://dist.apache.org/repos/dist/release/hadoop/common/KEYS"

HADOOP_ARCHIVE="$TEMP_SUB_WORKDIR/hadoop.tar.gz"
HADOOP_CONF_WORKDIR="$TEMP_SUB_WORKDIR/conf"

preinstall() {
  mkdir -p "$TEMP_SUB_WORKDIR" "$HADOOP_CONF_WORKDIR"

  echo "[Hadoop] Import Hadoop PubKey from $HADOOP_SIGN_KEY_URL..."
  curl -sf "$HADOOP_SIGN_KEY_URL" | gpg --import
}

download_archive() {
  echo "[Hadoop] Download Hadoop $HADOOP_VERSION from $HADOOP_BIN_URL..."

  rm -f "$HADOOP_ARCHIVE"
  curl -s "$HADOOP_BIN_URL" -o "$HADOOP_ARCHIVE"
  curl -s "$HADOOP_ASC_URL" -o "$HADOOP_ARCHIVE.asc"

  if [ ! -f "$HADOOP_ARCHIVE" ] || [ ! -f "$HADOOP_ARCHIVE.asc" ]; then
    echo >&2 '[Hadoop::WARN] Failed to download Hadoop archive or signature file.'
    return 1
  fi

  if ! gpg --verify "$HADOOP_ARCHIVE.asc" "$HADOOP_ARCHIVE"; then
    echo >&2 '[Hadoop::WARN] Failed to verify the signature of Hadoop archive.'
    return 2
  fi

  echo '[Hadoop] Signature verified. Extracting the archive to /opt...'
  mkdir -p /opt
  tar zxf "$HADOOP_ARCHIVE" -C /opt

  if [ ! -d "$HADOOP_INSTALL_DIR-$HADOOP_VERSION" ]; then
    echo >&2 '[Hadoop::WARN] Failed to extract the Hadoop archive.'
    return 3
  else
    mv "$HADOOP_INSTALL_DIR-$HADOOP_VERSION" "$HADOOP_INSTALL_DIR"
  fi

  return 0
}

configure_env() {
  local HADOOP_DIR=$(jq -r '.config.configuration.hadoop.common.hadoop_dir' "$DEPLOY_SPEC")

  if [ -z "$HADOOP_DIR" ] || [ "$HADOOP_DIR" == '/' ]; then
    HADOOP_DIR=/var/lib/hadoop  # fallback directory
    echo >&2 "[Hadoop::WARN] Hadoop directory has been reset to default directory: $HADOOP_DIR"
  fi

  mkdir -p "$HADOOP_DIR/hdfs/"{tmp,journal,name,data,history_tmp,history,logs}
  chown -R hduser:hduser "$HADOOP_DIR"
  chmod 0775 -R "$HADOOP_DIR"
}

configure_file() {
  local XML_CORE=core-site.xml
  local XML_HDFS=hdfs-site.xml
  local XML_MAPRED=mapred-site.xml
  local XML_YARN=yarn-site.xml

  set -e

  # Download and install configurations
  echo '[Hadoop] Download configuration templates...'
  curl -sf "$ASSET_URL/templates/hadoop/$XML_CORE.jinja2" -o "$HADOOP_CONF_WORKDIR/$XML_CORE.jinja2"
  curl -sf "$ASSET_URL/templates/hadoop/$XML_HDFS.jinja2" -o "$HADOOP_CONF_WORKDIR/$XML_HDFS.jinja2"
  curl -sf "$ASSET_URL/templates/hadoop/$XML_MAPRED.jinja2" -o "$HADOOP_CONF_WORKDIR/$XML_MAPRED.jinja2"
  curl -sf "$ASSET_URL/templates/hadoop/$XML_YARN.jinja2" -o "$HADOOP_CONF_WORKDIR/$XML_YARN.jinja2"

  echo '[Hadoop] Configuring files...'
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nodes, variable: (.cluster.common * .configuration.hadoop.common * .configuration.hadoop.file.core_site.variable), static: .configuration.hadoop.file.core_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HADOOP_CONF_WORKDIR/$XML_CORE.jinja2" | xmllint --format - > "$HADOOP_INSTALL_DIR/etc/hadoop/$XML_CORE"
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nodes, variable: (.cluster.common * .configuration.hadoop.common * .configuration.hadoop.file.hdfs_site.variable), static: .configuration.hadoop.file.hdfs_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HADOOP_CONF_WORKDIR/$XML_HDFS.jinja2" | xmllint --format - > "$HADOOP_INSTALL_DIR/etc/hadoop/$XML_HDFS"
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nodes, variable: (.cluster.common * .configuration.hadoop.common * .configuration.hadoop.file.mapred_site.variable), static: .configuration.hadoop.file.mapred_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HADOOP_CONF_WORKDIR/$XML_MAPRED.jinja2" | xmllint --format - > "$HADOOP_INSTALL_DIR/etc/hadoop/$XML_MAPRED"
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nodes, variable: (.cluster.common * .configuration.hadoop.common * .configuration.hadoop.file.yarn_site.variable), static: .configuration.hadoop.file.yarn_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HADOOP_CONF_WORKDIR/$XML_YARN.jinja2" | xmllint --format - > "$HADOOP_INSTALL_DIR/etc/hadoop/$XML_YARN"

  # Configure hadoop-env.sh
  sed -i -- 's#${JAVA_HOME}#'"$JAVA_HOME"'#g' "$HADOOP_INSTALL_DIR/etc/hadoop/hadoop-env.sh"

  # Configure slaves
  jq -r '.config | (.cluster.nodes | map(.server_name)[]) | . + ".'"$DNS_SUFFIX"'"' "$DEPLOY_SPEC" > "$HADOOP_INSTALL_DIR/etc/hadoop/slaves"

  set +e
}

configure_user() {
  local HADOOP_USER_HOME=/home/hduser
  local IDENTITY_URL=$(jq -r '.config.deployment.locator.identity_base_url' "$DEPLOY_SPEC")
  local HADOOP_PUB_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hduser.public' "$DEPLOY_SPEC")
  local HADOOP_PRIV_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hduser.private' "$DEPLOY_SPEC")
  local HADOOP_ADD_AUTH_KEY=$(jq -r '.config.cluster.identity.ssh.hduser.add_pubkey_as_authorized_key' "$DEPLOY_SPEC")

  echo '[Hadoop] Configuring User hduser...'

  mkdir -p "$HADOOP_USER_HOME/.ssh"
  chown hduser:hduser "$HADOOP_USER_HOME" "$HADOOP_USER_HOME/.ssh"

  curl -sf "$HADOOP_PUB_KEY" > "$HADOOP_USER_HOME/.ssh/id_rsa.pub"
  curl -sf "$HADOOP_PRIV_KEY" > "$HADOOP_USER_HOME/.ssh/id_rsa"

  chmod 0600 "$HADOOP_USER_HOME/.ssh/id_rsa.pub" "$HADOOP_USER_HOME/.ssh/id_rsa"
  chown hduser:hduser "$HADOOP_USER_HOME/.ssh/id_rsa.pub" "$HADOOP_USER_HOME/.ssh/id_rsa"

  if [ "$HADOOP_ADD_AUTH_KEY" == "true" ]; then
    cat "$HADOOP_USER_HOME/.ssh/id_rsa.pub" >> "$HADOOP_USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$HADOOP_USER_HOME/.ssh/authorized_keys"
    chown hduser:hduser "$HADOOP_USER_HOME/.ssh/authorized_keys"
  fi
}

configure_permission() {
  chown -R hduser:hduser "$HADOOP_INSTALL_DIR"
}

configure_remote_ssh() {
  local REMOTE_INSTANCE_CONFIG
  local REMOTE_INSTANCE_SSH_PORT

  # Setup SSH access to all other nodes for master nodes
  if [ "$INSTANCE_ROLE" == 'master' ]; then
    echo '[Hadoop] SSH Setup: Configuring SSH trusted hosts...'

    mkdir -p /home/hduser/.ssh

    jq -r '.config.cluster.nodes[] | .server_name' "$DEPLOY_SPEC" |
      while IFS=$'\n' read -r hostname; do
        REMOTE_INSTANCE_CONFIG=$(jq -rc '.config.cluster | .common * (.nodes[] | select(.server_name=="'"$hostname"'"))' "$DEPLOY_SPEC")
        REMOTE_INSTANCE_SSH_PORT=$(echo "$REMOTE_INSTANCE_CONFIG" | jq -r '.ssh_port')

        # clear DNS cache and sleep if remote host is not ready
        echo "[Hadoop] SSH Setup: Waiting for cluster node: $hostname..."
        systemctl restart systemd-resolved.service

        if port_wait "$hostname.$DNS_SUFFIX" "$REMOTE_INSTANCE_SSH_PORT" 5 20; then
          echo "[Hadoop] SSH Setup: Setting up access for cluster node $hostname..."
          ssh-keyscan -p "$REMOTE_INSTANCE_SSH_PORT" "$hostname.$DNS_SUFFIX" >> /home/hduser/.ssh/known_hosts
        else
          echo >&2 "[Hadoop::ERROR] SSH Setup: Cluster node $hostname may be down or the remote SSH service is not running."
        fi
      done

    chown -R hduser:hduser /home/hduser/.ssh
  fi
}

configure_service() {
  return 0 # tmp

  # Start JournalNode
  echo '[Hadoop] Starting JournalNode...'
  su - hduser -c 'hadoop-daemon.sh start journalnode'
  sleep 5

  if [ "$INSTANCE_ROLE" == 'master' ]; then

    jq -r '.config.cluster.nodes[] | .server_name' "$DEPLOY_SPEC" |
      while IFS=$'\n' read -r hostname; do
        if ! port_wait "$hostname.$DNS_SUFFIX" "$ZOOKEEPER_QUORUM_PORT" 5 20; then
          echo >&2 "[Hadoop:ERROR] Master Setup: Failed to wait for ZooKeeper service on $hostname!"
          return 1
        fi
      done

    if [ "$INSTANCE_SERVER_ID" -le 1 ]; then  # primary master
      echo '[Hadoop] Configuring primary master...'

      su - hduser -c 'hdfs zkfc -formatZK'
      su - hduser -c 'hdfs namenode -format'

      su - hduser -c 'start-all.sh'
      su - hduser -c 'mr-jobhistory-daemon.sh start historyserver'
    else  # backup masters
      echo '[Hadoop] Configuring backup masters...'

      su - hduser -c 'hdfs namenode -bootstrapStandby'
      su - hduser -c 'hadoop-daemon.sh start namenode'
      su - hduser -c 'yarn-daemon.sh start resourcemanager'
    fi

    echo '[Hadoop] HDFS service status:'
    su - hduser -c "hdfs haadmin -getServiceState nn$INSTANCE_SERVER_ID"

    echo '[Hadoop] Yarn service status:'
    su - hduser -c "yarn rmadmin -getServiceState rm$INSTANCE_SERVER_ID"
  fi

  su - hduser -c 'jps'
}

case "$1" in
  install)
    set -e
    preinstall
    download_archive
    configure_env
    configure_file
    configure_user
    configure_permission
    configure_remote_ssh
    configure_service
    set +e
    ;;
  *)
    echo "Usage: $0 {install}" >&2
    exit 1
    ;;
esac
