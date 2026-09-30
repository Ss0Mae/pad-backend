#!/bin/bash
# 4단계(a, EC2): Sentinel 페일오버. SIGKILL·SIGSTOP × {기본, REDIS_FAILOVER_DETECTOR=true} 각 2회. 20명·50rps·75초, 약 15초에 장애.
source "$(dirname "$0")/lib.sh"; ST=04/sentinel
SENT="REDIS_SENTINELS=127.0.0.1:26380,127.0.0.1:26381,127.0.0.1:26382 REDIS_MASTER_NAME=pad-master"
run() { local NAME=$1 FAULT=$2; shift 2
  [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; return; }
  app "bench/stop.sh; bash bench/redis-sentinel.sh" | tail -2
  start_servers "3001 3002" $SENT "$@" || return
  local RP=$(redis_pid 6380); sampler $ST $NAME $(app_pid 3001) $(app_pid 3002)
  case $FAULT in kill) CMD="kill -9 $RP && echo killed $RP";; pause) CMD="kill -STOP $RP && echo stopped $RP";; esac
  run_load_fault $ST $NAME 15 "$CMD" 0 "" --ports 3001,3002 --users 20 --rate 50 --duration 75
  sampler_stop
  app "kill -CONT $RP 2>/dev/null; grep -h 'switch-master\|+odown\|+sdown master' /tmp/rs/s26380.log | tail -4 | tee bench/results/$ST/$NAME.sentinel-events; grep -c switch-master /tmp/app-3001.log /tmp/app-3002.log; cp /tmp/app-3001.log bench/results/$ST/$NAME.app-3001.log; cp /tmp/app-3002.log bench/results/$ST/$NAME.app-3002.log; cp /tmp/rs/s26380.log bench/results/$ST/$NAME.sentinel.log"
}
for r in 1 2; do
  run sent_kill_r$r kill; run sent_pause_r$r pause
  run sent_pause_fd_r$r pause REDIS_FAILOVER_DETECTOR=true; run sent_kill_fd_r$r kill REDIS_FAILOVER_DETECTOR=true
done
app "bench/stop.sh; for p in 6380 6381 6382 26380 26381 26382; do redis-cli -p \$p shutdown nosave >/dev/null 2>&1; done; true"
fetch $ST; echo STAGE4A_DONE
