#!/bin/bash
# usage: wait-up.sh <port>... — 각 서버 로그에 기동 줄이 찍힐 때까지(최대 40초) 기다린다.
for p in "$@"; do
  for i in $(seq 1 40); do grep -q "bench app on $p" /tmp/app-$p.log 2>/dev/null && break; sleep 1; done
  grep -q "bench app on $p" /tmp/app-$p.log || { echo "server $p did not start"; tail -5 /tmp/app-$p.log; exit 1; }
done; sleep 1
