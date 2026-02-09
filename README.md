# CDH5 Docker (Apple Silicon Compatible)

This repository provides a **prebuilt Cloudera CDH5 training environment** packaged as a Docker image.  
It is compatible with **Apple Silicon (M1 / M2 / M3)** via amd64 emulation and replaces the original
Cloudera QuickStart VM.

The Docker image is published via **GitHub Container Registry (GHCR)**.

---

## What this is
- Runs via Docker using **linux/amd64 emulation**

## Prerequisites
- macOS (Apple Silicon recommended)
- Docker Desktop installed and running

**Ensure you have **~30 GB of free disk space**.

---

## Copying + Starting the Container

```bash
docker pull --platform linux/amd64 ghcr.io/stevenqcly/cloudera-cdh5:cdh5-v3 && \
docker run -d \
  --name cdh5-v3 \
  --platform linux/amd64 \
  --add-host localhost.localdomain:127.0.0.1 \
  --privileged \
  --tmpfs /run --tmpfs /tmp \
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
  ghcr.io/stevenqcly/cloudera-cdh5:cdh5-v3
```

---

## Web Interfaces

Once running, access services at:

- **Hue**: http://localhost:8888
- **YARN ResourceManager**: http://localhost:8088
- **HDFS NameNode**: http://localhost:50070
- **Oozie**: http://localhost:11000
- **Spark History Server**: http://localhost:18080

---

## Container management

Stop the container (Please ensure to run this in the container terminal upon every shutdown to prevent namenode/datanode corruption):
```bash
service impala-server stop
service impala-catalog stop
service impala-state-store stop

service oozie stop
service hue stop

service hadoop-yarn-resourcemanager stop
service hadoop-yarn-nodemanager stop

service hadoop-hdfs-datanode stop
service hadoop-hdfs-namenode stop
```

---

## Disclaimer

This environment is intended for **educational and training use only**.
