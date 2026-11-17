#!/bin/bash
# Mocked checks only: no package installation, systemd changes or SSH changes.
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../ssh_self_check.sh"

fixture_socket_active=false
service_active=true
fixture_socket_listen=''
fixture_listeners=''
expected_host=127.0.0.1
expected_port=22
handshake_ok=true
installed=true
valid_config=true

dpkg-query() { $installed && printf 'install ok installed'; }
sshd() { $valid_config; }
ss() { printf '%s\n' "$fixture_listeners"; }
systemctl() {
  case "$1" in
    is-active)
      case "${*: -1}" in ssh.socket) $fixture_socket_active ;; ssh.service) $service_active ;; *) return 1 ;; esac ;;
    show) printf '%s\n' "$fixture_socket_listen" ;;
    *) printf 'Unexpected systemctl mutation\n' >&2; exit 90 ;;
  esac
}
ssh-keyscan() {
  [[ $* == "-T 5 -p $expected_port $expected_host" ]] || return 1
  $handshake_ok || return 1
  printf 'mock-host ssh-ed25519 mock-key\n'
}

fixture_listeners='LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=123,fd=3))'
healthy
printf 'PASS: healthy service and IPv4 wildcard\n'
expected_port=2222
fixture_listeners='LISTEN 0 128 [::]:2222 [::]:* users:(("sshd",pid=123,fd=3))'
expected_host=::1
healthy
printf 'PASS: custom port and IPv6 wildcard\n'
expected_host=192.0.2.10
fixture_listeners='LISTEN 0 128 192.0.2.10:2222 0.0.0.0:* users:(("sshd",pid=123,fd=3))'
healthy
printf 'PASS: specific listen address\n'
service_active=false
fixture_socket_active=true
fixture_socket_listen='[::]:2222 (Stream)'
expected_host=::1
fixture_listeners='LISTEN 0 128 [::]:2222 [::]:* users:(("systemd",pid=1,fd=3))'
healthy
printf 'PASS: socket activation\n'
fixture_socket_listen='[::]:22 (Stream)'
if healthy; then printf 'FAIL: accepted unrelated systemd listener\n'; exit 1; fi
printf 'PASS: unrelated systemd listener rejected\n'
fixture_socket_listen='[::]:2222 (Stream)'
handshake_ok=false
if healthy; then printf 'FAIL: accepted failed handshake\n'; exit 1; fi
handshake_ok=true
printf 'PASS: failed handshake rejected\n'
valid_config=false
if healthy; then printf 'FAIL: accepted invalid config\n'; exit 1; fi
valid_config=true
printf 'PASS: invalid config rejected\n'
installed=false
if healthy; then printf 'FAIL: accepted missing package\n'; exit 1; fi
installed=true
printf 'PASS: missing package rejected\n'
fixture_socket_active=false
if healthy; then printf 'FAIL: accepted stopped units\n'; exit 1; fi
printf 'PASS: stopped units rejected\n'

apt_calls=0
apt_update_ok=true
apt-get() {
  apt_calls=$((apt_calls + 1))
  if [[ ${*: -1} == update ]]; then
    $apt_update_ok
  else
    [[ ${DEBIAN_FRONTEND:-} == noninteractive ]] || return 1
    [[ " $* " == *' --reinstall install openssh-server openssh-client '* ]] || return 1
    [[ " $* " == *' -o Dpkg::Options::=--force-confold '* ]] || return 1
    [[ " $* " == *' -o Dpkg::Options::=--force-confmiss '* ]] || return 1
    [[ " $* " != *purge* ]] || return 1
  fi
}
install_server
[[ $apt_calls == 2 ]]
printf 'PASS: reinstall preserves configuration and installs both packages\n'
apt_calls=0
apt_update_ok=false
if install_server; then printf 'FAIL: accepted APT index failure\n'; exit 1; fi
[[ $apt_calls == 1 ]]
printf 'PASS: APT index failure stops before reinstall\n'
