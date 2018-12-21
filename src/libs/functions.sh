#!/bin/bash

# Wait for a TCP port until it's up or timed out
# @args (string host, integer port, integer interval, integer retries)
port_wait() {
  local host=$1
  local port=$2
  local interval=${3:-5}
  local retries=${4:-3}

  if [ "$interval" -lt 1 ]; then
    interval=1
  fi

  if [ "$retries" -lt 1 ]; then
    retries=1
  fi

  local timeout=$(( interval * retries ))

  if timeout "$timeout" sh -c "until nc -z $host $port &> /dev/null; do sleep $interval; done"; then
    return 0
  else
    echo >&2 "Connection to $host:$port is timed out after $timeout seconds!"
    return 1
  fi
}
