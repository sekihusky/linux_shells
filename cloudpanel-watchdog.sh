#!/bin/bash

# 監控cloudpanel服務用

LOG_FILE="/var/log/cloudpanel-watchdog.log"
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

log() {
  echo "$DATE_TIME - $1" >> "$LOG_FILE"
}

check_and_restart() {
  local service_name="$1"
  if systemctl list-units --type=service | grep -q "$service_name"; then
    if ! systemctl is-active --quiet "$service_name"; then
      log "$service_name is down. Attempting to restart..."
      systemctl restart "$service_name"
      log "$service_name restarted."
    fi
  fi
}

# 1.檢查 Nginx
check_and_restart "nginx"

# 2️.檢查所有 PHP-FPM 版本
for fpm in $(systemctl list-units --type=service | grep -oP 'php[0-9]+\.[0-9]+-fpm'); do
  check_and_restart "$fpm"
done

# 3.檢查資料庫（MySQL 或 MariaDB）
if systemctl list-units --type=service | grep -q mariadb; then
  check_and_restart "mariadb"
elif systemctl list-units --type=service | grep -q mysql; then
  check_and_restart "mysql"
fi
