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
  local HDFS_DIR=$(jq -r '.config.configuration.hadoop.common.hadoop_hdfs_dir' "$DEPLOY_SPEC")

  if [ -z "$HDFS_DIR" ] || [ "$HDFS_DIR" == '/' ]; then
    HDFS_DIR=/var/lib/hadoop/hdfs  # fallback directory
    echo >&2 "[Hadoop::WARN] HDFS directory has been reset to default directory: $HDFS_DIR"
  fi

  mkdir -p $HDFS_DIR/{tmp,journal,name,data,history_tmp,history,logs}
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
  jq -rs '.[0] * .[1] | .config | { nodes: .cluster.nofdes, variable: (.cluster.common * .configuration.hadoop.common * .configuration.hadoop.file.yarn_site.variable), static: .configuration.hadoop.file.yarn_site.static, discovery: .discovery}' "$DEPLOY_SPEC_MIN" "$DEPLOY_SPEC" | jinja2 "$HADOOP_CONF_WORKDIR/$XML_YARN.jinja2" | xmllint --format - > "$HADOOP_INSTALL_DIR/etc/hadoop/$XML_YARN"

  # Configure hadoop-env.sh
  sed -i -- 's#${JAVA_HOME}#'"$JAVA_HOME"'#g' "$HADOOP_INSTALL_DIR/etc/hadoop/hadoop-env.sh"

  # Configure slaves
  jq -r '.config | (.cluster.nodes | map(.server_name)[]) | . + ".'"$DNS_SUFFIX"'"' "$DEPLOY_SPEC" > "$HADOOP_INSTALL_DIR/etc/hadoop/slaves"

  set +e
}

configure_user() {
  local HADOOP_USER_HOME=/home/hadoop
  local IDENTITY_URL=$(jq -r '.config.deployment.locator.identity_base_url' "$DEPLOY_SPEC")
  local HADOOP_PUB_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hadoop.public' "$DEPLOY_SPEC")
  local HADOOP_PRIV_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hadoop.private' "$DEPLOY_SPEC")
  local HADOOP_ADD_AUTH_KEY=$(jq -r '.config.cluster.identity.ssh.hadoop.add_authorized_key' "$DEPLOY_SPEC")

  set -e

  echo '[Hadoop] Configuring Hadoop user...'

  mkdir -p "$HADOOP_USER_HOME/.ssh"
  chown hadoop:hadoop "$HADOOP_USER_HOME" "$HADOOP_USER_HOME/.ssh"

  curl -sf "$HADOOP_PUB_KEY" > "$HADOOP_USER_HOME/.ssh/id_rsa.pub"
  curl -sf "$HADOOP_PRIV_KEY" > "$HADOOP_USER_HOME/.ssh/id_rsa"

  chmod 0600 "$HADOOP_USER_HOME/.ssh/id_rsa.pub" "$HADOOP_USER_HOME/.ssh/id_rsa"
  chown hadoop:hadoop "$HADOOP_USER_HOME/.ssh/id_rsa.pub" "$HADOOP_USER_HOME/.ssh/id_rsa"

  if [ "$HADOOP_ADD_AUTH_KEY" == "true" ]; then
    cat "$HADOOP_USER_HOME/.ssh/id_rsa.pub" >> "$HADOOP_USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$HADOOP_USER_HOME/.ssh/authorized_keys"
    chown hadoop:hadoop "$HADOOP_USER_HOME/.ssh/id_rsa.pub" "$HADOOP_USER_HOME/.ssh/id_rsa"
  fi

  set +e
}

case "$1" in
  install)
    set -e
    preinstall
    download_archive
    configure_env
    configure_file
    configure_user
    set +e
    ;;
  *)
    echo "Usage: $0 {install}" >&2
    exit 1
    ;;
esac
