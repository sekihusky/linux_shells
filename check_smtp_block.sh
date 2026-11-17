#!/bin/bash

add_ufw_rule() {
  echo "嘗試新增 UFW 封鎖對外 TCP 25 (IPv4/IPv6)..."
  ufw deny out to any port 25/tcp
  echo "已新增 UFW 封鎖規則，並重新載入 UFW"
  ufw reload
}

add_iptables_rule() {
  echo "嘗試新增 iptables 封鎖對外 TCP 25 (IPv4)..."
  iptables -A OUTPUT -p tcp --dport 25 -j DROP
  echo "嘗試新增 ip6tables 封鎖對外 TCP 25 (IPv6)..."
  ip6tables -A OUTPUT -p tcp --dport 25 -j DROP
  echo "規則已新增，但請確保有設定 iptables 規則保存與開機載入"
}

check_and_add_ufw() {
  ufw status numbered | grep -E 'OUT.*25/tcp.*DENY' >/dev/null
  if [ $? -eq 0 ]; then
    echo "✅ UFW 已封鎖對外 TCP 25 (IPv4/IPv6)"
  else
    echo "❌ UFW 未封鎖對外 TCP 25 (IPv4/IPv6)，正在新增..."
    add_ufw_rule
  fi
}

check_and_add_iptables() {
  iptables -S OUTPUT | grep -- "-p tcp" | grep -- "--dport 25" | grep -E "DROP|REJECT" >/dev/null
  local v4_blocked=$?

  ip6tables -S OUTPUT | grep -- "-p tcp" | grep -- "--dport 25" | grep -E "DROP|REJECT" >/dev/null
  local v6_blocked=$?

  if [ $v4_blocked -eq 0 ]; then
    echo "✅ iptables 已封鎖對外 TCP 25 (IPv4)"
  else
    echo "❌ iptables 未封鎖對外 TCP 25 (IPv4)，正在新增..."
    iptables -A OUTPUT -p tcp --dport 25 -j DROP
  fi

  if [ $v6_blocked -eq 0 ]; then
    echo "✅ ip6tables 已封鎖對外 TCP 25 (IPv6)"
  else
    echo "❌ ip6tables 未封鎖對外 TCP 25 (IPv6)，正在新增..."
    ip6tables -A OUTPUT -p tcp --dport 25 -j DROP
  fi

  echo "請注意：新增的 iptables 規則未必會在重開機後保留，請自行儲存規則。"
}

# 判斷系統 (以 /etc/os-release 判斷 ubuntu)
if grep -qi 'ubuntu' /etc/os-release; then
  check_and_add_ufw
else
  check_and_add_iptables
fi
