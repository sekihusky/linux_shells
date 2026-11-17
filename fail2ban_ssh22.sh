#!/bin/bash
# Ubuntu / Debian + systemd: protect SSH TCP 22 with Fail2ban + nftables.
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077

JAIL=sshd-port22
CONFIG=/etc/fail2ban/jail.d/99-ssh-port22.local
MARKER='# Managed by fail2ban_ssh22.sh'
BACKUP=''
HAD_CONFIG=false
PENDING=false
TEMP_CONFIG=''

log() { printf '[fail2ban-ssh22] %s\n' "$*"; }
fail() { log "錯誤：$*" >&2; exit 1; }

render_config() {
  cat <<'CONF'
# Managed by fail2ban_ssh22.sh
[sshd-port22]
enabled = true
filter = sshd[mode=normal]
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _SYSTEMD_UNIT=sshd.service + _COMM=sshd + _COMM=sshd-session
port = 22
protocol = tcp
usedns = no
maxretry = 5
findtime = 600
bantime = 3600
bantime.increment = false
ignoreself = true
ignoreip = 127.0.0.0/8 ::1
ignorecommand =
ignorecache =
action = nftables[type=multiport, name=sshd-port22, port="22", protocol=tcp, table=f2b-ssh22, chain=f2b-chain, actionstart_on_demand=false]
CONF
}

ssh22_ok() {
  local listeners line endpoint host keys
  listeners=$(ss -H -ltnp 'sport = :22') || return 1
  while IFS= read -r line; do
    [[ $line == *'"sshd"'* || $line == *'"systemd"'* ]] || continue
    read -r _ _ _ endpoint _ <<< "$line"
    [[ $endpoint == *:22 ]] || continue
    host=${endpoint%:22}
    host=${host#[}; host=${host%]}
    case "$host" in 0.0.0.0|'*') host=127.0.0.1 ;; ::) host=::1 ;; esac
    keys=$(ssh-keyscan -T 5 -p 22 "$host" 2>/dev/null) || continue
    [[ -n $keys ]] && return 0
  done <<< "$listeners"
  return 1
}

packages_ok() {
  local package
  for package in fail2ban nftables python3-systemd; do
    [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]] || return 1
  done
}

rules_ok() {
  local rules
  rules=$(nft list chain inet f2b-ssh22 f2b-chain 2>/dev/null) || return 1
  [[ $rules == *'type filter hook input'* ]] || return 1
  # Require a TCP 22 rule tied to this jail's IPv4 or IPv6 ban set.
  grep -Eq 'tcp dport (22|\{ 22 \}) (ip|ip6) saddr @addr(6)?-set-sshd-port22 .*reject' <<< "$rules"
}

check_status() {
  packages_ok || { log 'Fail2ban、nftables 或 python3-systemd 尚未完整安裝。'; return 1; }
  fail2ban-client -t || return 1
  systemctl is-active --quiet fail2ban || return 1
  fail2ban-client ping >/dev/null || return 1
  fail2ban-client status "$JAIL" || return 1
  [[ $(fail2ban-client get "$JAIL" maxretry) == 5 ]] || return 1
  [[ $(fail2ban-client get "$JAIL" findtime) == 600 ]] || return 1
  [[ $(fail2ban-client get "$JAIL" bantime) == 3600 ]] || return 1
  fail2ban-client get "$JAIL" journalmatch || return 1
  rules_ok || { log '沒有找到本腳本的 TCP 22 nftables 封鎖規則。'; return 1; }
}

rollback() {
  if $HAD_CONFIG; then
    cp -p -- "$BACKUP/99-ssh-port22.local" "$CONFIG" || return 1
    if systemctl is-active --quiet fail2ban; then
      fail2ban-client reload --restart "$JAIL" || return 1
    fi
  else
    rm -f -- "$CONFIG" || return 1
    if systemctl is-active --quiet fail2ban; then
      fail2ban-client stop "$JAIL" >/dev/null 2>&1 || true
    fi
  fi
  log '已還原本腳本的 jail 設定；已安裝的套件仍保留。'
}

cleanup() {
  local result=$?
  trap - EXIT
  [[ -z $TEMP_CONFIG ]] || rm -f -- "$TEMP_CONFIG"
  if $PENDING; then
    log '套用未完成，嘗試還原本腳本的 jail 設定。' >&2
    rollback || log "自動還原失敗，請從 $BACKUP 手動還原並檢查 Fail2ban。" >&2
    result=1
  fi
  exit "$result"
}

main() {
  local mode=install command attempt
  case "${1:-}" in
    '') ;;
    --check) mode=check ;;
    -h|--help)
      printf '用法：sudo bash fail2ban_ssh22.sh [--check]\n預設檢查、安裝並設定 SSH TCP 22 防護；--check 只檢查。\n'
      return 0 ;;
    *) fail '未知參數，請使用 --help。' ;;
  esac
  [[ $# -le 1 ]] || fail '參數過多。'
  [[ $EUID -eq 0 ]] || fail '請以 root 或 sudo 執行。'
  . /etc/os-release
  case "${ID:-}" in ubuntu|debian) ;; *) fail '僅支援 Ubuntu / Debian。' ;; esac
  [[ -d /run/systemd/system ]] || fail '需要正在運作的 systemd。'
  for command in systemctl ss ssh-keyscan dpkg-query grep; do
    command -v "$command" >/dev/null || fail "缺少必要指令：$command"
  done
  ssh22_ok || fail '未能在本機 TCP 22 完成 SSH 握手；請先修復 SSH，本腳本不修改 SSH 埠。'
  if [[ $mode == check ]]; then
    check_status || fail '防護檢查未通過。'
    log '本機 jail 與 nftables 規則檢查通過；未進行真實登入失敗／封鎖測試。'
    return 0
  fi
  for command in apt-get flock mktemp cp mv chmod install; do
    command -v "$command" >/dev/null || fail "缺少必要指令：$command"
  done
  exec 9>/run/lock/fail2ban-ssh22.lock
  flock -n 9 || fail '另一個設定工作正在執行。'
  trap cleanup EXIT

  if ! packages_ok; then
    apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends \
      -o DPkg::Lock::Timeout=60 -o Dpkg::Options::=--force-confold \
      install fail2ban nftables python3-systemd
  fi
  python3 -c 'from systemd import journal' || fail '無法載入 systemd journal Python 模組。'
  nft list ruleset >/dev/null || fail '無法操作 nftables；請確認核心支援與主機 NET_ADMIN 權限。'
  [[ -f /etc/fail2ban/action.d/nftables.conf ]] || fail '目前 Fail2ban 缺少 nftables action。'
  # Do not overwrite a pre-existing file owned by another administrator/tool.
  [[ ! -L $CONFIG ]] || fail '設定檔是符號連結，拒絕覆寫。'
  if [[ -e $CONFIG ]]; then
    [[ -f $CONFIG ]] || fail '設定路徑不是一般檔案。'
    grep -Fxq "$MARKER" "$CONFIG" || fail '同名設定檔不屬於本腳本，請先手動確認。'
    HAD_CONFIG=true
  fi
  BACKUP=$(mktemp -d /var/backups/fail2ban-ssh22.XXXXXX)
  cp -a -- /etc/fail2ban "$BACKUP/"
  if $HAD_CONFIG; then cp -p -- "$CONFIG" "$BACKUP/99-ssh-port22.local"; fi
  log "既有 Fail2ban 設定已備份：$BACKUP"
  install -d -m 755 /etc/fail2ban/jail.d
  TEMP_CONFIG=$(mktemp /etc/fail2ban/jail.d/.ssh22.XXXXXX)
  render_config > "$TEMP_CONFIG"
  chmod 644 "$TEMP_CONFIG"
  PENDING=true
  mv -f -- "$TEMP_CONFIG" "$CONFIG"
  TEMP_CONFIG=''
  fail2ban-client -t || fail '設定驗證失敗，停止套用。'
  # Reload only our jail. Do not restart SSH, UFW or nftables.service.
  if systemctl is-active --quiet fail2ban; then
    fail2ban-client reload --restart "$JAIL"
  else
    systemctl start fail2ban
  fi
  for attempt in 1 2 3 4 5; do
    if check_status; then
      systemctl enable fail2ban
      PENDING=false
      log '完成：10 分鐘內 5 次失敗，封鎖來源 IP 的 TCP 22 一小時。'
      log '未設定個人 IP 白名單。請保留目前連線，另開終端確認登入。'
      log "查看：sudo fail2ban-client status $JAIL"
      return 0
    fi
    sleep 2
  done
  journalctl --no-pager -n 50 -u fail2ban >&2 || true
  fail '套用後檢查失敗。'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
