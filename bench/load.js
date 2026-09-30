// 채팅 부하 + 전달 측정. 사용자를 여러 서버에 번갈아 붙이고 같은 채널에 넣은 뒤,
// 초당 RATE 개 메시지를 보내 각 메시지가 채널의 모든 사용자에게 닿는지 기록한다.
const { io } = require('socket.io-client');
const fs = require('fs');
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const ports = arg('ports', '3001,3002').split(',').map(Number);
const USERS = +arg('users', 20), RATE = +arg('rate', 50), DUR = +arg('duration', 30), CH = +arg('channel', 1);
const OUT = arg('out', '/tmp/load.json'), BASE = +arg('base', 1000);
const FAULT_AT = +arg('fault-at', 0), FAULT_CMD = arg('fault-cmd', ''); let faultT = null;
const { execSync } = require('child_process');
const t0 = Date.now(); const now = () => Date.now() - t0;
const users = []; const sent = new Map(); const recv = [];
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
  await Promise.all(Array.from({ length: USERS }, (_, i) => connect(i)));
  console.error(`joined ${USERS} users on ports ${ports}`);
  await new Promise(r => setTimeout(r, 1000));
  let id = 0; const start = now();
  if (FAULT_CMD) setTimeout(() => { faultT = now(); try { console.error('fault:', execSync(FAULT_CMD).toString().trim()); } catch (e) { console.error('fault err', e.message); } }, FAULT_AT * 1000);
  const timer = setInterval(() => {
    const u = users[id % USERS];
    const m = { id: ++id, from: u.i, t: now() };
    sent.set(m.id, { at: m.t, from: u.i, port: u.port });
    u.s.emit('sendMessage', { type: 'text', content: JSON.stringify(m), userId: u.userId, channelId: CH });
    if (now() - start > DUR * 1000) clearInterval(timer);
  }, 1000 / RATE);
  await new Promise(r => setTimeout(r, DUR * 1000 + 8000));
  const meta = users.map(u => ({ i: u.i, port: u.port }));
  fs.writeFileSync(OUT, JSON.stringify({ ports, USERS, RATE, DUR, start, faultT, users: meta, sent: [...sent], recv }));
  users.forEach(u => u.s.close());
  console.error('done', sent.size, 'sent', recv.length, 'recv');
  process.exit(0);
})();
