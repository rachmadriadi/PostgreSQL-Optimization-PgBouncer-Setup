#!/bin/bash

# =================================================================
# PostgreSQL Tuning & PgBouncer Auto-Config Script (Enterprise)
# Supports: PostgreSQL 12, 13, 14, 15, 16, 17 (and v11)
# Target OS: Debian/Ubuntu (Apt-based)
# =================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "--------------------------------------------------------"
echo "   PostgreSQL Enterprise Tuner & PgBouncer Setup        "
echo "--------------------------------------------------------"
echo -e "${NC}"

# 1. Check User (Must be Root)
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run this script as root (sudo).${NC}"
  exit 1
fi

# 2. Input Parameters from User
echo -e "${YELLOW}--- Input Configuration & Specifications ---${NC}"
read -p "PostgreSQL Version (e.g., 11, 15, 16): " PG_VERSION
read -p "PostgreSQL Port (default: 5432): " PG_PORT
PG_PORT=${PG_PORT:-5432}

read -p "Total Server RAM (in GB): " RAM_GB
read -p "Number of CPU Cores: " CPU_CORES
read -p "Storage Type (1: SSD/NVMe, 2: HDD): " DISK_TYPE
read -p "Estimated Concurrent Users/Connections: " TOTAL_USERS

echo -e "\n${BLUE}Additional Options:${NC}"
read -p "Enable Kernel Sysctl Tuning? (y/n): " TUNE_KERNEL
read -p "Open Port in Firewall (UFW)? (y/n): " SETUP_UFW
read -p "Create New Database User? (y/n): " CREATE_NEW_USER
read -p "Install & Configure PgBouncer? (y/n): " INSTALL_PGBOUNCER

# Input for New User (Data is stored first, execution later)
if [[ "$CREATE_NEW_USER" =~ ^[Yy]$ ]]; then
    read -p "New Username: " NEW_DB_USER
    read -p "New User Password (Visible): " NEW_DB_PASS
    read -p "Role/Privilege (e.g., SUPERUSER, CREATEDB, LOGIN): " NEW_DB_ROLE
    NEW_DB_ROLE=${NEW_DB_ROLE:-"LOGIN"}
fi

if [[ "$INSTALL_PGBOUNCER" =~ ^[Yy]$ ]]; then
    read -p "PgBouncer Port (default: 6432): " PGB_PORT
    PGB_PORT=${PGB_PORT:-6432}
    read -p "PgBouncer Admin Username (default: postgres): " PGB_ADMIN
    PGB_ADMIN=${PGB_ADMIN:-"postgres"}
    read -p "Password for PgBouncer User (Visible): " PGB_PASS
    echo "" 
fi

# Validate configuration path
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

if [ ! -f "$PG_CONF" ]; then
    echo -e "${RED}Error: Configuration file not found at $PG_CONF${NC}"
    exit 1
fi

# 3. Kernel Sysctl Tuning (Optional)
if [[ "$TUNE_KERNEL" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}--- Tuning Linux Kernel (sysctl) ---${NC}"
    SYSCTL_CONF="/etc/sysctl.d/99-postgresql-tuning.conf"
    cat <<EOF > "$SYSCTL_CONF"
# PostgreSQL Tuning
vm.swappiness = 10
vm.overcommit_memory = 2
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF
    sysctl -p "$SYSCTL_CONF" > /dev/null
    echo "Kernel tuned (Swappiness=10, Overcommit=2)"
fi

# 4. Hardware Tuning Calculation Logic
TOTAL_RAM_MB=$((RAM_GB * 1024))
SHARED_BUFFERS=$((TOTAL_RAM_MB / 4))
# Adjusted cap for large RAM (e.g., 80GB), limit 20GB shared buffers
if [ $SHARED_BUFFERS -gt 20480 ]; then SHARED_BUFFERS=20480; fi

EFFECTIVE_CACHE=$((TOTAL_RAM_MB * 3 / 4))
MAINT_WORK_MEM=$((TOTAL_RAM_MB / 16))
if [ $MAINT_WORK_MEM -gt 2048 ]; then MAINT_WORK_MEM=2048; fi

WORK_MEM_KB=$(( ((TOTAL_RAM_MB - SHARED_BUFFERS) * 1024) / (TOTAL_USERS * 3) ))
if [ $WORK_MEM_KB -lt 4096 ]; then WORK_MEM_KB=4096; fi

RPC="4.0"; if [ "$DISK_TYPE" == "1" ]; then RPC="1.1"; fi
MAX_PARALLEL=$((CPU_CORES / 2))
[ $MAX_PARALLEL -lt 2 ] && MAX_PARALLEL=2
PARA_MAINT=$((CPU_CORES / 4))
[ $PARA_MAINT -lt 2 ] && PARA_MAINT=2
[ $PARA_MAINT -gt 4 ] && PARA_MAINT=4

# 5. Backup & Update postgresql.conf
echo -e "\n${YELLOW}--- Applying PostgreSQL $PG_VERSION Optimizations ---${NC}"
cp "$PG_CONF" "${PG_CONF}.bak_$(date +%F_%T)"

update_config() {
    local param=$1; local value=$2
    if grep -q "^$param" "$PG_CONF"; then
        sed -i "s|^$param.*|$param = $value|" "$PG_CONF"
    else
        echo "$param = $value" >> "$PG_CONF"
    fi
}

update_config "port" "$PG_PORT"
update_config "max_connections" "$TOTAL_USERS"
update_config "shared_buffers" "'${SHARED_BUFFERS}MB'"
update_config "effective_cache_size" "'${EFFECTIVE_CACHE}MB'"
update_config "maintenance_work_mem" "'${MAINT_WORK_MEM}MB'"
update_config "checkpoint_completion_target" "0.9"
update_config "wal_buffers" "'16MB'"
update_config "default_statistics_target" "100"
update_config "random_page_cost" "$RPC"
update_config "effective_io_concurrency" "200"
update_config "work_mem" "'${WORK_MEM_KB}kB'"
update_config "huge_pages" "off"
update_config "min_wal_size" "'1GB'"
update_config "max_wal_size" "'4GB'"
update_config "max_worker_processes" "$CPU_CORES"
update_config "max_parallel_workers_per_gather" "$MAX_PARALLEL"
update_config "max_parallel_workers" "$CPU_CORES"
update_config "max_parallel_maintenance_workers" "$PARA_MAINT"
update_config "shared_preload_libraries" "'pg_stat_statements'"
update_config "pg_stat_statements.track" "all"

# 6. PgBouncer Section (If selected)
if [[ "$INSTALL_PGBOUNCER" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}--- Installing PgBouncer ---${NC}"
    apt-get update -y && apt-get install -y pgbouncer
    PGB_CONF="/etc/pgbouncer/pgbouncer.ini"
    PGB_AUTH="/etc/pgbouncer/userlist.txt"
    [ -f "$PGB_CONF" ] && cp "$PGB_CONF" "${PGB_CONF}.bak"

    cat <<EOF > "$PGB_CONF"
[databases]
* = host=127.0.0.1 port=$PG_PORT

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
listen_addr = 0.0.0.0
listen_port = $PGB_PORT
auth_type = md5
auth_file = $PGB_AUTH
admin_users = postgres, $PGB_ADMIN
stats_users = stats, postgres
pool_mode = transaction
max_client_conn = $((TOTAL_USERS * 3))
default_pool_size = $((TOTAL_USERS / 2))
reserve_pool_size = 10
ignore_startup_parameters = extra_float_digits
EOF

    echo "\"$PGB_ADMIN\" \"$PGB_PASS\"" > "$PGB_AUTH"
    chown postgres:postgres "$PGB_AUTH" && chmod 600 "$PGB_AUTH"

    if ! grep -q "127.0.0.1/32" "$PG_HBA"; then
        echo "host    all             all             127.0.0.1/32            md5" >> "$PG_HBA"
    fi
    systemctl enable pgbouncer && systemctl restart pgbouncer
fi

# 7. Setup Firewall (UFW)
if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    if command -v ufw > /dev/null; then
        echo -e "\n${YELLOW}--- Firewall Configuration (UFW) ---${NC}"
        ufw allow "$PG_PORT"/tcp
        [[ "$INSTALL_PGBOUNCER" =~ ^[Yy]$ ]] && ufw allow "$PGB_PORT"/tcp
        echo "Port $PG_PORT (Postgres) and $PGB_PORT (PgBouncer) opened."
    fi
fi

# 8. Finalization & SQL Execution
echo -e "\n${YELLOW}--- Restarting PostgreSQL $PG_VERSION ---${NC}"
systemctl restart "postgresql@$PG_VERSION-main"

# Allow 2 seconds for service to fully come up
sleep 2

if systemctl is-active --quiet "postgresql@$PG_VERSION-main"; then
    echo -e "${GREEN}PostgreSQL successfully running on port $PG_PORT.${NC}"
    
    # 1. Enable pg_stat_statements
    echo -e "${YELLOW}--- Enabling pg_stat_statements ---${NC}"
    cd /tmp && sudo -u postgres psql -p "$PG_PORT" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
    
    # 2. Create New User & Grant (If selected)
    if [[ "$CREATE_NEW_USER" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}--- Creating New User: $NEW_DB_USER ---${NC}"
        cd /tmp && sudo -u postgres psql -p "$PG_PORT" -c "CREATE ROLE $NEW_DB_USER WITH $NEW_DB_ROLE PASSWORD '$NEW_DB_PASS';"
        
        echo -e "\n${BLUE}PostgreSQL is Active. Please select a Database to GRANT access:${NC}"
        cd /tmp && sudo -u postgres psql -p "$PG_PORT" -lqt | cut -d \| -f 1 | grep -vE "^[[:space:]]*$"
        read -p "Enter database name to GRANT to user $NEW_DB_USER: " TARGET_DB

        if [ ! -z "$TARGET_DB" ]; then
            echo -e "${YELLOW}--- Granting Privileges to Database: $TARGET_DB ---${NC}"
            cd /tmp && sudo -u postgres psql -p "$PG_PORT" -c "GRANT ALL PRIVILEGES ON DATABASE \"$TARGET_DB\" TO $NEW_DB_USER;"
            cd /tmp && sudo -u postgres psql -p "$PG_PORT" -d "$TARGET_DB" -c "GRANT ALL ON SCHEMA public TO $NEW_DB_USER;"
            echo -e "${GREEN}Full access to database '$TARGET_DB' granted to $NEW_DB_USER.${NC}"
        fi
        echo -e "${GREEN}User $NEW_DB_USER processing complete.${NC}"
    fi
    
    # Final Summary
    echo -e "\n${YELLOW}=== COMPLETE TUNING SUMMARY ===${NC}"
    echo -e "PostgreSQL Port           : $PG_PORT"
    echo -e "Max Connections           : $TOTAL_USERS"
    echo -e "Shared Buffers            : ${SHARED_BUFFERS}MB"
    echo -e "Work Mem                  : ${WORK_MEM_KB}kB"
    echo -e "Worker Processes          : $CPU_CORES"
    if [[ "$CREATE_NEW_USER" =~ ^[Yy]$ ]]; then
        echo -e "New User                  : $NEW_DB_USER ($NEW_DB_ROLE)"
        echo -e "Database Granted          : $TARGET_DB"
    fi
    echo -e "${YELLOW}================================${NC}"
else
    echo -e "${RED}Failed to restart PostgreSQL. Please check logs with: journalctl -xe${NC}"
fi
