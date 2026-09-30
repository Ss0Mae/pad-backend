#!/bin/bash
# 1단계(EC2): 앱 박스에 서버 1대(3001, 어댑터 off), 부하기 박스에서 N×R 격자. usage: stage1.sh  (GRID_N/GRID_R 로 격자 지정)
source "$(dirname "$0")/lib.sh"; ST=01
for N in ${GRID_N:-20 50 100 200 500}; do for R in ${GRID_R:-50 200 500}; do
  NAME=n${N}_r${R}; [ -f "$REPO/bench/results/$ST/$NAME.res" ] && { echo skip $NAME; continue; }
  start_servers 3001 CHAT_REDIS_ADAPTER=off REDIS_HOST=127.0.0.1 REDIS_PORT=6390 || exit 1
  sampler $ST $NAME $(app_pid 3001)
  run_load $ST $NAME --ports 3001 --users $N --rate $R --duration 30 --workers ${WORKERS:-2}
  sampler_stop; app "cp /tmp/app-3001.log bench/results/$ST/$NAME.app.log"
done; done
app "bench/stop.sh"; fetch $ST; echo STAGE1_DONE
