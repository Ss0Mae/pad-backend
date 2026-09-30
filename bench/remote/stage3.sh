#!/bin/bash
# 3단계(EC2): 서버 2대 + 어댑터 on + 단일 redis 6390(Sentinel 없음). 20명·50rps·75초, 약 15초에 redis kill -9.
#  (a) dead: 그대로 방치  (b) restart: 30초 뒤 같은 포트로 재기동. 각 2회.
#  (c) restart_warn: (b)와 같되 서버를 node --unhandled-rejections=warn 으로 띄운다 — (a)(b)에서 서버 프로세스가
#      ioredis MaxRetriesPerRequestError(미처리 promise 거부)로 죽어 재접속 복구 자체를 잴 수 없었기 때문. 벤치 전용 플래그.
source "$(dirname "$0")/lib.sh"; ST=03
RESTART='redis-server --port 6390 --bind 127.0.0.1 --save "" --appendonly no --daemonize yes --logfile /tmp/redis-6390.log'
ENSURE="redis-cli -p 6390 ping >/dev/null 2>&1 || { $RESTART; sleep 1; }"
run() { local NAME=$1 MODE=$2; local FLAGS=""; [ $MODE = restart_warn ] && FLAGS="NODE_FLAGS=--unhandled-rejections=warn"
  [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; return; }
  app "$ENSURE"; start_servers "3001 3002" REDIS_HOST=127.0.0.1 REDIS_PORT=6390 $FLAGS || return
  local RP=$(redis_pid 6390); sampler $ST $NAME $(app_pid 3001) $(app_pid 3002)
  local KILL="kill -9 $RP && echo killed $RP"
  if [ $MODE = restart ] || [ $MODE = restart_warn ]; then run_load_fault $ST $NAME 15 "$KILL" 45 "$RESTART && echo restarted" --ports 3001,3002 --users 20 --rate 50 --duration 75
  else run_load_fault $ST $NAME 15 "$KILL" 0 "" --ports 3001,3002 --users 20 --rate 50 --duration 75; fi
  sampler_stop
  app "echo alive app3001=\$(kill -0 \$(cat /tmp/app-3001.pid) 2>/dev/null && echo yes || echo no) app3002=\$(kill -0 \$(cat /tmp/app-3002.pid) 2>/dev/null && echo yes || echo no) | tee bench/results/$ST/$NAME.alive; cp /tmp/app-3001.log bench/results/$ST/$NAME.app-3001.log; cp /tmp/app-3002.log bench/results/$ST/$NAME.app-3002.log; $ENSURE"
}
for r in 1 2; do run dead_r$r dead; run restart_r$r restart; done
for r in 1 2; do run restart_warn_r$r restart_warn; done
app "bench/stop.sh"; fetch $ST; echo STAGE3_DONE
