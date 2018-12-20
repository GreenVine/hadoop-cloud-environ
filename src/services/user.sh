#!/bin/bash

jq -r '.config.cluster.identity.ssh.ubuntu.authorized_keys | @tsv' "$DEPLOY_SPEC" |
  while IFS=$'\t' read -r key; do
    echo "$key" >> "/home/ubuntu/authorized_keys"
    chown ubuntu:ubuntu "/home/ubuntu/authorized_keys"
    chmod 0600 "/home/ubuntu/authorized_keys"
  done
