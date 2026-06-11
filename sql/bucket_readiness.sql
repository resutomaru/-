-- bucket_readiness — датчик готовности медиан (Ф5). Превращает «ждём непонятно сколько» в
--   «rtx3060_12g — дней через N». По каждому position_key (= грань медианы): сколько working-наблюдений
--   в окне 30д, темп за последнюю неделю, ETA до порога K>20 (решение 06-10: выборка K>20, окно 30д).
-- Источник — price_history (наполняется snapshot_price_history). Только для глаз/мониторинга, в продукт не пишет.
-- Порог 21 = «K>20». min_viable (≥8) — нижняя планка каскада §7.5 (model+brand≥8) для прикидки «что близко».

create or replace view public.bucket_readiness as
with w30 as (
  select position_key, item_category, condition, observed_at
  from price_history
  where observed_at >= now() - interval '30 days'
),
agg as (
  select position_key,
         max(item_category)                                                                         as item_category,
         count(*) filter (where condition = 'working')                                              as working_30d,
         count(*)                                                                                    as total_30d,
         count(*) filter (where condition = 'working' and observed_at >= now() - interval '7 days')  as working_7d
  from w30
  group by position_key
)
select
  position_key,
  item_category,
  working_30d,
  total_30d,
  (working_30d >= 8)            as min_viable,     -- нижняя планка каскада (§7.5)
  greatest(0, 21 - working_30d) as still_need,     -- сколько ещё до K>20
  round(working_7d / 7.0, 2)    as rate_per_day,   -- темп набора за последнюю неделю
  case
    when working_30d >= 21 then 'READY (K>20)'
    when working_7d = 0    then 'stalled (0 за неделю)'
    else 'ETA ~' || ceil((21 - working_30d) / (working_7d / 7.0))::text || ' дн'
  end                          as readiness
from agg
order by working_30d desc, total_30d desc;

-- Сводка одной строкой (выполнять отдельно):
-- select count(*) filter (where working_30d >= 21) as ready_buckets,
--        count(*) filter (where working_30d >= 8)  as viable_buckets,
--        count(*)                                   as buckets_tracked,
--        (select count(*) from price_history)       as total_observations
-- from bucket_readiness;
