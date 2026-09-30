#!/bin/bash
# EC2 벤치 오케스트레이션 공통부. 로컬(맥)에서 실행하며 앱 박스(서버·Redis·MySQL)와 부하기 박스(load.js)를 ssh 로 부린다.
#   앱 박스   t3.small  ubuntu@$APP_PUB  (~/pad-backend)     사설 $APP_IP
#   부하기    t3.medium ubuntu@$LOAD_PUB (~/pad-load/bench)
# 장애 명령은 앱 박스에서 실행하고 그 순간의 epoch ms 를 받아 부하기 JSON 의 faultT(t0 기준 상대 ms)로 기록한다.
# 두 박스 모두 Amazon Time Sync 를 쓰므로 시계 차이는 ms 단위다.
KEY=${KEY:-$HOME/.ssh/fillmap-key-soma.pem}; APP_PUB=${APP_PUB:-43.201.149.45}; LOAD_PUB=${LOAD_PUB:-54.180.140.228}; APP_IP=${APP_IP:-10.0.1.106}
SSHOPT=(-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i "$KEY")
REPO="${REPO:-$( [ -n "${BASH_SOURCE[0]}" ] && cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd || git rev-parse --show-toplevel )}"
app()   { ssh "${SSHOPT[@]}" ubuntu@$APP_PUB  "cd ~/pad-backend && export MYSQL_PWD=root && $*"; }
loadb() { ssh "${SSHOPT[@]}" ubuntu@$LOAD_PUB "cd ~/pad-load && $*"; }
epoch_ms() { date +%s%3N 2>/dev/null | grep -q N && python3 -c 'import time;print(int(time.time()*1000))' || date +%s%3N; }

sync_boxes() {
  rsync -az -e "ssh ${SSHOPT[*]}" "$REPO/bench/" --exclude results --exclude charts --exclude reports ubuntu@$APP_PUB:~/pad-backend/bench/
  rsync -az -e "ssh ${SSHOPT[*]}" "$REPO/src/modules/redis/redis-client.factory.ts" ubuntu@$APP_PUB:~/pad-backend/src/modules/redis/
  rsync -az -e "ssh ${SSHOPT[*]}" "$REPO"/bench/{load.js,analyze.py,cpustat.py,createch.js} ubuntu@$LOAD_PUB:~/pad-load/bench/
  app "chmod +x bench/*.sh"
}
# start_servers "<ports>" [env...]  — 앱 박스에서 서버를 띄우고 기동 줄을 기다린다
start_servers() { local ports=$1; shift; app "bench/stop.sh; mysql -h127.0.0.1 -uroot pad -e 'DELETE FROM online_users'; for p in $ports; do bench/start.sh \$p $*; done; bench/wait-up.sh $ports"; }
app_pid() { app "cat /tmp/app-$1.pid"; }
redis_pid() { app "redis-cli -p $1 info server | grep process_id | cut -d: -f2 | tr -d '\r'"; }
# sampler <stage> <name> <pid...>
#   pkill 패턴의 대괄호는 ssh 원격 셸 자신의 명령줄과 매치돼 스스로를 죽이는 일을 막는다.
sampler() { local st=$1 nm=$2; shift 2; app "pkill -f '[p]ython3 - bench/results' >/dev/null 2>&1; mkdir -p bench/results/$st; nohup bench/cpusample.sh bench/results/$st/$nm.cpu $* >/dev/null 2>&1 &"; }
sampler_stop() { app "pkill -f '[p]ython3 - bench/results' >/dev/null 2>&1; true"; }
# run_load <stage> <name> <load.js args...>   — 부하기 박스에서 실행, results/<stage>/<name>.{json,log,res}
run_load() { local st=$1 nm=$2; shift 2; loadb "mkdir -p results/$st && node bench/load.js --host $APP_IP $* --out results/$st/$nm.json 2> results/$st/$nm.log; python3 bench/analyze.py results/$st/$nm.json | tee results/$st/$nm.res"; }
# run_load_fault <stage> <name> <fault_at_s> "<app cmd>" <fault2_at_s|0> "<app cmd2|''>" <load.js args...>
#   부하 시작(접속 약 2초 뒤) 기준 fault_at 초에 앱 박스에서 명령을 실행하고 epoch 를 받아 JSON 에 faultT 로 넣는다.
run_load_fault() {
  local st=$1 nm=$2 f1=$3 c1=$4 f2=$5 c2=$6; shift 6
  loadb "mkdir -p results/$st && node bench/load.js --host $APP_IP $* --out results/$st/$nm.json 2> results/$st/$nm.log" & local LP=$!
  local t_launch=$(date +%s)
  sleep $((2 + f1)); local E1=$(app "echo EP=\$(date +%s%3N); $c1" | tee /tmp/fault-$nm.out | grep '^EP=' | cut -d= -f2)
  local E2=""
  if [ "$f2" != 0 ] && [ -n "$c2" ]; then sleep $((t_launch + 2 + f2 - $(date +%s))); E2=$(app "echo EP=\$(date +%s%3N); $c2" | tee -a /tmp/fault-$nm.out | grep '^EP=' | cut -d= -f2); fi
  wait $LP
  loadb "python3 - <<EOF
import json; f='results/$st/$nm.json'; d=json.load(open(f)); d['faultT']=${E1:-0}-d['t0']; d['fault2T']=${E2:-0}-d['t0'] if ${E2:-0} else None; d['faultEpoch']=${E1:-0}; d['fault2Epoch']=${E2:-0} or None
json.dump(d,open(f,'w'))
EOF
python3 bench/analyze.py results/$st/$nm.json | tee results/$st/$nm.res; cat /tmp/fault-$nm.out >> results/$st/$nm.log" ; cat /tmp/fault-$nm.out
}
# fetch <stage> — 두 박스의 results/<stage> 를 로컬 bench/results/<stage> 로 모으고 CPU 통계를 .res 에 붙인다
fetch() {
  mkdir -p "$REPO/bench/results/$1"
  rsync -az -e "ssh ${SSHOPT[*]}" ubuntu@$APP_PUB:~/pad-backend/bench/results/$1/ "$REPO/bench/results/$1/" 2>/dev/null
  rsync -az -e "ssh ${SSHOPT[*]}" ubuntu@$LOAD_PUB:~/pad-load/results/$1/ "$REPO/bench/results/$1/"   # 부하기 쪽 .res 가 최종
  python3 "$REPO/bench/finalize.py" "$REPO/bench/results/$1"
}
