# PAD 채팅 서버 확장 — 4단계 실측으로 잇는 이야기

2026-09-30, EC2 t3.small(dev 와 같은 사양, 채팅 서버·Redis·MySQL 동거) + 부하기 t3.medium 사설망. 절대값은 이 기계의 값이고, 읽을 것은 **구조 사이의 차이**다. 각 단계의 조건·표·그래프·한계는 링크한 보고서에 있다. 처음 로컬 맥북에서 잰 Sentinel 결과([RESULTS.md](RESULTS.md), [01-local-macbook.md](reports/01-local-macbook.md))는 대조용으로 남겼다.

## 1. 서버 1대는 어디서 끝나는가 → [01-single-server-limit.md](reports/01-single-server-limit.md)

채널 하나에 N 명이 초당 R 개를 보내면 서버는 초당 N×R 건을 전달한다. t3.small 의 Node 프로세스 1개는 **팬아웃 3만 전달/초까지 초별 p99 10 ms 안팎**(CPU 56~66%)이었고, **4만에서 CPU 90%·p99 수백 ms**, 10만에서 전달률 85.8% 로 떨어졌다. 채팅 서버는 이벤트 루프 하나라 CPU 한 코어에서 끝난다. 더 받으려면 프로세스를 늘려야 한다.

같은 코드가 맥북(M5)에서는 25만 전달/초에서야 포화했다 — 기계가 다르면 숫자가 3~5배 다르지만 "한 코어에서 끝난다"는 구조는 같다.

## 2. 2대로 늘리면 서로 안 보인다 → [02-two-servers-adapter.md](reports/02-two-servers-adapter.md)

서버를 3001·3002 두 프로세스로 나누고 사용자 100명을 반씩 붙였다. 어댑터 없이는 **다른 서버 사용자에게 0%**(15만 건 전부 유실), 같은 서버끼리는 100% 라 한 서버에서만 시험하면 모른다. 1:1 채팅방 생성은 옛 코드에서 `undefined.emit` 예외 20/20, 고친 현재 코드에서도 상대에게 조용히 안 감 0/20.

## 3. Redis 어댑터 → 같은 보고서

`@socket.io/redis-adapter` 를 붙이면 다른 서버 전달 **100%**, 채팅방 생성 20/20. 값은 p50 2 → 3 ms, 초별 p99 4 → 5~7 ms, Redis CPU 1~2%. 이제 Redis 가 서버 사이의 유일한 통로다.

## 4. 그 Redis 가 단일 장애점 → [03-redis-spof.md](reports/03-redis-spof.md)

Redis 1대를 `kill -9` 하면 다른 서버 전달이 **즉시 0** 이 되고, **10.5초 뒤 서버 프로세스 2개가 모두 죽는다** — ioredis 가 20번 재시도한 뒤 큐를 `MaxRetriesPerRequestError` 로 비우는데 어댑터가 publish 의 promise 를 받지 않아 미처리 거부로 Node 가 종료된다. 30초 뒤 Redis 를 살려도 살릴 서버가 없다. 프로세스만 살려 두면(진단용 `--unhandled-rejections=warn`) Redis 가 돌아온 뒤 0.5~1.1초에 복구된다. 결론 둘: Redis 를 1대만 두면 채팅 전체의 단일 장애점이고, 어떤 페일오버든 **10.5초 안에** 끝나야 한다.

## 5. Sentinel vs Cluster → [04-sentinel-vs-cluster.md](reports/04-sentinel-vs-cluster.md)

| | Sentinel | Cluster |
|---|---|---|
| Primary/마스터 SIGKILL | **6~7초** 복구, 유실 1,200~1,760건 | **영향 없음**(구독이 즉시 다른 노드로) |
| SIGSTOP(프로세스 멈춤) | 기본은 복구 안 됨 → `failoverDetector: true` 로 **7.5초**, 유실 0 | **복구 안 됨**, 대응 스위치 없음 |
| Redis 6개 CPU 합 (같은 부하) | 2.7% | 3.4% |
| 초별 p99 중앙값 | 4 ms | 7~10 ms |
| PUBLISH 경로 | Primary 1대 → 복제 | 무작위 마스터 → 클러스터 버스로 전 노드 |

## 6. Sentinel 채택

**Sentinel + `failoverDetector: true`.** 이 서비스의 Redis 는 pub/sub 중계라 샤딩할 데이터가 없고, 일반 pub/sub 은 Cluster 에서도 모든 노드로 퍼진다. 실측한 두 장애 유형을 옵션 하나로 다 넘기는 쪽이 Sentinel 이고, 코드 경로가 단일 노드와 같다.

**트레이드오프**: SIGKILL 에 6~7초 공백과 메시지 유실이 남는다(Cluster 는 없다). `down-after-milliseconds` 를 낮추면 줄지만 오탐과 맞바꾼다. 3단계의 10.5초 한계는 어느 쪽이든 앱에서 막아야 한다(`maxRetriesPerRequest` 조정 또는 publish 오류 처리 — 코드 변경이라 이번 범위 밖).

**다시 볼 조건**: Redis 데이터가 한 대 메모리를 넘거나, Primary 한 대의 PUBLISH·복제 대역폭이 병목이 되거나, node-redis 로 옮겨 sharded pub/sub 을 쓸 수 있게 되면 Cluster 를 다시 잰다.

## 실측하지 않은 것

- 1단계 500×500 셀(부하기 프로세스 사망), 팬아웃 5만 이상은 부하기 한계 표기.
- 1단계 순간 정체(30초 중 2~3초, 전체 p99 를 수백 ms 로 끌어올림)의 원인.
- Cluster 의 `commandTimeout` 조합, sharded pub/sub(`createShardedAdapter`, node-redis 필요), 무릎 부하에서의 Redis 비용.
- 모든 단계가 회차 1~2회다.

## 재현

`bench/remote/stage{1,2,3,4-sentinel,4-cluster,4-cost}.sh` — 로컬에서 앱 박스·부하기 박스를 ssh 로 부린다(`bench/remote/lib.sh` 의 주소). 로컬 한 대에서 돌리는 구판은 `bench/stage*.sh`·`bench/run.sh`. 그래프는 `bench/charts.py`, 표는 `bench/table.py <results dir>`.
