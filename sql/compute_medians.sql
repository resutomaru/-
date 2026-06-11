-- compute_medians — Фаза 5: почасовая медиана по бакетам (КАРКАС; значения честные, но ТОНКИЕ).
-- Решения зафиксированы ранее (06-10 §9 + бриф §7.5): working-only, окно 30д, отсечка выбросов,
--   порог K>20; нижняя планка каскада ≥8 — пишем медиану с флагом низкой уверенности в basis
--   (гейт Ф6 решает по basis, что показывать клиенту). n_trimmed < 8 → строки НЕТ («мало данных», RR-04).
-- Механика:
--   • источник — price_history (уже: 1 строка/лот, без сборок, без безключёвых; самолечится, D4);
--   • выбросы — IQR-забор (P25−1.5·IQR .. P75+1.5·IQR), медиана по уцелевшим; порог ≥8 считается
--     ПОСЛЕ отсечки (честная выборка; консервативно — «тихо лучше, чем ложно»);
--   • полный пересбор (delete+insert): medians ПОЛНОСТЬЮ производна — фиксы словарей/ключей не
--     оставляют хвостов (тот же принцип, что RR-19 для price_history);
--   • расписание — почасовое (pg_cron), как и названа Ф5 («почасовая медиана»).
-- ТЕНЕВОЙ РЕЖИМ (RR-16): в Telegram/клиентам НЕ светим, пока бакеты не дозреют (bucket_readiness)
--   и превью-находки не пройдут глазной тест E19 (перепутанный вариант → ложное «ниже рынка»).

create or replace function public.compute_medians() returns void language plpgsql as $$
begin
  delete from medians;
  insert into medians (position_key, item_category, median_price, sample_size, basis, window_days, computed_at)
  with w as (
    select position_key, item_category, price
    from price_history
    where condition = 'working'
      and observed_at >= now() - interval '30 days'
  ),
  q as (
    select position_key,
           percentile_cont(0.25) within group (order by price) as p25,
           percentile_cont(0.75) within group (order by price) as p75
    from w group by position_key
  ),
  t as (
    select w.position_key, w.item_category, w.price
    from w join q using (position_key)
    where w.price >= q.p25 - 1.5*(q.p75 - q.p25)
      and w.price <= q.p75 + 1.5*(q.p75 - q.p25)
  )
  select position_key,
         max(item_category),
         round(percentile_cont(0.5) within group (order by price))::bigint,
         count(*)::int,
         case when count(*) >= 21 then 'K>20' else 'K8-20-low' end,
         30,
         now()
  from t
  group by position_key
  having count(*) >= 8;
end $$;

-- обзор для глаз: медианы + темп набора из датчика готовности
create or replace view public.median_overview as
select m.position_key, m.item_category, m.median_price, m.sample_size, m.basis, m.computed_at,
       br.working_30d, br.rate_per_day
from medians m
left join bucket_readiness br using (position_key)
order by m.sample_size desc, m.median_price desc;

-- расписание (pg_cron), почасово на 3-й минуте (не пересекаясь с нормализатором */2 и снимком */5):
-- select cron.schedule('compute-medians', '3 * * * *', $$select public.compute_medians();$$);
-- снять: select cron.unschedule('compute-medians');

-- ПРЕВЬЮ-НАХОДКИ (глазной тест E19, НЕ продукт — пушей нет; гонять, когда medians непуста):
-- select l.title, l.price, m.median_price, m.sample_size, m.basis,
--        round(100.0*(1 - l.price::numeric/m.median_price)) as скидка_проц
-- from lots l join medians m using (position_key)
-- where l.condition='working' and l.is_component is distinct from false and l.price is not null
--   and l.price < m.median_price * 0.6
-- order by скидка_проц desc limit 30;
