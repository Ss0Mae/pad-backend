#!/bin/bash
cd "$(dirname "$0")/.."
for r in 2 3; do
  bash bench/run.sh S1_kill_r$r kill
  bash bench/run.sh S2_pause_r$r pause
  bash bench/run.sh S3_pause_fd_r$r pause REDIS_FAILOVER_DETECTOR=true
  bash bench/run.sh S4_kill_fd_r$r kill REDIS_FAILOVER_DETECTOR=true
done
bash bench/run.sh S4_kill_fd kill REDIS_FAILOVER_DETECTOR=true
echo BATCH_DONE
