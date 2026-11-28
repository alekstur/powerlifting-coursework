-- Подготовка данных: исходные строки -> очистка -> выступления -> таблицы дашборда.
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS mart;

-- Общие правила чтения полей CSV.
CREATE OR REPLACE FUNCTION core.read_number(value text) RETURNS numeric
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN value ~ '^-?[0-9]+([.][0-9]{1,2})?$' THEN value::numeric END
$$;
CREATE OR REPLACE FUNCTION core.read_date(value text) RETURNS date
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND pg_input_is_valid(value, 'date') THEN value::date END
$$;
CREATE OR REPLACE FUNCTION core.read_place(value text) RETURNS text
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN value ~ '^[1-9][0-9]*$' THEN 'ranked'
        WHEN value IN ('G','DQ','DD','NS') THEN value ELSE 'unknown' END
$$;

-- Границы исследовательских групп.


DROP TABLE IF EXISTS mart.age_groups CASCADE;
CREATE TABLE mart.age_groups (age_group_id integer PRIMARY KEY, age_group_label text, lower_inclusive_age integer, upper_inclusive_age integer, sort_order integer);

INSERT INTO mart.age_groups VALUES
(1, 'До 18 лет', 1, 17, 1),
(2, '18–23 года', 18, 23, 2),
(3, '24–39 лет', 24, 39, 3),
(4, '40–49 лет', 40, 49, 4),
(5, '50–59 лет', 50, 59, 5),
(6, '60 лет и старше', 60, 120, 6);


DROP TABLE IF EXISTS mart.bodyweight_bands CASCADE;
CREATE TABLE mart.bodyweight_bands (bodyweight_band_id integer PRIMARY KEY, bodyweight_band_label text, lower_exclusive_kg numeric, upper_inclusive_kg numeric, sort_order integer);

INSERT INTO mart.bodyweight_bands VALUES
(1, 'До 50 кг', 0, 50, 1),
(2, 'Свыше 50 до 60 кг', 50, 60, 2),
(3, 'Свыше 60 до 70 кг', 60, 70, 3),
(4, 'Свыше 70 до 80 кг', 70, 80, 4),
(5, 'Свыше 80 до 90 кг', 80, 90, 5),
(6, 'Свыше 90 до 100 кг', 90, 100, 6),
(7, 'Свыше 100 до 110 кг', 100, 110, 7),
(8, 'Свыше 110 до 120 кг', 110, 120, 8),
(9, 'Свыше 120 до 130 кг', 120, 130, 9),
(10, 'Свыше 130 до 140 кг', 130, 140, 10),
(11, 'Свыше 140 кг', 140, NULL, 11);


-- 1. Преобразование типов и назначение категорий.
DROP TABLE IF EXISTS core.entries CASCADE;
CREATE TABLE core.entries AS
-- Шаг 1. Читаем исходные строки: пустые поля становятся NULL, числа и даты получают нужный тип.
with parsed as (
    select r.snapshot_id, r.source_row_number as entry_id,
        core.read_number(r."Age") as age,
        core.read_number(r."BodyweightKg") as bodyweight_kg,
        core.read_number(r."Squat1Kg") as squat1_kg,
        core.read_number(r."Squat2Kg") as squat2_kg,
        core.read_number(r."Squat3Kg") as squat3_kg,
        core.read_number(r."Squat4Kg") as squat4_kg,
        core.read_number(r."Bench1Kg") as bench1_kg,
        core.read_number(r."Bench2Kg") as bench2_kg,
        core.read_number(r."Bench3Kg") as bench3_kg,
        core.read_number(r."Bench4Kg") as bench4_kg,
        core.read_number(r."Deadlift1Kg") as deadlift1_kg,
        core.read_number(r."Deadlift2Kg") as deadlift2_kg,
        core.read_number(r."Deadlift3Kg") as deadlift3_kg,
        core.read_number(r."Deadlift4Kg") as deadlift4_kg,
        core.read_number(r."Best3SquatKg") as best3_squat_kg,
        core.read_number(r."Best3BenchKg") as best3_bench_kg,
        core.read_number(r."Best3DeadliftKg") as best3_deadlift_kg,
        core.read_number(r."TotalKg") as total_kg,
        core.read_number(r."Dots") as dots,
        core.read_number(r."Wilks") as wilks,
        core.read_number(r."Glossbrenner") as glossbrenner,
        core.read_number(r."Goodlift") as goodlift,
        nullif(r."Name", '') as lifter_name,
        nullif(r."Sex", '') as sex,
        nullif(r."Event", '') as event,
        nullif(r."Equipment", '') as equipment,
        nullif(r."AgeClass", '') as reported_age_class,
        nullif(r."BirthYearClass", '') as reported_birth_year_class,
        nullif(r."Division", '') as division,
        nullif(r."WeightClassKg", '') as reported_weight_class,
        nullif(r."Place", '') as place,
        nullif(r."Tested", '') as tested,
        nullif(r."Country", '') as lifter_country,
        nullif(r."State", '') as lifter_state,
        nullif(r."Federation", '') as federation,
        nullif(r."ParentFederation", '') as parent_federation,
        nullif(r."MeetCountry", '') as meet_country,
        nullif(r."MeetState", '') as meet_state,
        nullif(r."MeetTown", '') as meet_town,
        nullif(r."MeetName", '') as meet_name,
        nullif(r."Sanctioned", '') as sanctioned,
        core.read_date(r."Date") as meet_date,
        (s.manifest->>'snapshot_date_from_filename')::date as snapshot_date,
        core.read_place(r."Place") as place_status,
        core.read_number(rtrim(r."WeightClassKg", '+')) as reported_weight_bound_kg,
        r."WeightClassKg" ~ '^[0-9]+([.][0-9]{1,2})?[+]?$' as weight_class_format_ok,
        -- Ключ повторного зачёта: сравниваем все исходные поля,
        -- кроме номера строки, дивизиона и числового места.
        -- SHA-256 — компактное представление этих сведений для группировки.
        sha256(convert_to(((to_jsonb(r) - array['snapshot_id','source_row_number','Division','Place'])
            || jsonb_build_object('place_status', core.read_place(r."Place")))::text, 'UTF8')) as canonical_key,
        -- Список полей, которые не удалось преобразовать в числа.
        array_remove(array[
            case when r."Age" <> '' and core.read_number(r."Age") is null then 'Age' end,
            case when r."BodyweightKg" <> '' and core.read_number(r."BodyweightKg") is null then 'BodyweightKg' end,
            case when r."Squat1Kg" <> '' and core.read_number(r."Squat1Kg") is null then 'Squat1Kg' end,
            case when r."Squat2Kg" <> '' and core.read_number(r."Squat2Kg") is null then 'Squat2Kg' end,
            case when r."Squat3Kg" <> '' and core.read_number(r."Squat3Kg") is null then 'Squat3Kg' end,
            case when r."Squat4Kg" <> '' and core.read_number(r."Squat4Kg") is null then 'Squat4Kg' end,
            case when r."Bench1Kg" <> '' and core.read_number(r."Bench1Kg") is null then 'Bench1Kg' end,
            case when r."Bench2Kg" <> '' and core.read_number(r."Bench2Kg") is null then 'Bench2Kg' end,
            case when r."Bench3Kg" <> '' and core.read_number(r."Bench3Kg") is null then 'Bench3Kg' end,
            case when r."Bench4Kg" <> '' and core.read_number(r."Bench4Kg") is null then 'Bench4Kg' end,
            case when r."Deadlift1Kg" <> '' and core.read_number(r."Deadlift1Kg") is null then 'Deadlift1Kg' end,
            case when r."Deadlift2Kg" <> '' and core.read_number(r."Deadlift2Kg") is null then 'Deadlift2Kg' end,
            case when r."Deadlift3Kg" <> '' and core.read_number(r."Deadlift3Kg") is null then 'Deadlift3Kg' end,
            case when r."Deadlift4Kg" <> '' and core.read_number(r."Deadlift4Kg") is null then 'Deadlift4Kg' end,
            case when r."Best3SquatKg" <> '' and core.read_number(r."Best3SquatKg") is null then 'Best3SquatKg' end,
            case when r."Best3BenchKg" <> '' and core.read_number(r."Best3BenchKg") is null then 'Best3BenchKg' end,
            case when r."Best3DeadliftKg" <> '' and core.read_number(r."Best3DeadliftKg") is null then 'Best3DeadliftKg' end,
            case when r."TotalKg" <> '' and core.read_number(r."TotalKg") is null then 'TotalKg' end,
            case when r."Dots" <> '' and core.read_number(r."Dots") is null then 'Dots' end,
            case when r."Wilks" <> '' and core.read_number(r."Wilks") is null then 'Wilks' end,
            case when r."Glossbrenner" <> '' and core.read_number(r."Glossbrenner") is null then 'Glossbrenner' end,
            case when r."Goodlift" <> '' and core.read_number(r."Goodlift") is null then 'Goodlift' end
        ], null)::text[] as invalid_numeric_fields,
        r."Date" <> '' and core.read_date(r."Date") is null as invalid_date
    from staging.raw_results r
    join staging.snapshots s using (snapshot_id)
    where s.sha256 = '0dec66dfd43a288742b8875ff8667aeaab1866496611b910b42ddc550d4c2b97'
) ,
-- Шаг 2. Проверяем возраст, весовую категорию и сумму трёх упражнений.
checked as (
    select *,
        coalesce(age between 1 and 120 and mod(age,1) in (0,0.5),false) as age_is_valid,
        coalesce(weight_class_format_ok and reported_weight_bound_kg > 0,false) as reported_weight_class_valid,
        case when weight_class_format_ok and reported_weight_bound_kg>0 then
            case when reported_weight_class like '%+' then 'lower_exclusive' else 'upper_inclusive' end
        end as reported_weight_bound_kind,
        coalesce(event='SBD' and equipment='Raw' and sex in ('M','F'),false) as is_primary_scope,
        case when best3_squat_kg>0 and best3_bench_kg>0 and best3_deadlift_kg>0
            then best3_squat_kg+best3_bench_kg+best3_deadlift_kg end as best3_sum_kg
    from parsed
)
-- Шаг 3. Назначаем группы и отдельные условия пригодности для разных задач.
select c.*, extract(year from meet_date)::integer as meet_year,
    coalesce(extract(year from meet_date) = extract(year from snapshot_date),false) as is_partial_snapshot_year,
    coalesce(age_is_valid and mod(age,1)=0.5,false) as age_is_approximate,
    a.age_group_id, a.age_group_label,
    age_is_valid and a.age_group_id is null as age_crosses_group_boundary,
    b.bodyweight_band_id, b.bodyweight_band_label,
    total_kg - best3_sum_kg as total_difference_kg,
    is_primary_scope and place_status in ('ranked','G','DQ','DD') as eligible_participation,
    coalesce(is_primary_scope and place_status in ('ranked','G') and total_kg>0,false) as eligible_result,
    is_primary_scope and place_status in ('ranked','G','DQ') as eligible_attempts,
    coalesce(is_primary_scope and place_status in ('ranked','G') and total_kg>0
        and best3_sum_kg>0 and abs(total_kg-best3_sum_kg)<=0.02,false) as eligible_lift_contribution
from checked c
-- Для возраста 23,5 проверяются оба возможных значения: 23 и 24.
left join mart.age_groups a on c.age_is_valid
    and floor(c.age)>=a.lower_inclusive_age and ceil(c.age)<=a.upper_inclusive_age
left join mart.bodyweight_bands b on c.bodyweight_kg>b.lower_exclusive_kg
    and (b.upper_inclusive_kg is null or c.bodyweight_kg<=b.upper_inclusive_kg);

CREATE UNIQUE INDEX entries_0_idx ON core.entries (entry_id);

ANALYZE core.entries;

-- 2. Связи повторных зачётов.
DROP TABLE IF EXISTS core.entry_links CASCADE;
CREATE TABLE core.entry_links AS
-- Одинаковый canonical_key означает повторные зачёты одного выступления.
-- MIN выбирает номер первой строки как общий номер выступления.
-- COUNT показывает, сколько исходных строк было в этой группе.

select snapshot_id, entry_id,
    min(entry_id) over (partition by canonical_key) as performance_id,
    count(*) over (partition by canonical_key) as source_entry_count
from core.entries;

CREATE UNIQUE INDEX entry_links_0_idx ON core.entry_links (entry_id);

CREATE INDEX entry_links_1_idx ON core.entry_links (performance_id);

ANALYZE core.entry_links;

-- 3. Одна строка на выступление.
DROP TABLE IF EXISTS core.performances CASCADE;
CREATE TABLE core.performances AS
-- Оставляем одну строку на выступление: первую из группы повторных зачётов.
-- Остальные исходные строки остаются в entries, а связи — в entry_links.

select l.performance_id, l.source_entry_count, e.*
from core.entries e
join core.entry_links l using (snapshot_id, entry_id)
where l.entry_id=l.performance_id;

CREATE UNIQUE INDEX performances_0_idx ON core.performances (performance_id);

ANALYZE core.performances;

-- 4. Отдельные попытки.
DROP TABLE IF EXISTS core.attempts CASCADE;
CREATE TABLE core.attempts AS
-- VALUES разворачивает 12 столбцов попыток в отдельные строки.
-- Знак веса задаёт исход: плюс — успех, минус — неудача, ноль — неизвестно.
-- Четвёртая попытка сохраняется, но is_standard_attempt для неё равен false.

select p.performance_id, p.snapshot_id, v.lift, v.attempt_number,
    v.signed_weight_kg, abs(v.signed_weight_kg) as attempted_weight_kg,
    case when v.signed_weight_kg>0 then true when v.signed_weight_kg<0 then false end as successful,
    v.attempt_number<=3 as is_standard_attempt,
    v.signed_weight_kg<>0 as outcome_known
from core.performances p
cross join lateral (values
    ('squat',1,p.squat1_kg),('squat',2,p.squat2_kg),('squat',3,p.squat3_kg),('squat',4,p.squat4_kg),
    ('bench',1,p.bench1_kg),('bench',2,p.bench2_kg),('bench',3,p.bench3_kg),('bench',4,p.bench4_kg),
    ('deadlift',1,p.deadlift1_kg),('deadlift',2,p.deadlift2_kg),('deadlift',3,p.deadlift3_kg),('deadlift',4,p.deadlift4_kg)
) v(lift,attempt_number,signed_weight_kg)
where v.signed_weight_kg is not null;

CREATE UNIQUE INDEX attempts_0_idx ON core.attempts (performance_id, lift, attempt_number);

ANALYZE core.attempts;

-- 5. Все учитываемые выступления.
DROP VIEW IF EXISTS mart.participation CASCADE;
CREATE VIEW mart.participation AS
-- Все учитываемые выступления SBD/Raw, отдельно M и F; неявки исключены.
select performance_id, snapshot_id, source_entry_count, sex, meet_date, meet_year,
    is_partial_snapshot_year, federation, parent_federation, meet_country,
    reported_weight_class, reported_weight_class_valid, reported_weight_bound_kg,
    reported_weight_bound_kind, bodyweight_kg, bodyweight_band_id, bodyweight_band_label,
    age, age_is_valid, age_is_approximate, age_crosses_group_boundary, age_group_id, age_group_label,
    reported_age_class, reported_birth_year_class, place_status, tested, sanctioned,
    total_kg, best3_squat_kg, best3_bench_kg, best3_deadlift_kg, best3_sum_kg, total_difference_kg,
    eligible_result, eligible_attempts, eligible_lift_contribution
from core.performances
where eligible_participation;

-- 6. Положительные суммы.
DROP VIEW IF EXISTS mart.results CASCADE;
CREATE VIEW mart.results AS
-- Для сравнения сумм оставляем только пригодный положительный результат.
select *, bodyweight_band_id is not null as eligible_weight_comparison,
    bodyweight_band_id is not null and age_group_id is not null as eligible_age_weight_comparison
from mart.participation
where eligible_result;

-- 7. Доли упражнений.
DROP VIEW IF EXISTS mart.lift_contributions CASCADE;
CREATE VIEW mart.lift_contributions AS
-- Доля упражнения = его лучший результат / сумма трёх упражнений.
select performance_id, best3_squat_kg, best3_bench_kg, best3_deadlift_kg, best3_sum_kg, total_kg,
    best3_squat_kg / best3_sum_kg as squat_share,
    best3_bench_kg / best3_sum_kg as bench_share,
    best3_deadlift_kg / best3_sum_kg as deadlift_share
from mart.results
where eligible_lift_contribution;

-- 8. Известные стандартные попытки.
DROP VIEW IF EXISTS mart.attempt_results CASCADE;
CREATE VIEW mart.attempt_results AS
-- Для успешности берём известные попытки 1–3, даже если итоговой суммы нет.
select a.performance_id, a.lift, a.attempt_number, a.attempted_weight_kg, a.successful,
    case when a.successful then 1 else 0 end as success_count,
    1 as observed_count
from core.attempts a
join mart.participation p using (performance_id)
where p.eligible_attempts and a.is_standard_attempt and a.outcome_known;

-- 9. Выступления для дашборда.
DROP TABLE IF EXISTS mart.dashboard_performances CASCADE;
CREATE TABLE mart.dashboard_performances AS
-- Одна строка на выступление. Неизвестные группы имеют отдельные подписи.
select performance_id, sex, meet_date, meet_year, is_partial_snapshot_year,
    coalesce(federation,'Неизвестно') as federation,
    coalesce(meet_country,'Неизвестно') as meet_country,
    bodyweight_kg, coalesce(bodyweight_band_id,99) as bodyweight_band_id,
    coalesce(bodyweight_band_label,'Неизвестно') as bodyweight_band_label,
    age, coalesce(age_group_id,99) as age_group_id,
    coalesce(age_group_label,'Неизвестно') as age_group_label,
    age_is_approximate, age_crosses_group_boundary,
    bodyweight_band_id is not null as known_weight,
    age_group_id is not null as known_age,
    place_status, coalesce(tested,'Не указано') as tested,
    eligible_result, eligible_attempts, eligible_lift_contribution,
    case when eligible_result then total_kg end as result_total_kg,
    case when eligible_lift_contribution then best3_squat_kg/best3_sum_kg end as squat_share,
    case when eligible_lift_contribution then best3_bench_kg/best3_sum_kg end as bench_share,
    case when eligible_lift_contribution then best3_deadlift_kg/best3_sum_kg end as deadlift_share
from mart.participation;

CREATE UNIQUE INDEX dashboard_performances_0_idx ON mart.dashboard_performances (performance_id);

CREATE INDEX dashboard_performances_1_idx ON mart.dashboard_performances (sex, meet_year);

ANALYZE mart.dashboard_performances;

-- 10. Попытки для дашборда.
DROP TABLE IF EXISTS mart.dashboard_attempts CASCADE;
CREATE TABLE mart.dashboard_attempts AS
select a.performance_id,case a.lift when 'squat' then 'Приседание' when 'bench' then 'Жим' else 'Тяга' end as lift,
    case a.lift when 'squat' then 1 when 'bench' then 2 else 3 end as lift_order,a.attempt_number,a.success_count,a.observed_count,
    p.sex,p.meet_year,p.meet_date,p.is_partial_snapshot_year,p.federation,
    p.bodyweight_band_id,p.bodyweight_band_label,p.age_group_id,p.age_group_label,
    p.eligible_result
from mart.attempt_results a join mart.dashboard_performances p using(performance_id);

CREATE INDEX dashboard_attempts_0_idx ON mart.dashboard_attempts (performance_id);

CREATE INDEX dashboard_attempts_1_idx ON mart.dashboard_attempts (sex, meet_year);

ANALYZE mart.dashboard_attempts;

-- 11. Доли для графика упражнений.
DROP VIEW IF EXISTS mart.dashboard_contributions CASCADE;
CREATE VIEW mart.dashboard_contributions AS
-- Из трёх долей в одной записи получаем три строки для графика упражнений.
select p.*,v.lift,v.lift_order,v.share
from mart.dashboard_performances p
cross join lateral(values
    ('Приседание',1,p.squat_share),('Жим',2,p.bench_share),('Тяга',3,p.deadlift_share)
) v(lift,lift_order,share)
where p.eligible_lift_contribution;

-- 12. Полнота сведений о попытках.
DROP VIEW IF EXISTS mart.dashboard_attempt_coverage CASCADE;
CREATE VIEW mart.dashboard_attempt_coverage AS
-- Для каждого выступления и упражнения считаем число известных попыток.
-- LEFT JOIN сохраняет также выступления без сведений о попытках.
with observed as (
    select performance_id,lift,count(*) as known_count
    from mart.dashboard_attempts group by performance_id,lift
)
select p.performance_id,p.sex,p.meet_year,p.meet_date,p.is_partial_snapshot_year,p.federation,
    p.bodyweight_band_id,p.bodyweight_band_label,p.age_group_id,p.age_group_label,
    l.lift,l.lift_order,coalesce(a.known_count,0) as known_count,
    case when a.known_count>0 then 1 else 0 end as has_attempts
from mart.dashboard_performances p
cross join (values('Приседание',1),('Жим',2),('Тяга',3)) l(lift,lift_order)
left join observed a on a.performance_id=p.performance_id and a.lift=l.lift
where p.eligible_attempts;
