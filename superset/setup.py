"""Создаём администратора, импортируем готовый дашборд и разрешаем локальный просмотр."""
import os
from pathlib import Path
from zipfile import ZipFile
from flask import g
from flask_login import login_user
from superset.app import create_app

app = create_app()
with app.test_request_context():
    from superset import db
    from superset.commands.dashboard.importers.dispatcher import ImportDashboardsCommand
    from superset.models.dashboard import Dashboard
    from superset.connectors.sqla.models import SqlaTable

    # 1. Создаём пользователя, только если его ещё нет.
    security = app.appbuilder.sm
    user = security.find_user(username='coursework')
    if user is None:
        user = security.add_user('coursework', 'Coursework', 'Local',
            'coursework@localhost.invalid', security.find_role('Admin'),
            os.environ['SUPERSET_ADMIN_PASSWORD'])
    login_user(user)
    g.user = user

    # 2. Читаем экспорт: настройки графиков и фильтров. Пароль подставляется локально.
    contents = {}
    passwords = {}
    with ZipFile(Path(__file__).with_name('dashboard.zip')) as archive:
        for name in archive.namelist():
            if name.endswith('/'):
                continue
            path = name.split('/', 1)[1]
            contents[path] = archive.read(name).decode('utf-8')
            if path.startswith('databases/'):
                passwords[path] = os.environ['SUPERSET_READER_PASSWORD']
    ImportDashboardsCommand(contents, passwords=passwords, overwrite=True).run()

    # 3. Разрешаем Public только просмотр учебного дашборда и его наборов данных.
    public = security.find_role('Public')
    dashboard = db.session.query(Dashboard).filter_by(slug='powerlifting-coursework').one()
    dashboard.roles = [public]
    for chart in dashboard.slices:
        dataset = chart.datasource
        permission = security.find_permission_view_menu('datasource_access', dataset.perm)
        if permission:
            security.add_permission_role(public, permission)
    db.session.commit()
    print('Дашборд импортирован. Локальный просмотр доступен.')
