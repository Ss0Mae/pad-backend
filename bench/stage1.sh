#!/bin/bash
# 1단계: 서버 1대(3001, 어댑터 off) 한계. 채널 1에 N명, 초당 R개 → 팬아웃 N×R 전달/초.
# usage: stage1.sh [WORKERS]   결과: bench/results/01/n<N>_r<R>.{json,res,cpu}
cd "$(dirname "$0")/.."; W=${1:-4}; OUT=bench/results/01; mkdir -p $OUT
export NODE_OPTIONS=
for N in ${GRID_N:-20 50 100 200}; do for R in ${GRID_R:-50 200 500}; do
  NAME=n${N}_r${R}; [ -f $OUT/$NAME.res ] && { echo "skip $NAME"; continue; }
  bench/stop.sh; mysql -h127.0.0.1 -uroot pad -e "DELETE FROM online_users"
  bench/start.sh 3001 CHAT_REDIS_ADAPTER=off REDIS_HOST=127.0.0.1 REDIS_PORT=6390; bench/wait-up.sh 3001 || exit 1
  SP=$(cat /tmp/app-3001.pid)
  bench/cpusample.sh $OUT/$NAME.cpu $SP & CS=$!
  T1=$(date +%s)
  node bench/load.js --ports 3001 --users $N --rate $R --duration 30 --workers $W --out $OUT/$NAME.json 2>$OUT/$NAME.log
  T2=$(date +%s); kill $CS 2>/dev/null; pkill -f "top -l 0" 2>/dev/null
  python3 bench/analyze.py $OUT/$NAME.json | tee $OUT/$NAME.res
  # 부하 창 = 접속(약 2초) 이후 30초
  python3 bench/cpustat.py $OUT/$NAME.cpu $((T1+3)) $((T1+33)) | tee -a $OUT/$NAME.res
  cp /tmp/app-3001.log $OUT/$NAME.app.log
done; done
bench/stop.sh; echo STAGE1_DONE
