#!/bin/bash

LOG_FILE="/var/log/webinoly-watchdog.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_and_restart() {
  local service_name="$1"

  if systemctl list-unit-files | grep -q "^$service_name"; then
    if ! systemctl is-active --quiet "$service_name"; then
      log "[!] $service_name is DOWN. Attempting to restart..."
      systemctl restart "$service_name"
      sleep 2
      if systemctl is-active --quiet "$service_name"; then
        log "[✔] $service_name restarted successfully."
      else
        log "[✘] Failed to restart $service_name!"
      fi
    else
      log "[OK] $service_name is running."
    fi
  else
    log "[i] $service_name is not installed or not found."
  fi
}

log "======== Webinoly Watchdog Check Started ========"

# 1. 檢查 Nginx
check_and_restart "nginx"

# 2. 檢查所有 PHP-FPM 版本
php_fpm_services=$(systemctl list-unit-files | grep -E '^php[0-9]+\.[0-9]+-fpm\.service' | awk '{print $1}')
for fpm_service in $php_fpm_services; do
  check_and_restart "$fpm_service"
done

# 3. 自動偵測 MariaDB 服務名稱
mariadb_service=$(systemctl list-unit-files | grep -E '^(mariadb|mysql)\.service' | awk '{print $1}' | head -n1)
if [ -n "$mariadb_service" ]; then
  check_and_restart "$mariadb_service"
else
  log "[i] No MariaDB service found (mariadb.service or mysql.service)"
fi

# 4. 可選：postfix
#check_and_restart "postfix"

log "======== Webinoly Watchdog Check Completed ========"
