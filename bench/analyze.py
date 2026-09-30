import json,sys
d=json.load(open(sys.argv[1]))
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
res['recovered_at_s']=rel(max(bad)) if bad else 0
print(json.dumps(res,ensure_ascii=False))
