#!/bin/bash
V=/workspace
mkdir -p "$V/swarm/Models" "$V/swarm/Output" "$V/swarm/Data"

cd /opt/SwarmUI
for d in Models Output Data; do
  rm -rf "$d"
  ln -s "$V/swarm/$d" "$d"
done

exec ./launch-linux.sh --launch_mode none --host 0.0.0.0
