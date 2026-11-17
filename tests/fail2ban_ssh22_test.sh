#!/bin/bash
# No real package, firewall or Fail2ban commands are executed.
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../fail2ban_ssh22.sh"
fixture_listener='LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=3,fd=4))'
fixture_host=127.0.0.1
fixture_handshake=true
fixture_rules='type filter hook input priority -1; policy accept;
tcp dport 22 ip saddr @addr-set-sshd-port22 reject'
fixture_package=true
fixture_retry=5
fixture_active=true
ss() { printf '%s\n' "$fixture_listener"; }
ssh-keyscan() {
  [[ $* == "-T 5 -p 22 $fixture_host" ]] || return 1
  $fixture_handshake || return 1
  printf 'host ssh-ed25519 test-key\n'
}
nft() { printf '%s\n' "$fixture_rules"; }
dpkg-query() { $fixture_package && printf 'install ok installed'; }
systemctl() { [[ $1 == is-active ]] && $fixture_active; }
fail2ban-client() {
  case "$*" in
    -t|ping|"status sshd-port22") return 0 ;;
    'get sshd-port22 maxretry') printf '%s\n' "$fixture_retry" ;;
    'get sshd-port22 findtime') printf '600\n' ;;
    'get sshd-port22 bantime') printf '3600\n' ;;
    'get sshd-port22 journalmatch') printf '_COMM=sshd\n' ;;
    *) printf 'Unexpected client operation: %s\n' "$*" >&2; return 1 ;;
  esac
}

ssh22_ok
printf 'PASS: SSH IPv4 port 22 handshake\n'
fixture_host=::1
fixture_listener='LISTEN 0 128 [::]:22 [::]:* users:(("systemd",pid=1,fd=4))'
ssh22_ok
printf 'PASS: SSH IPv6 socket handshake\n'
fixture_handshake=false
if ssh22_ok; then exit 1; fi
fixture_handshake=true
printf 'PASS: failed handshake rejected\n'
fixture_listener='LISTEN 0 128 [::]:2222 [::]:* users:(("sshd",pid=3,fd=4))'
if ssh22_ok; then exit 1; fi
printf 'PASS: non-22 port rejected\n'
check_status
printf 'PASS: installed active jail and TCP 22 rule\n'
fixture_rules='type filter hook input priority -1; policy accept;
tcp dport 2222 ip saddr @addr-set-sshd-port22 reject'
if rules_ok; then exit 1; fi
printf 'PASS: wrong firewall port rejected\n'
fixture_rules='type filter hook input priority -1; policy accept;
tcp dport 22 ip saddr @addr-set-other reject'
if rules_ok; then exit 1; fi
printf 'PASS: unrelated ban set rejected\n'
fixture_rules='type filter hook input priority -1; policy accept;
tcp dport 22 ip6 saddr @addr6-set-sshd-port22 reject'
rules_ok
printf 'PASS: IPv6 ban rule\n'
fixture_retry=99
if check_status; then exit 1; fi
fixture_retry=5
printf 'PASS: unexpected live threshold rejected\n'
fixture_package=false
if packages_ok; then exit 1; fi
fixture_package=true
printf 'PASS: missing package rejected\n'
config_text=$(render_config)
for required in 'backend = systemd' 'maxretry = 5' 'findtime = 600' 'bantime = 3600' 'ignoreip = 127.0.0.0/8 ::1' 'actionstart_on_demand=false'; do
  [[ $config_text == *"$required"* ]]
done
[[ $config_text != *ufw* ]]
printf 'PASS: journal backend, thresholds and non-UFW action\n'

# Test both rollback branches with isolated temporary files.
fixture_active=false
fixture_dir=$(mktemp -d)
CONFIG="$fixture_dir/jail.local"
BACKUP="$fixture_dir"
trap 'rm -f -- "$fixture_dir/jail.local" "$fixture_dir/99-ssh-port22.local"; rmdir -- "$fixture_dir"' EXIT
printf 'original\n' > "$BACKUP/99-ssh-port22.local"
printf 'replacement\n' > "$CONFIG"
HAD_CONFIG=true
rollback
[[ $(cat "$CONFIG") == original ]]
printf 'PASS: existing configuration restored on failure\n'
HAD_CONFIG=false
rollback
[[ ! -e $CONFIG ]]
printf 'PASS: new configuration removed on failure\n'
