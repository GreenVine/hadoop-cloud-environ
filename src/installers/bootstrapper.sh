#!/bin/bash

export JAVA_HOME=/usr/lib/jvm/java-8-oracle
export ZOOKEEPER_INSTALL_DIR=/usr/share/zookeeper
export HADOOP_INSTALL_DIR=/opt/hadoop
export HBASE_INSTALL_DIR=/opt/hbase

export DEPLOY_SPEC_MIN="$TEMP_WORKDIR/deployment-min.json"
export DNS_SUFFIX=$(jq -r '.config.discovery.dns.dns_suffix' "$DEPLOY_SPEC")
export INSTANCE_CONFIG=$(jq -rc '.config.cluster | .common * (.nodes[] | select(.server_name=="'"$NODE_HOSTNAME"'"))' "$DEPLOY_SPEC")

# Source environment file
. /etc/environment

# Configure Java environment variable
if ! grep -q "JAVA_HOME=" /etc/environment; then
  echo "JAVA_HOME=\"$JAVA_HOME\"" >> /etc/environment
fi

# Configure PATH
PATH_NEW="$PATH:$HADOOP_INSTALL_DIR/bin:$ZOOKEEPER_HOME/bin:$HBASE_INSTALL_DIR/bin:$HADOOP_INSTALL_DIR/sbin"
if ! grep -q "PATH=" /etc/environment; then
  echo "PATH=\"$PATH_NEW\"" >> /etc/environment
else
  sed -i -- "s#PATH=.*#PATH=\"$PATH_NEW\"#g" /etc/environment
fi

# Configure system environment variables
{
  echo "HADOOP_HOME=\"$HADOOP_INSTALL_DIR\""
  echo "ZOOKEEPER_HOME=\"$ZOOKEEPER_INSTALL_DIR\""
  echo "HBASE_HOME=\"$HBASE_INSTALL_DIR\""
  echo "HADOOP_MAPRED_HOME=\"$HADOOP_INSTALL_DIR\""
  echo "HADOOP_COMMON_HOME=\"$HADOOP_INSTALL_DIR\""
  echo "HADOOP_HDFS_HOME=\"$HADOOP_INSTALL_DIR\""
  echo "YARN_HOME=\"$HADOOP_INSTALL_DIR\""
  echo "HADOOP_COMMON_LIB_NATIVE_DIR=\"$HADOOP_INSTALL_DIR/lib/native\""
  echo "HADOOP_OPTS=\"-Djava.library.path=$HADOOP_INSTALL_DIR/lib/native\""
} >> /etc/environment
. /etc/environment

# Install Jinja CLI
pip3 install jinja2-cli

set -e

# Download minimum deployment specification
curl -sf "$ASSET_URL/templates/cluster-spec-min.json" -o "$DEPLOY_SPEC_MIN"

# Configure service discovery
curl -sf "$ASSET_URL/services/service-discovery.sh" | bash -s -- up

# Configure applications
curl -sf "$ASSET_URL/installers/zookeeper.sh" | bash -s -- install
curl -sf "$ASSET_URL/installers/hadoop.sh" | bash -s -- install
curl -sf "$ASSET_URL/installers/hbase.sh" | bash -s -- install

set +e

# Final clean-up
apt-mark unhold cloud-init
# rm -rf "$TEMP_WORKDIR"
