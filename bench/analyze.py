import json,sys,gzip
f=sys.argv[1]; d=json.load(gzip.open(f,'rt') if f.endswith('.gz') else open(f))
port={u['i']:u['port'] for u in d['users']}; N=d['USERS']; F=d.get('faultT')
sent={int(k):v for k,v in d['sent']}
got={}
for mid,ui,t in d['recv']: got.setdefault(mid,{})[ui]=t
same=cross=okS=okC=0; lat=[]; lostT=[]; lateT=[]
for mid,s in sent.items():
    r=got.get(mid,{})
    for ui in range(N):
        c=port[ui]!=s['port']
        if c: cross+=1
        else: same+=1
        if ui in r:
            l=r[ui]-s['at']; lat.append(l)
            if c: okC+=1
            else: okS+=1
            if l>1000: lateT.append(s['at'])
        elif c: lostT.append(s['at'])
q=lambda a,p: sorted(a)[max(0,int(len(a)*p)-1)] if a else None
rel=lambda t: round((t-F)/1000,2) if F is not None else round(t/1000,2)
res={'messages':len(sent),'same_node_delivery':round(okS/same,4) if same else None,'cross_node_delivery':round(okC/cross,4) if cross else None,
 'lost_cross_deliveries':cross-okC,'lost_same_deliveries':same-okS,
 'lost_window_s':[rel(min(lostT)),rel(max(lostT))] if lostT else None,
 'late_over_1s':len(lateT),'late_window_s':[rel(min(lateT)),rel(max(lateT))] if lateT else None,
 'p50_ms':q(lat,.5),'p99_ms':q(lat,.99),'max_ms':max(lat) if lat else None}
# 복구 시점: 장애 이후, 그 뒤로 보낸 모든 메시지가 다른 서버 사용자에게 1초 안에 닿기 시작한 송신 시각
bad=[]
for mid,s in sent.items():
    r=got.get(mid,{})
    for ui in range(N):
        if port[ui]!=s['port'] and (ui not in r or r[ui]-s['at']>1000): bad.append(s['at']); break
res['disrupted_messages']=len(bad)
# 초별 p99 의 중앙값·최대: 전체 p99 가 몇 초짜리 순간 정체(GC·CPU 스틸)에 끌려가는지, 정상 상태는 어떤지 가른다
sec={}
for mid,s in sent.items():
    k=int((s['at']-d['start'])/1000)
    for ui,t in got.get(mid,{}).items(): sec.setdefault(k,[]).append(t-s['at'])
secp=[q(v,.99) for k,v in sorted(sec.items()) if k<d['DUR']]
res['p99_per_sec_median']=q(secp,.5); res['p99_per_sec_max']=max(secp) if secp else None
res['secs_over_100ms']=sum(1 for v in secp if v>100)
res['sent_rate']=round(len(sent)/d['DUR'],1)
res['deliveries_per_s']=round(len(sent)*N/d['DUR'])
res['loader_cpu_pct']=round(d['loaderCpu']) if 'loaderCpu' in d else None
res['senders']=d.get('SENDERS'); res['workers']=d.get('WORKERS')
res['recovered_at_s']=rel(max(bad)) if bad else 0
print(json.dumps(res,ensure_ascii=False))
