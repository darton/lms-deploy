#!/bin/bash

# Use to Alma Linux 9 Minimal Server version.

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be executed as root or using sudo"
  exit 99
fi

systemd="$(ps --no-headers -o comm 1)"
if [ ! "${systemd}" = "systemd" ]; then
  echo "This system is not running systemd.  Exiting..."
  exit 100
fi


#####config###

enable_ssl=no

FQDN=localhost
WEBMASTER_EMAIL="hostmaster@localhost"
export APP_DIR=/var/www/app
export LMS_DIR="${APP_DIR}"/lms
export BACKUP_DIR=/mnt/backup

shell_user=lms
shell_group=lms
shell_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c8)

lms_db_host=localhost
lms_db_user=lms
lms_db_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
lms_db=lms

#####install#####
dnf update -y

dnf install httpd -y

dnf install mariadb -y
dnf install mariadb-server -y

dnf install firewalld -y

dnf install git -y
dnf install vi -y
dnf install unzip -y
dnf install wget -y
dnf install file -y
dnf install bc -y
dnf install rsync -y
dnf install postfix -y
dnf install s-nail -y
dnf install glibc-gconv-extra -y

dnf install flex -y
dnf install bison -y

dnf install perl-Config-IniFiles -y
dnf install perl-Mail-Sender -y
dnf install perl-DBD-MySQL -y

dnf install -y 'dnf-command(config-manager)'
dnf config-manager --set-enabled crb -y
dnf install mariadb-devel -y
dnf install libfl-static -y

dnf install setroubleshoot-server -y

dnf install epel-release -y
dnf install certbot python3-certbot-apache -y

#PHP
dnf module reset php -y
dnf module enable php:8.3 -y
dnf distro-sync -y
dnf install -y php php-cli php-common php-fpm \
php-mysqlnd php-gd php-xml php-soap \
php-mbstring php-intl php-process php-opcache \
php-zip php-bcmath php-snmp php-devel php-pecl-zip php-gmp


sed  's/^\([^#]\)/#\1/g' -i /etc/httpd/conf.d/welcome.conf
install -o root -g root -m 644 /dev/null /var/www/html/index.html

echo "date.timezone =Europe/Warsaw" >> /etc/php.ini

install -d -o root -g root -m 755 /etc/lms

cat > /etc/lms/lms.ini << EOF
[database]
type = mysql
host = $lms_db_host
user = $lms_db_user
password = $lms_db_password
database = $lms_db

[directories]
sys_dir = $LMS_DIR
backup_dir = $BACKUP_DIR
userpanel_dir = $LMS_DIR/userpanel
EOF

useradd $shell_user
echo "$shell_user:$shell_password" |chpasswd

install -d \
-o "$shell_user" \
-g "$shell_group" \
-m 755 \
"$APP_DIR"

su $shell_user -c "cd ${APP_DIR}; git clone https://github.com/lmsgit/lms.git" || exit 1
su $shell_user -c "cd ${LMS_DIR}; curl -sS https://getcomposer.org/installer | php" || exit 1
su $shell_user -c "cd ${LMS_DIR}; ${LMS_DIR}/composer.phar install" || exit 1

install -d \
-o "$shell_user" \
-g "$shell_group" \
-m 755 \
"$LMS_DIR/var"

install -d \
-o "$shell_user" \
-g "$shell_group" \
-m 770 \
"$LMS_DIR/var/tmp" \
"$LMS_DIR/var/sessions"

install -d \
-o "$shell_user" \
-g "$shell_group" \
-m 750 \
"${BACKUP_DIR}"

install -d \
-o "$shell_user" \
-g "$shell_group" \
-m 755 \
"${LMS_DIR}/js/xajax_js/deferred"

cat > /etc/httpd/conf.d/lms.conf <<EOF
<VirtualHost *:80>
  ServerAdmin ${WEBMASTER_EMAIL}
  DocumentRoot ${LMS_DIR}
  ServerName ${FQDN}
  ErrorLog logs/${FQDN}-error_log
  CustomLog logs/${FQDN}-access_log common
  
  DirectoryIndex index.php index.html
  
  <FilesMatch \.php$>
    SetHandler "proxy:unix:/run/php-fpm/php-fpm-lms.sock|fcgi://localhost/"
  </FilesMatch>
</VirtualHost>
EOF

cat > /etc/php-fpm.d/lms.conf <<EOF
[lms]

user = lms
group = lms

listen = /run/php-fpm/php-fpm-lms.sock
listen.acl_users = apache

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6

php_admin_value[open_basedir] = ${LMS_DIR}:/etc/lms/lms.ini:${APP_DIR}/var/sessions:${APP_DIR}/var/tmp:${BACKUP_DIR}
php_admin_value[session.save_path] = ${APP_DIR}/var/sessions
php_admin_value[upload_tmp_dir] = ${APP_DIR}/var/tmp
php_admin_value[sys_tmp_dir] = ${APP_DIR}/var/tmp
php_admin_value[memory_limit] = 512M
php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[max_execution_time] = 120
EOF

mv /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.conf.disabled
mv /etc/httpd/conf.d/php.conf /etc/httpd/conf.d/php.conf.disabled

systemctl enable --now firewalld
systemctl enable --now mariadb

php-fpm -t && systemctl enable --now php-fpm

mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$lms_db\` CHARACTER SET utf8 COLLATE utf8_polish_ci;"
mysql -u root -e "CREATE USER IF NOT EXISTS '$lms_db_user'@'$lms_db_host' IDENTIFIED BY '$lms_db_password';"
mysql -u root -e "GRANT ALL PRIVILEGES ON \`$lms_db\`.* TO '$lms_db_user'@'$lms_db_host';"
mysql -u root -e "FLUSH PRIVILEGES;"

mysql -u root -e "use $lms_db; source $LMS_DIR/doc/lms.mysql;"

firewall-cmd --zone=public --add-service=http
firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --reload

echo
echo "LMS DIR $LMS_DIR"
echo "LMS shell user account: $shell_user"
echo "LMS shell user password: $shell_password"

cd "${LMS_DIR}"/daemon

./configure --with-mysql --enable-debug0 --enable-debug1
make && make install

cat > /etc/systemd/system/lmsd.service <<EOF
[Unit]
Description=LMS Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/lmsd/bin/lmsd -f -C /etc/lms/lms.ini
Restart=on-failure
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lmsd.service
systemctl start lmsd.service

selinux_status=$(getenforce)

if [[ $selinux_status == Enforcing ]]
then
  systemctl enable --now setroubleshootd
  semanage fcontext -a -t httpd_sys_rw_content_t "$BACKUP_DIR(/.*)?"
  semanage fcontext -a -e /var/www/html "${APP_DIR}"
  semanage fcontext -a -t httpd_sys_rw_content_t "${APP_DIR}/var/sessions(/.*)?"
  semanage fcontext -a -t httpd_sys_rw_content_t "${APP_DIR}/var/tmp(/.*)?"
  semanage fcontext -a -t httpd_sys_rw_content_t "${LMS_DIR}/js/xajax_js/deferred(/.*)?"
  restorecon -R "${APP_DIR}"
  restorecon -R "$BACKUP_DIR"
fi

systemctl start httpd && systemctl enable httpd

if [ $enable_ssl == yes ]
then
  wget http://$FQDN/
  echo "run command ausearch -c 'httpd' --raw | audit2allow -M my-httpd; semodule -i my-httpd.pp"
  
  firewall-cmd --zone=public --add-service=https
  firewall-cmd --zone=public --permanent --add-service=https
  firewall-cmd --reload
  
  certbot --apache -d $FQDN
  systemctl restart httpd.service
else
  echo "If you want using SSL encryption later, run:"
  echo
  echo "firewall-cmd --zone=public --add-service=https"
  echo "firewall-cmd --zone=public --permanent --add-service=https"
  echo "certbot --apache -d $FQDN"
  echo "systemctl restart httpd.service"
fi

echo "Run mysql_secure_installation"
