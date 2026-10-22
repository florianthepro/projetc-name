#!/bin/sh
set -eu

# Nur dieser Block wird pro Projekt angepasst.
PROJECT_NAME="Project Name"
PROJECT_PATH="project-name"
PROJECT_REPOSITORY="https://github.com/florianthepro/project-name.git"
PROJECT_BRANCH="main"
PROJECTS_ROOT_DIRECTORY="/srv/webapps"
PROJECT_URL_PATH="/project-name"

DJANGO_VERSION="5.2.*"
GUNICORN_VERSION="23.*"
GUNICORN_WORKERS="3"
GUNICORN_TIMEOUT_SECONDS="30"

DJANGO_API_PREFIX="/api"
FRONTEND_DIRECTORY=""
FRONTEND_FALLBACK_FILE=""

CADDY_SITES_DIRECTORY="/etc/caddy/sites"

log() {
    printf '\n[%s] %s\n' "$PROJECT_PATH" "$1"
}

fail() {
    printf '\n[%s] Fehler: %s\n' "$PROJECT_PATH" "$1" >&2
    exit 1
}

prompt() {
    question="$1"
    default="$2"
    printf '%s [%s]: ' "$question" "$default" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [ -n "$answer" ] && printf '%s' "$answer" || printf '%s' "$default"
}

validate() {
    [ "$(id -u)" -eq 0 ] || fail "Mit sudo oder als root ausführen."
    [ -r /etc/os-release ] || fail "/etc/os-release fehlt."
    . /etc/os-release
    [ "${ID:-}" = "debian" ] || fail "Unterstützt wird Debian."
    printf '%s' "$PROJECT_PATH" | grep -Eq '^[a-z][a-z0-9-]{1,48}$' || fail "PROJECT_PATH ist ungültig."
}

set_paths() {
    PROJECT_ROOT="$PROJECTS_ROOT_DIRECTORY/$PROJECT_PATH"
    APP_DIRECTORY="$PROJECT_ROOT/app"
    VENV_DIRECTORY="$PROJECT_ROOT/venv"
    LOCAL_CADDY_DIRECTORY="$PROJECT_ROOT/caddy"
    DATA_DIRECTORY="/var/lib/$PROJECT_PATH"
    STATE_DIRECTORY="$DATA_DIRECTORY/state"
    CONFIG_DIRECTORY="/etc/$PROJECT_PATH"
    ENVIRONMENT_FILE="$CONFIG_DIRECTORY/environment"
    SERVICE_FILE="/etc/systemd/system/$PROJECT_PATH.service"
    CADDY_SITE_FILE="$CADDY_SITES_DIRECTORY/$PROJECT_PATH.caddy"
    SOCKET_DIRECTORY="/run/$PROJECT_PATH"
    SOCKET_PATH="$SOCKET_DIRECTORY/$PROJECT_PATH.sock"
    SERVICE_USER="$PROJECT_PATH"
    SERVICE_GROUP="$PROJECT_PATH"
}

configure_access() {
    printf '\n[1] HTTPS automatisch\n[2] HTTPS mit Zertifikatsdateien\n[3] HTTP\n' > /dev/tty
    TLS_MODE="${TLS_MODE:-$(prompt "Verbindung" "1")}" 
    DOMAIN="${DOMAIN:-$(prompt "Domain oder IP" "localhost")}" 
    SITE_ADDRESS="$DOMAIN"
    TLS_LINE=""

    case "$TLS_MODE" in
        1) DJANGO_HTTPS="true" ;;
        2)
            CERTIFICATE_PATH="${CERTIFICATE_PATH:-$(prompt "Zertifikat" "/etc/ssl/certs/$PROJECT_PATH.pem")}" 
            PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$(prompt "Privater Schlüssel" "/etc/ssl/private/$PROJECT_PATH.key")}" 
            [ -r "$CERTIFICATE_PATH" ] || fail "Zertifikat nicht lesbar."
            [ -r "$PRIVATE_KEY_PATH" ] || fail "Privater Schlüssel nicht lesbar."
            TLS_LINE="    tls $CERTIFICATE_PATH $PRIVATE_KEY_PATH"
            DJANGO_HTTPS="true"
            ;;
        3)
            SITE_ADDRESS="http://$DOMAIN"
            DJANGO_HTTPS="false"
            ;;
        *) fail "Ungültige Auswahl." ;;
    esac
}

install_system() {
    log "Systempakete installieren"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates caddy curl git openssl postgresql python3 python3-pip python3-venv
}

prepare_directories() {
    log "Benutzer und Verzeichnisse vorbereiten"
    id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --user-group --home-dir "$PROJECT_ROOT" --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    install -d -o root -g "$SERVICE_GROUP" -m 0750 "$PROJECTS_ROOT_DIRECTORY" "$PROJECT_ROOT" "$APP_DIRECTORY" "$VENV_DIRECTORY" "$LOCAL_CADDY_DIRECTORY"
    install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$DATA_DIRECTORY" "$STATE_DIRECTORY"
    install -d -o root -g "$SERVICE_GROUP" -m 0750 "$CONFIG_DIRECTORY"
    install -d -o root -g root -m 0755 "$CADDY_SITES_DIRECTORY"
    usermod -a -G "$SERVICE_GROUP" caddy
}

install_repository() {
    log "Repository laden"
    temporary="$(mktemp -d)"
    trap 'rm -rf "$temporary"' EXIT HUP INT TERM
    git clone --branch "$PROJECT_BRANCH" --depth 1 "$PROJECT_REPOSITORY" "$temporary/repository"
    [ -f "$temporary/repository/backend.py" ] || fail "backend.py fehlt."

    if [ -n "$(find "$APP_DIRECTORY" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        backup="$STATE_DIRECTORY/app-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup"
        cp -a "$APP_DIRECTORY/." "$backup/"
        log "Bestehende Dateien gesichert: $backup"
    fi

    find "$APP_DIRECTORY" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a "$temporary/repository/." "$APP_DIRECTORY/"
    rm -rf "$APP_DIRECTORY/.git"
    chown -R root:"$SERVICE_GROUP" "$APP_DIRECTORY"
    chmod -R u=rwX,g=rX,o= "$APP_DIRECTORY"
    rm -rf "$temporary"
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

prepare_database() {
    log "PostgreSQL vorbereiten"
    DB_NAME="$(printf '%s' "$PROJECT_PATH" | tr '-' '_')"
    DB_USER="$DB_NAME"
    DB_PASSWORD="$(openssl rand -hex 32)"
    [ -r "$ENVIRONMENT_FILE" ] && DB_PASSWORD="$(sed -n 's/^DATABASE_PASSWORD=//p' "$ENVIRONMENT_FILE" | head -n 1)"
    [ -n "$DB_PASSWORD" ] || DB_PASSWORD="$(openssl rand -hex 32)"

    runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"$DB_USER\" LOGIN PASSWORD '$DB_PASSWORD';"
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"$DB_USER\" PASSWORD '$DB_PASSWORD';"
    runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || runuser -u postgres -- createdb --owner "$DB_USER" "$DB_NAME"
}

write_environment() {
    log "Produktionswerte schreiben"
    SECRET_KEY="$(openssl rand -hex 64)"
    [ -r "$ENVIRONMENT_FILE" ] && SECRET_KEY="$(sed -n 's/^DJANGO_SECRET_KEY=//p' "$ENVIRONMENT_FILE" | head -n 1)"
    [ -n "$SECRET_KEY" ] || SECRET_KEY="$(openssl rand -hex 64)"

    cat > "$ENVIRONMENT_FILE" <<EOF
DJANGO_SECRET_KEY=$SECRET_KEY
DJANGO_DEBUG=false
DJANGO_HTTPS=$DJANGO_HTTPS
DJANGO_ALLOWED_HOSTS=$DOMAIN
DJANGO_API_PREFIX=$DJANGO_API_PREFIX
DATABASE_NAME=$DB_NAME
DATABASE_USER=$DB_USER
DATABASE_PASSWORD=$DB_PASSWORD
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432
EOF
    chown root:"$SERVICE_GROUP" "$ENVIRONMENT_FILE"
    chmod 0640 "$ENVIRONMENT_FILE"
}

run_backend_tasks() {
    log "Django prüfen und migrieren"
    runuser -u "$SERVICE_USER" -- sh -c "set -a; . '$ENVIRONMENT_FILE'; set +a; cd '$APP_DIRECTORY'; '$VENV_DIRECTORY/bin/python' backend.py check"
    runuser -u "$SERVICE_USER" -- sh -c "set -a; . '$ENVIRONMENT_FILE'; set +a; cd '$APP_DIRECTORY'; '$VENV_DIRECTORY/bin/python' backend.py migrate"
}

write_service() {
    log "systemd-Dienst schreiben"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=$PROJECT_NAME
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$APP_DIRECTORY
EnvironmentFile=$ENVIRONMENT_FILE
RuntimeDirectory=$PROJECT_PATH
RuntimeDirectoryMode=0750
ExecStart=$VENV_DIRECTORY/bin/gunicorn --bind unix:$SOCKET_PATH --umask 007 --workers $GUNICORN_WORKERS --timeout $GUNICORN_TIMEOUT_SECONDS backend:application
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIRECTORY $SOCKET_DIRECTORY

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$PROJECT_PATH.service"
}

write_caddy() {
    log "Caddy-Site schreiben"
    FRONTEND_BLOCK=""
    if [ -n "$FRONTEND_DIRECTORY" ]; then
        FRONTEND_ROOT="$APP_DIRECTORY/$FRONTEND_DIRECTORY"
        FALLBACK=""
        [ -n "$FRONTEND_FALLBACK_FILE" ] && FALLBACK="            try_files {path} /$FRONTEND_FALLBACK_FILE"
        FRONTEND_BLOCK="        handle {\n            root * $FRONTEND_ROOT\n$FALLBACK\n            file_server\n        }"
    fi

    cat > "$CADDY_SITE_FILE" <<EOF
$SITE_ADDRESS {
$TLS_LINE
    encode zstd gzip

    handle_path ${PROJECT_URL_PATH%/}/* {
        handle $DJANGO_API_PREFIX/* {
            reverse_proxy unix//$SOCKET_PATH
        }

$FRONTEND_BLOCK

        handle {
            reverse_proxy unix//$SOCKET_PATH
        }
    }

    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
        -Server
    }
}
EOF

    cp "$CADDY_SITE_FILE" "$LOCAL_CADDY_DIRECTORY/Caddyfile"
    grep -Fq 'import sites/*.caddy' /etc/caddy/Caddyfile || printf '\nimport sites/*.caddy\n' >> /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile
    systemctl enable caddy
}

start_and_check() {
    log "Dienste starten"
    systemctl restart "$PROJECT_PATH.service"
    systemctl reload caddy || systemctl restart caddy

    attempts=0
    while [ "$attempts" -lt 20 ]; do
        if runuser -u "$SERVICE_USER" -- curl --unix-socket "$SOCKET_PATH" -fsS "http://localhost$DJANGO_API_PREFIX/health" >/dev/null 2>&1; then
            printf '\nInstallation abgeschlossen.\nProjekt: %s\nPfad: %s\n' "$PROJECT_NAME" "$PROJECT_ROOT"
            return
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    systemctl status "$PROJECT_PATH.service" --no-pager || true
    fail "Health Check fehlgeschlagen. Vorhandene Daten wurden nicht gelöscht."
}

main() {
    validate
    set_paths
    configure_access
    install_system
    prepare_directories
    install_repository
    prepare_python
    prepare_database
    write_environment
    run_backend_tasks
    write_service
    write_caddy
    start_and_check
}

main "$@"
