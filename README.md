# Project Name

Kurze Beschreibung dieses Projekts.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/project-name/main/setup.sh | sudo bash
```

Das Setup fragt nach Domain und HTTP/HTTPS. Anschließend richtet das Setup Projektdateien, Python, PostgreSQL, Gunicorn, systemd und Caddy ein.

## Vor Verwendung anpassen

Am Anfang von `setup.sh`:

```sh
PROJECT_NAME="Project Name"
PROJECT_PATH="project-name"
PROJECT_REPOSITORY="https://github.com/florianthepro/project-name.git"
PROJECT_URL_PATH="/project-name"
```

In `backend.py`:

```python
FTPKIT_SOURCE = "git+https://github.com/florianthepro/ftpkit.git@main"
```

## Betrieb

```bash
sudo systemctl status project-name
sudo systemctl restart project-name
sudo journalctl -u project-name -f
```

## Dateien

```text
project-name/
├── README.md
├── structure.md
├── setup.sh
└── backend.py
```

Weitere Frontend- und Backend-Dateien werden passend zum konkreten Projekt ergänzt.
