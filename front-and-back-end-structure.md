# Frontend-, Backend- und Serverstruktur

## Repository

```text
new-projekt/
├── README.md
├── front-and-back-end-structure.md
├── setup.sh
├── backend.py
├── index.html
├── css/
│   ├── style.css
│   └── login.css
├── js/
│   ├── app.js
│   └── login.js
└── assets/
    ├── images/
    ├── icons/
    └── fonts/
```

## Aufgaben

- `setup.sh`: Debian-Pakete, Dienstbenutzer, Verzeichnisse, PostgreSQL, venv, systemd, Caddy und Health Check.
- `backend.py`: Python-Abhängigkeiten, Django-Konfiguration, Migrationen, WSGI-Anwendung, Health, Login, Logout und Sessionstatus.
- `index.html`: Einstieg des statischen Frontends.
- `css/`: globale und seitenspezifische Darstellung.
- `js/`: Health Check, Sitzungsstatus und Loginablauf.
- `assets/`: feste Bilder, Icons und Schriften.

## Zielstruktur auf dem Server

```text
/srv/webapps/new-projekt/
├── app/                         Projektdateien aus GitHub
├── venv/                        isolierte Python-Umgebung
└── caddy/
    └── Caddyfile                lokale Kopie der erzeugten Site

/var/lib/new-projekt/
├── media/                       Anwendungsdateien
├── private/                     nicht direkt öffentlich
└── state/                       Backups und Laufzeitzustand

/etc/new-projekt/
└── environment                  Geheimnisse und Produktionswerte

/etc/systemd/system/
└── new-projekt.service

/etc/caddy/sites/
└── new-projekt.caddy

/run/new-projekt/
└── new-projekt.sock
```

## Anfrageweg

```text
Browser
  → Caddy auf Port 80/443
      → HTML, CSS, JS und Assets direkt aus /srv/webapps/new-projekt/app
      → /api und /account über /run/new-projekt/new-projekt.sock
          → Gunicorn
              → Django in backend.py
                  → PostgreSQL
```

## Skalierung auf einem Server

Es gibt nur einen Caddy- und einen PostgreSQL-Dienst. Jedes Webprojekt erhält:

- eigenen Ordner unter `/srv/webapps/<project-path>`
- eigenen Linux-Benutzer
- eigene venv
- eigene PostgreSQL-Datenbank und Datenbankrolle
- eigenen systemd-Dienst
- eigenen Gunicorn-Socket
- eigene Caddy-Site unter `/etc/caddy/sites/`

`PROJECT_PATH` muss serverweit eindeutig sein. Domain und `PROJECT_URL_PATH` dürfen nicht mit einer vorhandenen Caddy-Route kollidieren.

## Was in backend.py mindestens vorhanden sein muss

- vor Django-Import ausführbarer Befehl `install`
- `application` als WSGI-Objekt für Gunicorn
- `check`, `migrate` und `create-admin`
- `/api/health`
- Datenbankkonfiguration ausschließlich aus Umgebungsvariablen
- sichere Session- und CSRF-Einstellungen
- keine Geheimnisse im Repository

## Vor der Fachentwicklung zu klären

- Benutzername oder E-Mail als Anmeldung
- Registrierung erlaubt oder nur Admin-Anlage
- Rollen und objektbezogene Berechtigungen
- Login-Rate-Limit und Sperrlogik
- eigene Datenmodelle und Migrationen
- Datei-Uploads, Typen, Größen und Malware-Prüfung
- öffentliche oder private Dateien
- Backup und Wiederherstellung von PostgreSQL und `/var/lib/<projekt>`
- Monitoring, Alarmierung und Log-Aufbewahrung
- URL unter eigener Domain oder gemeinsamem Unterpfad
- SPA-Fallback oder echte 404-Antwort

## Rechte

- Projektcode und venv sind im Betrieb nur lesbar.
- Der Dienstbenutzer darf nur unter `/var/lib/<projekt>` und am eigenen Socket schreiben.
- `/etc/<projekt>/environment` ist für root schreibbar und für die Projektgruppe lesbar.
- Private Dateien werden nicht direkt von Caddy ausgeliefert.
