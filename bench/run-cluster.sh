#!/bin/bash
# 4단계(b): Redis Cluster(7000~7005) 위에서 마스터 하나에 SIGKILL/SIGSTOP. run.sh 의 Cluster 판.
# usage: run-cluster.sh <name> <none|kill|pause> [app env...]
cd "$(dirname "$0")/.."; NAME=$1; FAULT=$2; shift 2; export NODE_OPTIONS=
bench/stop.sh; bash bench/redis-cluster.sh > /tmp/rc-setup.log; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
NODES="REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002"
bench/start.sh 3001 $NODES "$@"; bench/start.sh 3002 $NODES "$@"; bench/wait-up.sh 3001 3002 || exit 1; sleep 3
# 앱의 sub 클라이언트가 붙은 마스터를 고른다(그 노드가 죽어야 pub/sub 경로가 영향을 받는다). 못 찾으면 7000.
TARGET=$(for p in 7000 7001 7002; do redis-cli -p $p client list 2>/dev/null | grep -q "cmd=subscribe\|cmd=ssubscribe\|sub=[1-9]\|psub=[1-9]" && echo $p; done | head -1); TARGET=${TARGET:-7000}
PIDT=$(redis-cli -p $TARGET info server | grep process_id | cut -d: -f2 | tr -d '\r')
case $FAULT in
  kill) CMD="kill -9 $PIDT && echo killed master $TARGET pid $PIDT";;
  pause) CMD="kill -STOP $PIDT && echo stopped master $TARGET pid $PIDT";;
  *) CMD='';;
esac
echo "target=$TARGET pid=$PIDT" > /tmp/$NAME.target
node bench/load.js --ports 3001,3002 --users 20 --rate 50 --duration 75 --fault-at 15 --fault-cmd "$CMD" --out /tmp/$NAME.json
kill -CONT $PIDT 2>/dev/null
grep -h "FAIL\|failover\|elected\|Configuration change detected\|new master" /tmp/rc/*.log | tail -8
mkdir -p /tmp/logs; cp /tmp/app-3001.log /tmp/logs/$NAME-3001.log; cp /tmp/app-3002.log /tmp/logs/$NAME-3002.log; cat /tmp/rc/*.log > /tmp/logs/$NAME-cluster.log
python3 bench/analyze.py /tmp/$NAME.json | tee /tmp/$NAME.res; cat /tmp/$NAME.target >> /tmp/$NAME.res
