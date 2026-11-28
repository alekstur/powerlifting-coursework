-- study: 00_setup
-- Подготовка: период 2015–2025 и отдельные наборы для результатов, долей и попыток.
-- Только временные таблицы сессии: постоянные слои не изменяются.
create temp table research_settings as
select 2015 as first_year, 2025 as last_year, 30 as min_n;

create temp table research_all as select * from mart.participation;
analyze research_all;
create temp table research_p as
select p.* from research_all p cross join research_settings s
where p.meet_year between s.first_year and s.last_year;
create unique index on research_p(performance_id);
analyze research_p;
create temp table research_r as select * from research_p where eligible_result;
analyze research_r;
create temp table research_c as
select p.sex, p.bodyweight_band_id, p.bodyweight_band_label,
       p.age_group_id, p.age_group_label, c.*
from mart.lift_contributions c join research_p p using (performance_id);
analyze research_c;
create temp table research_a as
select a.*, p.sex, p.meet_year, p.bodyweight_band_id, p.age_group_id,
       p.eligible_result
from mart.attempt_results a join research_p p using (performance_id);
analyze research_a;

-- study: 01_weight
-- Задача 1. Типичный результат по массе: COUNT — численность, percentile_cont(0.5) — медиана.
select sex, bodyweight_band_id, max(bodyweight_band_label) as bodyweight_band_label,
       count(*) as n, count(*) >= (select min_n from research_settings) as sufficient_n,
       min(total_kg) as min_kg,
       percentile_cont(0.25) within group(order by total_kg) as q1_kg,
       percentile_cont(0.5) within group(order by total_kg) as median_kg,
       avg(total_kg) as mean_kg,
       percentile_cont(0.75) within group(order by total_kg) as q3_kg,
       percentile_cont(0.9) within group(order by total_kg) as p90_kg,
       max(total_kg) as max_kg, sum(total_kg) as sum_total_kg
from research_r where bodyweight_band_id is not null
group by sex, bodyweight_band_id;

-- study: 02_age_weight
-- Задача 2. Сравнение возрастов внутри одинаковой массы.
select sex, bodyweight_band_id, max(bodyweight_band_label) as bodyweight_band_label,
       age_group_id, max(age_group_label) as age_group_label,
       count(*) as n, count(*) >= (select min_n from research_settings) as sufficient_n,
       count(*) filter(where age_is_approximate) as approximate_age_n,
       min(total_kg) as min_kg,
       percentile_cont(0.25) within group(order by total_kg) as q1_kg,
       percentile_cont(0.5) within group(order by total_kg) as median_kg,
       avg(total_kg) as mean_kg,
       percentile_cont(0.75) within group(order by total_kg) as q3_kg,
       percentile_cont(0.9) within group(order by total_kg) as p90_kg,
       max(total_kg) as max_kg, sum(total_kg) as sum_total_kg
from research_r where bodyweight_band_id is not null and age_group_id is not null
group by sex, bodyweight_band_id, age_group_id;

-- study: 03_contributions
-- Задача 3. Сначала считаем доли для каждого выступления, затем среднее долей.
-- GROUPING SETS считает три уровня: пол; пол и масса; пол, масса и возраст.
select case when grouping(bodyweight_band_id)=1 then 'sex'
            when grouping(age_group_id)=1 then 'sex_weight' else 'sex_weight_age' end as grain,
       sex, bodyweight_band_id, age_group_id,
       count(*) as n, count(*) >= (select min_n from research_settings) as sufficient_n,
       sum(best3_squat_kg) as squat_kg_sum, sum(best3_bench_kg) as bench_kg_sum,
       sum(best3_deadlift_kg) as deadlift_kg_sum, sum(best3_sum_kg) as denominator_kg_sum,
       sum(squat_share) as squat_individual_share_sum,
       sum(bench_share) as bench_individual_share_sum,
       sum(deadlift_share) as deadlift_individual_share_sum,
       avg(squat_share) as squat_mean_share, avg(bench_share) as bench_mean_share,
       avg(deadlift_share) as deadlift_mean_share,
       sum(best3_squat_kg)/sum(best3_sum_kg) as squat_pooled_share,
       sum(best3_bench_kg)/sum(best3_sum_kg) as bench_pooled_share,
       sum(best3_deadlift_kg)/sum(best3_sum_kg) as deadlift_pooled_share
from research_c
group by grouping sets ((sex),(sex,bodyweight_band_id),(sex,bodyweight_band_id,age_group_id));

-- study: 04_yearly_groups
-- Задача 4. Годовые медианы для одинаковых категорий; отдельно по федерациям и в целом.
select case when grouping(federation)=1 then 'all_federations' else 'federation' end as grain,
       sex, bodyweight_band_id, max(bodyweight_band_label) as bodyweight_band_label,
       age_group_id, max(age_group_label) as age_group_label, federation, meet_year,
       count(*) as n, count(*) >= (select min_n from research_settings) as sufficient_n,
       percentile_cont(0.25) within group(order by total_kg) as q1_kg,
       percentile_cont(0.5) within group(order by total_kg) as median_kg,
       percentile_cont(0.75) within group(order by total_kg) as q3_kg
from research_r where bodyweight_band_id is not null and age_group_id is not null
group by grouping sets
 ((sex,bodyweight_band_id,age_group_id,meet_year),
  (sex,bodyweight_band_id,age_group_id,federation,meet_year));

-- study: 04b_reference_series
-- Примеры динамики выбираются по полноте данных. ROW_NUMBER нумерует кандидатов по охвату.
-- LAG берёт медиану предыдущего года для расчёта изменения.
-- Выбор примера по охвату, а не по росту/падению результата.
with candidates as (
 select sex,bodyweight_band_id,age_group_id,federation,min(n) as min_annual_n,sum(n) as series_n
 from q04_yearly_groups cross join research_settings s
 where grain='federation' and federation is not null
 group by sex,bodyweight_band_id,age_group_id,federation,s.first_year,s.last_year,s.min_n
 having count(distinct meet_year)=s.last_year-s.first_year+1 and min(n)>=s.min_n
), ranked as (
 select *,row_number() over(partition by sex order by min_annual_n desc,series_n desc,
                            federation collate "C",bodyweight_band_id,age_group_id) as choice
 from candidates
)
select y.*,r.min_annual_n,r.series_n,
       lag(y.median_kg) over(partition by y.sex order by y.meet_year) as previous_median_kg,
       y.median_kg-lag(y.median_kg) over(partition by y.sex order by y.meet_year) as change_kg
from ranked r join q04_yearly_groups y using(sex,bodyweight_band_id,age_group_id,federation)
where r.choice=1 and y.grain='federation';

-- study: 05_counts
-- Задача 5. Число выступлений по годам и категориям; SUM OVER даёт итог по полу и году.
with groups as (
 select sex,meet_year,bodyweight_band_id,age_group_id,count(*) as n,
        count(*) filter(where eligible_result) as positive_total_n,
        count(*) filter(where place_status='DQ') as dq_n,
        count(*) filter(where place_status='DD') as dd_n
 from research_p group by sex,meet_year,bodyweight_band_id,age_group_id
)
select *,n >= (select min_n from research_settings) as sufficient_n,
       sum(n) over(partition by sex,meet_year) as sex_year_n,
       n/sum(n) over(partition by sex,meet_year) as share_of_sex_year
from groups;

-- study: 05b_representation
-- Доля группы массы = число её выступлений / все выступления этого пола.
with groups as (
 select sex,bodyweight_band_id,max(bodyweight_band_label) as bodyweight_band_label,count(*) as n,
        count(*) filter(where age_group_id is not null) as known_age_group_n,
        count(*) filter(where eligible_result) as positive_total_n
 from research_p group by sex,bodyweight_band_id
)
select *,n >= (select min_n from research_settings) as sufficient_n,
       sum(n) over(partition by sex) as sex_n,
       n/sum(n) over(partition by sex) as share_of_sex
from groups;

-- study: 06_dispersion
-- Задача 6. Разброс: IQR = Q3 − Q1. Также сравниваем медиану, P90 и максимум.
select *,q3_kg-q1_kg as iqr_kg,p90_kg-median_kg as p90_minus_median_kg,
       max_kg-median_kg as max_minus_median_kg,
       (q3_kg-q1_kg)/nullif(median_kg,0) as iqr_over_median,
       p90_kg/nullif(median_kg,0) as p90_over_median
from q02_age_weight;

-- study: 06b_maxima_audit
-- Выбираем исходные выступления, давшие максимумы в группах.
select r.sex,r.bodyweight_band_id,r.age_group_id,r.performance_id,r.meet_date,
       r.federation,r.total_kg,r.best3_sum_kg,r.total_difference_kg,r.eligible_lift_contribution,
       d.n,d.sufficient_n
from research_r r join q06_dispersion d
on r.sex=d.sex and r.bodyweight_band_id=d.bodyweight_band_id
and r.age_group_id=d.age_group_id and r.total_kg=d.max_kg;

-- study: 07_attempts
-- Задача 7. Успешность = успешные / известные попытки.
-- GROUPING SETS считает итог по упражнению и отдельно по номеру подхода.
select sex,lift,case when grouping(attempt_number)=1 then 0 else attempt_number end as attempt_number,
       count(distinct performance_id) as performance_n,
       count(distinct performance_id) >= (select min_n from research_settings) as sufficient_n,
       sum(success_count) as successful_n,sum(observed_count)-sum(success_count) as failed_n,
       sum(observed_count) as observed_n,
       sum(success_count)::numeric/sum(observed_count) as success_rate,
       count(distinct performance_id) filter(where not eligible_result) as no_positive_total_performance_n
from research_a group by grouping sets((sex,lift),(sex,lift,attempt_number));

-- study: 07b_attempt_groups
-- Успешность внутри групп массы и возраста.
select sex,bodyweight_band_id,age_group_id,lift,
       count(distinct performance_id) as performance_n,
       count(distinct performance_id) >= (select min_n from research_settings) as sufficient_n,
       sum(success_count) as successful_n,sum(observed_count)-sum(success_count) as failed_n,
       sum(observed_count) as observed_n,
       sum(success_count)::numeric/sum(observed_count) as success_rate
from research_a group by sex,bodyweight_band_id,age_group_id,lift;

-- study: 07c_attempt_years
-- Успешность по годам и номеру подхода.
select sex,meet_year,lift,attempt_number,count(distinct performance_id) as performance_n,
       count(distinct performance_id) >= (select min_n from research_settings) as sufficient_n,
       sum(success_count) as successful_n,sum(observed_count)-sum(success_count) as failed_n,
       sum(observed_count) as observed_n,
       sum(success_count)::numeric/sum(observed_count) as success_rate
from research_a group by sex,meet_year,lift,attempt_number;

-- study: 07d_attempt_coverage
-- Покрытие = выступления с известными попытками / все пригодные выступления.
with eligible as (
 select sex,count(*) as eligible_performance_n from research_p where eligible_attempts group by sex
), per_performance as (
 select sex,lift,performance_id,count(*) as recorded_n
 from research_a group by sex,lift,performance_id
), observed as (
 select sex,lift,count(*) as with_attempts_n,sum(recorded_n) as observed_n,
        count(*) filter(where recorded_n=3) as with_all_three_n
 from per_performance group by sex,lift
)
select e.sex,l.lift,e.eligible_performance_n,
       coalesce(o.with_attempts_n,0) as with_attempts_n,
       coalesce(o.with_attempts_n,0)::numeric/e.eligible_performance_n as performance_coverage,
       coalesce(o.with_all_three_n,0) as with_all_three_n,
       coalesce(o.observed_n,0) as observed_n,3*e.eligible_performance_n as potential_slots,
       3*e.eligible_performance_n-coalesce(o.observed_n,0) as missing_or_unknown_slots
from eligible e cross join (values('squat'),('bench'),('deadlift')) l(lift)
left join observed o on o.sex=e.sex and o.lift=l.lift;

-- study: 08_coverage
-- Показываем, сколько данных доступно для каждого вида сравнения.
select sex,meet_year,bool_or(is_partial_snapshot_year) as partial_year,
       meet_year between (select first_year from research_settings)
                     and (select last_year from research_settings) as in_main_period,
       count(*) as participation_n,count(*) filter(where eligible_result) as result_n,
       count(*) filter(where eligible_result and bodyweight_band_id is not null) as weight_result_n,
       count(*) filter(where eligible_result and bodyweight_band_id is not null
                                            and age_group_id is not null) as age_weight_result_n,
       count(*) filter(where eligible_result and age is null) as result_age_missing_n,
       count(*) filter(where eligible_result and age_crosses_group_boundary) as result_age_boundary_n,
       count(*) filter(where eligible_result and age is not null and not age_is_valid) as result_age_invalid_n,
       count(*) filter(where eligible_lift_contribution) as contribution_n,
       count(*) filter(where eligible_attempts) as attempt_eligible_n
from research_all group by sex,meet_year;
