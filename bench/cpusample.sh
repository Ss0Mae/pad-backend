#!/bin/bash
# usage: cpusample.sh <out> <pid>... — 1초 간격으로 프로세스 CPU%·메모리를 기록한다.
# 출력: "epoch_s pid cpu mem" 한 줄씩. Linux 는 /proc/<pid>/stat 의 jiffies 차이로 계산(ps %cpu 는 수명 평균이라 안 씀),
# 'sys' 행은 기계 전체 CPU%(모든 코어 합/코어 수). macOS 는 top 스트리밍을 쓰고 첫 표본(수명 평균)은 분석에서 버린다.
OUT=$1; shift
if [ "$(uname)" = Linux ]; then
  exec python3 - "$OUT" "$@" <<'PY'
import sys, time, os
out=open(sys.argv[1],'w'); out.write('# linux\n'); pids=sys.argv[2:]; clk=os.sysconf('SC_CLK_TCK'); page=os.sysconf('SC_PAGE_SIZE')
def pstat(p):
    try:
        s=open(f'/proc/{p}/stat').read(); s=s[s.rindex(')')+2:].split()
        return int(s[11])+int(s[12]), int(s[21])*page/1048576
    except Exception: return None
def sysstat():
    v=list(map(int,open('/proc/stat').readline().split()[1:])); return sum(v), v[3]+v[4]
prev={p:pstat(p) for p in pids}; ps=sysstat(); t=time.time()
while True:
    time.sleep(max(0.05,1-(time.time()-t))); now=time.time(); dt=now-t; t=now
    lines=[]
    for p in pids:
        c=pstat(p)
        if c and prev.get(p): lines.append(f"{int(now)} {p} {((c[0]-prev[p][0])/clk/dt*100):.1f} {c[1]:.0f}M")
        prev[p]=c
    s=sysstat(); tot=s[0]-ps[0]; idle=s[1]-ps[1]; ps=s
    if tot>0: lines.append(f"{int(now)} sys {(tot-idle)/tot*100:.1f} 0M")
    out.write('\n'.join(lines)+'\n'); out.flush()
PY
fi
PIDS=""; for p in "$@"; do PIDS="$PIDS -pid $p"; done
exec top -l 0 -s 1 -stats pid,cpu,mem $PIDS | awk '/^[0-9]+ /{ cmd="date +%s"; cmd | getline t; close(cmd); print t, $1, $2, $3; fflush() }' > "$OUT"
