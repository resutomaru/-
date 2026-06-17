-- snapshot_price_history — накопление истории цен под медиану (Ф5). Закрывает «подтекание» ожидания:
--   до этого price_history была ПУСТА и никто в неё не писал, а цены жили только в lots (дедуп-снимок,
--   ON CONFLICT skip → даже снижение цены продавцом не обновлялось). Теперь каждый «годный» лот банкуется.
--
-- Что банкуем: компонент (gpu/cpu/ram/mobo/ssd/psu) + реальная цена (price is not null; trial-цены обнулены,
--   RR-17) + есть position_key + не-сборка (is_component is distinct from false). condition пишем КАК ЕСТЬ
--   (working/unknown/dead) — медиана фильтрует working-only на чтении, а нам полезно видеть и остальное.
-- Грань: ОДНА строка на лот. Обосновано тем, что lots.price заморожен (ON CONFLICT skip не обновляет цену),
--   поэтому второй строки для того же лота быть не может. on conflict (lot_id) do nothing → идемпотентно.
--   Если ингест начнут обновлять цену (ловить снижения) — пересмотреть грань (см. RR-19).
-- Производность: price_history ПОЛНОСТЬЮ выводится из lots → при фиксе словарей/ключей можно truncate+пересбор.
-- Первый прогон = бэкафилл: засеет все уже собранные реальные цены разом.
-- Расписание: pg_cron */5 (после нормализатора */2 — ключи к этому моменту проставлены; неключёванное
--   подхватится следующим прогоном). API НЕ дёргает, на суточный лимит rest-app НЕ влияет.

create unique index if not exists ph_lot_uidx on price_history (lot_id);

-- v2 (самоаудит D4): история САМОЛЕЧИТСЯ. do nothing → do update (ключ/категория/состояние всегда =
--   текущей разметке lots; price/observed_at НЕ трогаем — семантика первого наблюдения). Плюс
--   самочистка: лот выпал из компонентов / стал сборкой / потерял ключ → его строка истории уходит.
--   Ручные синки/чистки после фиксов словарей больше не нужны.
create or replace function public.snapshot_price_history() returns void language plpgsql as $$
begin
  insert into price_history (lot_id, position_key, item_category, price, condition, observed_at, region)
  select l.id, l.position_key, l.item_category, l.price,
         coalesce(l.condition, 'unknown'),
         coalesce(l.posted_at, l.fetched_at),
         l.region
  from lots l
  where l.item_category in ('gpu','cpu','ram','mobo','ssd','psu')
    and l.price is not null
    and l.position_key is not null
    and l.is_component is distinct from false
    and public.lot_is_used_private(l.title, l.description)   -- E19: только Б/У частное (новьё/магазин не задирают медиану)
  on conflict (lot_id) do update
    set position_key  = excluded.position_key,
        item_category = excluded.item_category,
        condition     = excluded.condition,
        region        = excluded.region
    where (price_history.position_key, price_history.item_category, price_history.condition)
          is distinct from (excluded.position_key, excluded.item_category, excluded.condition);

  delete from price_history ph using lots l
   where ph.lot_id = l.id
     and (l.item_category not in ('gpu','cpu','ram','mobo','ssd','psu')
          or l.is_component = false
          or l.position_key is null
          or not public.lot_is_used_private(l.title, l.description));  -- E19: вычищаем уже банкнутое новьё/магазин
end $$;

-- расписание (pg_cron). Требует: create extension if not exists pg_cron;
-- select cron.schedule('snapshot-price-history', '*/5 * * * *', $$select public.snapshot_price_history();$$);
-- снять:           select cron.unschedule('snapshot-price-history');
-- разовый прогон/бэкафилл прямо сейчас: select public.snapshot_price_history();
