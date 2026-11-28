SELECT 'attempt_mart_scope' AS check_name, to_jsonb(errors) AS details
FROM (
select a.performance_id from mart.attempt_results a
left join mart.participation p using(performance_id)
where p.performance_id is null or p.place_status not in ('ranked','G','DQ')
    or a.attempt_number not between 1 and 3 or a.attempted_weight_kg<=0
    or a.observed_count<>1 or a.success_count not in(0,1) or a.successful is null
) AS errors
UNION ALL
SELECT 'attempt_outcomes_valid' AS check_name, to_jsonb(errors) AS details
FROM (
select performance_id,lift,attempt_number from core.attempts
where attempt_number not between 1 and 4 or lift not in ('squat','bench','deadlift')
    or attempted_weight_kg<>abs(signed_weight_kg)
    or successful is distinct from (case when signed_weight_kg>0 then true when signed_weight_kg<0 then false end)
    or is_standard_attempt is distinct from (attempt_number<=3)
    or outcome_known is distinct from (signed_weight_kg<>0)
) AS errors
UNION ALL
SELECT 'attempts_reconcile_to_source' AS check_name, to_jsonb(errors) AS details
FROM (
with source_counts as (
    select
    
    
        count(nullif(r."Squat1Kg",'')) as squat1_n,
        coalesce(sum(abs(nullif(r."Squat1Kg",'')::numeric)),0) as squat1_weights,
        count(*) filter (where nullif(r."Squat1Kg",'')::numeric>0) as squat1_successes
        ,
    
        count(nullif(r."Squat2Kg",'')) as squat2_n,
        coalesce(sum(abs(nullif(r."Squat2Kg",'')::numeric)),0) as squat2_weights,
        count(*) filter (where nullif(r."Squat2Kg",'')::numeric>0) as squat2_successes
        ,
    
        count(nullif(r."Squat3Kg",'')) as squat3_n,
        coalesce(sum(abs(nullif(r."Squat3Kg",'')::numeric)),0) as squat3_weights,
        count(*) filter (where nullif(r."Squat3Kg",'')::numeric>0) as squat3_successes
        ,
    
        count(nullif(r."Squat4Kg",'')) as squat4_n,
        coalesce(sum(abs(nullif(r."Squat4Kg",'')::numeric)),0) as squat4_weights,
        count(*) filter (where nullif(r."Squat4Kg",'')::numeric>0) as squat4_successes
        ,
    
    
    
        count(nullif(r."Bench1Kg",'')) as bench1_n,
        coalesce(sum(abs(nullif(r."Bench1Kg",'')::numeric)),0) as bench1_weights,
        count(*) filter (where nullif(r."Bench1Kg",'')::numeric>0) as bench1_successes
        ,
    
        count(nullif(r."Bench2Kg",'')) as bench2_n,
        coalesce(sum(abs(nullif(r."Bench2Kg",'')::numeric)),0) as bench2_weights,
        count(*) filter (where nullif(r."Bench2Kg",'')::numeric>0) as bench2_successes
        ,
    
        count(nullif(r."Bench3Kg",'')) as bench3_n,
        coalesce(sum(abs(nullif(r."Bench3Kg",'')::numeric)),0) as bench3_weights,
        count(*) filter (where nullif(r."Bench3Kg",'')::numeric>0) as bench3_successes
        ,
    
        count(nullif(r."Bench4Kg",'')) as bench4_n,
        coalesce(sum(abs(nullif(r."Bench4Kg",'')::numeric)),0) as bench4_weights,
        count(*) filter (where nullif(r."Bench4Kg",'')::numeric>0) as bench4_successes
        ,
    
    
    
        count(nullif(r."Deadlift1Kg",'')) as deadlift1_n,
        coalesce(sum(abs(nullif(r."Deadlift1Kg",'')::numeric)),0) as deadlift1_weights,
        count(*) filter (where nullif(r."Deadlift1Kg",'')::numeric>0) as deadlift1_successes
        ,
    
        count(nullif(r."Deadlift2Kg",'')) as deadlift2_n,
        coalesce(sum(abs(nullif(r."Deadlift2Kg",'')::numeric)),0) as deadlift2_weights,
        count(*) filter (where nullif(r."Deadlift2Kg",'')::numeric>0) as deadlift2_successes
        ,
    
        count(nullif(r."Deadlift3Kg",'')) as deadlift3_n,
        coalesce(sum(abs(nullif(r."Deadlift3Kg",'')::numeric)),0) as deadlift3_weights,
        count(*) filter (where nullif(r."Deadlift3Kg",'')::numeric>0) as deadlift3_successes
        ,
    
        count(nullif(r."Deadlift4Kg",'')) as deadlift4_n,
        coalesce(sum(abs(nullif(r."Deadlift4Kg",'')::numeric)),0) as deadlift4_weights,
        count(*) filter (where nullif(r."Deadlift4Kg",'')::numeric>0) as deadlift4_successes
        
    
    
    from core.performances p
    join staging.raw_results r on r.snapshot_id=p.snapshot_id and r.source_row_number=p.entry_id
), expected as (
    select v.* from source_counts c cross join lateral (values
    
    
        ('squat', 1, c.squat1_n, c.squat1_weights, c.squat1_successes)
        ,
    
        ('squat', 2, c.squat2_n, c.squat2_weights, c.squat2_successes)
        ,
    
        ('squat', 3, c.squat3_n, c.squat3_weights, c.squat3_successes)
        ,
    
        ('squat', 4, c.squat4_n, c.squat4_weights, c.squat4_successes)
        ,
    
    
    
        ('bench', 1, c.bench1_n, c.bench1_weights, c.bench1_successes)
        ,
    
        ('bench', 2, c.bench2_n, c.bench2_weights, c.bench2_successes)
        ,
    
        ('bench', 3, c.bench3_n, c.bench3_weights, c.bench3_successes)
        ,
    
        ('bench', 4, c.bench4_n, c.bench4_weights, c.bench4_successes)
        ,
    
    
    
        ('deadlift', 1, c.deadlift1_n, c.deadlift1_weights, c.deadlift1_successes)
        ,
    
        ('deadlift', 2, c.deadlift2_n, c.deadlift2_weights, c.deadlift2_successes)
        ,
    
        ('deadlift', 3, c.deadlift3_n, c.deadlift3_weights, c.deadlift3_successes)
        ,
    
        ('deadlift', 4, c.deadlift4_n, c.deadlift4_weights, c.deadlift4_successes)
        
    
    
    ) v(lift,attempt_number,n,weights,successes)
), actual as (
    select lift,attempt_number,count(*) as n,coalesce(sum(attempted_weight_kg),0) as weights,
        count(*) filter(where successful) as successes
    from core.attempts group by lift,attempt_number
)
select * from expected e full join actual a using(lift,attempt_number)
where e.n is distinct from a.n or e.weights is distinct from a.weights or e.successes is distinct from a.successes
) AS errors
UNION ALL
SELECT 'attempts_without_total_preserved' AS check_name, to_jsonb(errors) AS details
FROM (
with expected as (
    select count(*) as n from mart.participation p
    where p.eligible_attempts and (p.total_kg is null or p.total_kg<=0)
      and exists(select 1 from core.attempts a where a.performance_id=p.performance_id and a.is_standard_attempt and a.outcome_known)
), actual as (
    select count(distinct a.performance_id) as n from mart.attempt_results a
    join mart.participation p using(performance_id)
    where p.total_kg is null or p.total_kg<=0
)
select * from expected e cross join actual a where e.n<>a.n
) AS errors
UNION ALL
SELECT 'canonical_content_matches' AS check_name, to_jsonb(errors) AS details
FROM (
-- Проверка по полному исходному содержимому, а не по повторному сравнению хешей.
select l.entry_id, l.performance_id
from core.entry_links l
join staging.raw_results a on a.snapshot_id=l.snapshot_id and a.source_row_number=l.entry_id
join staging.raw_results b on b.snapshot_id=l.snapshot_id and b.source_row_number=l.performance_id
where l.entry_id<>l.performance_id and (
    (to_jsonb(a)-array['snapshot_id','source_row_number','Division','Place'])
      is distinct from (to_jsonb(b)-array['snapshot_id','source_row_number','Division','Place'])
    or core.read_place(a."Place") <> core.read_place(b."Place")
)
) AS errors
UNION ALL
SELECT 'category_boundary_contract' AS check_name, to_jsonb(errors) AS details
FROM (
with ages(age, expected) as (values
    (0::numeric,null::integer),(17,1),(17.5,null),(18,2),(23,2),(23.5,null),
    (24,3),(39.5,null),(40,4),(49.5,null),(50,5),(59.5,null),(60,6),(105.5,6),
    (null,null),(121,null)
), weights(weight, expected) as (values
    (0::numeric,null::integer),(-1,null),(50,1),(50.01,2),(60,2),(60.01,3),
    (140,10),(140.01,11),(300,11),(null,null)
)
select 'age' as dimension, age as value from ages
left join mart.age_groups a on age between 1 and 120
    and floor(age)>=a.lower_inclusive_age and ceil(age)<=a.upper_inclusive_age
where a.age_group_id is distinct from expected
union all
select 'bodyweight',weight from weights
left join mart.bodyweight_bands b on weight>b.lower_exclusive_kg
    and (b.upper_inclusive_kg is null or weight<=b.upper_inclusive_kg)
where b.bodyweight_band_id is distinct from expected
) AS errors
UNION ALL
SELECT 'entry_categories_valid' AS check_name, to_jsonb(errors) AS details
FROM (
select entry_id from core.entries
where (age_group_id is not null and not age_is_valid)
    or (age_crosses_group_boundary and age_group_id is not null)
    or (bodyweight_band_id is not null and not (bodyweight_kg>0))
    or (reported_weight_class_valid and not (reported_weight_bound_kg>0))
    or cardinality(invalid_numeric_fields)>0 or invalid_date
) AS errors
UNION ALL
SELECT 'links_have_representative' AS check_name, to_jsonb(errors) AS details
FROM (
select l.entry_id from core.entry_links l
left join core.performances p using(performance_id)
where p.performance_id is null or p.snapshot_id<>l.snapshot_id
    or l.performance_id>l.entry_id or l.source_entry_count<1
) AS errors
UNION ALL
SELECT 'result_and_share_scope' AS check_name, to_jsonb(errors) AS details
FROM (
select performance_id from mart.results
where total_kg<=0 or total_kg is null or place_status not in ('ranked','G') or sex not in ('M','F')
union all
select performance_id from mart.lift_contributions
where best3_sum_kg<=0 or abs(total_kg-best3_sum_kg)>0.02
    or abs(squat_share+bench_share+deadlift_share-1)>0.000000001
    or least(squat_share,bench_share,deadlift_share)<=0
) AS errors
UNION ALL
SELECT 'snapshot_and_row_conservation' AS check_name, to_jsonb(errors) AS details
FROM (
with snapshot as (
    select count(*) as snapshots, coalesce(sum(record_count),0) as n
    from staging.snapshots where sha256='0dec66dfd43a288742b8875ff8667aeaab1866496611b910b42ddc550d4c2b97'
), counts as (
    select (select count(*) from core.entries) as entries,
           (select count(*) from core.entry_links) as links,
           (select coalesce(sum(source_entry_count),0) from core.performances) as represented
)
select * from snapshot cross join counts
where snapshots<>1 or n=0 or entries<>n or links<>n or represented<>n
) AS errors
UNION ALL
SELECT 'type_parsing_contract' AS check_name, to_jsonb(errors) AS details
FROM (
with fixtures(raw, expected) as (values
    ('',null::numeric),('0',0),('-100.25',-100.25),('23.5',23.5),
    ('NaN',null),('Infinity',null),('not a number',null),('12.345',null)
)
select raw from fixtures where core.read_number(raw) is distinct from expected
union all
select 'invalid date' where core.read_date('2026-02-30') is not null
union all
select 'valid leap day' where core.read_date('2024-02-29') is distinct from date '2024-02-29'
) AS errors