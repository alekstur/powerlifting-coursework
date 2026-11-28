"""Данные курсовой: загрузка CSV, подготовка таблиц и расчёты."""
import csv
import os
from datetime import datetime
import hashlib
import json
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[1]
FIELDS = [
    'Name', 'Sex', 'Event', 'Equipment', 'Age', 'AgeClass', 'BirthYearClass',
    'Division', 'BodyweightKg', 'WeightClassKg',
    'Squat1Kg', 'Squat2Kg', 'Squat3Kg', 'Squat4Kg', 'Best3SquatKg',
    'Bench1Kg', 'Bench2Kg', 'Bench3Kg', 'Bench4Kg', 'Best3BenchKg',
    'Deadlift1Kg', 'Deadlift2Kg', 'Deadlift3Kg', 'Deadlift4Kg', 'Best3DeadliftKg',
    'TotalKg', 'Place', 'Dots', 'Wilks', 'Glossbrenner', 'Goodlift', 'Tested',
    'Country', 'State', 'Federation', 'ParentFederation', 'Date',
    'MeetCountry', 'MeetState', 'MeetTown', 'MeetName', 'Sanctioned',
]


def connection_options():
    # Адрес и пароль базы передаются через окружение Docker.
    return {'connect_timeout': 15}


def check_file(source, manifest):
    """Проверяем контрольную сумму и названия столбцов CSV."""
    with source.open('rb') as file:
        file_hash = hashlib.file_digest(file, 'sha256').hexdigest()
    if file_hash != manifest['sha256']:
        raise ValueError('CSV отличается от снимка курсовой')
    with source.open(encoding='utf-8', newline='') as file:
        header = next(csv.reader(file))
    if header != FIELDS:
        raise ValueError('Неверный заголовок CSV')
    return file_hash


def already_loaded(connection, file_hash, expected_count):
    """Не допускаем второй загрузки того же файла."""
    query = 'SELECT snapshot_id FROM staging.snapshots WHERE sha256 = %s'
    snapshot = connection.execute(query, (file_hash,)).fetchone()
    if snapshot is None:
        return False
    query = 'SELECT count(*) FROM staging.raw_results WHERE snapshot_id = %s'
    count = connection.execute(query, snapshot).fetchone()[0]
    if count != expected_count:
        raise ValueError('Число строк в базе не совпадает с паспортом')
    print(f'Снимок уже загружен: {count} строк')
    return True


def copy_csv(connection, source, manifest):
    """Загружаем CSV во временную таблицу блоками по 1 МиБ."""
    column_names = []
    column_types = []
    for field in FIELDS:
        # Identifier правильно заключает имя столбца в SQL-кавычки.
        column_names.append(sql.Identifier(field))
        column_types.append(sql.SQL('{} text NOT NULL').format(sql.Identifier(field)))
    columns = sql.SQL(', ').join(column_names)
    definitions = sql.SQL(', ').join(column_types)
    query = sql.SQL('''CREATE TEMP TABLE load_buffer (
        source_row_number bigint GENERATED ALWAYS AS IDENTITY, {}
    ) ON COMMIT DROP''')
    connection.execute(query.format(definitions))
    query = sql.SQL('''COPY load_buffer ({}) FROM STDIN
        WITH (FORMAT CSV, HEADER MATCH, FORCE_NOT_NULL *, ENCODING 'UTF8')''')
    copied_hash = hashlib.sha256()
    with source.open('rb') as file, connection.cursor() as cursor:
        with cursor.copy(query.format(columns)) as copy:
            while True:
                block = file.read(1024 * 1024)
                if not block:
                    break
                copy.write(block)
                copied_hash.update(block)
    count = connection.execute('SELECT count(*) FROM load_buffer').fetchone()[0]
    if count != manifest['record_count'] or copied_hash.hexdigest() != manifest['sha256']:
        raise ValueError('CSV изменился или загружен не полностью')
    return columns, count


def save_snapshot(connection, source, manifest, columns):
    """Записываем сведения о снимке и переносим строки в постоянную таблицу."""
    query = '''INSERT INTO staging.snapshots
        (sha256, file_name, size_bytes, record_count, manifest)
        VALUES (%s, %s, %s, %s, %s) RETURNING snapshot_id'''
    values = (manifest['sha256'], source.name, source.stat().st_size,
              manifest['record_count'], Jsonb(manifest))
    snapshot_id = connection.execute(query, values).fetchone()[0]
    query = sql.SQL('''INSERT INTO staging.raw_results (snapshot_id, source_row_number, {})
        SELECT %s, source_row_number, {} FROM load_buffer ORDER BY source_row_number''')
    connection.execute(query.format(columns, columns), (snapshot_id,))


def load():
    manifest_path = ROOT / 'reports/snapshot/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    source = Path('/data/source') / manifest['file_name']
    file_hash = check_file(source, manifest)
    # Транзакция: при ошибке загрузка отменяется, при успехе сохраняется целиком.
    with psycopg.connect(**connection_options()) as connection:
        connection.execute((ROOT / 'sql/staging.sql').read_text(encoding='utf-8'))
        connection.execute('SELECT pg_advisory_xact_lock(72431003)')
        if already_loaded(connection, file_hash, manifest['record_count']):
            return
        columns, count = copy_csv(connection, source, manifest)
        save_snapshot(connection, source, manifest, columns)
    print(f'Загружено {count} строк')



def prepare():
    """Выполняем обычный SQL: очистка, объединение повторов и таблицы для анализа."""
    with psycopg.connect(**connection_options()) as connection:
        connection.execute((ROOT / 'sql/prepare.sql').read_text(encoding='utf-8'))
        errors = connection.execute((ROOT / 'sql/checks.sql').read_text(encoding='utf-8')).fetchmany(5)
        if errors:
            raise ValueError(f'Проверка данных не пройдена: {errors}')
    print('Данные подготовлены. Проверки пройдены.')


def read_queries():
    """В SQL-файле каждый раздел начинается с комментария -- study: имя."""
    text = (ROOT / 'sql/research.sql').read_text(encoding='utf-8')
    queries = []
    for section in text.split('-- study: ')[1:]:
        name, query = section.split('\n', 1)
        queries.append((name, query.strip().rstrip(';')))
    return queries


def export_result(connection, name, query, output):
    """Сохраняем промежуточную таблицу для следующих запросов и выгружаем CSV."""
    table = sql.Identifier('q' + name)
    create_table = sql.SQL('CREATE TEMP TABLE {} AS ').format(table)
    connection.execute(create_table + sql.SQL(query))
    cursor = connection.execute(sql.SQL('SELECT * FROM {} LIMIT 0').format(table))
    columns = []
    order = []
    for number, column in enumerate(cursor.description, start=1):
        columns.append(column.name)
        order.append(sql.Literal(number))
    # Сортируем по всем столбцам, чтобы повторные CSV имели одинаковый порядок.
    select_rows = sql.SQL('SELECT * FROM {} ORDER BY {}')
    cursor = connection.execute(select_rows.format(table, sql.SQL(', ').join(order)))
    with (output / (name + '.csv')).open('w', encoding='utf-8-sig', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(columns)
        writer.writerows(cursor)
    print(name)


def research():
    output = ROOT / 'reports/research' / datetime.now().strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, exist_ok=False)
    manifest_path = ROOT / 'reports/snapshot/manifest.json'
    snapshot = json.loads(manifest_path.read_text(encoding='utf-8'))
    with psycopg.connect(**connection_options()) as connection:
        # Все запросы читают одно согласованное состояние базы.
        connection.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        query = '''SELECT DISTINCT s.sha256 FROM core.performances p
                   JOIN staging.snapshots s USING(snapshot_id)'''
        hashes = connection.execute(query).fetchall()
        if hashes != [(snapshot['sha256'],)]:
            raise ValueError('В базе другой снимок данных')
        for name, query in read_queries():
            if name == '00_setup':
                connection.execute(query)
            else:
                export_result(connection, name, query, output)
    print(f'Результаты: {output}')



def setup_superset_database():
    with psycopg.connect(**connection_options(), autocommit=True) as conn:
        for role, key in [('superset_meta', 'SUPERSET_META_PASSWORD'), ('superset_reader', 'SUPERSET_READER_PASSWORD')]:
            password = os.environ.get(key)
            if not password:
                raise RuntimeError(f'Missing {key}')
            exists = conn.execute('select 1 from pg_roles where rolname=%s', (role,)).fetchone()
            command = 'ALTER ROLE' if exists else 'CREATE ROLE'
            conn.execute(sql.SQL(command + ' {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION').format(
                sql.Identifier(role), sql.Literal(password)))
        if not conn.execute("select 1 from pg_database where datname='superset_meta'").fetchone():
            conn.execute('CREATE DATABASE superset_meta OWNER superset_meta')
        conn.execute('GRANT CONNECT ON DATABASE powerlifting TO superset_reader')
        conn.execute('GRANT USAGE ON SCHEMA mart TO superset_reader')
        conn.execute('GRANT SELECT ON ALL TABLES IN SCHEMA mart TO superset_reader')
        conn.execute('ALTER DEFAULT PRIVILEGES IN SCHEMA mart GRANT SELECT ON TABLES TO superset_reader')
        conn.execute("ALTER ROLE superset_reader SET default_transaction_read_only = on")
        conn.execute("ALTER ROLE superset_reader SET statement_timeout = '180s'")
    print('Superset metadata database and read-only analytics role ready; passwords not logged.')



if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Данные курсовой: загрузка, подготовка и исследования')
    parser.add_argument('command', choices=['load', 'prepare', 'research', 'superset-db'])
    command = parser.parse_args().command
    if command == 'load':
        load()
    elif command == 'prepare':
        prepare()
    elif command == 'research':
        research()
    else:
        setup_superset_database()
