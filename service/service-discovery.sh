#!/bin/bash

ROUTE53_BATCH_FILE=$TEMP_WORKDIR/route53_batch
INSTANCE_PRIV_IPV4=$(cat /run/cloud-init/instance-data.json | jq -r '.ds."meta-data"."local-ipv4"')
ROUTE53_HOSTED_ZONE=$(cat $DEPLOY_SPEC | jq -r '.config.discovery.dns.route53ZoneId')

upsert() {
  echo "{
    \"Comment\": \"Update Record for Cluster Node\",
    \"Changes\": [
      {
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"$NODE_HOSTNAME.$DNS_SUFFIX\",
          \"Type\": \"A\",
          \"TTL\": 60,
          \"ResourceRecords\": [{ \"Value\": \"$INSTANCE_PRIV_IPV4\" }]
        }
      }
    ]
  }
  " > $ROUTE53_BATCH_FILE

  aws route53 change-resource-record-sets --hosted-zone-id "$ROUTE53_HOSTED_ZONE" --change-batch "file://$ROUTE53_BATCH_FILE"

  rm -f $ROUTE53_BATCH_FILE
}

delete() {
  echo "{
    \"Comment\": \"Delete Record for Cluster Node\",
    \"Changes\": [
      {
        \"Action\": \"DELETE\",
        \"ResourceRecordSet\": {
          \"Name\": \"$NODE_HOSTNAME.$DNS_SUFFIX\",
          \"Type\": \"A\",
          \"TTL\": 60,
          \"ResourceRecords\": [{ \"Value\": \"$INSTANCE_PRIV_IPV4\" }]
        }
      }
    ]
  }
  " > $ROUTE53_BATCH_FILE

  aws route53 change-resource-record-sets --hosted-zone-id "$ROUTE53_HOSTED_ZONE" --change-batch "file://$ROUTE53_BATCH_FILE"

  rm -f $ROUTE53_BATCH_FILE
}

case "$1" in
  up)
    upsert
    ;;
  down)
    delete
    ;;
  *)
    echo "Usage: $0 {up|down}" >&2
    exit 1
    ;;
esac
