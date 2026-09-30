#!/bin/bash
# 4단계 비용 축: 같은 부하(20명·50rps·30초)에서 Sentinel 구성(redis 6 프로세스) vs Cluster 구성(6 프로세스).
# 기록: Redis 프로세스별 CPU, 노드별 info stats/commandstats 전후 차(PUBLISH 호출 수·net 바이트), cluster bus publish 메시지 수.
cd "$(dirname "$0")/.."; OUT=bench/results/04/cost; mkdir -p $OUT; export NODE_OPTIONS=
snap() { # snap <tag> <ports...>
  local tag=$1; shift
  for p in "$@"; do
    { echo "## port $p"; redis-cli -p $p info stats | grep -E "total_commands_processed|total_net_input_bytes|total_net_output_bytes|total_net_repl_output_bytes|total_net_repl_input_bytes|pubsub_channels|instantaneous_ops_per_sec";
      redis-cli -p $p info commandstats | grep -E "cmdstat_publish|cmdstat_subscribe|cmdstat_ping";
      redis-cli -p $p info replication | grep -E "^role"; 
      redis-cli -p $p cluster info 2>/dev/null | grep -E "cluster_stats_messages_publish|cluster_stats_messages_sent|cluster_stats_messages_received"; } >> $OUT/$tag.stats
  done
}
measure() { # measure <name> <ports> <env...>
  local NAME=$1 PORTS=$2; shift 2
  bench/stop.sh; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
  bench/start.sh 3001 "$@"; bench/start.sh 3002 "$@"; bench/wait-up.sh 3001 3002 || return; sleep 2
  PIDS=""; for p in $PORTS; do PIDS="$PIDS $(redis-cli -p $p info server | grep process_id | cut -d: -f2 | tr -d '\r')"; done
  echo "ports=$PORTS pids=$PIDS" > $OUT/$NAME.pids
  rm -f $OUT/${NAME}_before.stats $OUT/${NAME}_after.stats
  snap ${NAME}_before $PORTS
  bench/cpusample.sh $OUT/$NAME.cpu $PIDS $(cat /tmp/app-3001.pid) $(cat /tmp/app-3002.pid) & CS=$!
  T1=$(date +%s)
  node bench/load.js --ports 3001,3002 --users 20 --rate 50 --duration 30 --out $OUT/$NAME.json 2>$OUT/$NAME.log
  snap ${NAME}_after $PORTS
  kill $CS 2>/dev/null; pkill -f "top -l 0" 2>/dev/null
  python3 bench/analyze.py $OUT/$NAME.json | tee $OUT/$NAME.res
  python3 bench/cpustat.py $OUT/$NAME.cpu $((T1+3)) $((T1+33)) | tee -a $OUT/$NAME.res
}
for r in 1 2; do
  bash bench/redis-sentinel.sh > /dev/null
  measure sentinel_r$r "6380 6381 6382 26380 26381 26382" REDIS_SENTINELS=127.0.0.1:26380,127.0.0.1:26381,127.0.0.1:26382 REDIS_MASTER_NAME=pad-master
  bench/stop.sh; for p in 6380 6381 6382 26380 26381 26382; do redis-cli -p $p shutdown nosave >/dev/null 2>&1; done
  bash bench/redis-cluster.sh > /dev/null
  measure cluster_r$r "7000 7001 7002 7003 7004 7005" REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002
  bench/stop.sh; bash bench/redis-cluster.sh stop
done
echo STAGE4C_DONE
