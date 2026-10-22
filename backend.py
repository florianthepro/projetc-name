#!/usr/bin/env python3
import argparse
import importlib
import importlib.util
import os
import subprocess
import sys


# ftpkit ist die gemeinsame, framework-unabhängige Python-Bibliothek.
# Allgemeine Funktionen für mehrere Projekte liegen dort.
# Django- und projektspezifische Logik bleibt in diesem Projekt.
FTPKIT_SOURCE = "git+https://github.com/florianthepro/ftpkit.git@main"


def install_package(package: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "pip", "install", package],
        check=True,
    )


def load_ftpkit(allow_install: bool = False):
    if importlib.util.find_spec("ftpkit") is None:
        if not allow_install:
            raise RuntimeError(
                "ftpkit fehlt. Zuerst `python backend.py install` ausführen."
            )
        install_package(FTPKIT_SOURCE)
        importlib.invalidate_caches()

    return importlib.import_module("ftpkit")


def install_dependencies(django_version: str, gunicorn_version: str) -> None:
    load_ftpkit(allow_install=True)
    install_package(f"Django=={django_version}")
    install_package(f"gunicorn=={gunicorn_version}")
    install_package("psycopg[binary]>=3.2,<4")


# Installation muss vor den Django-Imports möglich sein, weil eine neue venv
# Django und ftpkit zunächst noch nicht enthält.
if len(sys.argv) > 1 and sys.argv[1] == "install":
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("--django-version", default="5.2.*")
    parser.add_argument("--gunicorn-version", default="23.*")
    args = parser.parse_args()
    install_dependencies(args.django_version, args.gunicorn_version)
    raise SystemExit(0)


# Beim normalen Start wird ftpkit nur importiert. Es werden keine Pakete
# unkontrolliert aus dem Internet nachgeladen.
ftpkit = load_ftpkit()

from django.conf import settings


if not settings.configured:
    settings.configure(
        DEBUG=os.getenv("DJANGO_DEBUG", "false").lower() == "true",
        SECRET_KEY=os.environ["DJANGO_SECRET_KEY"],
        ALLOWED_HOSTS=[
            value.strip()
            for value in os.getenv("DJANGO_ALLOWED_HOSTS", "localhost").split(",")
            if value.strip()
        ],
        ROOT_URLCONF=__name__,
        INSTALLED_APPS=[
            "django.contrib.auth",
            "django.contrib.contenttypes",
            "django.contrib.sessions",
        ],
        MIDDLEWARE=[
            "django.middleware.security.SecurityMiddleware",
            "django.contrib.sessions.middleware.SessionMiddleware",
            "django.middleware.common.CommonMiddleware",
            "django.middleware.csrf.CsrfViewMiddleware",
            "django.contrib.auth.middleware.AuthenticationMiddleware",
            "django.middleware.clickjacking.XFrameOptionsMiddleware",
        ],
        DATABASES={
            "default": {
                "ENGINE": "django.db.backends.postgresql",
                "NAME": os.environ["DATABASE_NAME"],
                "USER": os.environ["DATABASE_USER"],
                "PASSWORD": os.environ["DATABASE_PASSWORD"],
                "HOST": os.getenv("DATABASE_HOST", "127.0.0.1"),
                "PORT": os.getenv("DATABASE_PORT", "5432"),
                "CONN_MAX_AGE": 60,
            }
        },
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SECURE=os.getenv("DJANGO_HTTPS", "true").lower() == "true",
        SESSION_COOKIE_SAMESITE="Lax",
        CSRF_COOKIE_SECURE=os.getenv("DJANGO_HTTPS", "true").lower() == "true",
        SECURE_PROXY_SSL_HEADER=("HTTP_X_FORWARDED_PROTO", "https"),
        USE_TZ=True,
        DEFAULT_AUTO_FIELD="django.db.models.BigAutoField",
    )


import django

django.setup()

from django.core.management import call_command
from django.core.wsgi import get_wsgi_application
from django.http import JsonResponse
from django.urls import path
from django.views.decorators.http import require_GET


@require_GET
def health(request):
    return JsonResponse({"status": "ok"})


api_prefix = os.getenv("DJANGO_API_PREFIX", "/api").strip("/")
urlpatterns = [path(f"{api_prefix}/health", health)]


# Gunicorn lädt das Backend über `backend:application`.
application = get_wsgi_application()


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    commands.add_parser("migrate")
    args = parser.parse_args()

    if args.command == "check":
        call_command("check", "--deploy")
    elif args.command == "migrate":
        call_command("migrate", interactive=False)


if __name__ == "__main__":
    main()
