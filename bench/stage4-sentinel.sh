#!/bin/bash
# 4단계(a): Sentinel 페일오버 재실행. SIGKILL·SIGSTOP × {기본, REDIS_FAILOVER_DETECTOR=true} 각 2회.
cd "$(dirname "$0")/.."; OUT=bench/results/04/sentinel; mkdir -p $OUT; export NODE_OPTIONS=
for r in 1 2; do
  for c in "kill:" "pause:" "pause:REDIS_FAILOVER_DETECTOR=true" "kill:REDIS_FAILOVER_DETECTOR=true"; do
    F=${c%%:*}; E=${c#*:}; NAME=sent_${F}${E:+_fd}_r$r
    [ -f $OUT/$NAME.res ] && { echo skip $NAME; continue; }
    bash bench/run.sh $NAME $F $E > /tmp/$NAME.out 2>&1
    cp /tmp/$NAME.json /tmp/$NAME.res $OUT/; cp /tmp/$NAME.out $OUT/$NAME.log
    cp /tmp/logs/$NAME-3001.log /tmp/logs/$NAME-3002.log /tmp/logs/$NAME-s.log $OUT/
    tail -1 $OUT/$NAME.res
  done
done
bench/stop.sh; for p in 6380 6381 6382 26380 26381 26382; do redis-cli -p $p shutdown nosave >/dev/null 2>&1; done
echo STAGE4A_DONE
