# Projektstruktur

Diese Vorlage definiert nur die gemeinsame Grundlage. Sie schreibt nicht vor, ob ein Projekt Login, Registrierung, Uploads, Admin-Oberfläche oder eine bestimmte Frontend-Struktur besitzt.

## Dateien der Vorlage

```text
project-name/
├── README.md       projektspezifische Kurzbeschreibung und Installation
├── structure.md    allgemeines technisches Konzept
├── setup.sh        Serverinstallation und Betrieb
└── backend.py      minimale Django-Anwendung
```

## Zuständigkeiten

### setup.sh

`setup.sh` ist nur für Infrastruktur zuständig:

- Debian prüfen
- benötigte Systempakete installieren
- Repository herunterladen
- Projektbenutzer und Verzeichnisse anlegen
- virtuelle Python-Umgebung erstellen
- `backend.py install`, `check` und `migrate` ausführen
- PostgreSQL-Datenbank und Datenbankbenutzer anlegen
- Gunicorn als systemd-Dienst einrichten
- Caddy installieren oder die vorhandene Installation erweitern
- HTTP oder HTTPS konfigurieren
- Dienste starten
- Health Check ausführen
- vorhandene Projektdateien vor dem Ersetzen sichern

`setup.sh` enthält keine Login-, Upload- oder Geschäftslogik.

### backend.py

`backend.py` enthält die minimale Django-Grundlage:

- `ftpkit` prüfen und beim Installationsbefehl installieren
- Django, Gunicorn und PostgreSQL-Treiber installieren
- Django aus geschützten Umgebungsvariablen konfigurieren
- PostgreSQL verbinden
- WSGI-Objekt `application` bereitstellen
- Befehle `install`, `check` und `migrate` bereitstellen
- `GET /api/health` bereitstellen

Nicht automatisch enthalten sind:

- Login und Registrierung
- Django-Admin
- eigene Datenmodelle
- Uploads
- Rollen und projektspezifische Berechtigungen
- projektspezifische API-Endpunkte
- Frontend-Dateien

Diese Bestandteile werden nur ergänzt, wenn das konkrete Projekt sie benötigt.

## ftpkit

`ftpkit` ist eine framework-unabhängige Python-Bibliothek für allgemeine, wiederverwendbare Funktionen.

In `ftpkit` gehören beispielsweise:

```text
Datei- und Pfadfunktionen
Validierung
Systeminformationen
Netzwerk-Hilfsfunktionen
allgemeine Sicherheitsprüfungen
```

Nicht in `ftpkit` gehören:

```text
Django-Modelle
Django-Routen
Sessions
Loginabläufe
projektspezifische Geschäftslogik
```

`backend.py install` installiert `ftpkit`, falls es in der Projekt-venv fehlt. Beim normalen Gunicorn-Start wird nichts aus dem Internet installiert oder aktualisiert.

## Serverstruktur

```text
/srv/webapps/<project-path>/
├── app/                 Dateien aus dem Repository
├── venv/                isolierte Python-Umgebung
└── caddy/
    └── Caddyfile        lokale Kopie der erzeugten Caddy-Site

/var/lib/<project-path>/
└── state/               Sicherungen und Laufzeitzustand

/etc/<project-path>/
└── environment          Geheimnisse und Produktionswerte

/etc/systemd/system/
└── <project-path>.service

/etc/caddy/sites/
└── <project-path>.caddy

/run/<project-path>/
└── <project-path>.sock
```

## Ablauf

```text
Browser
  → Caddy auf Port 80 oder 443
      → projektspezifische statische Dateien, falls vorhanden
      → dynamische Routen über den Unix-Socket
          → Gunicorn
              → Django aus backend.py
                  → PostgreSQL
```

## Mehrere Projekte auf einem Server

Gemeinsam genutzt werden:

```text
Caddy
PostgreSQL
Debian-Systempakete
```

Pro Projekt getrennt sind:

```text
PROJECT_PATH
Linux-Benutzer und Gruppe
Projektordner
Python-venv
PostgreSQL-Datenbank und Rolle
systemd-Dienst
Gunicorn-Socket
Caddy-Site
Konfiguration und Laufzeitdaten
```

`PROJECT_PATH`, Domain und öffentliche URL dürfen nicht mit einer vorhandenen Installation kollidieren.

## Erweiterung eines konkreten Projekts

Je nach Projekt können später ergänzt werden:

```text
index.html
css/
js/
assets/
Django-Modelle
API-Routen
Login und Registrierung
Admin-Oberfläche
Uploads
Tests
```

Vor dem öffentlichen Einsatz müssen Berechtigungen, Rate Limiting, Backups, Monitoring, Datenschutz und Wiederherstellung projektspezifisch festgelegt werden.
