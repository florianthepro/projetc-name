# Frontend-, Backend- und Serverstruktur

Dieses Dokument beschreibt das allgemeine Konzept für alle Projekte dieser Struktur. Projektspezifische Inhalte gehören in `README.md`, `backend.py` und die Frontend-Dateien.

## Repository-Struktur

```text
<repository>/
├── README.md
├── front-and-back-end-structure.md
├── setup.sh
├── backend.py
├── index.html
├── css/
│   ├── style.css
│   └── <seite>.css
├── js/
│   ├── app.js
│   └── <seite>.js
└── assets/
    ├── images/
    ├── icons/
    └── fonts/
```

## Aufgaben der Dateien

### `setup.sh`

`setup.sh` richtet ausschließlich Server und Betrieb ein:

- Debian und Root-Rechte prüfen
- Python, PostgreSQL, Caddy, Git und Systempakete installieren
- Projekt aus dem GitHub-Repository laden
- eigenen Linux-Benutzer und eigene Gruppe anlegen
- Projekt-, Daten- und Konfigurationsverzeichnisse anlegen
- virtuelle Python-Umgebung erstellen
- `backend.py install`, `check` und `migrate` ausführen
- eigene PostgreSQL-Datenbank und Datenbankrolle anlegen
- Gunicorn als systemd-Dienst einrichten
- projektspezifischen Gunicorn-Unix-Socket anlegen
- Caddy-Site erzeugen und bestehende Caddy-Installation erweitern
- Dienste starten und `/api/health` prüfen
- vorhandene Projektdateien vor Änderungen sichern
- verständlich melden, was erfolgreich war und was noch fehlt

`setup.sh` enthält keine fachliche Anwendungslogik.

### `backend.py`

`backend.py` enthält Django und die Backend-Anwendung:

- benötigte Python-Pakete installieren
- Django konfigurieren
- PostgreSQL aus geschützten Umgebungsvariablen verbinden
- WSGI-Objekt `application` für Gunicorn bereitstellen
- Django-Prüfungen und Migrationen ausführen
- Health-Endpunkt bereitstellen
- Djangos Benutzer, Passwort-Hashing, Sessions und CSRF-Schutz verwenden
- Login, Logout und Sessionstatus bereitstellen
- projektspezifische Modelle, APIs, Rechte und Uploadregeln enthalten

Verbindliche Befehle:

```bash
python backend.py install
python backend.py check
python backend.py migrate
python backend.py create-admin
```

Verbindliches Gunicorn-Objekt:

```python
application
```

### Frontend

- `index.html` ist der Einstiegspunkt.
- `css/style.css` enthält gemeinsame Gestaltung.
- zusätzliche CSS-Dateien enthalten seitenspezifische Gestaltung.
- `js/app.js` enthält gemeinsame Frontend-Logik.
- zusätzliche JavaScript-Dateien enthalten seitenspezifische Logik.
- `assets/` enthält ausschließlich feste öffentliche Dateien.
- Geheimnisse, Zugangsdaten und Sicherheitsentscheidungen gehören nie ins Frontend.
- Jede Frontend-Eingabe wird zusätzlich im Backend validiert.

## Zielstruktur auf dem Server

```text
/srv/webapps/<project-path>/
├── app/                          Dateien aus dem Repository
├── venv/                         isolierte Python-Umgebung
└── caddy/
    └── Caddyfile                 lokale Kopie der Caddy-Site

/var/lib/<project-path>/
├── media/                        durch die Anwendung erzeugte Dateien
├── private/                      nicht direkt öffentlich
└── state/                        Sicherungen und Laufzeitzustand

/etc/<project-path>/
└── environment                  Geheimnisse und Produktionswerte

/etc/systemd/system/
└── <project-path>.service

/etc/caddy/sites/
└── <project-path>.caddy

/run/<project-path>/
└── <project-path>.sock
```

## Bedeutung der Pfade

```text
/srv/webapps/<project-path>   statischer Projektcode und Python-Umgebung
/var/lib/<project-path>       dauerhaft veränderliche Anwendungsdaten
/etc/<project-path>           geschützte Konfiguration und Geheimnisse
/etc/systemd/system           systemweiter Dienststart
/etc/caddy/sites              aktive projektspezifische Caddy-Site
/run/<project-path>           flüchtiger Gunicorn-Socket
```

Der frei einstellbare gemeinsame Projektstamm ist:

```sh
PROJECTS_ROOT_DIRECTORY="/srv/webapps"
```

Das einzelne Projekt liegt darunter in:

```sh
PROJECT_PATH="<project-path>"
```

## Anfrageweg

```text
Browser
  → Caddy auf Port 80/443
      ├── HTML, CSS, JavaScript und Assets direkt aus app/
      └── /api, /account und optional /admin
            → Unix-Socket unter /run/<project-path>/
                → Gunicorn
                    → Django aus backend.py
                        → PostgreSQL
                        → /var/lib/<project-path>/
```

## Caddy

Auf einem Server läuft genau eine Caddy-Installation. Jedes Projekt erhält eine eigene Datei unter `/etc/caddy/sites/`.

Caddy übernimmt:

- Port 80 und 443
- automatisch verwaltetes HTTPS oder ein vorhandenes Zertifikat
- automatische Zertifikatserneuerung bei Caddy-verwaltetem HTTPS
- HTTP-zu-HTTPS-Weiterleitung
- statische Frontend-Dateien
- Reverse Proxy zum projektspezifischen Gunicorn-Socket
- gzip- und zstd-Komprimierung
- grundlegende Sicherheitsheader
- optionalen Frontend-Fallback

Caddy entscheidet nicht über Login, Uploadberechtigungen oder private Dateien. Diese Regeln gehören in `backend.py`.

## Django und PostgreSQL

Django verwendet PostgreSQL unter anderem für:

- Benutzer
- Gruppen und Berechtigungen
- Sessions
- Migrationen
- projektspezifische Datenmodelle

Jedes Projekt erhält eine eigene Datenbank, eine eigene Datenbankrolle und ein zufällig erzeugtes Passwort. Das Passwort wird nur in `/etc/<project-path>/environment` gespeichert.

## Mehrere Projekte auf demselben Server

Gemeinsam verwendet werden:

```text
Caddy
PostgreSQL
Debian-Systempakete
```

Für jedes Projekt getrennt sind:

```text
PROJECT_PATH
Linux-Benutzer und Gruppe
Repository und Projektordner
Python-venv
PostgreSQL-Datenbank und Rolle
systemd-Dienst
Gunicorn-Socket
Caddy-Site
Daten- und Konfigurationsordner
```

`PROJECT_PATH`, Domain und öffentlicher URL-Pfad dürfen nicht mit einer vorhandenen Installation kollidieren.

## Rechte

- Projektcode und venv sind im Betrieb nur lesbar.
- Der Projektdienst darf unter `/var/lib/<project-path>` schreiben.
- Der Gunicorn-Socket ist nur für Projektgruppe und Caddy erreichbar.
- `/etc/<project-path>/environment` ist nur für root und die Projektgruppe lesbar.
- private Dateien werden nicht direkt durch Caddy ausgeliefert.
- die Anwendung läuft nie als root.

## Frontend-Fallback

```sh
FRONTEND_FALLBACK_FILE=""
```

Leer bedeutet echtes HTTP 404 bei unbekannten Dateien oder Routen.

Für eine JavaScript-Single-Page-Anwendung:

```sh
FRONTEND_FALLBACK_FILE="index.html"
```

Dann liefert Caddy bei unbekannten Frontend-Routen `index.html`, damit JavaScript die Route verarbeitet.

## Vor dem öffentlichen Einsatz zu klären

- Domain und öffentlicher URL-Pfad
- Benutzername oder E-Mail als Anmeldung
- Registrierung und Kontoaktivierung
- Rollen und objektbezogene Berechtigungen
- Login-Rate-Limit und Sperrlogik
- Passwort-Reset und E-Mail-Versand
- projektspezifische Modelle und Migrationen
- Uploadtypen, Größenlimits und Malware-Prüfung
- öffentliche und private Dateien
- PostgreSQL- und Dateibackups
- Wiederherstellungstest
- Monitoring und Alarmierung
- Log-Aufbewahrung
- Datenschutz- und Aufbewahrungsregeln
