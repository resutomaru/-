-- =============================================================================
-- deal_golden — СЕТЬ на расчёт навара/маржи журнала (RR-10: цифры денег верны или не катим; RR-12).
-- Прогоняет РЕАЛЬНЫЙ view deal_ledger (НЕ копию формулы — урок NEW-4) на эталонных сделках с
--   вручную посчитанной истиной. Норма: mismatches = 0.
-- Сентинельный client_id '__golden_deal__' (не пересекается с живыми клиентами). deals — живая
--   таблица, поэтому в конце — ОЧИСТКА (раскомментировать и выполнить ПОСЛЕ просмотра вердикта).
-- ПРОЦЕСС-0: последний select = вердикт (виден в редакторе одной таблицей).
-- Запускать в Supabase SQL Editor, где развёрнут sql/deals.sql.
-- =============================================================================

-- 1) Эталонные сделки (идемпотентно: чистим прошлый сид перед посевом)
delete from deals where client_id = '__golden_deal__';
insert into deals (client_id, lot_id, item_title, item_category,
                   buy_price, bought_at,
                   cost_delivery, cost_repair, cost_fee, cost_travel, cost_other,
                   sell_price, sold_at, status, is_estimate, note)
values
 -- g1: чистая продажа без расходов        → навар 2000, маржа 40.0, вложено 5000
 ('__golden_deal__', null, 'g1 чистая',       'gpu',
   5000, date '2026-06-01',  0,   0, 0, 0, 0,  7000, date '2026-06-10', 'sold',     false, 'baseline'),
 -- g2: продажа с расходами (разбивка)       → навар 1000, маржа 16.7, вложено 6000
 ('__golden_deal__', null, 'g2 с расходами',  'cpu',
   5000, date '2026-06-01',  300, 700, 0, 0, 0, 7000, date '2026-06-08', 'sold',     false, 'разбор расходов'),
 -- g3: УБЫТОК (RR-10 — минус честно)        → навар -500, маржа -8.3, вложено 6000
 ('__golden_deal__', null, 'g3 убыток',       'ram',
   5000, date '2026-06-01',  1000, 0, 0, 0, 0, 5500, date '2026-06-05', 'sold',     false, 'отрицательный навар'),
 -- g4: В НАЛИЧИИ (не продано)               → навар NULL, маржа NULL, вложено 5500 (не угадываем)
 ('__golden_deal__', null, 'g4 в наличии',    'mobo',
   5000, current_date - 3,   500, 0, 0, 0, 0,  null, null,              'in_stock', false, 'продажи нет'),
 -- g5: НОЛЬ-БАЗА (защита от деления на ноль) → навар 100, маржа NULL
 ('__golden_deal__', null, 'g5 ноль-база',    'other',
   0,    date '2026-06-01',  0,   0, 0, 0, 0,  100,  date '2026-06-02', 'sold',     false, 'div0-guard');

-- 2) ВЕРДИКТ (норма: mismatches = 0) — последний select, виден в редакторе.
with expected(title, exp_навар, exp_маржа, exp_расходы, exp_вложено) as (
  values
    ('g1 чистая',      2000::bigint, 40.0::numeric, 0::bigint,    5000::bigint),
    ('g2 с расходами', 1000,         16.7,          1000,         6000),
    ('g3 убыток',      -500,         -8.3,          1000,         6000),
    ('g4 в наличии',   null,         null,          500,          5500),
    ('g5 ноль-база',   100,          null,          0,            0)
)
select
  count(*) filter (
    where l.навар           is distinct from e.exp_навар
       or l.маржа_проц      is distinct from e.exp_маржа
       or l.расходы_всего   is distinct from e.exp_расходы
       or l.деньги_в_товаре is distinct from e.exp_вложено
  )                                                            as mismatches_MUST_BE_0,
  count(*)                                                     as cases,
  -- инвариант g4: непроданное лежит ≥ 0 дней (дата not in future)
  count(*) filter (where e.title = 'g4 в наличии' and l.дней_в_обороте < 0) as g4_days_negative_MUST_BE_0
from expected e
join deal_ledger l on l.item_title = e.title and l.client_id = '__golden_deal__';

-- 3) ОЧИСТКА (выполнить ПОСЛЕ просмотра вердикта, чтобы сентинель не светился в дашбордах):
-- delete from deals where client_id = '__golden_deal__';
