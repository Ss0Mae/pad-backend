#!/bin/bash
# 2단계(EC2): 서버 2대(3001, 3002). (a) 어댑터 off (b) 어댑터 on(단일 redis 6390). 각 2회 + 레거시 게이트웨이 1회(1:1 채팅방 생성만).
# usage: stage2.sh <N> <R>
source "$(dirname "$0")/lib.sh"; ST=02; N=${1:-100}; R=${2:-200}
ENSURE='redis-cli -p 6390 ping >/dev/null 2>&1 || redis-server --port 6390 --bind 127.0.0.1 --save "" --appendonly no --daemonize yes --logfile /tmp/redis-6390.log'
run() { local NAME=$1; shift
  [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; return; }
  app "$ENSURE"; start_servers "3001 3002" REDIS_HOST=127.0.0.1 REDIS_PORT=6390 "$@" || return
  sampler $ST $NAME $(app_pid 3001) $(app_pid 3002) $(redis_pid 6390)
  run_load $ST $NAME --ports 3001,3002 --users $N --rate $R --duration 30 --workers ${WORKERS:-2}
  sampler_stop
  loadb "node bench/createch.js 20 $APP_IP | tee results/$ST/$NAME.createch.json"
  app "cp /tmp/app-3001.log bench/results/$ST/$NAME.app-3001.log; cp /tmp/app-3002.log bench/results/$ST/$NAME.app-3002.log"
}
for r in 1 2; do run off_r$r CHAT_REDIS_ADAPTER=off; run on_r$r CHAT_REDIS_ADAPTER=on; done
run legacy_off_r1 CHAT_REDIS_ADAPTER=off CHAT_GATEWAY=legacy
app "bench/stop.sh"; fetch $ST; echo STAGE2_DONE
