#!/bin/bash
cd "$(dirname "$0")/.."
for r in a b c d; do bash bench/run.sh K_fd_$r kill REDIS_FAILOVER_DETECTOR=true; done
echo BATCH_DONE
