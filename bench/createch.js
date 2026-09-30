// 서로 다른 서버에 붙은 두 사용자 사이에 1:1 채팅방을 N번 만들고, 상대방이 channelAdded 를 받는지 센다.
const { io } = require('socket.io-client');
const [pa, pb, N] = [3001, 3002, +(process.argv[2] || 20)];
let bGot = 0, aCreated = 0, aErr = 0;
const A = io(`http://127.0.0.1:${pa}/chat`, { query: { userId: 1 }, transports: ['websocket'] });
const B = io(`http://127.0.0.1:${pb}/chat`, { query: { userId: 2 }, transports: ['websocket'] });
B.on('channelAdded', () => bGot++);
A.on('channelCreated', () => aCreated++);
A.on('exception', () => aErr++);
setTimeout(async () => {
  for (let k = 0; k < N; k++) { A.emit('createChannel', { userId1: 1, userId2: 2 }); await new Promise(r => setTimeout(r, 100)); }
  setTimeout(() => { console.log(JSON.stringify({ tries: N, receiver_got_channelAdded: bGot, creator_got_channelCreated: aCreated, creator_got_exception: aErr })); process.exit(0); }, 2000);
}, 1500);
