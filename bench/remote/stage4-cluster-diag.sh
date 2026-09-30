#!/bin/bash
# 4단계(b) 보강: 장애 대상 노드를 "앱 구독 연결이 붙은 노드" 또는 "구독 없는 마스터" 로 고르고,
# 장애 직전 6개 노드의 client list(구독·pub 연결 위치)를 남긴다. usage: stage4-cluster-diag.sh <name> <kill|pause> <sub|nosub>
source "$(dirname "$0")/lib.sh"; ST=04/cluster; NAME=$1; FAULT=$2; PICK=$3
NODES="REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002"
app "bench/stop.sh; bash bench/redis-cluster.sh > /tmp/rc-setup.log; grep -E 'cluster_state|cluster_size' /tmp/rc-setup.log"
start_servers "3001 3002" $NODES || exit 1
app "mkdir -p bench/results/$ST; for p in 7000 7001 7002 7003 7004 7005; do echo \"## \$p \$(redis-cli -p \$p role | head -1)\"; redis-cli -p \$p client list | grep -v 'cmd=client' | sed 's/^.*addr=/addr=/' | cut -c1-120; done > bench/results/$ST/$NAME.clients"
SUBNODES=$(app "for p in 7000 7001 7002 7003 7004 7005; do redis-cli -p \$p client list | grep -q 'sub=[1-9]' && echo \$p; done | tr '\n' ' '")
MASTERS=$(app "for p in 7000 7001 7002 7003 7004 7005; do [ \"\$(redis-cli -p \$p role | head -1)\" = master ] && echo \$p; done | tr '\n' ' '")
echo "subscribers on: $SUBNODES / masters: $MASTERS"
if [ $PICK = sub ]; then TARGET=$(echo $SUBNODES | tr ' ' '\n' | head -1); else TARGET=$(for m in $MASTERS; do echo " $SUBNODES " | grep -q " $m " || echo $m; done | head -1); fi
TARGET=${TARGET:-7000}; RP=$(redis_pid $TARGET); ROLE=$(app "redis-cli -p $TARGET role | head -1")
echo "target=$TARGET role=$ROLE pid=$RP pick=$PICK subs=[$SUBNODES]" | tee /tmp/$NAME.target
sampler $ST $NAME $(app_pid 3001) $(app_pid 3002)
case $FAULT in kill) CMD="kill -9 $RP && echo killed $TARGET pid $RP";; pause) CMD="kill -STOP $RP && echo stopped $TARGET pid $RP";; esac
run_load_fault $ST $NAME 15 "$CMD" 0 "" --ports 3001,3002 --users 20 --rate 50 --duration 75
sampler_stop
app "kill -CONT $RP 2>/dev/null; echo '$(cat /tmp/$NAME.target)' > bench/results/$ST/$NAME.target; grep -h 'FAIL\|failover\|elected\|Failover' /tmp/rc/*.log | tail -8 > bench/results/$ST/$NAME.cluster-events; cp /tmp/app-3001.log bench/results/$ST/$NAME.app-3001.log; cp /tmp/app-3002.log bench/results/$ST/$NAME.app-3002.log; cat /tmp/rc/*.log > bench/results/$ST/$NAME.cluster.log; bench/stop.sh; bash bench/redis-cluster.sh stop; true"
fetch $ST; echo DIAG_DONE
