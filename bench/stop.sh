#!/bin/bash
for f in /tmp/app-*.pid; do [ -f $f ] && kill $(cat $f) 2>/dev/null; rm -f $f; done; sleep 1
