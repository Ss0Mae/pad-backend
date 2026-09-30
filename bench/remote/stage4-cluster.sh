#!/bin/bash
# 4단계(b, EC2): Redis Cluster(7000~7005, 마스터 3 + 레플리카 3) 위에서 마스터 하나에 SIGKILL·SIGSTOP 각 2회.
# 죽이는 마스터 = 앱의 구독(sub) 연결이 붙은 마스터(없으면 7000). ioredis Cluster 는 구독 연결을 무작위 노드 하나에 둔다.
source "$(dirname "$0")/lib.sh"; ST=04/cluster
NODES="REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002"
run() { local NAME=$1 FAULT=$2; shift 2
  [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; return; }
  app "bench/stop.sh; bash bench/redis-cluster.sh > /tmp/rc-setup.log; grep -E 'cluster_state|cluster_size' /tmp/rc-setup.log"
  start_servers "3001 3002" $NODES "$@" || return
  local TARGET=$(app "for p in 7000 7001 7002; do redis-cli -p \$p client list 2>/dev/null | grep -q 'sub=[1-9]\|psub=[1-9]' && echo \$p; done | head -1"); TARGET=${TARGET:-7000}
  local RP=$(redis_pid $TARGET); echo "target=$TARGET pid=$RP"
  sampler $ST $NAME $(app_pid 3001) $(app_pid 3002)
  case $FAULT in kill) CMD="kill -9 $RP && echo killed master $TARGET pid $RP";; pause) CMD="kill -STOP $RP && echo stopped master $TARGET pid $RP";; esac
  run_load_fault $ST $NAME 15 "$CMD" 0 "" --ports 3001,3002 --users 20 --rate 50 --duration 75
  sampler_stop
  app "kill -CONT $RP 2>/dev/null; echo target=$TARGET pid=$RP > bench/results/$ST/$NAME.target; grep -h 'FAIL\|failover\|elected\|Configuration change\|new master\|Failover' /tmp/rc/*.log | tail -8 | tee bench/results/$ST/$NAME.cluster-events; cp /tmp/app-3001.log bench/results/$ST/$NAME.app-3001.log; cp /tmp/app-3002.log bench/results/$ST/$NAME.app-3002.log; cat /tmp/rc/*.log > bench/results/$ST/$NAME.cluster.log"
}
for r in 1 2; do run clu_kill_r$r kill; run clu_pause_r$r pause; done
app "bench/stop.sh; bash bench/redis-cluster.sh stop; true"
fetch $ST; echo STAGE4B_DONE
