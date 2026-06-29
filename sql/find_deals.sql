-- deal_preview — Ф6 КАРКАС: гейты → светофор доверия → балл 0–10. ЧИСТАЯ ТЕНЬ (RR-16):
--   view только читает, никуда не шлёт; пуши/Telegram — Ф7, и только после глазного теста E19.
-- Кодифицирует ЗАФИКСИРОВАННЫЕ решения (исходный бриф + §9 от 06-10), ничего не изобретая:
--   ГЕЙТЫ: dead = hard drop; unknown проходит со штрафом в балле; сборки/qty (is_component=false) — вон;
--     цена ≤ медиана × (1−N%): gpu/cpu/ram/mobo = 40%, ssd/psu = 55% («только аномалии»).
--   БАЛЛ 0–10 (веса клиента: верх — свежесть/глубина скидки/раб-нераб; середина — срочность, новизна):
--     глубина скидки 0..4 (линейно от порога до 70%, глубже НЕ бонусируем — см. светофор);
--     свежесть 0..3 (≤2ч=3, ≤6ч=2, ≤24ч=1); ясность working=2; срочность +0.5; новьё/гарантия +0.5.
--   СВЕТОФОР (RR-06, «красное не прячем — помечаем»): red = скидка >70% («слишком хорошо» = развод-
--     подозрение, §9) | фото ≤1 | описание <40 симв; yellow = unknown | фото ≤3; иначе green.
--   basis НЕ гейтим в превью (для глаз нужны и тонкие бакеты) — Ф7 пушит только basis='K>20'
--     (+min_score из конфига клиента). Дефолты захардкожены до Ф8 (конфиг из client_configs/Sheets).
-- Сейчас medians пуста → view пуст. Оживает сам по мере созревания бакетов (bucket_readiness).
-- Глазной тест E19 (когда появятся строки): смотреть title↔position_key↔median — не перепутан ли вариант.
-- v2: балл/светофор вынесены в функции lot_score / lot_trust (sql/lot_score.sql) — там канон правил;
--   эта view — тонкая обёртка. Сеть на скоринг: audit/score/score_golden.sql.

create or replace view public.deal_preview as
with base as (
  select l.id, l.title, l.url, l.price, l.posted_at,
         l.item_category, l.position_key, l.condition,
         l.region, l.city, l.seller_type, l.images, l.description,
         m.median_price, m.sample_size, m.basis,
         1 - l.price::numeric / m.median_price as discount,
         case when l.item_category in ('ssd','psu') then 0.55 else 0.40 end as need_disc,
         coalesce(array_length(string_to_array(nullif(l.images,''),','),1),0) as n_photos
  from lots l
  join medians m using (position_key)
  where l.price is not null and l.price > 0
    and l.condition in ('working','unknown')
    and l.is_component is distinct from false
    and l.item_category in ('gpu','cpu','ram','mobo','ssd','psu')
)
-- url: каноничная ссылка avito.ru/<номер> (slug из rest-app битый — склеивает номер с названием → 404)
select b.id, b.title, 'https://www.avito.ru/' || b.id as url, b.price, b.median_price, b.sample_size, b.basis,
       round(100 * b.discount)::int as скидка_проц,
       b.item_category, b.position_key, b.condition, b.region, b.city,
       b.posted_at, b.n_photos,
       public.lot_trust(b.discount, b.n_photos, length(coalesce(b.description,'')), b.condition) as trust,
       public.lot_score(b.discount, b.need_disc,
                        extract(epoch from (now() - b.posted_at)) / 3600.0,
                        b.condition, b.title || ' ' || coalesce(b.description,'')) as score
from base b
where b.discount >= b.need_disc
order by score desc, скидка_проц desc;
alter view public.deal_preview set (security_invoker = on);

-- Сводка для глаз (выполнять отдельно):
-- select trust, count(*), round(avg(score),1) as avg_score from deal_preview group by trust;
-- Топ находок: select * from deal_preview limit 20;
