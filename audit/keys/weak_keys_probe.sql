-- =============================================================================
-- ЗОНДЫ слабых ключей (реестр: weak_keys.md). Прогонять ПО ОДНОМУ (ПРОЦЕСС-0),
-- результат (CSV/скрин) — в чат. Только чтение. Решения по 🟠 принимаем после цифр.
-- =============================================================================

-- ЗОНД №1 — GPU без объёма в ключе: какие модели и сколько (вариативные по объёму
--   модели = E17-риск: 1060 3/6GB, 580 4/8GB, 3060 8/12GB и т.п.)
select l.position_key,
       count(*)                                   as лотов,
       count(*) filter (where l.condition='working') as working,
       min(l.price)                               as min_цена,
       max(l.price)                               as max_цена
from lots l
where l.item_category = 'gpu'
  and l.position_key is not null
  and l.position_key !~ '_[0-9]+g$'
group by l.position_key
order by лотов desc
limit 40;

-- ЗОНД №2 — SSD: доля безбрендовых и без-интерфейсных ключей (раскомментировать, прогнать отдельно):
-- select count(*)                                            as всего_с_ключом,
--        count(*) filter (where position_key ~ '^[0-9]')     as без_бренда,
--        count(*) filter (where position_key !~ '(nvme|sata)$') as без_интерфейса,
--        count(*) filter (where position_key ~ '^[0-9]' and position_key !~ '(nvme|sata)$') as голый_объём
-- from lots where item_category='ssd' and position_key is not null;

-- ЗОНД №2б — примеры безбрендовых SSD глазами (что там реально лежит):
-- select left(title,90) as title, position_key, price, condition
-- from lots where item_category='ssd' and position_key ~ '^[0-9]'
-- order by position_key limit 30;

-- ЗОНД №4 — R7: КОЛИЧЕСТВО в лоте (цена за N штук в бакете одиночного товара — «2 x Xeon», «10 шт»).
--   Подозреваемые среди компонентов С КЛЮЧОМ (именно они идут в медиану). Глазами: нужен ли qty-гард.
-- select item_category, left(title,90) as title, position_key, price
-- from lots
-- where item_category in ('gpu','cpu','ram','mobo','ssd','psu')
--   and position_key is not null
--   and title ~* '(\y\d+\s*(шт|штук|pcs)\y|\yпар[аы]\y|\y[2-9]\s*[xх]\s*(xeon|проц|cpu|i[3579]|ryzen|плат|карт)|\yлот\s*\d+)'
-- order by item_category limit 60;

-- ЗОНД №3 — разброс цен ВНУТРИ намеренно-грубых бакетов (mobo-сокет, psu-ватты):
--   гонять, когда в price_history накопится материал (датчик: bucket_readiness).
--   p75/p25 ≥ ~2 на working-наблюдениях = бакет-каша, выносим решение заказчику.
-- select item_category, position_key,
--        count(*) as n_working,
--        round(percentile_cont(0.25) within group (order by price))::bigint as p25,
--        round(percentile_cont(0.50) within group (order by price))::bigint as p50,
--        round(percentile_cont(0.75) within group (order by price))::bigint as p75,
--        round((percentile_cont(0.75) within group (order by price))::numeric
--            / nullif((percentile_cont(0.25) within group (order by price))::numeric,0), 2) as p75_к_p25
-- from price_history
-- where condition='working'
--   and (item_category='psu' or (item_category='mobo' and position_key ~ '^(lga|am|fm)'))
-- group by item_category, position_key
-- having count(*) >= 5
-- order by p75_к_p25 desc nulls last;
