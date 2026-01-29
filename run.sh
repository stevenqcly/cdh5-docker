#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/stevenqcly/cloudera-cdh5:cdh5-v2"
NAME="cdh5"

echo "[1/4] Pulling image: $IMAGE"
docker pull --platform linux/amd64 "$IMAGE"

echo "[2/4] Removing existing container (if any): $NAME"
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "[3/4] Starting container: $NAME"
docker run -d \
  --name "$NAME" \
  --platform linux/amd64 \
  --privileged \
  --tmpfs /run --tmpfs /tmp \
  -p 8888:8888 \
  -p 8088:8088 \
  -p 50070:50070 \
  -p 11000:11000 \
  -p 18080:18080 \
  -p 60010:60010 \
  -p 60030:60030 \
  -p 2181:2181 \
  -p 10000:10000 \
  -p 10002:10002 \
  "$IMAGE" >/dev/null

echo "[4/4] Done."
echo "Open:"
echo "  Hue:   http://localhost:8888"
echo "  YARN:  http://localhost:8088"
echo "  HDFS:  http://localhost:50070"
echo "  Oozie: http://localhost:11000"
echo "  Spark: http://localhost:18080"
echo
echo "Logs: docker logs -f $NAME"
