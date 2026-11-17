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

### 範例：已登入 Linux，直接下載單支腳本

假設你已經在 Linux 主機的終端，想從這個公開 GitHub 儲存庫下載 `add_user_key.sh` 使用，不需要 clone 整個專案，也不需要 GitHub SSH 金鑰。

直接複製以下指令，會下載到目前目錄，語法檢查通過後執行（若已有同名檔案會覆蓋）：

```bash
curl -fL -o add_user_key.sh https://raw.githubusercontent.com/sekihusky/linux_shells/main/add_user_key.sh && \
  bash -n add_user_key.sh && \
  sudo bash add_user_key.sh
```

如果你已經以 **root** 登入，使用這個版本：

```bash
curl -fL -o add_user_key.sh https://raw.githubusercontent.com/sekihusky/linux_shells/main/add_user_key.sh && \
  bash -n add_user_key.sh && \
  bash add_user_key.sh
```

若只想下載、暫時不執行：

```bash
curl -fL -o add_user_key.sh https://raw.githubusercontent.com/sekihusky/linux_shells/main/add_user_key.sh
```

需要下載其他腳本時，將上方「只下載」指令中的兩處 `add_user_key.sh` 換成該腳本的實際檔名。若出現 `curl: command not found`，Ubuntu／Debian 可先執行 `sudo apt update && sudo apt install -y curl`（root 可省略 `sudo`）。

執行後依提示輸入帳號、貼上 SSH **公鑰**，並選擇是否授予 sudo 權限；既有帳號可選擇是否重設密碼。以 `bash` 執行不需要另外設定 `chmod +x`。

完成後保留目前連線，在自己的電腦另開終端測試（替換帳號、主機 IP 與私鑰路徑）：

```bash
ssh -i ~/.ssh/id_ed25519 your_user@your_server_ip
```

## 腳本索引

### 帳號、SSH 與網路

| 腳本 | 功能 | 使用前確認 |
| --- | --- | --- |
| [add_user_key.sh](add_user_key.sh) | 建立或更新帳號、附加 SSH 公鑰，可選擇授予 sudo 權限 | Ubuntu／Debian；需要 root、`ssh-keygen`；互動式執行 |
| [fail2ban_ssh22.sh](fail2ban_ssh22.sh) | 檢查並安裝 Fail2ban，以 nftables 封鎖 SSH TCP 22 的重複登入失敗來源 | Ubuntu／Debian + systemd；需要 root 與主機防火牆權限；不依賴 UFW；支援 `--check` |
| [ssh_self_check.sh](ssh_self_check.sh) | 檢查 SSH 套件、設定、服務與本機握手；異常時嘗試啟動，必要時重新安裝 OpenSSH | Ubuntu／Debian + systemd；需要 root；支援 `--check` 僅檢查模式 |
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

目前腳本未預設個人或公網 IP 白名單，也沒有 SSH／SFTP 使用者白名單。SSH 自我檢查使用回環位址測試本機服務，測試檔另含示範位址。Fail2ban 腳本只預設排除回環與主機自身位址，不加入個人來源 IP 白名單。部署前仍需確認以下設定：

| 腳本 | 設定位置 | 說明 |
| --- | --- | --- |
| [cf_update.sh](cf_update.sh) | `CF_IPV4`、`CF_IPV6`、`set_real_ip_from` | 從 Cloudflare 官方端點動態取得 IP 清單，設定 Nginx 信任的代理來源；不是 SSH 或防火牆白名單 |
| [chk-db.sh](chk-db.sh) | `HOST=localhost`、`PORT=3306` | 預設檢查本機資料庫；若改成遠端主機，失敗時腳本仍會嘗試重啟本機資料庫服務 |
| [fail2ban_ssh22.sh](fail2ban_ssh22.sh) | 檢查並安裝 Fail2ban，以 nftables 封鎖 SSH TCP 22 的重複登入失敗來源 | Ubuntu／Debian + systemd；需要 root 與主機防火牆權限；不依賴 UFW；支援 `--check` |
| [ssh_self_check.sh](ssh_self_check.sh) | 檢查 SSH 套件、設定、服務與本機握手；異常時嘗試啟動，必要時重新安裝 OpenSSH | Ubuntu／Debian + systemd；需要 root；支援 `--check` 僅檢查模式 |
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

從 Windows 複製腳本時，請使用 UTF-8（無 BOM）與 LF 換行。`.gitattributes` 已固定帳號設定、SSH 自我檢查、Fail2ban 腳本及其測試使用 LF；其他腳本仍需確認。若遇到 `$'\r': command not found`，可針對該檔案轉換，例如：

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

### SSH 自我檢查與修復

`ssh_self_check.sh` 適用於使用 systemd 管理標準 `ssh.service`／`ssh.socket` 的 Ubuntu／Debian 主機。預設檢查並修復，正常時不重新安裝。若主機自行指定其他 sshd 設定檔、服務名稱或啟動參數，需先調整腳本，不適合直接套用。

已登入 Linux 後，下載並執行：

```bash
curl -fL -o ssh_self_check.sh https://raw.githubusercontent.com/sekihusky/linux_shells/main/ssh_self_check.sh && \
  bash -n ssh_self_check.sh && \
  sudo bash ssh_self_check.sh
```

只檢查、不安裝套件或重啟服務：

```bash
sudo bash ssh_self_check.sh --check
```

root 已登入時可省略 `sudo`。需要 `ss`（iproute2）；完整握手檢查需要 `ssh-keyscan`（openssh-client），修復模式會與伺服器套件一同安裝。只檢查模式在缺少必要元件時回報失敗。

修復流程：

1. 檢查 `openssh-server` 安裝狀態與 `sshd -t` 設定／主機金鑰檢查。
2. 確認 SSH 服務或 socket 狀態，從實際監聽位址與埠測試 SSH 主機金鑰交換；支援非 22 埠、IPv4／IPv6 與 socket 啟動。
3. 異常時先將 `/etc/ssh` 與現有 `/etc/default/ssh` 備份至 `/var/backups/ssh-self-check.*`，備份目錄僅 root 可讀；補齊 `/run/sshd`，設定有效時先嘗試啟動。
4. 若仍異常，更新 APT 索引並重新安裝 `openssh-server`、`openssh-client`，保留既有設定、補回缺少的套件設定檔；不執行 purge。只產生缺少的預設主機金鑰，不覆蓋現有金鑰。
5. 設定驗證通過後重新啟動並再次檢查。仍有問題時輸出服務狀態與最近日誌，以非零狀態結束，不反覆重裝。

**檢查通過代表至少一個本機 SSH 端點能完成主機金鑰交換**，不代表所有監聽位址、外部網路或個別帳號一定能登入。腳本不修改防火牆、雲端安全群組、使用者公鑰或登入政策，也不強制啟用開機自動啟動。`--check` 的握手可能觸發已啟用的 socket 啟動服務。

若設定本身錯誤，保留設定的重裝不一定能修好；腳本會回報 `sshd -t` 錯誤，請修正後再執行。重新安裝套件可能觸發系統維護腳本重啟 SSH，執行修復時請保留目前連線並備妥主機控制台；完成後另開終端測試登入。缺少或已移除的主機金鑰重新產生後，客戶端可能需要核對新的指紋。

退出狀態：`0` 表示本機檢查通過或修復成功；非零表示檢查／修復失敗。不建議在尚未驗證主機環境前直接排程自動重裝。

開發驗證（模擬指令，不會操作系統 SSH 或 APT）：

```bash
bash -n ssh_self_check.sh
bash tests/ssh_self_check_test.sh
```

檢查與保留設定的行為依據：[sshd 手冊](https://manpages.debian.org/bookworm/openssh-server/sshd.8.en.html)、[ssh-keyscan 手冊](https://manpages.debian.org/bookworm/openssh-client/ssh-keyscan.1.en.html)、[Ubuntu 套件設定檔說明](https://ubuntu.com/server/docs/explanation/software/changing-package-files/)。

### SSH TCP 22 的 Fail2ban 防護（不依賴 UFW）

`fail2ban_ssh22.sh` 適用於無法用固定 IP 白名單限制 SSH 來源、但主機仍可操作 nftables 的 Ubuntu／Debian + systemd 環境。它根據登入失敗紀錄封鎖來源，**不會把 TCP 22 改成只允許白名單，也不會替你開啟被防火牆阻擋的 22 埠**。

在 Linux 主機下載並執行：

```bash
curl -fL -o fail2ban_ssh22.sh https://raw.githubusercontent.com/sekihusky/linux_shells/main/fail2ban_ssh22.sh && \
  bash -n fail2ban_ssh22.sh && \
  sudo bash fail2ban_ssh22.sh
```

只檢查、不安裝或修改設定：

```bash
sudo bash fail2ban_ssh22.sh --check
```

root 已登入時可省略 `sudo`。腳本先驗證本機 TCP 22 的 SSH 握手；需要 `ss`（iproute2）與 `ssh-keyscan`（openssh-client）。若 SSH 尚未運作，先修復 SSH；此腳本不安裝 SSH 或修改其連接埠。

| 項目 | 設定 |
| --- | --- |
| 獨立 jail | `sshd-port22` |
| 設定檔 | `/etc/fail2ban/jail.d/99-ssh-port22.local` |
| 判斷條件 | 同一來源 IP 在 600 秒（10 分鐘）內累計 5 次符合 SSH filter 的失敗 |
| 封鎖時間 | 3600 秒（1 小時） |
| 封鎖範圍 | 該來源 IP 對主機的 TCP 22 |
| 日誌來源 | systemd journal，使用 SSH 單元／程序條件 |
| 封鎖方式 | Fail2ban `nftables` multiport action；獨立 `inet f2b-ssh22` table |
| 忽略來源 | 回環位址 `127.0.0.0/8`、`::1` 與主機自身位址；沒有預設個人 IP 白名單 |

缺少套件時安裝 `fail2ban`、`nftables`、`python3-systemd`。套用前備份 `/etc/fail2ban` 至 `/var/backups/fail2ban-ssh22.*`；設定驗證通過後載入獨立 jail，確認實際 TCP 22 封鎖規則存在，再啟用 Fail2ban 開機自動啟動。腳本不呼叫 UFW、不清空 nftables ruleset，也不重啟 SSH 或 `nftables.service`。

再次執行會將本腳本管理的 jail 還原為上表參數。其他 jail 保留；若主機已有 `sshd` jail，兩者可能同時監控 SSH，封鎖條件依各自設定。套件首次安裝也可能啟動發行版預設 jail。若同名設定檔並非本腳本建立，會停止而不覆寫。

設定或套用檢查失敗時，會嘗試還原本腳本的 jail 設定，已安裝套件仍保留。`--check` 成功只代表本機套件、jail、參數及封鎖規則檢查通過，尚未驗證真實登入失敗是否產生並匹配日誌；握手也可能觸發 `ssh.socket` 啟動 SSH。

查看與管理：

```bash
# 查看失敗次數與已封鎖來源
sudo fail2ban-client status sshd-port22
sudo fail2ban-client get sshd-port22 banip

# 查看實際防火牆規則
sudo nft list table inet f2b-ssh22

# 查看 Fail2ban 與 SSH 日誌
sudo journalctl -u fail2ban -n 50 --no-pager
sudo journalctl -u ssh.service -u sshd.service -n 50 --no-pager

# 解除單一 IP 誤封：將 YOUR_IP 換成實際來源 IP
sudo fail2ban-client set sshd-port22 unbanip YOUR_IP
```

如果該 IP 同時被其他 jail 封鎖，需另外在對應 jail 解除。沒有固定白名單也表示管理員或共用 NAT 出口可能因連續輸錯而被封鎖；安裝時保留目前連線並備妥主機控制台。若主機禁止 nftables／缺少 `NET_ADMIN` 權限，Fail2ban 無法繞過此限制。

此 jail 的日誌 filter 會讀取符合條件的 SSH 失敗紀錄；若 SSH 同時監聽其他埠，其他埠的失敗也可能被計數，但此 jail 只封鎖 TCP 22。它不取代 SSH 公鑰驗證，也不是用來防禦流量型 DDoS。

模擬測試（不操作實際防火牆或套件）：

```bash
bash -n fail2ban_ssh22.sh
bash tests/fail2ban_ssh22_test.sh
```

設定參考：[Fail2ban 官方 jail 設定](https://github.com/fail2ban/fail2ban/blob/1.0.2/config/jail.conf)、[官方 nftables action](https://github.com/fail2ban/fail2ban/blob/1.0.2/config/action.d/nftables.conf)、[fail2ban-client 手冊](https://manpages.debian.org/bookworm/fail2ban/fail2ban-client.1.en.html)。

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
