#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys


def install_dependencies(django_version: str, gunicorn_version: str) -> None:
    packages = [
        f"Django=={django_version}",
        f"gunicorn=={gunicorn_version}",
        "psycopg[binary]>=3.2,<4",
    ]
    subprocess.run([sys.executable, "-m", "pip", "install", *packages], check=True)


def configure_django() -> None:
    from django.conf import settings

    if settings.configured:
        return

    admin_enabled = os.getenv("DJANGO_ADMIN_ENABLED", "false").lower() == "true"
    installed_apps = [
        "django.contrib.auth",
        "django.contrib.contenttypes",
        "django.contrib.sessions",
        "django.contrib.messages",
        "django.contrib.staticfiles",
    ]
    if admin_enabled:
        installed_apps.append("django.contrib.admin")

    settings.configure(
        DEBUG=os.getenv("DJANGO_DEBUG", "false").lower() == "true",
        SECRET_KEY=os.environ["DJANGO_SECRET_KEY"],
        ALLOWED_HOSTS=[x.strip() for x in os.getenv("DJANGO_ALLOWED_HOSTS", "localhost").split(",") if x.strip()],
        ROOT_URLCONF=__name__,
        INSTALLED_APPS=installed_apps,
        MIDDLEWARE=[
            "django.middleware.security.SecurityMiddleware",
            "django.contrib.sessions.middleware.SessionMiddleware",
            "django.middleware.common.CommonMiddleware",
            "django.middleware.csrf.CsrfViewMiddleware",
            "django.contrib.auth.middleware.AuthenticationMiddleware",
            "django.contrib.messages.middleware.MessageMiddleware",
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
        TEMPLATES=[
            {
                "BACKEND": "django.template.backends.django.DjangoTemplates",
                "DIRS": [],
                "APP_DIRS": True,
                "OPTIONS": {
                    "context_processors": [
                        "django.template.context_processors.request",
                        "django.contrib.auth.context_processors.auth",
                        "django.contrib.messages.context_processors.messages",
                    ]
                },
            }
        ],
        PASSWORD_HASHERS=[
            "django.contrib.auth.hashers.PBKDF2PasswordHasher",
            "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
            "django.contrib.auth.hashers.Argon2PasswordHasher",
            "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
            "django.contrib.auth.hashers.ScryptPasswordHasher",
        ],
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


if len(sys.argv) > 1 and sys.argv[1] == "install":
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("--django-version", default="5.2.*")
    parser.add_argument("--gunicorn-version", default="23.*")
    install_args = parser.parse_args()
    install_dependencies(install_args.django_version, install_args.gunicorn_version)
    raise SystemExit(0)

configure_django()

from django.contrib import admin
from django.contrib.auth import authenticate, login, logout
from django.core.management import call_command
from django.http import JsonResponse
from django.urls import path
from django.views.decorators.csrf import ensure_csrf_cookie
from django.views.decorators.http import require_GET, require_POST
import json


@require_GET
def health(request):
    return JsonResponse({"status": "ok"})


@ensure_csrf_cookie
@require_GET
def session_status(request):
    if not request.user.is_authenticated:
        return JsonResponse({"authenticated": False})
    return JsonResponse({
        "authenticated": True,
        "username": request.user.get_username(),
    })


@require_POST
def login_view(request):
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "Ungueltiges JSON"}, status=400)

    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", ""))
    if not username or not password:
        return JsonResponse({"error": "Benutzername und Passwort erforderlich"}, status=400)

    user = authenticate(request, username=username, password=password)
    if user is None:
        return JsonResponse({"error": "Anmeldung fehlgeschlagen"}, status=401)

    login(request, user)
    return JsonResponse({"authenticated": True, "username": user.get_username()})


@require_POST
def logout_view(request):
    logout(request)
    return JsonResponse({"authenticated": False})


api_prefix = os.getenv("DJANGO_API_PREFIX", "/api").strip("/")
account_prefix = os.getenv("DJANGO_ACCOUNT_PREFIX", "/account").strip("/")
admin_prefix = os.getenv("DJANGO_ADMIN_PREFIX", "/admin").strip("/")

urlpatterns = [
    path(f"{api_prefix}/health", health),
    path(f"{account_prefix}/session", session_status),
    path(f"{account_prefix}/login", login_view),
    path(f"{account_prefix}/logout", logout_view),
]

if os.getenv("DJANGO_ADMIN_ENABLED", "false").lower() == "true":
    urlpatterns.append(path(f"{admin_prefix}/", admin.site.urls))

from django.core.wsgi import get_wsgi_application

application = get_wsgi_application()


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    install_parser = sub.add_parser("install")
    install_parser.add_argument("--django-version", default="5.2.*")
    install_parser.add_argument("--gunicorn-version", default="23.*")
    sub.add_parser("check")
    sub.add_parser("migrate")
    sub.add_parser("create-admin")
    args = parser.parse_args()

    if args.command == "check":
        call_command("check", "--deploy")
    elif args.command == "migrate":
        call_command("migrate", interactive=False)
    elif args.command == "create-admin":
        call_command("createsuperuser")


if __name__ == "__main__":
    main()
