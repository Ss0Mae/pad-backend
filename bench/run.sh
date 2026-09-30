#!/bin/bash
# usage: run.sh <name> <none|kill|pause> [app env...]
cd "$(dirname "$0")/.."; NAME=$1; FAULT=$2; shift 2
bench/stop.sh; bash bench/redis-sentinel.sh >/dev/null; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
SENT="REDIS_SENTINELS=127.0.0.1:26380,127.0.0.1:26381,127.0.0.1:26382 REDIS_MASTER_NAME=pad-master"
bench/start.sh 3001 $SENT "$@"; bench/start.sh 3002 $SENT "$@"; bench/wait-up.sh 3001 3002 || exit 1; sleep 3
case $FAULT in
  kill) CMD='kill -9 $(redis-cli -p 6380 info server | grep process_id | cut -d: -f2 | tr -d "\r") && echo killed';;
  pause) CMD='kill -STOP $(redis-cli -p 6380 info server | grep process_id | cut -d: -f2 | tr -d "\r") && echo stopped';;
  *) CMD='';;
esac
PID6380=$(redis-cli -p 6380 info server | grep process_id | cut -d: -f2 | tr -d "\r")
node bench/load.js --users 20 --rate 50 --duration 75 --fault-at 15 --fault-cmd "$CMD" --out /tmp/$NAME.json
kill -CONT $PID6380 2>/dev/null
grep -h "switch-master\|+odown\|+sdown master" /tmp/rs/s26380.log | tail -4
grep -c "switch-master" /tmp/app-3001.log /tmp/app-3002.log
mkdir -p /tmp/logs; cp /tmp/app-3001.log /tmp/logs/$NAME-3001.log; cp /tmp/app-3002.log /tmp/logs/$NAME-3002.log; cp /tmp/rs/s26380.log /tmp/logs/$NAME-s.log
python3 bench/analyze.py /tmp/$NAME.json | tee /tmp/$NAME.res
