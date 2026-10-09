#!/bin/bash
V=/workspace
mkdir -p "$V/swarm/Models" "$V/swarm/Output" "$V/swarm/Data"

cd /opt/SwarmUI
for d in Models Output Data; do
  rm -rf "$d"
  ln -s "$V/swarm/$d" "$d"
done

# Password for Jupyter comes from the template's JUPYTER_PASSWORD variable
if [ -n "$JUPYTER_PASSWORD" ]; then
  export JUPYTER_TOKEN="$JUPYTER_PASSWORD"
fi
   jupyter lab --port=8888 --ip=* --allow-root --no-browser \
     --ServerApp.allow_origin=* --ServerApp.root_dir=/workspace &

exec ./launch-linux.sh --launch_mode none --host 0.0.0.0
