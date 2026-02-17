#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="cdh5-v3"
IMAGE="ghcr.io/stevenqcly/cloudera-cdh5:cdh5-v3"

echo "=================================================="
echo "[cdh5-docker] Pulling image for linux/amd64..."
echo "Image: $IMAGE"
echo "=================================================="

docker pull --platform linux/amd64 "$IMAGE"

# If a container with this name exists, remove it to avoid name conflicts
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "=================================================="
  echo "[cdh5-docker] Existing container '$CONTAINER_NAME' found."
  echo "[cdh5-docker] Stopping/removing old container..."
  echo "=================================================="
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

echo "=================================================="
echo "[cdh5-docker] Starting container '$CONTAINER_NAME'..."
echo "=================================================="

docker run -d \
  --name "$CONTAINER_NAME" \
  --platform linux/amd64 \
  --add-host localhost.localdomain:127.0.0.1 \
  --privileged \
  --tmpfs /run \
  --tmpfs /tmp \
  -p 8888:8888 \
  -p 8088:8088 \
  -p 8042:8042 \
  -p 50070:50070 \
  -p 11000:11000 \
  -p 19888:19888 \
  -p 18080:18080 \
  -p 60010:60010 \
  -p 60030:60030 \
  -p 2181:2181 \
  -p 10000:10000 \
  -p 10002:10002 \
  "$IMAGE"

echo "=================================================="
echo "[cdh5-docker] ✅ Container started!"
echo
echo "Useful UIs (open in your browser):"
echo "  Hue (if running):          http://localhost:8888"
echo "  YARN ResourceManager:      http://localhost:8088"
echo "  NodeManager:               http://localhost:8042"
echo "  HDFS NameNode:             http://localhost:50070"
echo "  Oozie:                     http://localhost:11000"
echo "  Spark History Server:      http://localhost:18080"
echo "  MapReduce JobHistory:      http://localhost:19888"
echo "  HBase Master:              http://localhost:60010"
echo "  HBase RegionServer:        http://localhost:60030"
echo
echo "To check logs:"
echo "  docker logs -f $CONTAINER_NAME"
echo
echo "To enter the container:"
echo "  docker exec -it $CONTAINER_NAME bash"
echo "=================================================="
