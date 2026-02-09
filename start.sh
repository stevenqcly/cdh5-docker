#!/usr/bin/env bash
set -euo pipefail

echo "[start] Bringing up CDH5/Cloudera services (best-effort)..."

# Some CentOS6 init scripts assume these exist
mkdir -p /var/run /run /tmp /logs
chmod 1777 /tmp || true

# Ensure loopback up (sometimes helps old scripts)
if command -v ifconfig >/dev/null 2>&1; then
  ifconfig lo up || true
fi

# ------------------------------------------------------------------------------
# Spark tempdir + local dirs (container-safe)
# ------------------------------------------------------------------------------
mkdir -p /var/tmp/java /var/tmp/spark || true
chmod 1777 /var/tmp/java /var/tmp/spark || true

cat >/etc/profile.d/spark_cdh5_docker.sh <<'EOF'
export SPARK_CONF_DIR=/etc/spark/conf
export _JAVA_OPTIONS="-Djava.io.tmpdir=/var/tmp/java"
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=/var/tmp/java"
export SPARK_LOCAL_DIRS="/var/tmp/spark"
EOF
chmod 644 /etc/profile.d/spark_cdh5_docker.sh || true

export SPARK_CONF_DIR=/etc/spark/conf
export _JAVA_OPTIONS="-Djava.io.tmpdir=/var/tmp/java"
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=/var/tmp/java"
export SPARK_LOCAL_DIRS="/var/tmp/spark"

# Ensure Spark defaults include driver tmpdir + local dirs (+ optional codec)
SPARK_DEFAULTS="/etc/spark/conf/spark-defaults.conf"
touch "$SPARK_DEFAULTS" || true

grep -q '^spark\.driver\.extraJavaOptions' "$SPARK_DEFAULTS" 2>/dev/null || \
  echo "spark.driver.extraJavaOptions -Djava.io.tmpdir=/var/tmp/java" >> "$SPARK_DEFAULTS"

grep -q '^spark\.local\.dir' "$SPARK_DEFAULTS" 2>/dev/null || \
  echo "spark.local.dir /var/tmp/spark" >> "$SPARK_DEFAULTS"

# Optional: avoid snappy JNI issues in old CDH containers
grep -q '^spark\.io\.compression\.codec' "$SPARK_DEFAULTS" 2>/dev/null || \
  echo "spark.io.compression.codec lzf" >> "$SPARK_DEFAULTS"

# ---------- Environment ----------
export JAVA_HOME="${JAVA_HOME:-/usr/java/jdk1.7.0_67}"
export HADOOP_HOME="${HADOOP_HOME:-/usr/lib/hadoop}"

# Your RM logs show it reads conf.pseudo
export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-/etc/hadoop/conf.pseudo}"
export YARN_CONF_DIR="${YARN_CONF_DIR:-/etc/hadoop/conf.pseudo}"

export PATH="/usr/lib/hadoop/bin:/usr/lib/hadoop/sbin:/usr/lib/hadoop-yarn/bin:/usr/lib/hadoop-yarn/sbin:/usr/lib/hadoop-mapreduce/bin:/usr/lib/hadoop-hdfs/bin:$PATH"

# Yarn scripts in some VM->Docker conversions look for yarn-config.sh under /usr/lib/hadoop-yarn/libexec
if [ ! -e /usr/lib/hadoop-yarn/libexec/yarn-config.sh ] && [ -e /usr/lib/hadoop/libexec/yarn-config.sh ]; then
  mkdir -p /usr/lib/hadoop-yarn/libexec
  ln -sf /usr/lib/hadoop/libexec/yarn-config.sh /usr/lib/hadoop-yarn/libexec/yarn-config.sh || true
fi

# Some legacy scripts call /bin/yarn; make it available if missing
if [ ! -e /bin/yarn ] && [ -x /usr/lib/hadoop-yarn/bin/yarn ]; then
  ln -sf /usr/lib/hadoop-yarn/bin/yarn /bin/yarn || true
fi

# Helper: start service if init script exists
svc_start() {
  local s="$1"
  if [ -x "/etc/init.d/$s" ]; then
    service "$s" start || true
  fi
}

# ---------- Optional: SSH ----------
svc_start sshd

# ---------- Cloudera Manager (usually absent in training images) ----------
svc_start cloudera-scm-server
svc_start cloudera-scm-agent

# ---------- HDFS ----------
svc_start hadoop-hdfs-namenode
svc_start hadoop-hdfs-datanode
svc_start hdfs-namenode
svc_start hdfs-datanode

# ---------- HDFS dirs needed by Spark History + YARN log aggregation ----------
echo "[start] Ensuring HDFS dirs for Spark event logs and YARN aggregated logs..."

# Spark event log dir (history server reads this)
su -s /bin/bash -c "hdfs dfs -mkdir -p /user/spark/applicationHistory >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chmod 1777 /user/spark/applicationHistory >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chown -R spark:spark /user/spark >/dev/null 2>&1 || true" hdfs || true

# YARN log aggregation directory in HDFS (yarn.nodemanager.remote-app-log-dir=/tmp/logs)
su -s /bin/bash -c "hdfs dfs -mkdir -p /tmp/logs >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chmod 1777 /tmp/logs >/dev/null 2>&1 || true" hdfs || true

# ---------- CRITICAL: Fix NodeManager local log dir EPERM ----------
# Never use /var/log/... as the actual NM log dir in Docker (chmod often fails).
mkdir -p /var/lib/hadoop-yarn/userlogs || true
# NM runs as yarn; give it ownership and permissive mode (what NM expects)
chown -R yarn:yarn /var/lib/hadoop-yarn/userlogs 2>/dev/null || true
chmod 1777 /var/lib/hadoop-yarn/userlogs 2>/dev/null || true

# Provide legacy path via symlink (some tools/log scrapes assume /var/log/hadoop-yarn/userlogs)
mkdir -p /var/log/hadoop-yarn || true
rm -rf /var/log/hadoop-yarn/userlogs 2>/dev/null || true
ln -sf /var/lib/hadoop-yarn/userlogs /var/log/hadoop-yarn/userlogs || true

# Also ensure NM local dirs exist
mkdir -p /var/lib/hadoop-yarn/cache/yarn/nm-local-dir || true
chown -R yarn:yarn /var/lib/hadoop-yarn/cache/yarn 2>/dev/null || true
chmod -R 1777 /var/lib/hadoop-yarn/cache/yarn/nm-local-dir 2>/dev/null || true

# ---------- YARN + MR History ----------
rm -f /var/run/hadoop-yarn/yarn-yarn-nodemanager.pid 2>/dev/null || true
rm -f /var/run/hadoop-yarn/yarn-yarn-resourcemanager.pid 2>/dev/null || true

svc_start hadoop-yarn-resourcemanager
svc_start hadoop-yarn-nodemanager
svc_start hadoop-mapreduce-historyserver

svc_start yarn-resourcemanager
svc_start yarn-nodemanager
svc_start mapreduce-historyserver

# ---------- Verify YARN NodeManager registration (time-bounded) ----------
echo "[start] Verifying YARN NodeManager registration..."
YARN_OK=0

for i in $(seq 1 25); do
  if ! pgrep -f 'org\.apache\.hadoop\.yarn\.server\.resourcemanager\.ResourceManager' >/dev/null 2>&1; then
    /usr/lib/hadoop-yarn/sbin/yarn-daemon.sh start resourcemanager >/dev/null 2>&1 || true
  fi
  if ! pgrep -f 'org\.apache\.hadoop\.yarn\.server\.nodemanager\.NodeManager' >/dev/null 2>&1; then
    /usr/lib/hadoop-yarn/sbin/yarn-daemon.sh start nodemanager >/dev/null 2>&1 || true
  fi

  if command -v timeout >/dev/null 2>&1; then
    OUT="$(timeout 3s /usr/lib/hadoop-yarn/bin/yarn node -list 2>/dev/null || true)"
    NODES="$(echo "$OUT" | awk '/Total Nodes/ {print $3}' || echo 0)"
  else
    NODES=0
  fi

  if [ "${NODES:-0}" != "0" ]; then
    YARN_OK=1
    break
  fi

  sleep 1
done

if [ "$YARN_OK" -ne 1 ]; then
  echo "[start] WARNING: YARN has 0 nodes. Some MR/Sqoop/Spark-on-YARN jobs may hang in ACCEPTED."
  echo "[start] Recent NodeManager log (if any):"
  tail -n 120 /var/log/hadoop-yarn/yarn-yarn-nodemanager-*.log 2>/dev/null || true
  echo "[start] Recent ResourceManager log (if any):"
  tail -n 120 /var/log/hadoop-yarn/yarn-yarn-resourcemanager-*.log 2>/dev/null || true
else
  echo "[start] YARN OK."
fi

# ---------- HDFS dirs needed by Hive/Spark ----------
echo "[start] Ensuring HDFS temp/warehouse dirs..."
su -s /bin/bash -c "hdfs dfs -mkdir -p /tmp /user/hive/warehouse >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chmod -R 1777 /tmp >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chmod -R 777 /user/hive/warehouse >/dev/null 2>&1 || true" hdfs || true
su -s /bin/bash -c "hdfs dfs -chown -R hive:hive /user/hive/warehouse >/dev/null 2>&1 || true" hdfs || true

# ---------- MySQL (Hue depends on it) ----------
echo "[start] Ensuring MySQL is up for Hue..."
svc_start mysqld
if [ -x /etc/init.d/mysqld ]; then /etc/init.d/mysqld start 2>/dev/null || true; fi

for i in $(seq 1 45); do
  [ -S /var/lib/mysql/mysql.sock ] && break
  sleep 1
done

if [ ! -S /var/lib/mysql/mysql.sock ]; then
  echo "[start] WARNING: MySQL socket not found; Hue may fail until mysqld finishes starting."
  tail -n 60 /var/log/mysqld.log 2>/dev/null || true
fi

# ---------- Hue ----------
echo "[start] Starting Hue..."
svc_start hue
sleep 2
if command -v netstat >/dev/null 2>&1; then
  if ! netstat -plnt 2>/dev/null | grep -q ":8888 "; then
    echo "[start] Hue not listening on 8888 yet; retrying Hue start..."
    service hue stop >/dev/null 2>&1 || true
    svc_start hue
  fi
fi

# ---------- Oozie / ZK / HBase / Spark History ----------
svc_start zookeeper-server
svc_start oozie
svc_start hbase-master
svc_start hbase-regionserver
svc_start spark-history-server

# ---------- Hive ----------
echo "[start] Starting Hive Metastore..."
svc_start hive-metastore

echo "[start] Waiting for Hive Metastore (9083)..."
for i in $(seq 1 45); do
  if netstat -plnt 2>/dev/null | grep -q ":9083 " || ss -lntp 2>/dev/null | grep -q ":9083 "; then
    break
  fi
  sleep 1
done

echo "[start] Starting HiveServer2..."
svc_start hive-server2

echo "[start] Waiting for HiveServer2 (10000)..."
HS2_OK=0
for i in $(seq 1 60); do
  if netstat -plnt 2>/dev/null | grep -q ":10000 " || ss -lntp 2>/dev/null | grep -q ":10000 "; then
    HS2_OK=1
    break
  fi
  sleep 1
done

if [ "$HS2_OK" -ne 1 ]; then
  echo "[start] WARNING: HiveServer2 did not come up on 10000. Recent logs:"
  tail -n 160 /var/log/hive/hive-server2.log 2>/dev/null || true
else
  echo "[start] HiveServer2 is listening on 10000."
fi

echo "[start] Hive smoke test (beeline select 1)..."
if command -v timeout >/dev/null 2>&1; then
  timeout 20s beeline -u jdbc:hive2://localhost:10000/default -n training -e "select 1" >/dev/null 2>&1 || true
else
  ( beeline -u jdbc:hive2://localhost:10000/default -n training -e "select 1" >/dev/null 2>&1 || true ) &
fi

echo "[start] Done. Container will stay alive."
tail -f /dev/null
