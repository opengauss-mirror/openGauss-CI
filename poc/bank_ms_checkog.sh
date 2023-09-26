#!/bin/bash
# 工具名: openGauss检测工具
# 工具用途: 可以通过该工具检测出数据库相关配置信息
# 作者: zhangao
# 时间: 2023-06-30

# PostgreSQL Connection Info
PGHOST="localhost"
PGPORT="5432"
PGUSER="username"
PGPASSWORD="password"
PGDATABASE="database"
# N秒内的时间范围，可以根据实际情况修改
N_SECONDS=60
# 输出文件路径
output_file="/home/user/output.txt"

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "Timestamp: $TIMESTAMP" > "$output_file"

    # Total connections
    TOTAL_CONNECTIONS=$(gsql -h localhost -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity;")
    echo "Total Connections: $TOTAL_CONNECTIONS"  > "$output_file"

    # New connections in the last N seconds
    NEW_CONNECTIONS=$(gsql -h localhost -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity WHERE state_change >= now() - interval '$N_SECONDS seconds';")
    echo "New Connections (Last $N_SECONDS seconds): $NEW_CONNECTIONS" > "$output_file"

    # SQL active statistics
    SQL_ACTIVE=$(gsql -h localhost -U $PGUSER -d $PGDATABASE -t -c
    "SELECT query FROM pg_stat_activity WHERE state = 'active';")
    echo "SQL Active Statistics: $SQL_ACTIVE" > "$output_file"

    # Calculate QPS
    QPS=$(gsql -h localhost -U $PGUSER -d $PGDATABASE -t -c
    "SELECT sum(calls) / $N_SECONDS FROM pg_stat_statements;")
    echo "QPS: $QPS" > "$output_file"

    # Active sessions
    ACTIVE_SESSIONS=$(gsql -h localhost -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';")
    echo "Active Sessions: $ACTIVE_SESSIONS" > "$output_file"

    # Total Connections
    total_connections=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity;")
    echo "Total Connections: $total_connections" > "$output_file"

    # New Connections in Last N Seconds
    new_connections=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity WHERE backend_start >= now() - interval '$N_SECONDS seconds';")
    echo "New Connections in Last $N_SECONDS Seconds: $new_connections" > "$output_file"

    # Active Queries
    active_queries=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';")
    echo "Active Queries: $active_queries" > "$output_file"

    # Queries Per Second (QPS)
    qps=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT sum(calls) / $N_SECONDS FROM pg_stat_statements;")
    echo "Queries Per Second (QPS): $qps" > "$output_file"

    # Active Sessions
    active_sessions=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';")
    echo "Active Sessions: $active_sessions" > "$output_file"

    # Data Space
    data_space=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT pg_size_pretty(pg_database_size(current_database()));")
    echo "Data Space: $data_space" > "$output_file"

    # Log Space
    log_space=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT pg_size_pretty(pg_wal_size());")
    echo "Log Space: $log_space" > "$output_file"

    # Standby Delay
    standby_delay=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT pg_last_xact_replay_timestamp();")
    echo "Standby Delay: $standby_delay" > "$output_file"

    # Apply Delay
    apply_delay=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT now() - pg_last_xact_replay_timestamp();")
    echo "Apply Delay: $apply_delay" > "$output_file"

    # Replication Slot Delay
    slot_delay=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) FROM pg_replication_slots;")
    echo "Replication Slot Delay: $slot_delay" > "$output_file"

    # Archive Delay
    archive_delay=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn();")
    echo "Archive Delay: $archive_delay" > "$output_file"

    # Transactions Per Second (TPS)
    tps=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT sum(xact_commit) / $N_SECONDS FROM pg_stat_database;")
    echo "Transactions Per Second (TPS): $tps" > "$output_file"

    # Rollbacks Per Second (RPS)
    rps=$(gsql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -c
    "SELECT sum(xact_rollback) / $N_SECONDS FROM pg_stat_database;")
    echo "Rollbacks Per Second (RPS): $rps" > "$output_file"

    sleep $N_SECONDS
done