-- journal_capture — КАНОН захвата сделок в журнал (spec §6.8). Telegram-бот («купил?»/команды)
--   и Google-Sheets-синк зовут ЭТИ функции — вторую копию логики вставки не держим (NEW-4).
--   • buy_lot   — «Купил» из находки: автозаполнение товара из lots, цена = переданная или цена лота.
--   • mark_sold — отметить продажу: статус→sold, факт; навар посчитает deal_ledger (формулу не дублируем).
-- Идемпотентность «купил»: одну находку (client_id, lot_id) в журнал дважды не кладём (объявление =
--   один физический экземпляр). Ручные сделки (lot_id NULL) — без ограничения.
-- Деплой: после sql/deals.sql. Функции security-invoker (по умолчанию) — n8n ходит ролью postgres.

-- защита от двойного «купил»
create unique index if not exists deals_client_lot_uq
  on deals (client_id, lot_id) where lot_id is not null;

-- buy_lot — завести сделку из находки (возвращает id сделки; идемпотентно)
create or replace function public.buy_lot(
  p_client_id text, p_lot_id bigint, p_buy_price bigint default null
) returns bigint language plpgsql as $$
declare v_id bigint; l lots%rowtype; v_price bigint;
begin
  select id into v_id from deals where client_id = p_client_id and lot_id = p_lot_id;
  if found then return v_id; end if;                       -- уже куплено — вернуть существующую

  select * into l from lots where id = p_lot_id;
  if not found then raise exception 'buy_lot: lot % not found', p_lot_id; end if;

  v_price := coalesce(p_buy_price, l.price);
  if v_price is null then
    raise exception 'buy_lot: lot % has no price — pass p_buy_price', p_lot_id;
  end if;

  insert into deals (client_id, lot_id, item_title, item_category, position_key, source_url,
                     buy_price, bought_at, status)
  values (p_client_id, p_lot_id, l.title, l.item_category, l.position_key, l.url,
          v_price, current_date, 'in_stock')
  returning id into v_id;
  return v_id;
end $$;

-- mark_sold — отметить продажу (навар считает deal_ledger)
create or replace function public.mark_sold(
  p_deal_id bigint, p_sell_price bigint,
  p_sold_at date default current_date, p_channel text default null
) returns bigint language plpgsql as $$
begin
  update deals
     set sell_price   = p_sell_price,
         sold_at      = p_sold_at,
         sell_channel = coalesce(p_channel, sell_channel),
         status       = 'sold',
         is_estimate  = false
   where id = p_deal_id;
  if not found then raise exception 'mark_sold: deal % not found', p_deal_id; end if;
  return p_deal_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Проверка вручную (отдельно; подставь реальный id из lots):
--   select buy_lot('vovchik', (select id from lots where price is not null
--                              and item_category='gpu' limit 1));   -- заведёт сделку, вернёт id
--   select * from deal_ledger where client_id='vovchik' order by id desc limit 1;  -- автозаполнение видно
--   select mark_sold(<тот id>, 7000);                              -- продал за 7000
--   select навар, маржа_проц from deal_ledger where id = <тот id>; -- навар посчитан
--   -- очистка теста: delete from deals where lot_id = <тот lot_id> and client_id='vovchik';
-- ─────────────────────────────────────────────────────────────────────────────
