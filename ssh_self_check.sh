#!/bin/bash
# Ubuntu / Debian + systemd. Default: check and repair; --check: check only.
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

log() { printf '[ssh-self-check] %s\n' "$*"; }
fail() { log "錯誤：$*" >&2; exit 1; }

package_ok() {
  [[ $(dpkg-query -W -f='${Status}' openssh-server 2>/dev/null) == 'install ok installed' ]]
}

config_ok() {
  command -v sshd >/dev/null && sshd -t
}

# Probe actual listeners, including non-default ports and ssh.socket activation.
# Success means at least one local SSH endpoint completed host-key exchange.
probe_ssh() {
  local listeners socket_listen='' socket_active=false endpoint host port keys line
  command -v ssh-keyscan >/dev/null || return 1
  listeners=$(ss -H -ltnp) || return 1
  if systemctl is-active --quiet ssh.socket; then
    socket_active=true
    socket_listen=$(systemctl show ssh.socket -p Listen --value) || return 1
  fi
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    read -r _ _ _ endpoint _ <<< "$line"
    [[ $endpoint == *:* ]] || continue
    port=${endpoint##*:}
    [[ $port =~ ^[0-9]+$ ]] || continue
    if [[ $line != *'"sshd"'* ]]; then
      # Only accept systemd listeners belonging to the active SSH socket.
      $socket_active || continue
      [[ $line == *'"systemd"'* ]] || continue
      [[ $socket_listen == *":$port (Stream)"* ]] || continue
    fi
    host=${endpoint%:*}
    host=${host#[}
    host=${host%]}
    case "$host" in
      0.0.0.0|'*') host=127.0.0.1 ;;
      ::) host=::1 ;;
    esac
    keys=$(ssh-keyscan -T 5 -p "$port" "$host" 2>/dev/null) || continue
    if [[ -n $keys ]]; then
      log "本機 SSH 握手成功：$host:$port"
      return 0
    fi
  done <<< "$listeners"
  return 1
}

healthy() {
  package_ok || { log 'openssh-server 未完整安裝。'; return 1; }
  config_ok || { log 'sshd 設定或主機金鑰檢查失敗。'; return 1; }
  if ! systemctl is-active --quiet ssh.service && ! systemctl is-active --quiet ssh.socket; then
    log 'ssh.service 與 ssh.socket 都未啟動。'
    return 1
  fi
  probe_ssh || { log '未找到可完成握手的本機 SSH 監聽端點。'; return 1; }
}

diagnostics() {
  systemctl --no-pager --full status ssh.service ssh.socket >&2 || true
  journalctl --no-pager -n 40 -u ssh.service -u ssh.socket >&2 || true
}

backup_config() {
  local backup_dir
  backup_dir=$(mktemp -d /var/backups/ssh-self-check.XXXXXX) || return 1
  if [[ -d /etc/ssh ]]; then
    cp -a -- /etc/ssh "$backup_dir/" || return 1
  fi
  if [[ -f /etc/default/ssh ]]; then
    cp -a -- /etc/default/ssh "$backup_dir/default-ssh" || return 1
  fi
  log "設定與現有主機金鑰備份：$backup_dir（僅 root 可讀）"
}

install_server() {
  log '安裝／重新安裝 OpenSSH，保留現有設定；不執行 purge。'
  apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update || return 1
  DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o DPkg::Lock::Timeout=60 \
    -o Dpkg::Options::=--force-confold \
    -o Dpkg::Options::=--force-confmiss \
    --reinstall install openssh-server openssh-client || return 1
}

main() {
  local mode=repair unit=ssh.service command attempt
  case "${1:-}" in
    '') ;;
    --check) mode=check ;;
    -h|--help)
      printf '用法：sudo bash ssh_self_check.sh [--check]\n預設檢查並修復；--check 只檢查、不安裝或重啟。\n'
      return 0 ;;
    *) fail '不支援的參數。使用 --help 查看用法。' ;;
  esac
  [[ $# -le 1 ]] || fail '參數過多。'
  [[ $EUID -eq 0 ]] || fail '請使用 root 或 sudo 執行。'
  [[ -r /etc/os-release ]] || fail '找不到 /etc/os-release。'
  . /etc/os-release
  case "${ID:-}" in ubuntu|debian) ;; *) fail '僅支援 Ubuntu / Debian。' ;; esac
  [[ -d /run/systemd/system ]] || fail '需要正在運作的 systemd。'
  for command in systemctl dpkg-query ss; do
    command -v "$command" >/dev/null || fail "缺少必要指令：$command"
  done

  if [[ $mode == check ]]; then
    if healthy; then
      log '檢查通過；尚未驗證外部連線或個別帳號登入。'
      return 0
    fi
    diagnostics
    return 1
  fi

  for command in apt-get flock mktemp cp install journalctl; do
    command -v "$command" >/dev/null || fail "缺少必要指令：$command"
  done
  exec 9>/run/lock/ssh-self-check.lock
  flock -n 9 || fail '已有另一個檢查／修復工作執行中。'
  if healthy; then
    log 'SSH 正常，不需重新安裝。'
    return 0
  fi
  if systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket; then
    unit=ssh.socket
  fi
  backup_config || fail '備份失敗，停止修復。'
  # sshd -t needs its runtime directory on Debian / Ubuntu.
  install -d -o root -g root -m 755 /run/sshd
  if package_ok && config_ok; then
    log "先嘗試啟動 $unit。"
    systemctl start "$unit" || true
    if healthy; then
      log 'SSH 已恢復，不需重新安裝；未變更原本的開機啟動設定。'
      return 0
    fi
  fi

  install_server || { diagnostics; fail 'APT 安裝失敗，請查看上方錯誤；不會反覆重裝。'; }
  systemctl daemon-reload
  # Generate only missing default host keys; never overwrite existing keys.
  ssh-keygen -A
  if ! config_ok; then
    diagnostics
    fail '重裝後設定仍無效。保留原設定，請依 sshd -t 錯誤修正；未主動重啟服務。'
  fi
  log "重新啟動 $unit 並驗證。"
  systemctl restart "$unit" || { diagnostics; fail 'SSH 啟動失敗。'; }
  if [[ $unit == ssh.socket ]] && systemctl is-active --quiet ssh.service; then
    systemctl restart ssh.service || { diagnostics; fail 'SSH 服務重新啟動失敗。'; }
  fi
  for attempt in 1 2 3; do
    if healthy; then
      log '修復成功。請另開終端測試實際登入；本機檢查不涵蓋防火牆、雲端安全群組或帳號權限。'
      return 0
    fi
    sleep 2
  done
  diagnostics
  fail '重裝後仍未通過檢查，請檢查設定、埠衝突與服務日誌。'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
