#!/bin/bash
# usage: cpusample.sh <out> <pid>... — 1초 간격으로 프로세스 CPU%·메모리를 기록한다(macOS top 스트리밍).
# 출력: "epoch_s pid cpu mem" 한 줄씩. 첫 표본은 top 이 프로세스 수명 전체 평균을 내므로 분석에서 버린다.
OUT=$1; shift; PIDS=""; for p in "$@"; do PIDS="$PIDS -pid $p"; done
exec top -l 0 -s 1 -stats pid,cpu,mem $PIDS | awk '/^[0-9]+ /{ cmd="date +%s"; cmd | getline t; close(cmd); print t, $1, $2, $3; fflush() }' > "$OUT"
