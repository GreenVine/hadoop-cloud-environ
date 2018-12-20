#!/bin/bash

jq -r '.config.cluster.identity.ssh.ubuntu.authorized_keys | to_entries[] | .value' "$DEPLOY_SPEC" |
  while IFS=$'\n' read -r key; do
    echo "$key" >> "/home/ubuntu/.ssh/authorized_keys"
    chown ubuntu:ubuntu "/home/ubuntu/.ssh/authorized_keys"
    chmod 0600 "/home/ubuntu/.ssh/authorized_keys"
  done
