# .res 요약을 한 줄씩 표로. usage: table.py <results dir>
import json,glob,os,sys
for f in sorted(glob.glob(f'{sys.argv[1]}/*.res')):
    n=os.path.basename(f)[:-4]; l=[x for x in open(f) if x.startswith('{')]
    if not l: print(n,'(no data)'); continue
    a=json.loads(l[0]); c=json.loads(l[1]) if len(l)>1 else {}
    procs={k:v for k,v in c.items() if k!='sys'}; sy=c.get('sys',{})
    cpu=' '.join(f"{v['cpu_avg']:.0f}/{v['cpu_peak']:.0f}" for v in procs.values())
    print(f"{n:16} fan{a['deliveries_per_s']:>7} del {a['same_node_delivery']} cross {a['cross_node_delivery']} p50 {a['p50_ms']} p99 {a['p99_ms']} max {a['max_ms']} secP99 med/max/over {a.get('p99_per_sec_median')}/{a.get('p99_per_sec_max')}/{a.get('secs_over_100ms')} lost {a['lost_cross_deliveries']}/{a['lost_same_deliveries']} late {a['late_over_1s']} rec {a['recovered_at_s']} | cpu {cpu} sys {sy.get('cpu_avg')} mem {' '.join(str(v['mem_max_mb']) for v in procs.values())} | loader {a['loader_cpu_pct']}")
