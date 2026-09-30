# bench/results/ 의 원시 결과에서 보고서용 그래프를 만든다. usage: charts.py [01|02|03|04|all]
import json, os, sys, glob, statistics
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
BG='#fcfcfb'; C=['#2a78d6','#eb6834','#1baf7a','#eda100']
plt.rcParams.update({'font.family':'AppleGothic','axes.unicode_minus':False,'figure.facecolor':BG,'axes.facecolor':BG,
  'savefig.facecolor':BG,'axes.spines.top':False,'axes.spines.right':False,'axes.titlelocation':'left','axes.titleweight':'bold','axes.titlesize':13})
R='bench/results'; OUT='bench/charts'; os.makedirs(OUT,exist_ok=True)
def res(path):
    lines=[l for l in open(path).read().splitlines() if l.startswith('{')]
    a=json.loads(lines[0]); c=json.loads(lines[1]) if len(lines)>1 else {}
    return a,c
def label(ax,bars,fmt='{:.0f}',dy=0):
    for b in bars:
        h=b.get_height()
        if h is None or h!=h: continue
        ax.annotate(fmt.format(h),(b.get_x()+b.get_width()/2,h),ha='center',va='bottom',fontsize=9,xytext=(0,2+dy),textcoords='offset points')
def series(js, bucket=1.0, cross=True):
    """송신 시각(장애 기준 상대 s) 버킷별 (다른|같은) 서버 전달률과 p99."""
    d=json.load(open(js)); port={u['i']:u['port'] for u in d['users']}; N=d['USERS']; F=d.get('faultT') or d['start']
    sent={int(k):v for k,v in d['sent']}; got={}
    for mid,ui,t in d['recv']: got.setdefault(mid,{})[ui]=t
    b={}
    for mid,s in sent.items():
        k=int((s['at']-F)/1000/bucket)*bucket; r=got.get(mid,{})
        e=b.setdefault(k,[0,0,[]])
        for ui in range(N):
            if (port[ui]!=s['port'])!=cross: continue
            e[1]+=1
            if ui in r and r[ui]-s['at']<=1000: e[0]+=1
            if ui in r: e[2].append(r[ui]-s['at'])
    ks=sorted(b); return ks,[b[k][0]/b[k][1]*100 if b[k][1] else None for k in ks],[sorted(b[k][2])[int(len(b[k][2])*.99)-1] if b[k][2] else None for k in ks]

def stage1():
    cells={}
    for f in sorted(glob.glob(f'{R}/01/n*_r*.res')):
        n,r=os.path.basename(f)[:-4].split('_'); a,c=res(f); cpu=list(c.values())[0] if c else {}
        cells[(int(n[1:]),int(r[1:]))]=(a,cpu)
    if not cells: return
    Ns=sorted({k[0] for k in cells}); Rs=sorted({k[1] for k in cells})
    fig,axs=plt.subplots(1,3,figsize=(14,4.4))
    for i,r in enumerate(Rs):
        xs=[n for n in Ns if (n,r) in cells]
        axs[0].plot(xs,[cells[(n,r)][0]['p99_ms'] for n in xs],'o-',color=C[i],label=f'{r} msg/s')
        for n in xs: axs[0].annotate(f"{cells[(n,r)][0]['p99_ms']}",(n,cells[(n,r)][0]['p99_ms']),fontsize=8,xytext=(3,3),textcoords='offset points')
        axs[1].plot(xs,[cells[(n,r)][1].get('cpu_avg') for n in xs],'o-',color=C[i],label=f'{r} msg/s')
        for n in xs: axs[1].annotate(f"{cells[(n,r)][1].get('cpu_avg',0):.0f}",(n,cells[(n,r)][1].get('cpu_avg')),fontsize=8,xytext=(3,3),textcoords='offset points')
        axs[2].plot(xs,[cells[(n,r)][0]['loader_cpu_pct'] for n in xs],'o-',color=C[i],label=f'{r} msg/s')
        for n in xs: axs[2].annotate(f"{cells[(n,r)][0]['loader_cpu_pct']}",(n,cells[(n,r)][0]['loader_cpu_pct']),fontsize=8,xytext=(3,3),textcoords='offset points')
    axs[0].axhline(100,ls='--',color='#999',lw=1); axs[0].set_yscale('log'); axs[0].set_title('전달 지연 p99 (ms, 로그축) — 점선 100 ms'); axs[0].set_xlabel('채널 사용자 수 N')
    axs[1].set_title('서버 프로세스 CPU 평균 (%)'); axs[1].set_xlabel('채널 사용자 수 N')
    axs[2].set_title('부하기 CPU 합계 (%, 프로세스 4개)'); axs[2].set_xlabel('채널 사용자 수 N')
    for ax in axs: ax.legend(frameon=False,fontsize=9); ax.set_xticks(Ns)
    fig.suptitle('1단계 · 서버 1대: 채널 1개 팬아웃 N×R (노트북 1대, 30초)',x=0.01,ha='left',fontsize=14,fontweight='bold')
    fig.tight_layout(); fig.savefig(f'{OUT}/01-single-server-limit.png',dpi=150); plt.close(fig)
    # 팬아웃(전달/초) 대 p99 산점
    fig,ax=plt.subplots(figsize=(7,4.2))
    for i,r in enumerate(Rs):
        pts=[(cells[(n,r)][0]['deliveries_per_s'],cells[(n,r)][0]['p99_ms'],n) for n in Ns if (n,r) in cells]
        ax.plot([p[0] for p in pts],[p[1] for p in pts],'o-',color=C[i],label=f'{r} msg/s')
        for x,y,n in pts: ax.annotate(f'N={n}',(x,y),fontsize=8,xytext=(3,3),textcoords='offset points')
    ax.set_xscale('log'); ax.set_yscale('log'); ax.axhline(100,ls='--',color='#999',lw=1)
    ax.set_xlabel('팬아웃 (전달/초 = N×R)'); ax.set_ylabel('p99 (ms)'); ax.set_title('1단계 · 팬아웃 대 p99'); ax.legend(frameon=False)
    fig.tight_layout(); fig.savefig(f'{OUT}/01-fanout-vs-p99.png',dpi=150); plt.close(fig)

def stage2():
    rows={}
    for f in sorted(glob.glob(f'{R}/02/*_r*.res')):
        k=os.path.basename(f)[:-4].rsplit('_r',1)[0]; a,c=res(f); rows.setdefault(k,[]).append((a,c))
    if not rows: return
    keys=[k for k in ['off','on'] if k in rows]; names={'off':'어댑터 없음','on':'Redis 어댑터'}
    fig,axs=plt.subplots(1,3,figsize=(13,4.2))
    same=[statistics.mean(a['same_node_delivery'] for a,_ in rows[k])*100 for k in keys]
    cross=[statistics.mean(a['cross_node_delivery'] for a,_ in rows[k])*100 for k in keys]
    x=range(len(keys)); w=0.38
    b1=axs[0].bar([i-w/2 for i in x],same,w,color=C[0],label='같은 서버'); b2=axs[0].bar([i+w/2 for i in x],cross,w,color=C[1],label='다른 서버')
    label(axs[0],b1,'{:.1f}%'); label(axs[0],b2,'{:.1f}%'); axs[0].set_ylim(0,115); axs[0].set_title('전달률 (%)'); axs[0].legend(frameon=False)
    p50=[statistics.mean(a['p50_ms'] for a,_ in rows[k]) for k in keys]; p99=[statistics.mean(a['p99_ms'] for a,_ in rows[k]) for k in keys]
    b1=axs[1].bar([i-w/2 for i in x],p50,w,color=C[0],label='p50'); b2=axs[1].bar([i+w/2 for i in x],p99,w,color=C[1],label='p99')
    label(axs[1],b1,'{:.0f}'); label(axs[1],b2,'{:.0f}'); axs[1].set_title('전달 지연 (ms) — 닿은 전달만'); axs[1].legend(frameon=False)
    # CPU: 서버 2대 합, redis
    def cpu(k,which):
        vals=[]
        for a,c in rows[k]:
            pids=sorted(c.keys()); # 순서: 3001,3002,redis (stage2.sh 순)
            if which=='app': vals.append(sum(c[p]['cpu_avg'] for p in list(c)[:2]))
            else: vals.append(list(c.values())[2]['cpu_avg'] if len(c)>2 else 0)
        return statistics.mean(vals)
    b1=axs[2].bar([i-w/2 for i in x],[cpu(k,'app') for k in keys],w,color=C[0],label='서버 2대 합'); b2=axs[2].bar([i+w/2 for i in x],[cpu(k,'redis') for k in keys],w,color=C[2],label='Redis')
    label(axs[2],b1,'{:.0f}%'); label(axs[2],b2,'{:.1f}%'); axs[2].set_title('CPU 평균 (%)'); axs[2].legend(frameon=False)
    for ax in axs: ax.set_xticks(list(x)); ax.set_xticklabels([names[k] for k in keys])
    a0=rows[keys[0]][0][0]
    fig.suptitle(f"2단계 · 서버 2대, 사용자 {a0['messages']//a0['sent_rate']//30*0+int(json.load(open(glob.glob(f'{R}/02/{keys[0]}_r1.json')[0]))['USERS'])}명·{a0['sent_rate']:.0f} msg/s (2회 평균)",x=0.01,ha='left',fontsize=14,fontweight='bold')
    fig.tight_layout(); fig.savefig(f'{OUT}/02-two-servers-adapter.png',dpi=150); plt.close(fig)

def stage3():
    fig,axs=plt.subplots(2,1,figsize=(11,6.4),sharex=True)
    for i,(k,t) in enumerate([('dead','Redis 죽인 뒤 방치'),('restart','30초 뒤 같은 포트로 재기동')]):
        for r in (1,2):
            f=f'{R}/03/{k}_r{r}.json'
            if not os.path.exists(f): continue
            ks,cr,_=series(f); _,sm,_=series(f,cross=False)
            axs[i].plot(ks,cr,color=C[1],lw=1.8 if r==1 else 1,alpha=1 if r==1 else .5,label=f'다른 서버 전달률 (r{r})')
            axs[i].plot(ks,sm,color=C[0],lw=1.8 if r==1 else 1,alpha=1 if r==1 else .5,label=f'같은 서버 전달률 (r{r})')
        axs[i].axvline(0,color='#333',ls='--',lw=1); axs[i].text(0.3,50,'kill -9',fontsize=9)
        if k=='restart': axs[i].axvline(30,color='#1baf7a',ls='--',lw=1); axs[i].text(30.3,50,'재기동',fontsize=9,color='#1baf7a')
        axs[i].set_ylim(-5,110); axs[i].set_ylabel('1초 안 전달률 (%)'); axs[i].set_title(f'{t}'); axs[i].legend(frameon=False,fontsize=8,loc='lower right')
    axs[1].set_xlabel('장애 기준 송신 시각 (s)')
    fig.suptitle('3단계 · 단일 Redis 장애 (서버 2대 + 어댑터, 20명·50 msg/s)',x=0.01,ha='left',fontsize=14,fontweight='bold')
    fig.tight_layout(); fig.savefig(f'{OUT}/03-redis-spof.png',dpi=150); plt.close(fig)

def stage4():
    def med(pat, key):
        vals=[]
        for f in glob.glob(pat):
            a,_=res(f); v=a[key]
            vals.append(v)
        return vals
    groups=[('Sentinel\nSIGKILL 기본',f'{R}/04/sentinel/sent_kill_r*.res'),('Sentinel\nSIGSTOP 기본',f'{R}/04/sentinel/sent_pause_r*.res'),
            ('Sentinel\nSIGKILL +fd',f'{R}/04/sentinel/sent_kill_fd_r*.res'),('Sentinel\nSIGSTOP +fd',f'{R}/04/sentinel/sent_pause_fd_r*.res'),
            ('Cluster\nSIGKILL',f'{R}/04/cluster/clu_kill_r*.res'),('Cluster\nSIGSTOP',f'{R}/04/cluster/clu_pause_r*.res')]
    groups=[(n,p) for n,p in groups if glob.glob(p)]
    if not groups: return
    fig,axs=plt.subplots(1,2,figsize=(13,4.6))
    x=list(range(len(groups))); w=0.3
    for j,key in enumerate(['recovered_at_s']):
        vals=[med(p,key) for _,p in groups]
        for i,v in enumerate(vals):
            for r,val in enumerate(v):
                capped=min(val,60); col=C[0] if 'Sentinel' in groups[i][0] else C[1]
                b=axs[0].bar(i+(r-0.5)*w,capped,w,color=col,alpha=1 if r==0 else .6)
                axs[0].annotate('복구 안 됨' if val>=59 else f'{val:.1f}s',(i+(r-0.5)*w,capped),ha='center',va='bottom',fontsize=8,xytext=(0,2),textcoords='offset points')
    axs[0].set_title('복구 시점 (s, 장애 후) — 회차별, 60 s = 측정 창 끝까지 미복구'); axs[0].set_ylim(0,70)
    lost=[med(p,'lost_cross_deliveries') for _,p in groups]; late=[med(p,'late_over_1s') for _,p in groups]
    for i in x:
        for r in range(len(lost[i])):
            b1=axs[1].bar(i+(r-0.5)*w,lost[i][r],w,color=C[1],alpha=1 if r==0 else .6); b2=axs[1].bar(i+(r-0.5)*w,late[i][r],w,bottom=lost[i][r],color=C[3],alpha=1 if r==0 else .6)
            axs[1].annotate(f'{lost[i][r]+late[i][r]:,}',(i+(r-0.5)*w,lost[i][r]+late[i][r]),ha='center',va='bottom',fontsize=8,xytext=(0,2),textcoords='offset points')
    axs[1].set_title('다른 서버 전달: 유실(주황) + 1초 넘게 지연(노랑), 건수'); 
    for ax in axs: ax.set_xticks(x); ax.set_xticklabels([g[0] for g in groups],fontsize=9)
    fig.suptitle('4단계 · Sentinel vs Cluster 페일오버 (20명·50 msg/s·75초, 15초에 장애)',x=0.01,ha='left',fontsize=14,fontweight='bold')
    fig.tight_layout(); fig.savefig(f'{OUT}/04-failover-sentinel-vs-cluster.png',dpi=150); plt.close(fig)
    # 타임라인: 각 구성 r1
    fig,axs=plt.subplots(len(groups),1,figsize=(11,1.7*len(groups)+1),sharex=True)
    for i,(n,p) in enumerate(groups):
        f=sorted(glob.glob(p))[0].replace('.res','.json'); ks,cr,_=series(f)
        axs[i].plot(ks,cr,color=C[0] if 'Sentinel' in n else C[1]); axs[i].axvline(0,color='#333',ls='--',lw=1); axs[i].set_ylim(-5,110)
        axs[i].set_ylabel(n.replace('\n',' '),fontsize=8,rotation=0,ha='right',va='center')
    axs[-1].set_xlabel('장애 기준 송신 시각 (s)'); axs[0].set_title('다른 서버 1초 안 전달률 (%) — 회차 1')
    fig.tight_layout(); fig.savefig(f'{OUT}/04-failover-timeline.png',dpi=150); plt.close(fig)

def cost():
    rows={}
    for f in glob.glob(f'{R}/04/cost/*_r*.res'):
        k=os.path.basename(f)[:-4].rsplit('_r',1)[0]; a,c=res(f); pids=open(f.replace('.res','.pids')).read().split('pids=')[1].split()
        redis=sum(c[p]['cpu_avg'] for p in pids if p in c); app=sum(c[p]['cpu_avg'] for p in c if p not in pids)
        rows.setdefault(k,[]).append((redis,app,a['p99_ms']))
    if not rows: return
    keys=[k for k in ['sentinel','cluster'] if k in rows]; names={'sentinel':'Sentinel (redis 3 + sentinel 3)','cluster':'Cluster (마스터 3 + 레플리카 3)'}
    fig,axs=plt.subplots(1,2,figsize=(11,4.2)); x=list(range(len(keys))); w=0.38
    b1=axs[0].bar([i-w/2 for i in x],[statistics.mean(v[0] for v in rows[k]) for k in keys],w,color=C[2],label='Redis 프로세스 6개 합')
    b2=axs[0].bar([i+w/2 for i in x],[statistics.mean(v[1] for v in rows[k]) for k in keys],w,color=C[0],label='채팅 서버 2대 합')
    label(axs[0],b1,'{:.1f}%'); label(axs[0],b2,'{:.1f}%'); axs[0].set_title('CPU 평균 (%) — 20명·50 msg/s'); axs[0].legend(frameon=False)
    b=axs[1].bar(x,[statistics.mean(v[2] for v in rows[k]) for k in keys],0.5,color=C[1]); label(axs[1],b,'{:.0f} ms'); axs[1].set_title('전달 지연 p99 (ms)')
    for ax in axs: ax.set_xticks(x); ax.set_xticklabels([names[k] for k in keys],fontsize=9)
    fig.suptitle('4단계 · 같은 부하에서 구성별 비용 (2회 평균)',x=0.01,ha='left',fontsize=14,fontweight='bold')
    fig.tight_layout(); fig.savefig(f'{OUT}/04-cost.png',dpi=150); plt.close(fig)

which=sys.argv[1] if len(sys.argv)>1 else 'all'
for name,fn in [('01',stage1),('02',stage2),('03',stage3),('04',stage4),('04',cost)]:
    if which in ('all',name):
        try: fn()
        except Exception as e: print(name,'skipped:',repr(e))
print('charts done')
