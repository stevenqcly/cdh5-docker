FROM cloudera-cdh5:imported

COPY start.sh /start.sh
RUN chmod +x /start.sh

COPY yarn-site.xml /etc/hadoop/conf.pseudo/yarn-site.xml
COPY mapred-site.xml /etc/hadoop/conf.pseudo/mapred-site.xml

# --- Spark config (CDH5 uses /etc/spark/conf -> alternatives -> spark-conf) ---
COPY spark-env.sh /etc/spark/conf/spark-env.sh
COPY spark-defaults.conf /etc/spark/conf/spark-defaults.conf

# Permissions are helpful for consistency
RUN chmod 0755 /etc/spark/conf/spark-env.sh && \
    chmod 0644 /etc/spark/conf/spark-defaults.conf


EXPOSE \
  7180 8888 \
  8088 8042 19888 13562 \
  50070 50075 50090 \
  10000 10002 9083 \
  18080 4040 \
  11000 \
  60010 60030 \
  2181

CMD ["/start.sh"]
