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

# ---------- Environment (critical in containerized CDH5) ----------
export JAVA_HOME="${JAVA_HOME:-/usr/java/jdk1.7.0_67}"
export HADOOP_HOME="${HADOOP_HOME:-/usr/lib/hadoop}"

# Prefer conf.pseudo (your logs show RM reads /etc/hadoop/conf.pseudo/yarn-site.xml)
export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-/etc/hadoop/conf.pseudo}"
export YARN_CONF_DIR="${YARN_CONF_DIR:-/etc/hadoop/conf.pseudo}"

export PATH="/usr/lib/hadoop/bin:/usr/lib/hadoop/sbin:/usr/lib/hadoop-yarn/bin:/usr/lib/hadoop-yarn/sbin:/usr/lib/hadoop-mapreduce/bin:/usr/lib/hadoop-hdfs/bin:$PATH"

# Yarn scripts in some CDH5 VM-to-Docker conversions look for yarn-config.sh under /usr/lib/hadoop-yarn/libexec
if [ ! -e /usr/lib/hadoop-yarn/libexec/yarn-config.sh ] && [ -e /usr/lib/hadoop/libexec/yarn-config.sh ]; then
  mkdir -p /usr/lib/hadoop-yarn/libexec
  ln -sf /usr/lib/hadoop/libexec/yarn-config.sh /usr/lib/hadoop-yarn/libexec/yarn-config.sh || true
fi

# Some legacy scripts call /bin/yarn; make it available if missing
if [ ! -e /bin/yarn ] && [ -x /usr/lib/hadoop-yarn/bin/yarn ]; then
  ln -sf /usr/lib/hadoop-yarn/bin/yarn /bin/yarn || true
fi

# ---------- Optional: SSH ----------
if [ -x /etc/init.d/sshd ]; then
  service sshd start || true
fi

# ---------- Cloudera Manager (usually absent in training images) ----------
service cloudera-scm-server start || true
service cloudera-scm-agent start || true

# ---------- HDFS ----------
service hadoop-hdfs-namenode start || true
service hadoop-hdfs-datanode start || true
# Alternate names sometimes present
service hdfs-namenode start || true
service hdfs-datanode start || true

# ---------- YARN + MR History ----------
# Fix common "Address already in use" / stale pidfiles BEFORE starting YARN
rm -f /var/run/hadoop-yarn/yarn-yarn-nodemanager.pid 2>/dev/null || true
rm -f /var/run/hadoop-yarn/yarn-yarn-resourcemanager.pid 2>/dev/null || true

# Start RM/NM best-effort (init scripts often vary by image)
service hadoop-yarn-resourcemanager start || true
service hadoop-yarn-nodemanager start || true
service hadoop-mapreduce-historyserver start || true

# Alternate names sometimes present
service yarn-resourcemanager start || true
service yarn-nodemanager start || true
service mapreduce-historyserver start || true

# ---------- Verify YARN NodeManager registration (time-bounded, non-blocking) ----------
echo "[start] Verifying YARN NodeManager registration..."
YARN_OK=0

for i in $(seq 1 20); do
  # If ResourceManager isn't running, try starting it directly
  if ! pgrep -f 'org\.apache\.hadoop\.yarn\.server\.resourcemanager\.ResourceManager' >/dev/null 2>&1; then
    /usr/lib/hadoop-yarn/sbin/yarn-daemon.sh start resourcemanager >/dev/null 2>&1 || true
  fi

  # If NodeManager isn't running, try starting it directly
  if ! pgrep -f 'org\.apache\.hadoop\.yarn\.server\.nodemanager\.NodeManager' >/dev/null 2>&1; then
    /usr/lib/hadoop-yarn/sbin/yarn-daemon.sh start nodemanager >/dev/null 2>&1 || true
  fi

  # Don't let yarn CLI hang container boot
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
  tail -n 80 /var/log/hadoop-yarn/yarn-yarn-nodemanager-*.log 2>/dev/null || true
  echo "[start] Recent ResourceManager log (if any):"
  tail -n 80 /var/log/hadoop-yarn/yarn-yarn-resourcemanager-*.log 2>/dev/null || true
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
service mysqld start 2>/dev/null || /etc/init.d/mysqld start 2>/dev/null || true

for i in $(seq 1 45); do
  [ -S /var/lib/mysql/mysql.sock ] && break
  sleep 1
done

if [ ! -S /var/lib/mysql/mysql.sock ]; then
  echo "[start] WARNING: MySQL socket not found; Hue may fail until mysqld finishes starting."
  tail -n 40 /var/log/mysqld.log 2>/dev/null || true
fi

# ---------- Hue ----------
echo "[start] Starting Hue..."
service hue start || true
# If Hue didn't bind yet, try one restart
sleep 2
if command -v netstat >/dev/null 2>&1; then
  if ! netstat -plnt 2>/dev/null | grep -q ":8888 "; then
    echo "[start] Hue not listening on 8888 yet; retrying Hue start..."
    service hue stop >/dev/null 2>&1 || true
    service hue start || true
  fi
fi

# ---------- Oozie / ZK / HBase / Spark History ----------
service zookeeper-server start || true
service oozie start || true
service hbase-master start || true
service hbase-regionserver start || true
service spark-history-server start || true

# ---------- Hive (time-bounded, non-blocking smoke test) ----------
echo "[start] Starting Hive Metastore..."
service hive-metastore start || true

echo "[start] Waiting for Hive Metastore (9083)..."
for i in $(seq 1 45); do
  if netstat -plnt 2>/dev/null | grep -q ":9083 " || ss -lntp 2>/dev/null | grep -q ":9083 "; then
    break
  fi
  sleep 1
done

echo "[start] Starting HiveServer2..."
service hive-server2 start || true

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
  tail -n 120 /var/log/hive/hive-server2.log 2>/dev/null || true
else
  echo "[start] HiveServer2 is listening on 10000."
fi

# Optional, non-blocking smoke test (won't stall container boot)
echo "[start] Hive smoke test (beeline select 1)..."
if command -v timeout >/dev/null 2>&1; then
  timeout 20s beeline -u jdbc:hive2://localhost:10000/default -n training -e "select 1" >/dev/null 2>&1 || true
else
  ( beeline -u jdbc:hive2://localhost:10000/default -n training -e "select 1" >/dev/null 2>&1 || true ) &
fi

echo "[start] Done. Container will stay alive."
tail -f /dev/null
