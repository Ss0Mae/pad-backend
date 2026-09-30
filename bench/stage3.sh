#!/bin/bash
# 3단계: 서버 2대 + 어댑터 on + 단일 redis 6390(Sentinel 없음). 20명·50rps·75초, 15초에 redis kill -9.
#  (a) 그대로 60초 방치  (b) 30초 뒤 같은 포트로 redis 재기동. 각 2회.
cd "$(dirname "$0")/.."; OUT=bench/results/03; mkdir -p $OUT; export NODE_OPTIONS=
RESTART='redis-server --port 6390 --bind 127.0.0.1 --save "" --appendonly no --daemonize yes --logfile /tmp/redis-6390.log'
ensure_redis() { redis-cli -p 6390 ping >/dev/null 2>&1 || { eval $RESTART; sleep 1; }; }
run() { # run <name> <mode: dead|restart>
  NAME=$1; MODE=$2; [ -f $OUT/$NAME.res ] && { echo "skip $NAME"; return; }
  ensure_redis; bench/stop.sh; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
  bench/start.sh 3001 REDIS_HOST=127.0.0.1 REDIS_PORT=6390; bench/start.sh 3002 REDIS_HOST=127.0.0.1 REDIS_PORT=6390; bench/wait-up.sh 3001 3002 || return
  RP=$(redis-cli -p 6390 info server | grep process_id | cut -d: -f2 | tr -d '\r')
  bench/cpusample.sh $OUT/$NAME.cpu $(cat /tmp/app-3001.pid) $(cat /tmp/app-3002.pid) & CS=$!
  KILL="kill -9 $RP && echo killed $RP"
  if [ $MODE = restart ]; then
    node bench/load.js --ports 3001,3002 --users 20 --rate 50 --duration 75 --fault-at 15 --fault-cmd "$KILL" \
      --fault2-at 45 --fault2-cmd "$RESTART && echo restarted" --out $OUT/$NAME.json 2>$OUT/$NAME.log
  else
    node bench/load.js --ports 3001,3002 --users 20 --rate 50 --duration 75 --fault-at 15 --fault-cmd "$KILL" --out $OUT/$NAME.json 2>$OUT/$NAME.log
  fi
  kill $CS 2>/dev/null; pkill -f "top -l 0" 2>/dev/null
  echo "alive app3001=$(kill -0 $(cat /tmp/app-3001.pid) 2>/dev/null && echo yes || echo no) app3002=$(kill -0 $(cat /tmp/app-3002.pid) 2>/dev/null && echo yes || echo no)" | tee $OUT/$NAME.alive
  python3 bench/analyze.py $OUT/$NAME.json | tee $OUT/$NAME.res
  cp /tmp/app-3001.log $OUT/$NAME.app-3001.log; cp /tmp/app-3002.log $OUT/$NAME.app-3002.log
  ensure_redis
}
for r in 1 2; do run dead_r$r dead; run restart_r$r restart; done
bench/stop.sh; echo STAGE3_DONE
