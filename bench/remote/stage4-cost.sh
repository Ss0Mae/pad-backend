#!/bin/bash
# 4단계 비용 축(EC2): 같은 부하(20명·50rps·30초)에서 Sentinel 구성(redis 6 프로세스) vs Cluster 구성(6 프로세스).
# 기록: Redis 프로세스별 CPU, 노드별 info stats/commandstats 전후(PUBLISH 호출 수·net 바이트), cluster bus publish 메시지 수.
source "$(dirname "$0")/lib.sh"; ST=04/cost
SNAP='snap() { tag=$1; shift; for p in "$@"; do { echo "## port $p"; redis-cli -p $p info stats | grep -E "total_commands_processed|total_net_input_bytes|total_net_output_bytes|total_net_repl_output_bytes|total_net_repl_input_bytes|pubsub_channels"; redis-cli -p $p info commandstats | grep -E "cmdstat_publish|cmdstat_subscribe|cmdstat_ping|cmdstat_replconf"; redis-cli -p $p info replication | grep -E "^role"; redis-cli -p $p cluster info 2>/dev/null | grep -E "cluster_stats_messages_publish|cluster_stats_messages_sent|cluster_stats_messages_received"; } >> bench/results/'$ST'/$tag.stats; done; }'
measure() { local NAME=$1 PORTS=$2; shift 2
  [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; return; }
  start_servers "3001 3002" "$@" || return; sleep 2
  local PIDS=$(app "for p in $PORTS; do redis-cli -p \$p info server | grep process_id | cut -d: -f2 | tr -d '\r'; done | tr '\n' ' '")
  app "mkdir -p bench/results/$ST; echo 'ports=$PORTS pids=$PIDS' > bench/results/$ST/$NAME.pids; rm -f bench/results/$ST/${NAME}_before.stats bench/results/$ST/${NAME}_after.stats; $SNAP; snap ${NAME}_before $PORTS"
  sampler $ST $NAME $PIDS $(app_pid 3001) $(app_pid 3002)
  run_load $ST $NAME --ports 3001,3002 --users 20 --rate 50 --duration 30
  app "$SNAP; snap ${NAME}_after $PORTS"; sampler_stop
}
for r in 1 2; do
  app "bench/stop.sh; bash bench/redis-sentinel.sh > /dev/null"
  measure sentinel_r$r "6380 6381 6382 26380 26381 26382" REDIS_SENTINELS=127.0.0.1:26380,127.0.0.1:26381,127.0.0.1:26382 REDIS_MASTER_NAME=pad-master
  app "bench/stop.sh; for p in 6380 6381 6382 26380 26381 26382; do redis-cli -p \$p shutdown nosave >/dev/null 2>&1; done; bash bench/redis-cluster.sh > /dev/null"
  measure cluster_r$r "7000 7001 7002 7003 7004 7005" REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002
  app "bench/stop.sh; bash bench/redis-cluster.sh stop; true"
done
fetch $ST; echo STAGE4C_DONE
