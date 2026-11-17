#!/bin/bash
# Ubuntu / Debian: create a user or append an SSH public key.
# Run interactively: sudo bash add_user_key.sh
set -Eeuo pipefail
umask 077

fail() { printf '錯誤：%s\n' "$*" >&2; exit 1; }
trap 'printf "操作失敗（第 %s 行），已完成的變更不會自動復原。\n" "$LINENO" >&2' ERR
[[ $EUID -eq 0 ]] || fail '請使用 sudo bash add_user_key.sh 執行。'
for command in getent id ssh-keygen mktemp awk stat cp mv install useradd usermod passwd; do
  command -v "$command" >/dev/null || fail "缺少必要指令：$command"
done

confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer || fail '輸入已中斷。'
  [[ $answer == y || $answer == Y ]]
}

read -r -p '請輸入使用者名稱: ' username || fail '輸入已中斷。'
[[ $username =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || fail '帳號須以小寫字母或底線開頭，只能包含小寫字母、數字、底線、連字號，最多 32 字元。'
existing=false
if id "$username" >/dev/null 2>&1; then
  existing=true
  [[ $(id -u "$username") -ne 0 ]] || fail '此腳本不處理 root 或其他 UID 0 帳號。'
fi

printf '請貼上一行 SSH 公鑰（例如 ssh-ed25519 AAAA... comment）：\n'
IFS= read -r ssh_key || fail '輸入已中斷。'
ssh_key=${ssh_key%$'\r'}
read -r key_type key_blob key_comment <<< "$ssh_key"
case "$key_type" in
  ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
  *) fail '請輸入原始公鑰；不接受私鑰、authorized_keys 選項或不支援的金鑰類型。' ;;
esac
[[ -n ${key_blob:-} ]] || fail '公鑰內容不能為空。'
work_dir=$(mktemp -d)
staged_file=''
cleanup() {
  [[ -z $staged_file ]] || rm -f -- "$staged_file"
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
printf '%s\n' "$ssh_key" > "$work_dir/key.pub"
ssh-keygen -lf "$work_dir/key.pub" || fail 'SSH 公鑰格式無效。'

set_password=false
grant_sudo=false
if $existing; then
  if confirm '是否重設既有帳號密碼？'; then set_password=true; fi
else
  printf '將建立新帳號，必須設定密碼以供 sudo 等操作使用。\n'
  set_password=true
fi
if confirm '是否授予管理員 sudo 權限？'; then
  command -v sudo >/dev/null || fail '請先安裝並設定 sudo。'
  getent group sudo >/dev/null || fail '找不到 sudo 群組；此腳本適用 Ubuntu / Debian。'
  grant_sudo=true
fi

if ! $existing; then
  useradd -m -U -s /bin/bash "$username"
fi
account=$(getent passwd "$username") || fail '找不到帳號資料。'
IFS=: read -r account_name account_password user_uid user_gid account_gecos user_home user_shell <<< "$account"
[[ $user_home == /* && $user_home != / && -d $user_home && ! -L $user_home ]] || fail '家目錄必須是已存在的絕對路徑，且不能為 / 或符號連結。'
[[ $(stat -c %u -- "$user_home") == "$user_uid" ]] || fail '家目錄擁有者不是該使用者，請先手動確認。'
home_mode=$(stat -c %a -- "$user_home")
(( (8#$home_mode & 0022) == 0 )) || fail '家目錄可被群組或其他人寫入，請先手動修正。'

ssh_dir="$user_home/.ssh"
auth_file="$ssh_dir/authorized_keys"
[[ ! -L $ssh_dir && ! -L $auth_file ]] || fail '.ssh 或 authorized_keys 是符號連結，拒絕修改。'
[[ ! -e $ssh_dir || -d $ssh_dir ]] || fail '.ssh 不是目錄。'
[[ ! -e $auth_file || -f $auth_file ]] || fail 'authorized_keys 不是一般檔案。'
if [[ -e $auth_file ]]; then
  [[ $(stat -c %h -- "$auth_file") == 1 ]] || fail 'authorized_keys 有硬連結，拒絕修改。'
fi

if $set_password; then passwd "$username"; fi
install -d -m 700 -o "$user_uid" -g "$user_gid" -- "$ssh_dir"
# Match key material, including existing entries with restrictions. Do not
# append an unrestricted duplicate of a restricted key.
if [[ -f $auth_file ]] && awk -v type="$key_type" -v blob="$key_blob" '
  /^[[:space:]]*#/ { next }
  { for (i=1; i<NF; i++) if ($i == type && $(i+1) == blob) found=1 }
  END { exit !found }
' "$auth_file"; then
  printf '此公鑰已存在，保留原本的內容與限制。\n'
else
  staged_file=$(mktemp "$ssh_dir/.authorized_keys.XXXXXX")
  if [[ -f $auth_file ]]; then
    backup_file=$(mktemp "$ssh_dir/authorized_keys.backup.XXXXXX")
    cp -- "$auth_file" "$backup_file"
    chmod 600 -- "$backup_file"
    printf '原有金鑰已備份至：%s\n' "$backup_file"
    cat -- "$auth_file" > "$staged_file"
    # A blank separator also handles an existing file without a final newline.
    printf '\n' >> "$staged_file"
  fi
  printf '%s\n' "$ssh_key" >> "$staged_file"
  chown "$user_uid:$user_gid" -- "$staged_file"
  chmod 600 -- "$staged_file"
  mv -f -- "$staged_file" "$auth_file"
  staged_file=''
fi
chown "$user_uid:$user_gid" -- "$auth_file"
chmod 600 -- "$auth_file"
if $grant_sudo; then usermod -aG sudo "$username"; fi

printf '\n完成：%s 的公鑰已設定於 %s\n' "$username" "$auth_file"
if $set_password; then printf '密碼設定成功。\n'; fi
if $grant_sudo; then printf '已加入 sudo 群組；實際權限依主機 sudoers 設定。\n'; fi
printf '請保留目前連線，另開終端測試 SSH 登入；實際登入仍依 sshd 設定。\n'
