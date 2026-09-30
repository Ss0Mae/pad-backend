#!/bin/bash
# Redis Primary 1(6380) + Replica 2(6381,6382) + Sentinel 3(26380~26382), down-after 5s, quorum 2
D=/tmp/rs; for p in 6380 6381 6382 26380 26381 26382; do redis-cli -p $p shutdown nosave >/dev/null 2>&1; done; sleep 1; rm -rf $D; mkdir -p $D
for p in 6380 6381 6382; do
  mkdir -p $D/$p
  extra=""; [ $p != 6380 ] && extra="--replicaof 127.0.0.1 6380"
  redis-server --port $p --bind 127.0.0.1 --dir $D/$p --save "" --appendonly no --daemonize yes --logfile $D/$p.log $extra
done
sleep 1
for s in 26380 26381 26382; do
cat > $D/s$s.conf <<C
port $s
bind 127.0.0.1
daemonize yes
logfile $D/s$s.log
dir $D
sentinel monitor pad-master 127.0.0.1 6380 2
sentinel down-after-milliseconds pad-master 5000
sentinel failover-timeout pad-master 10000
sentinel parallel-syncs pad-master 1
C
redis-server $D/s$s.conf --sentinel
done
sleep 2; redis-cli -p 26380 sentinel get-master-addr-by-name pad-master; redis-cli -p 6380 info replication | grep connected_slaves
