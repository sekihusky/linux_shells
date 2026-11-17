#!/bin/bash

disable_ipv6() {
  echo "🚫 停用 IPv6 中..."

  if grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
    echo "✅ /etc/sysctl.conf 已包含 IPv6 關閉設定"
  else
    echo -e "\n# Disable IPv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
  fi

  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

  echo "✅ IPv6 已停用（立即生效），也會在開機時自動關閉。"
}

enable_ipv6() {
  echo "🔁 還原 IPv6 中..."

  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0

  sudo sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
  sudo sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf

  echo "✅ IPv6 已開啟（立即生效），永久設定也已移除。"
}

check_status() {
  echo "🔎 檢查 IPv6 狀態..."
  ip -6 addr show | grep inet6 || echo "❌ 沒有啟用中的 IPv6 地址"
}

echo "======= IPv6 管理腳本 ======="
echo "1) 停用 IPv6（立即與永久）"
echo "2) 還原 IPv6（立即與永久）"
echo "3) 檢查目前 IPv6 狀態"
echo "0) 離開"
echo "============================="
read -p "請選擇操作項目 [0-3]: " opt

case $opt in
  1) disable_ipv6 ;;
  2) enable_ipv6 ;;
  3) check_status ;;
  0) echo "👋 再見！"; exit 0 ;;
  *) echo "❌ 無效的選項，請輸入 0-3" ;;
esac
