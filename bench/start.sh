#!/bin/bash
# usage: start.sh <port> [env...]   NODE_FLAGS=... 를 env 로 주면 node 실행 플래그로 붙는다(예: --unhandled-rejections=warn).
cd "$(dirname "$0")/.."
PORT=$1; shift
env PORT=$PORT "$@" TS_NODE_TRANSPILE_ONLY=1 sh -c 'exec node $NODE_FLAGS -r ts-node/register -r tsconfig-paths/register bench/main.ts' > /tmp/app-$PORT.log 2>&1 &
echo $! > /tmp/app-$PORT.pid
