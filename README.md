# Анализ результатов пауэрлифтинга

[Курсовая Word](docs/Курсовая_Турлыкин.docx) · [Исходные данные](https://github.com/alekstur/powerlifting-coursework/releases/tag/coursework-v1)

Python загружает CSV и запускает SQL. PostgreSQL хранит и обрабатывает данные.
Superset показывает графики. Использован полный снимок OpenPowerlifting:
4 043 255 записей. Основной период сравнения — 2015–2025.

## Установка

Нужны Docker Desktop и Python. Распакуйте исходный CSV из Releases в папку `openpowerlifting-2026-10-03`.
Скопируйте `.env.example` в `.env` и задайте пароль PostgreSQL.

```powershell
python src/setup.py
docker compose build app superset
docker compose up -d --wait postgres
docker compose run --rm app python src/main.py load
docker compose run --rm app python src/main.py prepare
docker compose run --rm app python src/main.py superset-db
docker compose run --rm superset superset db upgrade
docker compose run --rm superset superset init
docker compose run --rm superset python /app/coursework/setup.py
docker compose up -d --wait superset
```

## Обычный запуск

```powershell
docker compose up -d --wait postgres superset
```

Дашборд: http://localhost:8088/superset/dashboard/powerlifting-coursework/.
Остановка с сохранением данных: `docker compose stop`.
Для редактирования: пользователь `coursework`, пароль `SUPERSET_ADMIN_PASSWORD` из `.env`.

## Расчёты

```powershell
docker compose run --rm app python src/main.py research
```

CSV сохраняются в `reports/research`. Проверенные результаты курсовой — `reports/results.zip`.

## Что разбирать на защите

- `src/main.py`: загрузка, подготовка таблиц и запуск исследований.
- `sql/prepare.sql`: очистка данных, повторные зачёты и группы массы/возраста.
- `sql/research.sql`: семь исследований и формулы показателей.
- `sql/checks.sql`: проверка правильности подготовленных данных.

`sql/staging.sql` создаёт исходные таблицы. `src/setup.py` генерирует недостающие
локальные ключи. В `superset` лежат готовый дашборд, его настройки и импорт.
`compose.yaml` и `Dockerfile` описывают запуск среды.
Данные: [OpenPowerlifting](https://www.openpowerlifting.org); лицензия сохранена рядом с CSV.
