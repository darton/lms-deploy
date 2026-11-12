# AlmaLinux Apache VHost & PHP-FPM Provisioner

Automatyzacja wdrażania wirtualnych hostów Apache, dedykowanych pul PHP-FPM oraz certyfikatów SSL (`acme.sh` z wtyczką DNS ISPConfig) na systemach AlmaLinux.

## Wymagania
- AlmaLinux 9 / Apache (`httpd`) / PHP-FPM
- `acme.sh` zainstalowany w systemie
- Dostęp z uprawnieniami `sudo`

## Szybki start

1. Sklonuj repozytorium na serwerze (np. do `/opt/vhost-manager`):
   ```bash
   git clone [https://github.com/twoj-login/almalinux-vhost-manager.git](https://github.com/twoj-login/almalinux-vhost-manager.git) /opt/vhost-manager
   cd /opt/vhost-manager
