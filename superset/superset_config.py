"""Локальный Superset: метаданные отдельно, аналитическая учетная запись read-only."""
import os
from urllib.parse import quote_plus

SECRET_KEY = os.environ['SUPERSET_SECRET_KEY']
SQLALCHEMY_DATABASE_URI = ('postgresql+psycopg2://superset_meta:' +
                           quote_plus(os.environ['SUPERSET_META_PASSWORD']) + '@postgres:5432/superset_meta')
SQLALCHEMY_TRACK_MODIFICATIONS = False
WTF_CSRF_ENABLED = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Lax'
APP_NAME = 'Пауэрлифтинг · OpenPowerlifting'
LANGUAGES = {'en': {'flag': 'us', 'name': 'English'}, 'ru': {'flag': 'ru', 'name': 'Русский'}}
BABEL_DEFAULT_LOCALE = 'ru'
THEME_DARK = None
PUBLIC_ROLE_LIKE = 'Public'
FEATURE_FLAGS = {'DASHBOARD_RBAC': True}
ROW_LIMIT = 50000
SQL_MAX_ROW = 100000
SUPERSET_WEBSERVER_TIMEOUT = 180
SQLLAB_TIMEOUT = 180
SQLLAB_ASYNC_TIME_LIMIT_SEC = 180
CACHE_CONFIG = {'CACHE_TYPE': 'SimpleCache', 'CACHE_DEFAULT_TIMEOUT': 300}
DATA_CACHE_CONFIG = {'CACHE_TYPE': 'SimpleCache', 'CACHE_DEFAULT_TIMEOUT': 300}

# CSP, CSRF, проверка паролей и остальные настройки безопасности остаются включенными.
