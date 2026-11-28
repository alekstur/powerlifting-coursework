"""Создаёт только недостающие пароли и ключи в локальном .env."""
from pathlib import Path
import secrets

path = Path(__file__).resolve().parents[1] / '.env'
if not path.exists():
    raise SystemExit('Create .env for PostgreSQL first; see .env.example.')
text = path.read_text(encoding='utf-8-sig')
# Читаем уже заданные значения, чтобы не менять существующие пароли.
keys = {}
for line in text.splitlines():
    if line.lstrip().startswith('#') or '=' not in line:
        continue
    name, value = line.split('=', 1)
    keys[name.strip()] = value.strip()

names = ('SUPERSET_SECRET_KEY', 'SUPERSET_META_PASSWORD',
         'SUPERSET_READER_PASSWORD', 'SUPERSET_ADMIN_PASSWORD')
add = []
for name in names:
    if name not in keys:
        add.append(f'{name}={secrets.token_urlsafe(48)}')
    elif not keys[name] or keys[name].startswith('replace_'):
        raise SystemExit(
            f'{name} is blank/a placeholder. Remove its placeholder line, then rerun before initial setup.')
if add:
    with path.open('a', encoding='utf-8', newline='\n') as f:
        f.write('\n' + '\n'.join(add) + '\n')
print(f'Added {len(add)} missing Superset secrets; existing credentials preserved; values not printed.')
