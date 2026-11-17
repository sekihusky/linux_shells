#!/bin/bash
HOST=localhost
PORT=3306
EMAIL="your@email.com"
HOSTNAME=$(hostname)

# 檢查資料庫 port 是否活著
if timeout 2 bash -c "</dev/tcp/$HOST/$PORT" &>/dev/null; then
  echo "alive"
else
  echo "die"

  # 判斷資料庫類型（MariaDB or MySQL）
  DB_TYPE=$(mysql -V 2>/dev/null)

  if [[ "$DB_TYPE" == *"MariaDB"* ]]; then
    echo "Detected MariaDB"
    systemctl restart mariadb.service
    SERVICE_RESTARTED="mariadb"
  elif [[ "$DB_TYPE" == *"Distrib"* ]]; then
    echo "Detected MySQL"
    systemctl restart mysql.service
    SERVICE_RESTARTED="mysql"
  else
    echo "Unknown DB type or mysql not found"
    SERVICE_RESTARTED="unknown"
  fi

  # 發送 email 通知
  # mail 指令需先安裝並設定：
  # Debian/Ubuntu: apt install mailutils
  # RHEL/CentOS/Rocky: dnf install mailx
  mail -s "[DB ALERT] $HOSTNAME database down - restarted $SERVICE_RESTARTED" "$EMAIL" <<EOF
[警告通知] 資料庫連線失敗

主機：$HOSTNAME
IP/Port：$HOST:$PORT
偵測時間：$(date)
資料庫類型：$DB_TYPE
執行動作：已嘗試重啟 $SERVICE_RESTARTED

請檢查系統日誌確認狀況。
EOF

fi
