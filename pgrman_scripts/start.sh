#!/bin/bash

case "$1" in
  start)
    service cron restart
    cron
    ;;
  stop)
    service cron stop
    ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
esac
