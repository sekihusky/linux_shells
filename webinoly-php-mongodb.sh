#!/bin/bash
#
# Install MongoDB PHP extension for Webinoly (PHP-FPM + Nginx)
# Supports PHP 8.3 / 8.4
#

set -e

# 偵測 PHP 版本（優先偵測 fpm）
PHP_VERSION=$(ls /etc/php | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -n1)

if [ -z "$PHP_VERSION" ]; then
    echo "❌ 找不到已安裝的 PHP 版本，請先安裝 Webinoly (包含 PHP-FPM)"
    exit 1
fi

echo "✅ 偵測到 PHP 版本: $PHP_VERSION"

# 安裝必要套件
echo "📦 安裝必要套件..."
sudo apt update
sudo apt install -y php${PHP_VERSION}-dev php-pear pkg-config libssl-dev

# 安裝 MongoDB extension
echo "🔧 安裝 MongoDB PHP extension..."
yes '' | sudo pecl install -f mongodb

# 啟用 extension
INI_FPM="/etc/php/${PHP_VERSION}/fpm/conf.d/20-mongodb.ini"
INI_CLI="/etc/php/${PHP_VERSION}/cli/conf.d/20-mongodb.ini"

echo "extension=mongodb.so" | sudo tee $INI_FPM > /dev/null
echo "extension=mongodb.so" | sudo tee $INI_CLI > /dev/null

echo "✅ MongoDB extension 已寫入:"
echo " - $INI_FPM"
echo " - $INI_CLI"

# 重啟服務
echo "🔄 重啟 PHP-FPM 及 Nginx..."
sudo systemctl restart php${PHP_VERSION}-fpm
sudo systemctl restart nginx

echo "🎉 完成！請在網站目錄放置 phpinfo() 檔案驗證 MongoDB extension 是否已啟用。"
