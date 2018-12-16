#!/bin/bash

ZOOKEEPER_CONF_DIR=/etc/zookeeper/conf

if [ "$MASTER_REPLICA" -ge 1 ]; then
  for i in $(seq $MASTER_REPLICA); do
    echo "server.$i=master$i.$ENVIRON_DNS_SUFFIX:2888:3888" >> $ZOOKEEPER_CONF_DIR/zoo.cfg
  done
else
  echo 'Invalid number of master replica'
  exit 1
fi

if [ "$SLAVE_REPLICA" -ge 1 ]; then
  for i in $(seq $(( $MASTER_REPLICA + 1)) $(( $SLAVE_REPLICA + $MASTER_REPLICA))); do
    echo "server.$i=slave$(($i - $SLAVE_REPLICA)).$ENVIRON_DNS_SUFFIX:2888:3888" >> $ZOOKEEPER_CONF_DIR/zoo.cfg
  done
else
  echo 'Invalid number of slave replica'
  exit 2
fi
