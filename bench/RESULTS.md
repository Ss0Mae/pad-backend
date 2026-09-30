# PAD 채팅 서버 확장 · Redis Sentinel 실험 결과 (2026-09-30)

## 환경
- 로컬 1대에서 PAD 채팅 서버 2대(3001, 3002) + Redis 7.0 Primary 1 + Replica 2 + Sentinel 3(down-after 5 s, quorum 2).
- 게이트웨이(`src/chat/chat.gateway.ts`), Socket.IO, `@socket.io/redis-adapter`, ioredis 는 PAD 코드 그대로.
- **DB 계층만 대역**(`bench/fake-chat.service.ts`): 이 환경에서 Prisma 엔진을 받을 수 없어 ChatService 를 최소 구현으로 바꿨다. 서버 간에 공유돼야 하는 `online_users` 만 실제 MariaDB 테이블을 쓴다.
- 부하(`bench/load.js`): 사용자 20명을 두 서버에 번갈아 붙여 채널 1에 넣고 초당 50개 메시지(75초). 메시지마다 모든 사용자의 수신 시각을 기록.
- 장애(`bench/run.sh`): 부하 15초 뒤 Primary 에 SIGKILL(강제 종료) 또는 SIGSTOP(프로세스 정지).
- 복구 시점 = 장애 이후 "그 뒤로 보낸 모든 메시지가 다른 서버 사용자에게 1초 안에 닿기 시작한" 송신 시각.

## 1. 서버 2대 (Redis 어댑터 없음 → 있음)
| | 어댑터 없음 | Redis 어댑터 |
|---|---:|---:|
| 같은 서버 사용자 전달률 | 100% | 100% |
| 다른 서버 사용자 전달률 | **0%** | **100%** |
| 전달 지연 p99 | 4 ms | 6 ms |
| 1:1 채팅방 생성(상대가 다른 서버) | 0/20 (20건 모두 `TypeError: Cannot read properties of undefined (reading 'emit')`) | 20/20 |

## 2. Sentinel 페일오버 (중앙값)
| 장애 | ioredis 설정 | 회수 | 복구 시점 | 다른 서버로 못 간 전달 | 1초 넘게 늦은 전달 |
|---|---|---:|---:|---:|---:|
| SIGKILL | 기본 | 6 | 6.9 s | 1,710 | 1,473 |
| SIGSTOP | 기본 | 3 | **복구 안 됨(60 s 측정 창 끝까지)** | 29,660 | 0 |
| SIGSTOP | `failoverDetector: true` | 5 | **8.9 s** | 2,210 | 2,017 |
| SIGKILL | `failoverDetector: true` | 13 | 7.2 s | 1,710 | 1,470 |

- SIGSTOP 기본: Sentinel 은 약 6 s 에 새 Primary 로 전환(+switch-master)했지만 앱의 pub/sub 연결은 끊기지 않아 옛 Primary 에 남았다. ioredis Sentinel 연결은 기본값(`failoverDetector: false`)에서 +switch-master 를 구독하지 않는다.
- `failoverDetector: true` 는 Sentinel 의 +switch-master 를 구독해 승격 즉시 재연결한다.
- 장애 구간 메시지는 일부 유실, 일부는 ioredis 오프라인 큐에 쌓였다가 재연결 뒤 최대 약 9 s 늦게 도착했다.
- 같은 서버 사용자끼리는 모든 장애 중에도 100% 전달(로컬 브로드캐스트는 Redis 를 거치지 않음).
- SIGKILL + failoverDetector 13회 중 1회는 60 s 동안 복구되지 않았다. 당시 로그를 남기지 못했고 이후 10회에서 재현되지 않아 원인 미확인.

## Cluster 를 쓰지 않은 이유
채팅 이벤트 중계는 쓰기량이 적고 데이터가 Primary 한 대 메모리로 충분하다. Cluster 에서 일반 PUBLISH 는 모든 노드로 퍼지므로 샤딩 이점을 보려면 sharded pub/sub(Redis 7, `createShardedAdapter`)로 바꿔야 한다. 현재 규모에서는 Sentinel 로 가용성만 확보했다.
