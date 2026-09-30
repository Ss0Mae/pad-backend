# cpusample.sh 출력에서 창(window) 안 표본의 pid별 평균·피크 CPU%, 최대 메모리를 낸다.
# usage: cpustat.py <sample file> [from_epoch to_epoch]
import sys
f=sys.argv[1]; lo=float(sys.argv[2]) if len(sys.argv)>2 else 0; hi=float(sys.argv[3]) if len(sys.argv)>3 else 1e18
def mem(s):
    s=s.rstrip('+-'); u=s[-1]; v=float(s[:-1]) if u in 'KMG' else float(s)
    return v*{'K':1,'M':1024,'G':1048576}.get(u,1)/1024  # MB
rows={}
first=set(); lines=open(f).read().splitlines(); linux=bool(lines) and lines[0].startswith('# linux')
for line in lines:
    if line.startswith('#'): continue
    t,pid,cpu,m=line.split()[:4]
    if not linux and pid not in first: first.add(pid); continue   # macOS top 첫 표본(수명 전체 평균) 제외
    t=float(t)
    if t<lo or t>hi: continue
    rows.setdefault(pid,[]).append((float(cpu),mem(m)))
import json
out={pid:{'n':len(v),'cpu_avg':round(sum(c for c,_ in v)/len(v),1),'cpu_peak':max(c for c,_ in v),'mem_max_mb':round(max(m for _,m in v),1)} for pid,v in rows.items() if v}
print(json.dumps(out))
