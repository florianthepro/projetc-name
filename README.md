# New Projekt

Minimale Vorlage für ein statisches Frontend mit einem Django-Backend auf Debian. Caddy liefert das Frontend aus und leitet API- und Account-Anfragen über einen projektspezifischen Unix-Socket an Gunicorn weiter.

## Vor der Verwendung anpassen

Am Anfang von `setup.sh` mindestens prüfen:

- `PROJECT_NAME`
- `PROJECT_PATH`
- `PROJECT_REPOSITORY`
- `PROJECT_URL_PATH`
- Django- und Gunicorn-Version
- Django-Admin aktiv oder deaktiviert
- Frontend-Fallback leer für 404 oder `index.html` für eine SPA

In `backend.py` müssen projektspezifische Modelle, APIs, Rechte, Uploadregeln und zusätzliche Pakete ergänzt werden.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/new-projekt/main/setup.sh | sudo bash
```

Das Setup fragt nach HTTP oder HTTPS und der Domain. Bei automatisch verwaltetem HTTPS beschafft und erneuert Caddy das Zertifikat.

## Betrieb

```bash
sudo systemctl status new-projekt
sudo systemctl restart new-projekt
sudo journalctl -u new-projekt -f
```

Django-Administrator anlegen, nachdem `DJANGO_ADMIN_ENABLED="true"` gesetzt und das Setup erneut ausgeführt wurde:

```bash
sudo -u new-projekt sh -c 'set -a; . /etc/new-projekt/environment; set +a; /srv/webapps/new-projekt/venv/bin/python /srv/webapps/new-projekt/app/backend.py create-admin'
```

## Wichtige Endpunkte

```text
GET  /api/health
GET  /account/session
POST /account/login
POST /account/logout
```

Login und Logout verwenden Djangos Session- und CSRF-Schutz. Das Frontend muss vor POST-Anfragen zuerst `/account/session` aufrufen und den gesetzten CSRF-Cookie als `X-CSRFToken` mitsenden.

## Hinweis zur Vorlage

Die Dateien bilden eine Mindeststruktur, keine fertige Fachanwendung. Vor einem öffentlichen Einsatz müssen insbesondere Domain, URL-Pfad, Berechtigungen, Rate Limiting, Uploadregeln, Backups, Monitoring und projektspezifische Tests festgelegt werden.
