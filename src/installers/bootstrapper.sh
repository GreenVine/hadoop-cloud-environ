#!/bin/bash

export JAVA_HOME=/usr/lib/jvm/java-8-oracle
export HADOOP_INSTALL_DIR=/opt/hadoop
export HBASE_INSTALL_DIR=/opt/hbase

export DEPLOY_SPEC_MIN="$TEMP_WORKDIR/deployment-min.json"
export DNS_SUFFIX=$(jq -r '.config.discovery.dns.dns_suffix' "$DEPLOY_SPEC")
export INSTANCE_CONFIG=$(jq -rc '.config.cluster | .common * (.nodes[] | select(.server_name=="'"$NODE_HOSTNAME"'"))' "$DEPLOY_SPEC")

# Configure Java
if ! grep -q "JAVA_HOME" /etc/environment; then
  echo "JAVA_HOME=\"$JAVA_HOME\"" >> /etc/environment
  . /etc/environment
fi

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
curl -sf "$ASSET_URL/installers/hbase.sh" | bash

set +e

# Final clean-up
apt-mark unhold cloud-init
# rm -rf "$TEMP_WORKDIR"
