# {{PROJECT_NAME}}

{{KURZE_PROJEKTBESCHREIBUNG}}

## Aufruf

```text
{{PROJEKT_URL}}
```

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/{{GITHUB_BENUTZER}}/{{REPOSITORY}}/main/setup.sh | sudo bash
```

Während der Installation werden Domain, HTTP/HTTPS und gegebenenfalls vorhandene Zertifikatsdateien abgefragt.

## Projektwerte

Die projektspezifischen Werte stehen am Anfang von `setup.sh`:

```sh
PROJECT_NAME="{{ANZEIGENAME}}"
PROJECT_PATH="{{TECHNISCHER_NAME}}"
PROJECT_REPOSITORY="https://github.com/{{GITHUB_BENUTZER}}/{{REPOSITORY}}.git"
PROJECT_BRANCH="main"
PROJECT_URL_PATH="/{{URL_PFAD}}"
```

`PROJECT_PATH` muss klein geschrieben, serverweit eindeutig und ohne Leerzeichen sein.

## Inhalt

```text
{{REPOSITORY}}/
├── README.md
├── front-and-back-end-structure.md
├── setup.sh
├── backend.py
├── index.html
├── css/
├── js/
└── assets/
```

## Backend

`backend.py` enthält die minimale Django-Anwendung und wird um die projektspezifische Logik ergänzt:

- {{DATENMODELLE}}
- {{API_ENDPUNKTE}}
- {{ROLLEN_UND_RECHTE}}
- {{UPLOADREGELN}}
- {{WEITERE_PYTHON_PAKETE}}

Grundlegende Endpunkte:

```text
GET  /api/health
GET  /account/session
POST /account/login
POST /account/logout
```

## Betrieb

```bash
sudo systemctl status {{PROJECT_PATH}}
sudo systemctl restart {{PROJECT_PATH}}
sudo journalctl -u {{PROJECT_PATH}} -f
```

## Noch festzulegen

- produktive Domain: `{{DOMAIN}}`
- URL-Pfad: `{{URL_PFAD}}`
- Anmeldung über: `{{BENUTZERNAME_ODER_EMAIL}}`
- Registrierung: `{{AKTIV_ODER_DEAKTIVIERT}}`
- Django-Admin: `{{AKTIV_ODER_DEAKTIVIERT}}`
- Frontend-Fallback: `{{LEER_FUER_404_ODER_INDEX_HTML}}`
- Backupziel: `{{BACKUPZIEL}}`
- Monitoring: `{{MONITORING}}`
