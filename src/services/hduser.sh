#!/bin/bash

HADOOP_USER_HOME=/home/hduser
IDENTITY_URL=$(jq -r '.config.deployment.locator.identity_base_url' "$DEPLOY_SPEC")
HADOOP_PUB_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hadoop.public' "$DEPLOY_SPEC")
HADOOP_PRIV_KEY=$IDENTITY_URL/$(jq -r '.config.cluster.identity.ssh.hadoop.private' "$DEPLOY_SPEC")
HADOOP_ADD_AUTH_KEY=$(jq -r '.config.cluster.identity.ssh.hadoop.add_pubkey_as_authorized_key' "$DEPLOY_SPEC")

echo 'Adding authorized keys...'
jq -r '.config.cluster.identity.ssh.ubuntu.authorized_keys | to_entries[] | .value' "$DEPLOY_SPEC" |
  while IFS=$'\n' read -r key; do
    echo "$key" >> "/home/ubuntu/.ssh/authorized_keys"
    chown ubuntu:ubuntu "/home/ubuntu/.ssh/authorized_keys"
    chmod 0600 "/home/ubuntu/.ssh/authorized_keys"
  done

echo 'Configuring hduser...'
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
