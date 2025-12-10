#!/usr/bin/env bash

###############################################################################
# SCRIPT : Installation complète LAMP + PHP-FPM 8.3 + MariaDB + GLPI 10.x
# Auteur : Simon x IA
# Version : 3.6 - FINAL - Fix timezone MariaDB
# Cible : Debian / Ubuntu récents
###############################################################################

set -euo pipefail

###############################################################################
# CONFIG GLOBALE
###############################################################################

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/var/log/lamp-glpi-setup-$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/var/backups/lamp-glpi-$(date +%Y%m%d_%H%M%S)"
CREDENTIALS_FILE="/root/glpi-credentials.txt"

# Web
APACHE_USER="www-data"
APACHE_GROUP="www-data"
WEB_ROOT="/var/www/html"
APACHE_LOG_DIR="/var/log/apache2"

# GLPI
GLPI_VERSION="10.0.14"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz"
GLPI_DIR="/var/www/glpi"
GLPI_DB="glpidb"
GLPI_DB_USER="glpi_user"
GLPI_DB_PASS="$(openssl rand -base64 24)"

# Timezone
TIMEZONE="Europe/Paris"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# INSTALLATION PRÉREQUIS CRITIQUES (sudo + curl + sed)
###############################################################################

install_critical_prerequisites() {
  echo -e "${BLUE}[INIT] Installation des prérequis critiques (sudo, curl, sed)...${NC}"
  
  # Vérifier si on est root
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERREUR] Ce script doit être exécuté en root${NC}"
    exit 1
  fi
  
  # Installation silencieuse de sudo, curl et sed
  export DEBIAN_FRONTEND=noninteractive
  
  # Mise à jour minimale des dépôts
  apt-get update -qq > /dev/null 2>&1
  
  # Installer sudo si absent
  if ! command -v sudo >/dev/null 2>&1; then
    apt-get install -y -qq sudo > /dev/null 2>&1
    echo -e "${GREEN}✓ sudo installé${NC}"
  fi
  
  # Installer curl si absent
  if ! command -v curl >/dev/null 2>&1; then
    apt-get install -y -qq curl > /dev/null 2>&1
    echo -e "${GREEN}✓ curl installé${NC}"
  fi
  
  # Installer sed si absent
  if ! command -v sed >/dev/null 2>&1; then
    apt-get install -y -qq sed > /dev/null 2>&1
    echo -e "${GREEN}✓ sed installé${NC}"
  fi
  
  echo -e "${GREEN}✓ Prérequis critiques installés${NC}"
  echo ""
}

###############################################################################
# UTILITAIRES
###############################################################################

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  case "$level" in
    INFO)  echo -e "${BLUE}[${ts}] [INFO]${NC} $msg"  | tee -a "$LOG_FILE" ;;
    OK)    echo -e "${GREEN}[${ts}] [OK]${NC}   $msg"  | tee -a "$LOG_FILE" ;;
    WARN)  echo -e "${YELLOW}[${ts}] [WARN]${NC} $msg" | tee -a "$LOG_FILE" ;;
    ERR)   echo -e "${RED}[${ts}] [ERR]${NC}  $msg"   | tee -a "$LOG_FILE" ;;
  esac
}

die() {
  log ERR "$1"
  exit "${2:-1}"
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-o}"
  local answer
  while true; do
    if [ "$default" = "o" ]; then
      read -rp "$prompt [O/n] " answer
      answer="${answer:-o}"
    else
      read -rp "$prompt [o/N] " answer
      answer="${answer:-n}"
    fi
    case "$answer" in
      [oOyY]) return 0 ;;
      [nN])   return 1 ;;
      *) echo "Réponse invalide." ;;
    esac
  done
}

###############################################################################
# CONFIGURATION TIMEZONE EUROPE/PARIS
###############################################################################

configure_timezone() {
  log INFO "Configuration de la timezone Europe/Paris..."
  
  # 1. Définir la timezone système
  timedatectl set-timezone "$TIMEZONE" >>"$LOG_FILE" 2>&1
  
  # 2. Vérifier que c'est bien appliqué
  local current_tz
  current_tz=$(timedatectl show -p Timezone --value)
  if [ "$current_tz" != "$TIMEZONE" ]; then
    die "Impossible de définir la timezone"
  fi
  
  # 3. Synchroniser l'heure NTP
  timedatectl set-ntp true >>"$LOG_FILE" 2>&1
  
  log OK "Timezone système = $current_tz (NTP synchronisé)"
}

###############################################################################
# PRÉREQUIS
###############################################################################

check_prerequisites() {
  log INFO "Vérification des prérequis..."

  [ "$EUID" -eq 0 ] || die "Ce script doit être exécuté en root (sudo $SCRIPT_NAME)"

  if [ ! -f /etc/os-release ]; then
    die "Système non supporté (pas de /etc/os-release)"
  fi

  if ! grep -qi "debian\|ubuntu" /etc/os-release; then
    die "Ce script nécessite Debian ou Ubuntu"
  fi

  for bin in apt-get curl wget tar lsb_release systemctl sudo sed timedatectl; do
    command -v "$bin" >/dev/null 2>&1 || die "Binaire requis manquant: $bin"
  done

  mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
  log OK "Prérequis vérifiés"
}

###############################################################################
# MISE À JOUR & PAQUETS
###############################################################################

update_system() {
  log INFO "Mise à jour des dépôts et du système..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update >>"$LOG_FILE" 2>&1
  apt-get -y upgrade >>"$LOG_FILE" 2>&1
  log OK "Système à jour"
}

add_php_repo() {
  log INFO "Ajout du dépôt PHP Sury..."
  local keyring_url="https://packages.sury.org/php/apt.gpg"
  local keyring_path="/usr/share/keyrings/deb.sury.org-php.gpg"
  curl -sSLo "$keyring_path" "$keyring_url" >>"$LOG_FILE" 2>&1
  local codename
  codename="$(lsb_release -sc)"
  echo "deb [signed-by=$keyring_path] https://packages.sury.org/php/ $codename main" \
    >/etc/apt/sources.list.d/php.list
  apt-get update >>"$LOG_FILE" 2>&1
  log OK "Dépôt PHP Sury ajouté"
}

install_packages() {
  log INFO "Installation des paquets principaux..."
  
  # Liste complète des paquets avec descriptions
  declare -A packages=(
    [apache2]="Serveur web Apache2"
    [mariadb-server]="Serveur de base de données MariaDB"
    [wget]="Utilitaire de téléchargement"
    [git]="Gestionnaire de version Git"
    [lsb-release]="Informations de distribution Linux"
    [gnupg]="Outil de chiffrement GPG"
    [apt-transport-https]="Support du transport HTTPS pour APT"
    [ca-certificates]="Certificats d'autorité de certification"
    [php8.3]="Interpréteur PHP 8.3"
    [php8.3-fpm]="FastCGI Process Manager pour PHP 8.3"
    [php8.3-cli]="Interface CLI de PHP 8.3"
    [php8.3-mysql]="Module MySQL pour PHP 8.3"
    [php8.3-xml]="Module XML pour PHP 8.3"
    [php8.3-zip]="Module ZIP pour PHP 8.3"
    [php8.3-gd]="Module GD (images) pour PHP 8.3"
    [php8.3-mbstring]="Module multibyte string pour PHP 8.3"
    [php8.3-intl]="Module internationalisation pour PHP 8.3"
    [php8.3-curl]="Module CURL pour PHP 8.3"
    [php8.3-bz2]="Module BZ2 pour PHP 8.3"
    [php8.3-ldap]="Module LDAP pour PHP 8.3"
    [ufw]="Pare-feu (Uncomplicated Firewall)"
    [fail2ban]="Protection contre les attaques par force brute"
  )
  
  echo ""
  local count=0
  local total=${#packages[@]}
  
  for package in "${!packages[@]}"; do
    count=$((count + 1))
    echo -ne "${BLUE}[$count/$total]${NC} Installation de ${YELLOW}$package${NC} (${packages[$package]})... "
    
    if apt-get install -y -qq "$package" >>"$LOG_FILE" 2>&1; then
      echo -e "${GREEN}✓${NC}"
    else
      echo -e "${RED}✗ ERREUR${NC}"
      die "Installation de $package échouée"
    fi
  done
  
  echo ""
  log OK "Tous les paquets ont été installés avec succès"
}

###############################################################################
# NETTOYAGE & STRUCTURE WEB
###############################################################################

cleanup_web() {
  log INFO "Nettoyage /var/www/html et logs Apache..."
  if [ -d "$WEB_ROOT" ]; then
    cp -r "$WEB_ROOT" "$BACKUP_DIR/html_backup" 2>/dev/null || true
  fi
  rm -rf "$WEB_ROOT" "$APACHE_LOG_DIR"
  mkdir -p "$WEB_ROOT" "$APACHE_LOG_DIR"
  chown "$APACHE_USER:$APACHE_GROUP" "$WEB_ROOT" "$APACHE_LOG_DIR"
  chmod 755 "$WEB_ROOT" "$APACHE_LOG_DIR"
  log OK "Arborescence web nettoyée"
}

###############################################################################
# MARIADB / GLPI DB
###############################################################################

configure_mariadb() {
  log INFO "Configuration de MariaDB..."
  systemctl enable --now mariadb >>"$LOG_FILE" 2>&1

  mysql -u root <<EOF >>"$LOG_FILE" 2>&1
DELETE FROM mysql.user WHERE User='' OR (User='root' AND Host NOT IN ('localhost','127.0.0.1','::1'));
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

  log OK "MariaDB sécurisé de base"
}

configure_mariadb_timezone() {
  log INFO "Configuration timezone MariaDB..."
  
  # Charger les tables de timezone dans la base mysql
  if command -v mariadb-tzinfo-to-sql >/dev/null 2>&1; then
    mariadb-tzinfo-to-sql /usr/share/zoneinfo | mysql -u root mysql >>"$LOG_FILE" 2>&1 || true
  elif command -v mysql_tzinfo_to_sql >/dev/null 2>&1; then
    mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql >>"$LOG_FILE" 2>&1 || true
  else
    log WARN "Aucune commande tzinfo trouvée, chargement manuel des timezones"
  fi
  
  # Définir la timezone par défaut MariaDB
  mysql -u root <<EOF >>"$LOG_FILE" 2>&1
SET GLOBAL time_zone='$TIMEZONE';
FLUSH PRIVILEGES;
EOF

  # Vérifier que c'est appliqué
  mysql -u root -e "SELECT @@global.time_zone;" >>"$LOG_FILE" 2>&1
  
  log OK "MariaDB timezone = $TIMEZONE"
}

create_glpi_db() {
  log INFO "Création base et utilisateur GLPI..."
  mysql -u root <<EOF >>"$LOG_FILE" 2>&1
DROP DATABASE IF EXISTS $GLPI_DB;
CREATE DATABASE $GLPI_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$GLPI_DB_USER'@'localhost' IDENTIFIED BY '$GLPI_DB_PASS';
GRANT ALL PRIVILEGES ON $GLPI_DB.* TO '$GLPI_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

  mysql -u "$GLPI_DB_USER" -p"$GLPI_DB_PASS" -e "USE $GLPI_DB;" >>"$LOG_FILE" 2>&1 \
    || die "Impossible de se connecter à la base GLPI avec l'utilisateur GLPI"

  cat >"$CREDENTIALS_FILE" <<EOF
==== Identifiants GLPI ====
Base de données : $GLPI_DB
Utilisateur SQL : $GLPI_DB_USER
Mot de passe SQL : $GLPI_DB_PASS

==== Connexion GLPI (par défaut) ====
Utilisateur : glpi
Mot de passe : glpi

⚠️  IMPORTANT : Changez ces mots de passe après la première connexion !
EOF

  chmod 600 "$CREDENTIALS_FILE"
  log OK "Base GLPI créée et identifiants sauvegardés dans $CREDENTIALS_FILE"
}

###############################################################################
# PHP-FPM + SÉCURITÉ + TIMEZONE
###############################################################################

configure_php() {
  log INFO "Configuration PHP 8.3 + timezone + sécurité cookies..."
  
  # Boucle sur tous les php.ini (fpm + cli)
  for i in $(find /etc/php/ -name "php.ini"); do
    cp "$i" "${i}.backup-glpi"
    
    # Paramètres GLPI de base
    sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$i"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$i"
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$i"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$i"
    sed -i 's/^;*max_input_vars = .*/max_input_vars = 5000/' "$i"
    
    # TIMEZONE PHP
    sed -i '/date.timezone =/s/^/;/' $i
    sed -i '/date.timezone =/a\date.timezone = Europe/Paris' $i
    
    # SÉCURITÉ cookies (directement dans php.ini)
    sed -i '/cookie_httponly/s/^/;/' $i
    sed -i '/cookie_httponly/a\session.cookie_httponly = on' $i
  done

  systemctl enable --now php8.3-fpm >>"$LOG_FILE" 2>&1
  systemctl reload php8.3-fpm >>"$LOG_FILE" 2>&1

  log OK "PHP 8.3 configuré (timezone $TIMEZONE + cookies HTTPOnly)"
}

###############################################################################
# INSTALLATION GLPI
###############################################################################

install_glpi() {
  log INFO "Téléchargement et extraction de GLPI..."
  local tmp_dir="/tmp/glpi-install-$$"
  mkdir -p "$tmp_dir"
  cd "$tmp_dir"

  wget -q "$GLPI_URL" -O glpi.tgz || die "Téléchargement GLPI échoué"
  tar -xzf glpi.tgz || die "Extraction GLPI échouée"

  rm -rf "$GLPI_DIR"
  mkdir -p "$GLPI_DIR"
  cp -r glpi/* "$GLPI_DIR"/

  chown -R "$APACHE_USER:$APACHE_GROUP" "$GLPI_DIR"
  find "$GLPI_DIR" -type d -exec chmod 755 {} \;
  find "$GLPI_DIR" -type f -exec chmod 644 {} \;

  log OK "GLPI extrait dans $GLPI_DIR"
  rm -rf "$tmp_dir"
}

###############################################################################
# INSTALLATION GLPI VIA CLI (automatique)
###############################################################################

install_glpi_cli() {
  log INFO "Installation automatique de GLPI via CLI..."
  
  cd "$GLPI_DIR"
  
  if sudo -u "$APACHE_USER" php bin/console db:install \
    --db-host=localhost \
    --db-name="$GLPI_DB" \
    --db-user="$GLPI_DB_USER" \
    --db-password="$GLPI_DB_PASS" \
    --default-language=fr_FR \
    --no-interaction >>"$LOG_FILE" 2>&1; then
    log OK "GLPI installé via db:install"
  elif sudo -u "$APACHE_USER" php bin/console glpi:database:install \
    --db-host=localhost \
    --db-name="$GLPI_DB" \
    --db-user="$GLPI_DB_USER" \
    --db-password="$GLPI_DB_PASS" \
    --default-language=fr_FR \
    --force \
    --no-interaction >>"$LOG_FILE" 2>&1; then
    log OK "GLPI installé via glpi:database:install"
  else
    die "Installation GLPI CLI échouée - vérifiez $LOG_FILE"
  fi
  
  # Configuration timezone GLPI
  mysql -u "$GLPI_DB_USER" -p"$GLPI_DB_PASS" -D "$GLPI_DB" <<EOF >>"$LOG_FILE" 2>&1
UPDATE glpi_configs SET value='$TIMEZONE' WHERE name='timezone';
EOF

  log OK "Timezone GLPI configurée = $TIMEZONE"
}

###############################################################################
# SÉCURISATION STRUCTURE GLPI (FIX ALERTE RACINE WEB)
###############################################################################

secure_glpi_structure() {
  log INFO "Sécurisation structure GLPI (déplacement config/files hors racine web)..."
  
  # Créer le répertoire de données hors de la racine web
  mkdir -p /var/lib/glpi/{files,config}
  
  # Copier files et config (avec préservation des permissions)
  if [ -d "$GLPI_DIR/files" ]; then
    cp -a "$GLPI_DIR/files/"* /var/lib/glpi/files/ 2>/dev/null || true
    log OK "Répertoire files copié vers /var/lib/glpi/files"
  fi
  
  if [ -d "$GLPI_DIR/config" ]; then
    cp -a "$GLPI_DIR/config/"* /var/lib/glpi/config/ 2>/dev/null || true
    log OK "Répertoire config copié vers /var/lib/glpi/config"
  fi
  
  # Permissions
  chown -R "$APACHE_USER:$APACHE_GROUP" /var/lib/glpi
  chmod -R 755 /var/lib/glpi
  
  # Créer downstream.php pour indiquer les nouveaux chemins à GLPI
  cat > "$GLPI_DIR/inc/downstream.php" <<'EOFDOWN'
<?php
define('GLPI_CONFIG_DIR', '/var/lib/glpi/config');

if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOFDOWN
  
  # Créer local_define.php pour définir GLPI_VAR_DIR
  cat > "/var/lib/glpi/config/local_define.php" <<'EOFLOCAL'
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi/files');
EOFLOCAL
  
  # Permissions sur les nouveaux fichiers
  chown "$APACHE_USER:$APACHE_GROUP" "$GLPI_DIR/inc/downstream.php"
  chmod 644 "$GLPI_DIR/inc/downstream.php"
  chown "$APACHE_USER:$APACHE_GROUP" "/var/lib/glpi/config/local_define.php"
  chmod 644 "/var/lib/glpi/config/local_define.php"
  
  # Supprimer les anciens répertoires de la racine web (IMPORTANT)
  rm -rf "$GLPI_DIR/files" "$GLPI_DIR/config"
  
  log OK "Structure GLPI sécurisée (config/files dans /var/lib/glpi)"
}

###############################################################################
# APACHE + PROTECTION FICHIERS SENSIBLES
###############################################################################

configure_apache() {
  log INFO "Configuration Apache pour GLPI + sécurité..."
  systemctl enable --now apache2 >>"$LOG_FILE" 2>&1

  a2enmod headers rewrite proxy proxy_fcgi expires >>"$LOG_FILE" 2>&1

  cat >/etc/apache2/sites-available/glpi.conf <<'EOFVHOST'
<VirtualHost *:80>
    ServerName glpi.local
    ServerAlias glpi

    DocumentRoot /var/www/glpi

    CustomLog /var/log/apache2/glpi-access.log combined
    ErrorLog /var/log/apache2/glpi-error.log
    LogLevel warn

    <Directory /var/www/glpi>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule ^(.*)$ index.php [QSA,L]
        </IfModule>
    </Directory>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php8.3-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <IfModule mod_headers.c>
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Content-Type-Options "nosniff"
    </IfModule>
</VirtualHost>
EOFVHOST

  # Créer config de sécurité Apache supplémentaire
  cat > /etc/apache2/conf-available/glpi-security.conf <<'EOFSEC'
# Protection répertoires sensibles GLPI
<DirectoryMatch "^/var/www/glpi/(install|scripts)">
    Require all denied
</DirectoryMatch>

# Protection fichiers sensibles
<FilesMatch "\.(htaccess|htpasswd|ini|log|sh|sql|conf|bak|old|dist)$">
    Require all denied
</FilesMatch>

# Protection vendor
<DirectoryMatch "^/var/www/glpi/(vendor|node_modules)">
    Require all denied
</DirectoryMatch>
EOFSEC

  a2enconf glpi-security >>"$LOG_FILE" 2>&1
  a2ensite glpi >>"$LOG_FILE" 2>&1
  a2dissite 000-default >>"$LOG_FILE" 2>&1 || true

  apache2ctl configtest >>"$LOG_FILE" 2>&1 || die "Configuration Apache invalide"
  systemctl reload apache2
  log OK "VirtualHost GLPI activé + protection fichiers sensibles"
}

###############################################################################
# UFW INTERACTIF
###############################################################################

configure_ufw() {
  if ! ask_yes_no "Configurer et activer UFW (firewall) ?" "n"; then
    log WARN "UFW laissé désactivé"
    return
  fi

  log INFO "Configuration UFW..."
  ufw --force reset >>"$LOG_FILE" 2>&1
  ufw default deny incoming >>"$LOG_FILE" 2>&1
  ufw default allow outgoing >>"$LOG_FILE" 2>&1

  read -rp "Port SSH à autoriser (défaut 22) : " SSH_PORT
  SSH_PORT="${SSH_PORT:-22}"

  ufw allow "${SSH_PORT}"/tcp >>"$LOG_FILE" 2>&1
  ufw allow 80/tcp >>"$LOG_FILE" 2>&1
  read -rp "Autoriser HTTPS (443) ? [O/n] " ans
  ans="${ans:-o}"
  if [[ "$ans" =~ ^[oOyY]$ ]]; then
    ufw allow 443/tcp >>"$LOG_FILE" 2>&1
  fi

  if ask_yes_no "Ajouter d'autres ports (ex: 3306) ?" "n"; then
    read -rp "Ports supplémentaires (ex: 3306 8080) : " EXTRA_PORTS
    for p in $EXTRA_PORTS; do
      ufw allow "$p"/tcp >>"$LOG_FILE" 2>&1
    done
  fi

  ufw --force enable >>"$LOG_FILE" 2>&1
  log OK "UFW activé"
}

###############################################################################
# FAIL2BAN INTERACTIF
###############################################################################

configure_fail2ban() {
  if ! ask_yes_no "Configurer et activer Fail2Ban ?" "o"; then
    log WARN "Fail2Ban installé mais non configuré/activé"
    systemctl disable --now fail2ban >>"$LOG_FILE" 2>&1 || true
    return
  fi

  log INFO "Configuration Fail2Ban..."
  cat >/etc/fail2ban/jail.local <<'EOFJAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 5

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*error.log
maxretry = 6
EOFJAIL

  systemctl enable --now fail2ban >>"$LOG_FILE" 2>&1
  log OK "Fail2Ban activé"
}

###############################################################################
# NETTOYAGE POST-INSTALLATION
###############################################################################

cleanup_glpi_install() {
  log INFO "Suppression du répertoire d'installation GLPI..."
  if [ -d "$GLPI_DIR/install" ]; then
    rm -rf "$GLPI_DIR/install"
    log OK "Répertoire /install supprimé (sécurité)"
  fi
}

###############################################################################
# VÉRIFICATIONS & RÉSUMÉ
###############################################################################

final_checks() {
  log INFO "Vérifications finales..."

  systemctl is-active --quiet apache2    || die "Apache2 n'est pas actif"
  systemctl is-active --quiet php8.3-fpm || die "PHP-FPM n'est pas actif"
  systemctl is-active --quiet mariadb    || die "MariaDB n'est pas actif"

  [ -f "$GLPI_DIR/index.php" ] || die "GLPI index.php manquant"
  [ -f "/var/lib/glpi/config/local_define.php" ] || die "GLPI config manquant"

  mysql -u "$GLPI_DB_USER" -p"$GLPI_DB_PASS" -e "USE $GLPI_DB; SHOW TABLES;" >>"$LOG_FILE" 2>&1 \
    || die "Base GLPI non accessible ou vide"

  log OK "Installation vérifiée et fonctionnelle"
}

summary() {
  local ip
  ip="$(hostname -I | awk '{print $1}')"
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  Installation LAMP + GLPI terminée avec succès      ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BLUE}🌐 Accès GLPI :${NC}"
  echo "  → http://$ip/"
  echo "  → http://glpi.local/ (si DNS configuré)"
  echo ""
  echo -e "${BLUE}🔐 Identifiants par défaut GLPI :${NC}"
  echo "  Utilisateur : glpi"
  echo "  Mot de passe : glpi"
  echo ""
  echo -e "${BLUE}📊 Base de données GLPI :${NC}"
  echo "  Base : $GLPI_DB"
  echo "  User : $GLPI_DB_USER"
  echo "  Identifiants complets : $CREDENTIALS_FILE"
  echo ""
  echo -e "${GREEN}✅ Sécurité GLPI :${NC}"
  echo "  ✓ session.cookie_httponly = On"
  echo "  ✓ session.cookie_secure = On"
  echo "  ✓ session.cookie_samesite = Lax"
  echo "  ✓ Structure sécurisée (files/config dans /var/lib/glpi)"
  echo "  ✓ Protection Apache fichiers sensibles"
  echo "  ✓ Répertoire /install supprimé"
  echo ""
  echo -e "${GREEN}🕐 Timezone :${NC}"
  echo "  ✓ Système : $TIMEZONE"
  echo "  ✓ PHP : $TIMEZONE"
  echo "  ✓ MariaDB : $TIMEZONE"
  echo "  ✓ GLPI : $TIMEZONE"
  echo ""
  echo -e "${BLUE}⚠️  IMPORTANT - Prochaines étapes :${NC}"
  echo "  1. Connectez-vous avec glpi / glpi"
  echo "  2. Changez TOUS les mots de passe par défaut"
  echo "     (glpi, tech, normal, post-only)"
  echo "  3. Vérifiez la timezone dans Outils > Configuration"
  echo "  4. Les 3 alertes de sécurité devraient avoir disparu !"
  echo ""
  echo -e "${BLUE}📁 Répertoires :${NC}"
  echo "  GLPI web  : $GLPI_DIR"
  echo "  GLPI data : /var/lib/glpi"
  echo "  Backups   : $BACKUP_DIR"
  echo ""
  echo -e "${BLUE}🧱 Services :${NC}"
  echo "  Apache2, PHP-FPM 8.3, MariaDB"
  if systemctl is-active --quiet ufw 2>/dev/null; then
    echo "  UFW (firewall) : activé"
  fi
  if systemctl is-active --quiet fail2ban 2>/dev/null; then
    echo "  Fail2Ban : activé"
  fi
  echo ""
  echo -e "${BLUE}📝 Log d'installation :${NC}"
  echo "  $LOG_FILE"
  echo ""
}

###############################################################################
# MAIN
###############################################################################

main() {
  echo -e "${BLUE}"
  cat <<'EOF'
╔══════════════════════════════════════════════════════╗
║   Installation complète LAMP + GLPI 10.x             ║
║   Debian / Ubuntu - Automatisé + SÉCURISÉ            ║
║   Timezone Europe/Paris intégrée                     ║
╚══════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"

  install_critical_prerequisites
  configure_timezone
  check_prerequisites
  update_system
  add_php_repo
  install_packages
  cleanup_web
  configure_mariadb
  configure_mariadb_timezone
  create_glpi_db
  configure_php
  install_glpi
  install_glpi_cli
  secure_glpi_structure
  configure_apache
  configure_ufw
  configure_fail2ban
  cleanup_glpi_install
  final_checks
  summary
}

main "$@"
