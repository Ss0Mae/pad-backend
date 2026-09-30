#!/bin/bash
# usage: start.sh <port> [env...]
cd "$(dirname "$0")/.."
PORT=$1; shift
env PORT=$PORT "$@" TS_NODE_TRANSPILE_ONLY=1 node -r ts-node/register -r tsconfig-paths/register bench/main.ts > /tmp/app-$PORT.log 2>&1 &
echo $! > /tmp/app-$PORT.pid
