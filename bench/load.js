// 채팅 부하 + 전달 측정. 사용자를 여러 서버에 번갈아 붙이고 같은 채널에 넣은 뒤,
// 초당 RATE 개 메시지를 보내 각 메시지가 채널의 모든 사용자에게 닿는지 기록한다.
//   --senders S   메시지를 보내는 사용자 수(기본 = 전원). 앞에서부터 S명이 돌아가며 보낸다.
//   --workers K   부하기 자체가 병목이 되지 않도록 사용자를 K개 프로세스에 나눠 붙인다(기본 1).
//                 각 프로세스는 자기 사용자 몫만큼 보내고 받으며, 부모가 결과를 하나로 합친다.
//   --fault-at s --fault-cmd "..."   부하 시작 s초 뒤 장애 명령 실행(부모 프로세스만). --fault2-* 는 두 번째 명령.
// 출력 JSON 의 시각은 모두 t0 기준 상대 ms. loaderCpu 는 부하 구간 동안 부하기 프로세스들의 CPU 사용률 합(%).
const { io } = require('socket.io-client');
const fs = require('fs');
const { execSync, fork } = require('child_process');
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const ports = arg('ports', '3001,3002').split(',').map(Number);
const USERS = +arg('users', 20), RATE = +arg('rate', 50), DUR = +arg('duration', 30), CH = +arg('channel', 1);
const SENDERS = Math.min(USERS, +arg('senders', USERS));
const OUT = arg('out', '/tmp/load.json'), BASE = +arg('base', 1000);
const WORKERS = +arg('workers', 1), SHARD = +arg('shard', -1);
const FAULT_AT = +arg('fault-at', 0), FAULT_CMD = arg('fault-cmd', '');
const FAULT2_AT = +arg('fault2-at', 0), FAULT2_CMD = arg('fault2-cmd', '');
const T0 = +arg('t0', Date.now()); const now = () => Date.now() - T0;
const cpuPct = (a, b, ms) => ((b.user - a.user) + (b.system - a.system)) / 1000 / ms * 100;

// ---- 부모: 자식 K개를 띄우고 결과를 합친다 ----
if (WORKERS > 1 && SHARD < 0) {
  const parts = [], kids = [];
  for (let j = 0; j < WORKERS; j++) {
    const out = `${OUT}.part${j}`; parts.push(out);
    const args = process.argv.slice(2).filter((a, i, arr) => !(arr[i - 1] === '--out' || a === '--out' || arr[i - 1] === '--fault-cmd' || a === '--fault-cmd' || arr[i - 1] === '--fault2-cmd' || a === '--fault2-cmd'));
    kids.push(new Promise(r => fork(__filename, [...args, '--shard', String(j), '--t0', String(T0), '--out', out], { stdio: 'inherit' }).on('exit', r)));
  }
  // 장애 명령은 부모가 실행한다. 자식은 접속·조인에 약 1초 쓰므로 그만큼 늦춘다(자식과 같은 기준).
  let faultT = null, fault2T = null;
  const runFault = (cmd, tag) => { const t = now(); try { console.error(`${tag}:`, execSync(cmd).toString().trim()); } catch (e) { console.error(`${tag} err`, e.message); } return t; };
  const CONNECT_MS = 2500;
  if (FAULT_CMD) setTimeout(() => { faultT = runFault(FAULT_CMD, 'fault'); }, CONNECT_MS + FAULT_AT * 1000);
  if (FAULT2_CMD) setTimeout(() => { fault2T = runFault(FAULT2_CMD, 'fault2'); }, CONNECT_MS + FAULT2_AT * 1000);
  Promise.all(kids).then(() => {
    const merged = { ports, USERS, RATE, DUR, SENDERS, WORKERS, start: null, faultT, fault2T, users: [], sent: [], recv: [], loaderCpu: 0, loaderCpuParts: [] };
    for (const p of parts) {
      const d = JSON.parse(fs.readFileSync(p)); fs.unlinkSync(p);
      merged.start = merged.start === null ? d.start : Math.min(merged.start, d.start);
      merged.users.push(...d.users);
      for (const x of d.sent) merged.sent.push(x);   // 수십만 건이라 spread 는 스택을 넘긴다
      for (const x of d.recv) merged.recv.push(x);
      merged.loaderCpu += d.loaderCpu; merged.loaderCpuParts.push(d.loaderCpu);
    }
    merged.users.sort((a, b) => a.i - b.i);
    fs.writeFileSync(OUT, JSON.stringify(merged));
    console.error('done', merged.sent.length, 'sent', merged.recv.length, 'recv', 'loaderCpu', merged.loaderCpu.toFixed(0) + '%');
    process.exit(0);
  });
  return;
}

// ---- 단일 프로세스 또는 자식 하나 ----
const K = Math.max(1, WORKERS), J = Math.max(0, SHARD);
const per = Math.ceil(USERS / K), lo = J * per, hi = Math.min(USERS, lo + per);
const users = []; const sent = new Map(); const recv = [];
let faultT = null, fault2T = null;
function connect(i) {
  return new Promise(res => {
    const port = ports[i % ports.length], userId = BASE + i;
    const s = io(`http://127.0.0.1:${port}/chat`, { query: { userId }, transports: ['websocket'], reconnection: true });
    const u = { i, userId, port, s, joined: false };
    s.on('message', m => { try { const c = JSON.parse(m.content); recv.push([c.id, i, now()]); } catch (e) {} });
    s.on('channelJoined', () => { u.joined = true; res(u); });
    s.on('connect', () => s.emit('joinChannel', { userId, channelId: CH }));
    users.push(u);
  });
}
(async () => {
  const joinAll = Promise.all(Array.from({ length: hi - lo }, (_, k) => connect(lo + k)));
  await Promise.race([joinAll, new Promise((_, rej) => setTimeout(() => rej(new Error('join timeout 30s')), 30000))])
    .catch(e => { console.error(e.message); process.exit(2); });
  console.error(`joined ${hi - lo} users (${lo}..${hi - 1}) on ports ${ports}`);
  await new Promise(r => setTimeout(r, 1000));
  const mySenders = users.filter(u => u.i < SENDERS);
  const myRate = RATE * mySenders.length / SENDERS;      // 이 프로세스가 보낼 초당 개수
  const idBase = J * 10_000_000;
  let id = 0, si = 0, acc = 0; const start = now(); let last = Date.now();
  const cpu0 = process.cpuUsage(); let cpu1 = null, cpuEnd = null;
  const runFault = (cmd, tag) => { const t = now(); try { console.error(`${tag}:`, execSync(cmd).toString().trim()); } catch (e) { console.error(`${tag} err`, e.message); } return t; };
  if (SHARD < 0) {
    if (FAULT_CMD) setTimeout(() => { faultT = runFault(FAULT_CMD, 'fault'); }, FAULT_AT * 1000);
    if (FAULT2_CMD) setTimeout(() => { fault2T = runFault(FAULT2_CMD, 'fault2'); }, FAULT2_AT * 1000);
  }
  // 타이머 흔들림과 무관하게 평균 속도를 지키도록 누적기로 보낸다(틱 5ms).
  const timer = setInterval(() => {
    const t = Date.now(); acc += myRate * (t - last) / 1000; last = t;
    while (acc >= 1 && mySenders.length) {
      acc -= 1;
      const u = mySenders[si++ % mySenders.length];
      const m = { id: idBase + (++id), from: u.i, t: now() };
      sent.set(m.id, { at: m.t, from: u.i, port: u.port });
      u.s.emit('sendMessage', { type: 'text', content: JSON.stringify(m), userId: u.userId, channelId: CH });
    }
    if (now() - start > DUR * 1000) { clearInterval(timer); cpu1 = process.cpuUsage(); cpuEnd = now(); }
  }, 5);
  await new Promise(r => setTimeout(r, DUR * 1000 + 8000));
  const meta = users.map(u => ({ i: u.i, port: u.port }));
  const loaderCpu = cpuPct(cpu0, cpu1 || process.cpuUsage(), (cpuEnd || now()) - start);
  fs.writeFileSync(OUT, JSON.stringify({ ports, USERS, RATE, DUR, SENDERS, WORKERS: K, start, faultT, fault2T, users: meta, sent: [...sent], recv, loaderCpu }));
  users.forEach(u => u.s.close());
  console.error('done', sent.size, 'sent', recv.length, 'recv', 'loaderCpu', loaderCpu.toFixed(0) + '%');
  process.exit(0);
})();
