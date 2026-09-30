# 결과 디렉터리 마무리: 원시 JSON 마다 <name>.res 를 새로 쓴다 — 1줄째 analyze.py 요약, 2줄째(있으면) 부하 구간의 CPU 통계
# (<name>.cpu 를 송신 시작~끝 창으로 자른 값). 원시 JSON 은 gzip 으로 바꾼다(저장소 크기). analyze.py·charts.py 는 .json.gz 를 그대로 읽는다.
# usage: finalize.py <results dir>
import sys, os, glob, json, gzip, subprocess
D=sys.argv[1]; here=os.path.dirname(os.path.abspath(__file__))
for js in sorted(glob.glob(f'{D}/*.json')+glob.glob(f'{D}/*.json.gz')):
    name=os.path.basename(js).split('.json')[0]
    if name.endswith('.createch'): continue
    d=json.load(gzip.open(js,'rt') if js.endswith('.gz') else open(js))
    lines=[subprocess.run([sys.executable,f'{here}/analyze.py',js],capture_output=True,text=True).stdout.strip()]
    cpu=f'{D}/{name}.cpu'
    if os.path.exists(cpu) and 't0' in d:
        lo=(d['t0']+d['start'])/1000; hi=lo+d['DUR']
        lines.append(subprocess.run([sys.executable,f'{here}/cpustat.py',cpu,str(lo),str(hi)],capture_output=True,text=True).stdout.strip())
    res=f'{D}/{name}.res'
    extra=[l for l in open(res).read().splitlines() if not l.startswith('{')] if os.path.exists(res) else []   # pids= 같은 메모 줄은 보존
    open(res,'w').write('\n'.join(lines+extra)+'\n')
    if js.endswith('.json'):
        with open(js,'rb') as fi, gzip.open(js+'.gz','wb') as fo: fo.write(fi.read())
        os.remove(js)
print('finalized',D)
