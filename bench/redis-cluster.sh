#!/bin/bash
# Redis Cluster: 마스터 3 + 레플리카 3 (7000~7005), cluster-node-timeout 5000.
# usage: redis-cluster.sh [stop]
D=/tmp/rc; PORTS="7000 7001 7002 7003 7004 7005"
for p in $PORTS; do redis-cli -p $p shutdown nosave >/dev/null 2>&1; done; sleep 1
[ "$1" = stop ] && exit 0
rm -rf $D; mkdir -p $D
for p in $PORTS; do
  mkdir -p $D/$p
  redis-server --port $p --bind 127.0.0.1 --dir $D/$p --save "" --appendonly no --daemonize yes --logfile $D/$p.log \
    --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
done
sleep 1
redis-cli --cluster create $(for p in $PORTS; do echo -n "127.0.0.1:$p "; done) --cluster-replicas 1 --cluster-yes > $D/create.log 2>&1
# 슬롯 배분과 레플리카 동기화가 끝날 때까지 기다린다
for i in $(seq 1 30); do
  redis-cli -p 7000 cluster info | grep -q "cluster_state:ok" && break; sleep 1
done
redis-cli -p 7000 cluster info | grep -E "cluster_state|cluster_known_nodes|cluster_size"
redis-cli -p 7000 cluster nodes
