-- deals — «Помощник · Журнал-бухгалтерия» (spec §6.9): полный учёт прибыли перекупа, заменяет эксель.
-- ШАГ 1 «Помощника»: слой ДАННЫХ + РАСЧЁТА. Не зависит от интерфейса ввода/просмотра
--   (Telegram-кнопка «купил?», Google-Sheets, веб-кабинет — следующий шаг; читать будут deal_ledger/дашборды).
--
-- Дисциплина проекта:
--   • Сырая таблица РЕДАКТИРУЕМА целиком (RR-10: всё правится; цену продажи НЕ угадываем — NULL пока нет факта).
--   • Навар/маржа/дни — ПРОИЗВОДНОЕ, считается в ОДНОМ месте (view deal_ledger), как lot_score для скоринга:
--     вторую копию формулы не держим (урок NEW-4). Дашборды — тонкие обёртки над deal_ledger.
--   • Мульти-тенант: client_id на каждой строке (RR-08). Связь мягкая (как sent_log — без жёсткого FK).
--   • Расходы — РАЗБИВКОЙ (RR-10 «виден разбор закупка+расходы→навар»): доставка/ремонт/комиссия/дорога/прочее.
--   • «оценка» vs «факт» — разной меткой (is_estimate, RR-10).
--   • Деньги — bigint рубли (как lots.price); даты покупки/продажи — date (время не нужно).
-- Сеть на расчёт навара: audit/journal/deal_golden.sql (RR-10/RR-12 — правки формулы без mismatches=0 не катим).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Сырая таблица сделок
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists deals (
  id            bigserial primary key,
  client_id     text   not null,             -- → client_configs.client_id (мягкая связь)
  lot_id        bigint,                       -- → lots.id; NULL = ручная сделка / импорт старого экселя (§6.9)
  -- товар
  item_title    text,                         -- модель/название (из находки или вручную)
  item_category text,                         -- gpu/cpu/ram/mobo/ssd/psu/other/assembly
  position_key  text,                         -- ключ позиции (аналитика по моделям; из находки)
  source_url    text,                         -- ссылка на объявление
  -- закупка (факт)
  buy_price     bigint not null,
  bought_at     date   not null default current_date,
  -- расходы (разбивка — RR-10)
  cost_delivery bigint not null default 0,    -- доставка
  cost_repair   bigint not null default 0,    -- ремонт/чистка
  cost_fee      bigint not null default 0,    -- комиссия площадки
  cost_travel   bigint not null default 0,    -- дорога/бензин
  cost_other    bigint not null default 0,    -- прочее
  -- продажа (факт; NULL пока не продано — НЕ угадываем, RR-10)
  sell_price    bigint,
  sold_at       date,
  sell_channel  text,                         -- авито/телеграм/из рук/...
  -- состояние сделки
  status        text   not null default 'in_stock'
                check (status in ('in_stock','sold','returned','repairing','written_off')),
  is_estimate   boolean not null default false,   -- «оценка» vs «факт» (RR-10)
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists deals_client_idx on deals (client_id, status);
create index if not exists deals_sold_idx    on deals (client_id, sold_at);
create index if not exists deals_lot_idx     on deals (lot_id);

-- штамп updated_at на любую правку (кабинет/Sheets-синк не забудут отметку времени)
create or replace function public.deals_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists deals_touch_trg on deals;
create trigger deals_touch_trg before update on deals
  for each row execute function public.deals_touch();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) deal_ledger — ЕДИНЫЙ канон расчёта навара (security_invoker — NEW-5).
--    навар        = продажа − закупка − все расходы  (ТОЛЬКО для проданных, иначе NULL — не угадываем).
--    деньги_в_товаре = закупка + расходы             (сколько вложено в экземпляр; «оборотка» в наличии).
--    дней_в_обороте  = (продажа − покупка) для проданных, иначе (сегодня − покупка) = «лежит N дней».
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.deal_ledger as
select d.*,
       x.расходы_всего,
       d.buy_price + x.расходы_всего as деньги_в_товаре,
       case when d.sell_price is not null
            then d.sell_price - d.buy_price - x.расходы_всего end as навар,
       case when d.sell_price is not null and (d.buy_price + x.расходы_всего) > 0
            then round(100.0 * (d.sell_price - d.buy_price - x.расходы_всего)
                              / (d.buy_price + x.расходы_всего), 1) end as маржа_проц,
       case when d.status = 'sold' and d.sold_at is not null
            then (d.sold_at - d.bought_at)
            else (current_date - d.bought_at) end as дней_в_обороте
from deals d
cross join lateral (select (d.cost_delivery + d.cost_repair + d.cost_fee
                            + d.cost_travel + d.cost_other)::bigint as расходы_всего) x;
alter view public.deal_ledger set (security_invoker = on);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Дашборды кабинета (spec §6.9) — обёртки над deal_ledger, security_invoker.
-- ─────────────────────────────────────────────────────────────────────────────

-- 3a) Сводка на клиента: прибыль, число сделок, % в плюс, средняя маржа, деньги в товаре, оборачиваемость.
create or replace view public.deal_dashboard as
select client_id,
       count(*)                                                       as сделок_всего,
       count(*) filter (where status = 'in_stock')                    as в_наличии,
       count(*) filter (where status = 'sold')                        as продано,
       coalesce(sum(навар)           filter (where status = 'sold'), 0)     as навар_всего,
       coalesce(sum(sell_price)      filter (where status = 'sold'), 0)     as выручка,
       coalesce(sum(деньги_в_товаре) filter (where status = 'in_stock'), 0) as деньги_в_товаре,
       round(100.0 * count(*) filter (where status = 'sold' and навар > 0)
             / nullif(count(*) filter (where status = 'sold'), 0), 0)       as в_плюс_проц,
       round(avg(маржа_проц)     filter (where status = 'sold'), 1)         as маржа_сред_проц,
       round(avg(дней_в_обороте) filter (where status = 'sold'), 0)         as оборачиваемость_дней
from deal_ledger
group by client_id;
alter view public.deal_dashboard set (security_invoker = on);

-- 3b) Топ/анти-категории по навару (на клиента).
create or replace view public.deal_by_category as
select client_id,
       coalesce(item_category, '(без категории)')               as item_category,
       count(*) filter (where status = 'sold')                  as продано,
       coalesce(sum(навар) filter (where status = 'sold'), 0)   as навар,
       round(avg(маржа_проц) filter (where status = 'sold'), 1) as маржа_сред_проц
from deal_ledger
group by client_id, coalesce(item_category, '(без категории)');
alter view public.deal_by_category set (security_invoker = on);

-- 3c) Кэшфлоу по месяцам (по дате продажи).
create or replace view public.deal_cashflow as
select client_id,
       date_trunc('month', sold_at)::date as месяц,
       count(*)                           as продано,
       coalesce(sum(sell_price), 0)       as выручка,
       coalesce(sum(навар), 0)            as навар
from deal_ledger
where status = 'sold' and sold_at is not null
group by client_id, date_trunc('month', sold_at)::date
order by client_id, месяц;
alter view public.deal_cashflow set (security_invoker = on);

-- ─────────────────────────────────────────────────────────────────────────────
-- Деплой: выполнить этот файл в Supabase SQL Editor → затем audit/journal/deal_golden.sql (вердикт = 0).
-- Для глаз (отдельно):  select * from deal_dashboard;   select * from deal_ledger order by id desc;
-- ─────────────────────────────────────────────────────────────────────────────
