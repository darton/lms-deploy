# --- KONFIGURACJA ---
DOMAIN ?= lms.example.com

CERT_DIR ?= /etc/pki/tls/certs
KEY_DIR ?= /etc/pki/tls/private

WEB_SERVICE ?= httpd
APP_ROOT ?= /var/www/$(DOMAIN)
APP_USER ?= lms
APP_GROUP ?= lms
WEB_ROOT ?= $(APP_ROOT)/web
BACKUP_DIR ?= /mnt/backup

#Apache
APACHE_CONF_DIR ?= /etc/httpd/conf.d
CONF_FILE ?= $(APACHE_CONF_DIR)/$(DOMAIN).conf

#ACME
ACME_SH ?= /root/.acme.sh/acme.sh
DNS_PLUGIN ?= dns_ispconfig
DNS_SLEEP ?= 20

# PHP-FPM
PHP_FPM_DIR ?= /etc/php-fpm.d
PHP_FPM_CONF ?= $(PHP_FPM_DIR)/$(DOMAIN).conf
PHP_SOCKET ?= /run/php-fpm/$(DOMAIN).sock


# --------------------

.PHONY: help issue install vhost setup renew check

help:
        @echo "Dostępne komendy:"
        @echo "  make issue       - Wystawia nowy certyfikat przez acme.sh (DNS-01)"
        @echo "  make install     - Konfiguruje acme.sh do automatycznej instalacji certyfikatu"
        @echo "  make php-fpm     - Generuje plik konfiguracyjny puli PHP-FPM dla $(DOMAIN)"
        @echo "  make vhost       - Generuje plik konfiguracyjny Apache z szablonu dla $(DOMAIN)"
        @echo "  make setup       - Wykonuje pełną konfigurację krok po kroku (issue -> install -> vhost)"
        @echo "  make renew       - Wymusza odnowienie certyfikatu i wdrożenie go"
        @echo "  make check       - Sprawdza poprawność konfiguracji serwera WWW"

issue:
        @echo "[+] Wystawianie certyfikatu dla $(DOMAIN) przy użyciu Let's Encrypt i wtyczki $(DNS_PLUGIN)..."
        $(ACME_SH) --set-default-ca --server letsencrypt
        $(ACME_SH) --issue --dns $(DNS_PLUGIN) -d $(DOMAIN) --dnssleep $(DNS_SLEEP)
        @echo "[+] Certyfikat został pomyślnie wystawiony."

install:
        @echo "[+] Konfigurowanie automatycznej instalacji certyfikatu w ścieżkach systemowych..."
        $(ACME_SH) --install-cert -d $(DOMAIN) \
                --cert-file       $(CERT_DIR)/$(DOMAIN).crt \
                --key-file        $(KEY_DIR)/$(DOMAIN).key \
                --fullchain-file  $(CERT_DIR)/$(DOMAIN)-fullchain.crt \
                --reloadcmd       "systemctl reload $(WEB_SERVICE)"
        @echo "[+] Instalacja powiązana."


php-fpm:
        @echo "[+] Generowanie konfiguracji PHP-FPM dla $(DOMAIN)..."
        cp php-fpm.template php-fpm.tmp
        sed -i 's|DOMAIN_PLACEHOLDER|$(DOMAIN)|g' php-fpm.tmp
        sed -i 's|APP_ROOT_PLACEHOLDER|$(APP_ROOT)|g' php-fpm.tmp
        sed -i 's|WEB_ROOT_PLACEHOLDER|$(WEB_ROOT)|g' php-fpm.tmp
        sed -i 's|APP_USER_PLACEHOLDER|$(APP_USER)|g' php-fpm.tmp
        sed -i 's|APP_GROUP_PLACEHOLDER|$(APP_GROUP)|g' php-fpm.tmp
        sed -i 's|BACKUP_DIR_PLACEHOLDER|$(BACKUP_DIR)|g' php-fpm.tmp
        mv php-fpm.tmp $(PHP_FPM_CONF)
        chmod 644 $(PHP_FPM_CONF)
        systemctl restart php-fpm
        @echo "[+] Pula PHP-FPM została wdrożona i zrestartowana."

vhost: php-fpm
        @echo "[+] Tworzenie katalogu dla strony: $(WEB_ROOT)..."
        mkdir -p $(WEB_ROOT)
        @echo "[+] Generowanie vhosta z szablonu vhost.template..."
        cp vhost.template $(CONF_FILE)
        sed -i 's/DOMAIN_PLACEHOLDER/$(DOMAIN)/g' $(CONF_FILE)
        sed -i 's|WEB_ROOT_PLACEHOLDER|$(WEB_ROOT)|g' $(CONF_FILE)
        sed -i 's|CERT_DIR_PLACEHOLDER|$(CERT_DIR)|g' $(CONF_FILE)
        sed -i 's|KEY_DIR_PLACEHOLDER|$(KEY_DIR)|g' $(CONF_FILE)
        sed -i 's|PHP_SOCKET_PLACEHOLDER|$(PHP_SOCKET)|g' $(CONF_FILE)
        @echo "[+] Gotowe."
        $(MAKE) check

setup: issue install vhost
        @echo "[+] Pełna konfiguracja domeny $(DOMAIN) zakończona sukcesem!"
        systemctl restart $(WEB_SERVICE)

renew:
        @echo "[+] Odnawianie i wdrażanie certyfikatu dla $(DOMAIN)..."
        $(ACME_SH) --renew -d $(DOMAIN) --force
        @echo "[+] Proces zakończony."

check:
        @echo "[+] Sprawdzanie konfiguracji serwera $(WEB_SERVICE)..."
        httpd -t
