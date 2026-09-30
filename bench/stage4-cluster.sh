#!/bin/bash
# 4단계(b): Cluster 마스터 하나에 SIGKILL·SIGSTOP 각 2회.
cd "$(dirname "$0")/.."; OUT=bench/results/04/cluster; mkdir -p $OUT; export NODE_OPTIONS=
for r in 1 2; do for F in kill pause; do
  NAME=clu_${F}_r$r; [ -f $OUT/$NAME.res ] && { echo skip $NAME; continue; }
  bash bench/run-cluster.sh $NAME $F > /tmp/$NAME.out 2>&1
  cp /tmp/$NAME.json /tmp/$NAME.res $OUT/; cp /tmp/$NAME.out $OUT/$NAME.log
  cp /tmp/logs/$NAME-3001.log /tmp/logs/$NAME-3002.log /tmp/logs/$NAME-cluster.log $OUT/
  tail -2 $OUT/$NAME.res
done; done
bench/stop.sh; bash bench/redis-cluster.sh stop; echo STAGE4B_DONE
