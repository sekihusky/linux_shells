#!/bin/bash

# Script: restart-all-php.sh
# 說明: 檢查多版本 PHP-FPM 是否正常運作，異常時才重啟
# 適用: CloudPanel / Ubuntu 環境

PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")

for VERSION in "${PHP_VERSIONS[@]}"
do
  SERVICE="php${VERSION}-fpm"

  # 檢查這個 PHP 版本是否安裝中並有系統服務
  if systemctl list-units --type=service | grep -q "$SERVICE"; then

    # 檢查服務是否正在執行
    if systemctl is-active --quiet $SERVICE; then
      echo "[$(date)] $SERVICE is running normally."
    else
      echo "[$(date)] $SERVICE is NOT running. Attempting to restart..."
      systemctl restart $SERVICE
      sleep 1
      if systemctl is-active --quiet $SERVICE; then
        echo "[$(date)] $SERVICE restarted successfully."
      else
        echo "[$(date)] ERROR: Failed to restart $SERVICE."
      fi
    fi

  else
    echo "[$(date)] $SERVICE is not installed or not managed by systemd."
  fi
