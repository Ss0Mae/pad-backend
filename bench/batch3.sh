#!/bin/bash
cd "$(dirname "$0")/.."
for r in e f g h i j; do bash bench/run.sh K_fd_$r kill REDIS_FAILOVER_DETECTOR=true; done
for r in a b c; do bash bench/run.sh K_def_$r kill; done
echo BATCH_DONE
