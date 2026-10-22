#!/bin/sh
set -eu

# Projekt
PROJECT_NAME="New Projekt"
PROJECT_PATH="new-projekt"
PROJECT_REPOSITORY="https://github.com/florianthepro/new-projekt.git"
PROJECT_BRANCH="main"
PROJECTS_ROOT_DIRECTORY="/srv/webapps"
PROJECT_URL_PATH="/new-projekt"

# Django
DJANGO_VERSION="5.2.*"
DJANGO_ADMIN_ENABLED="false"
DJANGO_API_PREFIX="/api"
DJANGO_ACCOUNT_PREFIX="/account"
DJANGO_ADMIN_PREFIX="/admin"

# Gunicorn
GUNICORN_VERSION="23.*"
GUNICORN_WORKERS="3"
GUNICORN_TIMEOUT_SECONDS="30"
GUNICORN_RUNTIME_ROOT="/run"

# PostgreSQL: Django nutzt die Datenbank fuer Benutzer, Sessions,
# Berechtigungen, Migrationen und projektspezifische Daten.
DATABASE_ENGINE="postgresql"

# Frontend: leer = 404, fuer eine SPA z. B. "index.html"
FRONTEND_FALLBACK_FILE=""

# Caddy
CADDY_SITES_DIRECTORY="/etc/caddy/sites"
CADDY_COMPRESSION_ENABLED="true"
CADDY_SECURITY_HEADERS_ENABLED="true"

CADDYFILE_TEMPLATE='__SITE_ADDRESS__ {
__TLS_CONFIGURATION____URL_ROUTE__ {
        handle __API_PREFIX__/* {
            reverse_proxy unix//__SOCKET_PATH__
        }

        handle __ACCOUNT_PREFIX__/* {
            reverse_proxy unix//__SOCKET_PATH__
        }

__ADMIN_HANDLER__
        handle {
            root * __APP_DIRECTORY__
__FALLBACK_LINE__            file_server
        }
    }
__ROOT_ROUTE__
__COMPRESSION__
__SECURITY_HEADERS__
}'

log() { printf '\n[%s] %s\n' "$PROJECT_PATH" "$1"; }
warn() { printf '\n[%s] Hinweis: %s\n' "$PROJECT_PATH" "$1" >&2; }
fail() { printf '\n[%s] Fehler: %s\n' "$PROJECT_PATH" "$1" >&2; exit 1; }

validate_defaults() {
    [ "$(id -u)" -eq 0 ] || fail "Mit sudo oder als root ausfuehren."
    [ -r /etc/os-release ] || fail "/etc/os-release fehlt."
    . /etc/os-release
    [ "${ID:-}" = "debian" ] || fail "Unterstuetzt wird Debian."
    printf '%s' "$PROJECT_PATH" | grep -Eq '^[a-z][a-z0-9-]{1,48}$' || fail "PROJECT_PATH ist ungueltig."
    [ "$DATABASE_ENGINE" = "postgresql" ] || fail "Diese Vorlage unterstuetzt nur PostgreSQL."
    case "$PROJECT_URL_PATH" in /|/*/) : ;; /*) PROJECT_URL_PATH="$PROJECT_URL_PATH/" ;; *) fail "PROJECT_URL_PATH muss mit / beginnen." ;; esac
}

set_paths() {
    PROJECT_ROOT_DIRECTORY="$PROJECTS_ROOT_DIRECTORY/$PROJECT_PATH"
    APP_DIRECTORY="$PROJECT_ROOT_DIRECTORY/app"
    VENV_DIRECTORY="$PROJECT_ROOT_DIRECTORY/venv"
    LOCAL_CADDY_DIRECTORY="$PROJECT_ROOT_DIRECTORY/caddy"
    LOCAL_CADDYFILE="$LOCAL_CADDY_DIRECTORY/Caddyfile"
    GUNICORN_SOCKET_DIRECTORY="$GUNICORN_RUNTIME_ROOT/$PROJECT_PATH"
    GUNICORN_SOCKET_PATH="$GUNICORN_SOCKET_DIRECTORY/$PROJECT_PATH.sock"
    DATA_DIRECTORY="/var/lib/$PROJECT_PATH"
    MEDIA_DIRECTORY="$DATA_DIRECTORY/media"
    PRIVATE_DIRECTORY="$DATA_DIRECTORY/private"
    STATE_DIRECTORY="$DATA_DIRECTORY/state"
    CONFIG_DIRECTORY="/etc/$PROJECT_PATH"
    ENVIRONMENT_FILE="$CONFIG_DIRECTORY/environment"
    SYSTEMD_SERVICE_FILE="/etc/systemd/system/$PROJECT_PATH.service"
    SYSTEM_CADDY_SITE_FILE="$CADDY_SITES_DIRECTORY/$PROJECT_PATH.caddy"
    SERVICE_USER="$PROJECT_PATH"
    SERVICE_GROUP="$PROJECT_PATH"
}

prompt() {
    question="$1"; default="$2"
    if [ -r /dev/tty ]; then
        printf '%s [%s]: ' "$question" "$default" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
        [ -n "$answer" ] && printf '%s' "$answer" || printf '%s' "$default"
    else
        printf '%s' "$default"
    fi
}

configure_public_access() {
    printf '\nVerbindung\n[1] HTTPS automatisch mit Caddy\n[2] HTTPS mit vorhandenem Zertifikat\n[3] Nur HTTP\n' > /dev/tty 2>/dev/null || true
    TLS_MODE="${TLS_MODE:-$(prompt "Auswahl" "1")}" 
    DOMAIN="${DOMAIN:-$(prompt "Domain oder IP ohne Protokoll" "localhost")}" 
    SITE_ADDRESS="$DOMAIN"
    TLS_CONFIGURATION=""
    case "$TLS_MODE" in
        1) : ;;
        2)
            CERTIFICATE_PATH="${CERTIFICATE_PATH:-$(prompt "Pfad zum Zertifikat" "/etc/ssl/certs/$PROJECT_PATH.pem")}" 
            PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$(prompt "Pfad zum privaten Schluessel" "/etc/ssl/private/$PROJECT_PATH.key")}" 
            [ -r "$CERTIFICATE_PATH" ] || fail "Zertifikat nicht lesbar: $CERTIFICATE_PATH"
            [ -r "$PRIVATE_KEY_PATH" ] || fail "Privater Schluessel nicht lesbar: $PRIVATE_KEY_PATH"
            TLS_CONFIGURATION="    tls $CERTIFICATE_PATH $PRIVATE_KEY_PATH\n"
            ;;
        3) SITE_ADDRESS="http://$DOMAIN"; warn "HTTP verschluesselt weder Anmeldedaten noch Sitzungen." ;;
        *) fail "Ungueltige Verbindungswahl." ;;
    esac
}

install_system_packages() {
    log "Systempakete pruefen"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates caddy curl git openssl postgresql python3 python3-pip python3-venv
}

prepare_identity_and_directories() {
    log "Benutzer und Verzeichnisse vorbereiten"
    id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --user-group --home-dir "$PROJECT_ROOT_DIRECTORY" --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    install -d -o root -g "$SERVICE_GROUP" -m 0750 "$PROJECTS_ROOT_DIRECTORY" "$PROJECT_ROOT_DIRECTORY" "$APP_DIRECTORY" "$VENV_DIRECTORY" "$LOCAL_CADDY_DIRECTORY"
    install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$DATA_DIRECTORY" "$MEDIA_DIRECTORY" "$PRIVATE_DIRECTORY" "$STATE_DIRECTORY"
    install -d -o root -g "$SERVICE_GROUP" -m 0750 "$CONFIG_DIRECTORY"
    install -d -o root -g root -m 0755 "$CADDY_SITES_DIRECTORY"
    usermod -a -G "$SERVICE_GROUP" caddy
}

install_project_files() {
    log "Projektdateien aus $PROJECT_BRANCH laden"
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
    git clone --branch "$PROJECT_BRANCH" --depth 1 "$PROJECT_REPOSITORY" "$temp_dir/repository"
    [ -f "$temp_dir/repository/backend.py" ] || fail "backend.py fehlt im Repository."
    [ -f "$temp_dir/repository/index.html" ] || fail "index.html fehlt im Repository."

    if [ -n "$(find "$APP_DIRECTORY" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        backup="$STATE_DIRECTORY/app-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup"
        cp -a "$APP_DIRECTORY/." "$backup/"
        warn "Vorhandene Projektdateien wurden nach $backup gesichert."
    fi

    find "$APP_DIRECTORY" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a "$temp_dir/repository/." "$APP_DIRECTORY/"
    rm -rf "$APP_DIRECTORY/.git"
    chown -R root:"$SERVICE_GROUP" "$APP_DIRECTORY"
    find "$APP_DIRECTORY" -type d -exec chmod 0750 {} +
    find "$APP_DIRECTORY" -type f -exec chmod 0640 {} +
    chmod 0750 "$APP_DIRECTORY/setup.sh"
    rm -rf "$temp_dir"
    trap - EXIT HUP INT TERM
}

prepare_python() {
    log "Python-Umgebung vorbereiten"
    [ -x "$VENV_DIRECTORY/bin/python" ] || python3 -m venv "$VENV_DIRECTORY"
    "$VENV_DIRECTORY/bin/python" -m pip install --upgrade pip
    "$VENV_DIRECTORY/bin/python" "$APP_DIRECTORY/backend.py" install --django-version "$DJANGO_VERSION" --gunicorn-version "$GUNICORN_VERSION"
    chown -R root:"$SERVICE_GROUP" "$VENV_DIRECTORY"
    chmod -R g+rX "$VENV_DIRECTORY"
}

prepare_postgresql() {
    log "PostgreSQL vorbereiten"
    DB_NAME="$(printf '%s' "$PROJECT_PATH" | tr '-' '_')"
    DB_USER="$DB_NAME"
    if [ -r "$ENVIRONMENT_FILE" ]; then
        DB_PASSWORD="$(sed -n 's/^DATABASE_PASSWORD=//p' "$ENVIRONMENT_FILE" | head -n 1)"
    else
        DB_PASSWORD=""
    fi
    [ -n "$DB_PASSWORD" ] || DB_PASSWORD="$(openssl rand -hex 32)"
    runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"$DB_USER\" LOGIN PASSWORD '$DB_PASSWORD';"
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"$DB_USER\" PASSWORD '$DB_PASSWORD';"
    runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || runuser -u postgres -- createdb --owner "$DB_USER" "$DB_NAME"
}

write_environment() {
    log "Geschuetzte Konfiguration schreiben"
    if [ -r "$ENVIRONMENT_FILE" ]; then
        SECRET_KEY="$(sed -n 's/^DJANGO_SECRET_KEY=//p' "$ENVIRONMENT_FILE" | head -n 1)"
    else
        SECRET_KEY=""
    fi
    [ -n "$SECRET_KEY" ] || SECRET_KEY="$(openssl rand -hex 64)"
    cat > "$ENVIRONMENT_FILE" <<EOF
PROJECT_NAME=$PROJECT_NAME
PROJECT_PATH=$PROJECT_PATH
PROJECT_URL_PATH=$PROJECT_URL_PATH
DJANGO_SECRET_KEY=$SECRET_KEY
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=$DOMAIN
DJANGO_ADMIN_ENABLED=$DJANGO_ADMIN_ENABLED
DJANGO_API_PREFIX=$DJANGO_API_PREFIX
DJANGO_ACCOUNT_PREFIX=$DJANGO_ACCOUNT_PREFIX
DJANGO_ADMIN_PREFIX=$DJANGO_ADMIN_PREFIX
DATABASE_ENGINE=postgresql
DATABASE_NAME=$DB_NAME
DATABASE_USER=$DB_USER
DATABASE_PASSWORD=$DB_PASSWORD
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
DATA_DIRECTORY=$DATA_DIRECTORY
MEDIA_DIRECTORY=$MEDIA_DIRECTORY
PRIVATE_DIRECTORY=$PRIVATE_DIRECTORY
STATE_DIRECTORY=$STATE_DIRECTORY
EOF
    chown root:"$SERVICE_GROUP" "$ENVIRONMENT_FILE"
    chmod 0640 "$ENVIRONMENT_FILE"
}

run_backend_tasks() {
    log "Django pruefen und migrieren"
    runuser -u "$SERVICE_USER" -- env PATH="$VENV_DIRECTORY/bin:/usr/bin:/bin" HOME="$PROJECT_ROOT_DIRECTORY" sh -c "set -a; . '$ENVIRONMENT_FILE'; set +a; cd '$APP_DIRECTORY'; python backend.py check"
    runuser -u "$SERVICE_USER" -- env PATH="$VENV_DIRECTORY/bin:/usr/bin:/bin" HOME="$PROJECT_ROOT_DIRECTORY" sh -c "set -a; . '$ENVIRONMENT_FILE'; set +a; cd '$APP_DIRECTORY'; python backend.py migrate"
}

write_systemd_service() {
    log "systemd-Dienst schreiben"
    cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=$PROJECT_NAME
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$APP_DIRECTORY
EnvironmentFile=$ENVIRONMENT_FILE
RuntimeDirectory=$PROJECT_PATH
RuntimeDirectoryMode=0750
ExecStart=$VENV_DIRECTORY/bin/gunicorn --bind unix:$GUNICORN_SOCKET_PATH --umask 007 --workers $GUNICORN_WORKERS --timeout $GUNICORN_TIMEOUT_SECONDS backend:application
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIRECTORY $GUNICORN_SOCKET_DIRECTORY

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable "$PROJECT_PATH.service"
}

render_caddyfile() {
    if [ "$PROJECT_URL_PATH" = "/" ]; then
        URL_ROUTE=""
        ROOT_ROUTE=""
    else
        URL_ROUTE="    handle_path ${PROJECT_URL_PATH%/}/* {"
        ROOT_ROUTE="    }"
    fi
    ADMIN_HANDLER=""
    [ "$DJANGO_ADMIN_ENABLED" = "true" ] && ADMIN_HANDLER="        handle $DJANGO_ADMIN_PREFIX/* {\n            reverse_proxy unix//$GUNICORN_SOCKET_PATH\n        }"
    FALLBACK_LINE=""
    [ -n "$FRONTEND_FALLBACK_FILE" ] && FALLBACK_LINE="            try_files {path} /$FRONTEND_FALLBACK_FILE\n"
    COMPRESSION=""
    [ "$CADDY_COMPRESSION_ENABLED" = "true" ] && COMPRESSION="    encode zstd gzip"
    SECURITY_HEADERS=""
    [ "$CADDY_SECURITY_HEADERS_ENABLED" = "true" ] && SECURITY_HEADERS='    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
        -Server
    }'
    printf '%s\n' "$CADDYFILE_TEMPLATE" | sed \
        -e "s|__SITE_ADDRESS__|$SITE_ADDRESS|g" \
        -e "s|__TLS_CONFIGURATION__|$(printf '%b' "$TLS_CONFIGURATION" | sed ':a;N;$!ba;s/\n/\\n/g')|g" \
        -e "s|__URL_ROUTE__|$URL_ROUTE|g" \
        -e "s|__ROOT_ROUTE__|$ROOT_ROUTE|g" \
        -e "s|__API_PREFIX__|$DJANGO_API_PREFIX|g" \
        -e "s|__ACCOUNT_PREFIX__|$DJANGO_ACCOUNT_PREFIX|g" \
        -e "s|__SOCKET_PATH__|$GUNICORN_SOCKET_PATH|g" \
        -e "s|__ADMIN_HANDLER__|$ADMIN_HANDLER|g" \
        -e "s|__APP_DIRECTORY__|$APP_DIRECTORY|g" \
        -e "s|__FALLBACK_LINE__|$FALLBACK_LINE|g" \
        -e "s|__COMPRESSION__|$COMPRESSION|g" \
        -e "s|__SECURITY_HEADERS__|$SECURITY_HEADERS|g"
}

write_caddy_configuration() {
    log "Caddy konfigurieren"
    render_caddyfile > "$LOCAL_CADDYFILE"
    cp "$LOCAL_CADDYFILE" "$SYSTEM_CADDY_SITE_FILE"
    chown root:root "$LOCAL_CADDYFILE" "$SYSTEM_CADDY_SITE_FILE"
    chmod 0644 "$LOCAL_CADDYFILE" "$SYSTEM_CADDY_SITE_FILE"
    grep -Fq 'import sites/*.caddy' /etc/caddy/Caddyfile || printf '\nimport sites/*.caddy\n' >> /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile
    systemctl enable caddy
}

start_and_check() {
    log "Dienste starten"
    systemctl restart "$PROJECT_PATH.service"
    systemctl reload caddy || systemctl restart caddy
    count=0
    while [ "$count" -lt 20 ]; do
        if runuser -u "$SERVICE_USER" -- curl --unix-socket "$GUNICORN_SOCKET_PATH" -fsS "http://localhost$DJANGO_API_PREFIX/health" >/dev/null 2>&1; then
            printf '\nInstallation abgeschlossen.\nProjekt: %s\nPfad: %s\nCaddy: %s\n' "$PROJECT_NAME" "$PROJECT_ROOT_DIRECTORY" "$SYSTEM_CADDY_SITE_FILE"
            return
        fi
        count=$((count + 1)); sleep 1
    done
    systemctl status "$PROJECT_PATH.service" --no-pager || true
    fail "Health Check fehlgeschlagen. Vorhandene Daten wurden nicht geloescht."
}

main() {
    validate_defaults
    set_paths
    configure_public_access
    install_system_packages
    prepare_identity_and_directories
    install_project_files
    prepare_python
    prepare_postgresql
    write_environment
    run_backend_tasks
    write_systemd_service
    write_caddy_configuration
    start_and_check
}

main "$@"
