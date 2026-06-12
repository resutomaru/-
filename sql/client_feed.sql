-- client_feed — Ф6: фильтр + скоринг НА КЛИЕНТА (мульти-тенант поверх ОДНОГО общего сбора). ТЕНЬ.
-- Конфиг — строка client_configs (Ф8 подключит синк из Google Sheets; пока сид ниже).
-- Канон скоринга — lot_score / lot_trust (sql/lot_score.sql); пороги N% — из discount_pct клиента
--   (одно место правил: deal_preview остаётся ОБЩИМ обзором с дефолтами, Ф7-бот будет читать client_feed).
-- Гейты на клиента: его категории, его N% по категориям, регионы/города (пусто = вся Россия),
--   стоп-слова, include-слова (пусто = все), min_score. dead и сборки отрезаны до клиентского слоя.
-- RR-08 (приватность): client_id на каждой строке; chat_id заполняется в Ф7 при подключении бота.

-- Сид первого клиента (идемпотентно: do nothing — конфиг живые данные, повторный прогон НЕ затирает):
insert into client_configs (client_id, display_name, chat_id, categories, discount_pct, min_score, active)
values ('vovchik', 'Вовчик', 'TBD',
        '{gpu,cpu,ram,mobo,ssd,psu}',
        '{"gpu":40,"cpu":40,"ram":40,"mobo":40,"ssd":55,"psu":55}'::jsonb,
        0, true)
on conflict (client_id) do nothing;

create or replace view public.client_feed as
with base as (
  select l.id, l.title, l.url, l.price, l.posted_at, l.item_category, l.position_key,
         l.condition, l.region, l.city, l.description,
         m.median_price, m.sample_size, m.basis,
         1 - l.price::numeric / m.median_price as discount,
         coalesce(array_length(string_to_array(nullif(l.images,''),','),1),0) as n_photos
  from lots l
  join medians m using (position_key)
  where l.price is not null and l.price > 0
    and l.condition in ('working','unknown')
    and l.is_component is distinct from false
    and l.item_category in ('gpu','cpu','ram','mobo','ssd','psu')
),
matched as (
  select c.client_id, c.min_score, b.*,
         coalesce((c.discount_pct->>b.item_category)::numeric / 100, 0.40) as need_disc
  from base b
  join client_configs c on c.active
  where b.item_category = any (c.categories)
    and b.discount >= coalesce((c.discount_pct->>b.item_category)::numeric / 100, 0.40)
    and (coalesce(array_length(c.regions,1),0) = 0 or b.region = any (c.regions))
    and (coalesce(array_length(c.cities,1),0)  = 0 or b.city  = any (c.cities))
    and not exists (select 1 from unnest(c.stop_words) sw
                    where sw <> '' and b.title ilike '%'||sw||'%')
    and (coalesce(array_length(c.include_keywords,1),0) = 0
         or exists (select 1 from unnest(c.include_keywords) kw
                    where b.title ilike '%'||kw||'%'))
),
scored as (
  select m.client_id, m.id, m.title, m.url, m.price, m.median_price, m.sample_size, m.basis,
         round(100 * m.discount)::int as скидка_проц,
         m.item_category, m.position_key, m.condition, m.region, m.city,
         m.posted_at, m.n_photos, m.min_score,
         public.lot_trust(m.discount, m.n_photos, length(coalesce(m.description,'')), m.condition) as trust,
         public.lot_score(m.discount, m.need_disc,
                          extract(epoch from (now() - m.posted_at)) / 3600.0,
                          m.condition, m.title || ' ' || coalesce(m.description,'')) as score
  from matched m
)
select client_id, id, title, url, price, median_price, sample_size, basis,
       скидка_проц, item_category, position_key, condition, region, city,
       posted_at, n_photos, trust, score
from scored
where score >= coalesce(min_score, 0)
order by client_id, score desc, скидка_проц desc;
alter view public.client_feed set (security_invoker = on);

-- Для глаз (выполнять отдельно):
-- select client_id, count(*), round(avg(score),1) from client_feed group by client_id;
-- Тест мульти-тенанта (RR-08, когда появится 2-й клиент): «второй клиент видит ДРУГОЕ».
