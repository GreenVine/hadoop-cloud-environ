#!/bin/bash

export JAVA_HOME=/usr/lib/jvm/java-8-oracle
export ZOOKEEPER_INSTALL_DIR=/usr/share/zookeeper
export HADOOP_INSTALL_DIR=/opt/hadoop
export HBASE_INSTALL_DIR=/opt/hbase

export DEPLOY_SPEC_MIN="$TEMP_WORKDIR/deployment-min.json"
export DNS_SUFFIX=$(jq -r '.config.discovery.dns.dns_suffix' "$DEPLOY_SPEC")
export TARBALL_URL=$(jq -r '.config.deployment.locator.tarball_base_url' "$DEPLOY_SPEC")

export INSTANCE_CONFIG=$(jq -rc '.config.cluster | .common * (.nodes[] | select(.server_name=="'"$NODE_HOSTNAME"'"))' "$DEPLOY_SPEC")
export INSTANCE_ROLE=$(echo "$INSTANCE_CONFIG" | jq -r '.server_role')
export INSTANCE_SERVER_ID=$(echo "$INSTANCE_CONFIG" | jq -r '.server_id')

# Update user bash file
{
  echo "export JAVA_HOME=$JAVA_HOME"
  echo 'export HADOOP_HOME=~/hadoop-2.7.1'
  echo 'export ZOOKEEPER_HOME=~/zookeeper-3.4.6'
  echo 'export HBASE_HOME=~/hbase-1.3.1'
  echo 'export PATH=$PATH:$HADOOP_HOME/bin:$ZOOKEEPER_HOME/bin:$HBASE_HOME/bin'
  echo 'export PATH=$PATH:$HADOOP_HOME/sbin:$SPARK_HOME/sbin'
  echo 'export HADOOP_MAPRED_HOME=$HADOOP_HOME'
  echo 'export HADOOP_COMMON_HOME=$HADOOP_HOME'
  echo 'export HADOOP_HDFS_HOME=$HADOOP_HOME'
  echo 'export YARN_HOME=$HADOOP_HOME'
  echo 'export HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_HOME/lib/native'
  echo 'export HADOOP_OPTS="-Djava.library.path=$HADOOP_HOME/lib/native"'
} >> /home/hduser/.bashrc

set -e

# Download minimum deployment specification
echo 'Preparing libraries and installers...'
curl -sf "$ASSET_URL/templates/cluster-spec-min.json" -o "$DEPLOY_SPEC_MIN"

# Configure system services
echo 'Configuring system services...'
curl -sf "$ASSET_URL/services/service-discovery.sh" | bash -s -- up
curl -sf "$ASSET_URL/services/hduser.sh" | bash

# Configure Hadoop services
echo 'Configuring Hadoop services...'
curl -sf "$TARBALL_URL/hduser-home.txz" -o "$TEMP_WORKDIR/hduser-home.txz"
tar xJfv "$TEMP_WORKDIR/hduser-home.txz" -C /home/hduser

# Configure ZooKeeper services
echo 'Configuring ZooKeeper services...'
echo "$INSTANCE_SERVER_ID" > /home/hduser/zookeeper-3.4.6/zkd/myid
chown -R hduser:hduser /home/hduser

set +e

# Final clean-up
apt-mark unhold cloud-init
rm -rf "$TEMP_WORKDIR"
