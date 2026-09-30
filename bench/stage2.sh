#!/bin/bash
# 2단계: 서버 2대(3001, 3002). (a) 어댑터 off (b) 어댑터 on(단일 redis 6390). 각 2회 + 1:1 채팅방 생성 시험.
# usage: stage2.sh <N> <R>   결과: bench/results/02/
cd "$(dirname "$0")/.."; N=${1:-100}; R=${2:-200}; OUT=bench/results/02; mkdir -p $OUT; export NODE_OPTIONS=
RP=$(redis-cli -p 6390 info server | grep process_id | cut -d: -f2 | tr -d '\r')
run() { # run <name> <env...>
  NAME=$1; shift; [ -f $OUT/$NAME.res ] && { echo "skip $NAME"; return; }
  bench/stop.sh; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
  bench/start.sh 3001 REDIS_HOST=127.0.0.1 REDIS_PORT=6390 "$@"; bench/start.sh 3002 REDIS_HOST=127.0.0.1 REDIS_PORT=6390 "$@"; bench/wait-up.sh 3001 3002 || return
  bench/cpusample.sh $OUT/$NAME.cpu $(cat /tmp/app-3001.pid) $(cat /tmp/app-3002.pid) $RP & CS=$!
  T1=$(date +%s)
  node bench/load.js --ports 3001,3002 --users $N --rate $R --duration 30 --workers 4 --out $OUT/$NAME.json 2>$OUT/$NAME.log
  kill $CS 2>/dev/null; pkill -f "top -l 0" 2>/dev/null
  python3 bench/analyze.py $OUT/$NAME.json | tee $OUT/$NAME.res
  python3 bench/cpustat.py $OUT/$NAME.cpu $((T1+3)) $((T1+33)) | tee -a $OUT/$NAME.res
  echo "pids app3001=$(cat /tmp/app-3001.pid) app3002=$(cat /tmp/app-3002.pid) redis=$RP" >> $OUT/$NAME.res
  # 1:1 채팅방 생성(생성자 3001, 상대 3002)
  node bench/createch.js 20 | tee $OUT/$NAME.createch.json
  cp /tmp/app-3001.log $OUT/$NAME.app-3001.log; cp /tmp/app-3002.log $OUT/$NAME.app-3002.log
}
for r in 1 2; do
  run off_r$r CHAT_REDIS_ADAPTER=off
  run on_r$r CHAT_REDIS_ADAPTER=on
done
# 어댑터 도입 전 게이트웨이로 1:1 채팅방 생성만(undefined.emit 재현)
run legacy_off_r1 CHAT_REDIS_ADAPTER=off CHAT_GATEWAY=legacy
bench/stop.sh; echo STAGE2_DONE
