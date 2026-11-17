# linux_shells

Linux 主機維運用 Bash 腳本集合，涵蓋 SSH 帳號、公鑰、防火牆、資料庫連線檢查與服務監控。主要用於 Ubuntu／Debian，以及 CloudPanel、Webinoly 主機；各支腳本的環境需求不同，請依用途選用。

## 取得與更新

首次下載（須已設定 GitHub SSH 金鑰）：

```bash
git clone git@github.com:sekihusky/linux_shells.git
cd linux_shells
```

更新既有儲存庫：

```bash
cd /你的路徑/linux_shells
git pull --ff-only
```

若主機上修改過腳本設定，更新前先用 `git status` 檢查，保留本機變更後再整合更新。

### 範例：在 Linux 主機下載並使用 add_user_key.sh

若儲存庫為公開狀態，可使用 `curl` 單獨下載，不需要安裝 Git 或設定 GitHub SSH 金鑰。在 Linux 主機的終端執行：

```bash
# 下載 main 分支的腳本到獨立暫存目錄，並檢查 Bash 語法
script_dir=$(mktemp -d) && \
  curl -fL --output "$script_dir/add_user_key.sh" \
    https://raw.githubusercontent.com/sekihusky/linux_shells/main/add_user_key.sh && \
  bash -n "$script_dir/add_user_key.sh"
```

確認下載與語法檢查成功後，在同一個終端查看內容並執行：

```bash
cat "$script_dir/add_user_key.sh"
sudo bash "$script_dir/add_user_key.sh"
```

依提示輸入帳號、貼上 SSH **公鑰**，並選擇是否授予 sudo 權限；既有帳號可選擇是否重設密碼。以 `bash` 執行不需要另外設定 `chmod +x`。若已用 root 登入，可省略 `sudo`。

完成後，保留目前連線，在自己的電腦另開終端測試（替換帳號、主機 IP 與私鑰路徑）：

```bash
ssh -i ~/.ssh/id_ed25519 your_user@your_server_ip
```

若儲存庫是私人儲存庫，請改用上方的 SSH `git clone` 方式；該 Linux 主機須具備儲存庫存取權限。進入下載的 `linux_shells` 目錄後執行 `sudo bash add_user_key.sh`。

## 腳本索引

### 帳號、SSH 與網路

| 腳本 | 功能 | 使用前確認 |
| --- | --- | --- |
| [add_user_key.sh](add_user_key.sh) | 建立或更新帳號、附加 SSH 公鑰，可選擇授予 sudo 權限 | Ubuntu／Debian；需要 root、`ssh-keygen`；互動式執行 |
| [check_smtp_block.sh](check_smtp_block.sh) | 檢查並新增對外 TCP 25 封鎖規則 | Ubuntu 使用 UFW，其他系統使用 iptables／ip6tables；會影響直接透過 TCP 25 寄信 |
| [ipv6.sh](ipv6.sh) | 互動式停用、恢復 IPv6 或查看位址 | 修改即時 sysctl 與 `/etc/sysctl.conf`；原設計用於 Ubuntu 24 |
| [cf_update.sh](cf_update.sh) | 取得 Cloudflare IP 清單，產生 Nginx 真實來源 IP 設定 | 需要 `curl`、Nginx；覆寫 `/etc/nginx/conf.d/cloudflare.conf`，通過 `nginx -t` 後重啟 Nginx |

### 資料庫連線檢查

| 腳本 | 功能 | 使用前確認 |
| --- | --- | --- |
| [chk-db.sh](chk-db.sh) | 檢查資料庫 TCP 連線，失敗時嘗試重啟本機 MariaDB／MySQL 並寄信 | 設定 `HOST`、`PORT`、`EMAIL`；需要 systemd、MySQL 用戶端與已設定的 `mail`；不驗證 SQL 查詢 |

### CloudPanel 與 Webinoly

| 腳本 | 功能 | 使用前確認 |
| --- | --- | --- |
| [cloudpanel-watchdog.sh](cloudpanel-watchdog.sh) | 檢查偵測到的 Nginx、PHP-FPM、MariaDB／MySQL 服務，異常時嘗試重啟 | CloudPanel／systemd；日誌為 `/var/log/cloudpanel-watchdog.log` |
| [health-php.sh](health-php.sh) | 依 `PHP_VERSIONS` 檢查 PHP-FPM，異常時嘗試重啟 | CloudPanel／Ubuntu；依實際安裝版本調整清單 |
| [webinoly-watchdog.sh](webinoly-watchdog.sh) | 偵測 Nginx、PHP-FPM、MariaDB／MySQL，檢查並嘗試重啟服務 | Webinoly／systemd；日誌為 `/var/log/webinoly-watchdog.log` |
| [webinoly-php-mongodb.sh](webinoly-php-mongodb.sh) | 從 `/etc/php` 選取最高版本，透過 PECL 安裝 MongoDB PHP 擴充，啟用 FPM／CLI 設定 | Webinoly／APT 環境；確認選到的 PHP 版本與實際網站一致；會安裝套件並重啟 PHP-FPM、Nginx |

監控腳本以服務狀態或 TCP 連線為判斷依據，並非完整的網站健康檢查。`cloudpanel-watchdog.sh` 與 `health-php.sh` 使用 `systemctl list-units` 探索服務，可能略過未載入的服務。

## IP、主機與存取設定

目前目錄中的腳本沒有寫死的個別 IP 位址，也沒有 SSH／SFTP 使用者白名單。部署前仍需確認以下設定：

| 腳本 | 設定位置 | 說明 |
| --- | --- | --- |
| [cf_update.sh](cf_update.sh) | `CF_IPV4`、`CF_IPV6`、`set_real_ip_from` | 從 Cloudflare 官方端點動態取得 IP 清單，設定 Nginx 信任的代理來源；不是 SSH 或防火牆白名單 |
| [chk-db.sh](chk-db.sh) | `HOST=localhost`、`PORT=3306` | 預設檢查本機資料庫；若改成遠端主機，失敗時腳本仍會嘗試重啟本機資料庫服務 |
| [check_smtp_block.sh](check_smtp_block.sh) | UFW／iptables 的 OUTPUT 規則 | 封鎖對任意目的位址的 TCP 25，沒有指定來源或目的 IP 白名單 |
| [add_user_key.sh](add_user_key.sh) | 執行時輸入帳號與公鑰 | 未預設個別使用者或 IP 白名單；SSH 來源限制由主機另行設定 |

## 執行方式

先閱讀要使用的腳本，調整其中的路徑、帳號、主機位址或版本設定。使用 Bash 執行，不要以 `sh` 取代：

```bash
# 僅檢查語法，不執行腳本
bash -n add_user_key.sh

# 執行帳號與公鑰設定
sudo bash add_user_key.sh
```

涉及帳號、防火牆、系統設定與服務重啟的腳本通常需要 root 權限。

從 Windows 複製腳本時，請使用 UTF-8（無 BOM）與 LF 換行。`.gitattributes` 已固定 `add_user_key.sh` 使用 LF；其他腳本仍需確認。若遇到 `$'\r': command not found`，可針對該檔案轉換，例如：

```bash
sed -i 's/\r$//' add_user_key.sh
bash -n add_user_key.sh
```

### 新增 SSH 公鑰

執行 `sudo bash add_user_key.sh` 後，依提示輸入帳號名稱及一行原始 SSH 公鑰：

- 新帳號：建立家目錄與 Bash shell，並要求設定密碼。
- 既有帳號：可選擇是否重設密碼，預設不重設。
- sudo 權限：另行詢問，預設不新增；不會撤銷既有權限。
- 公鑰：驗證格式後附加至 `~/.ssh/authorized_keys`；保留既有內容，已存在的金鑰不重複加入。
- 備份：修改既有金鑰檔前，在同一 `.ssh` 目錄建立 `authorized_keys.backup.*`。
- 權限：只調整 `.ssh` 與金鑰檔，不遞迴修改整個家目錄；拒絕 UID 0 帳號及檢查到的異常路徑。

若中途失敗，已完成的變更不會自動復原。完成後保留目前連線，另開終端測試登入；實際 SSH 與 sudo 權限仍依主機的 sshd／sudoers 設定。

## 排程範例

以下假設腳本放在 `/root/linux_shells`。先手動確認成功，再選用需要的排程；CloudPanel 與 Webinoly watchdog 選擇符合主機環境的一種。

編輯 `/etc/crontab`，此格式包含執行帳號欄位：

```cron
# 每分鐘執行 Webinoly 服務檢查；腳本本身會寫入日誌
* * * * * root /usr/bin/flock -n /run/lock/webinoly-watchdog.lock /bin/bash /root/linux_shells/webinoly-watchdog.sh >/dev/null 2>&1

# 或每分鐘執行 CloudPanel 服務檢查；腳本本身會寫入日誌
# * * * * * root /usr/bin/flock -n /run/lock/cloudpanel-watchdog.lock /bin/bash /root/linux_shells/cloudpanel-watchdog.sh >/dev/null 2>&1
```

`flock` 用來避免同一工作重疊執行，部署前確認 `/usr/bin/flock` 存在。若使用 `sudo crontab -e`，須移除每行的 `root` 欄位。日誌請搭配 logrotate 管理。

`add_user_key.sh` 與 `ipv6.sh` 需要互動輸入，不適合直接放進 cron。防火牆腳本會修改規則，請先核對設定與實際執行結果，再決定是否排程。
