-- api_journal — ПИЛОН 2 (backend-design §6): RPC-поверхность журнала. Единый канон для mini-app/бота/Sheets.
-- Каждая функция: принимает init_data → verify_initData → client_id → работает ТОЛЬКО по нему.
-- security definer (RLS обходит, но изолирует ЯВНЫМ фильтром client_id = cid; RLS — второй пояс).
-- Возврат — единый конверт: {ok:true,data:...} | {ok:false,error:{code,msg}}.
-- Захват — через канон buy_lot/mark_sold (формулу навара не дублируем, NEW-4).

-- me — профиль клиента + его конфиг
create or replace function public.me(p_init_data text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data',jsonb_build_object(
    'client',(select to_jsonb(c) from clients c where c.client_id=cid),
    'config',(select to_jsonb(cc) from client_configs cc where cc.client_id=cid)));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- journal_dashboard — сводка кабинета
create or replace function public.journal_dashboard(p_init_data text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data',
    coalesce((select to_jsonb(d) from deal_dashboard d where d.client_id=cid),
             jsonb_build_object('client_id',cid,'сделок_всего',0,'в_наличии',0,'продано',0,'навар_всего',0)));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- journal_list — список сделок (deal_ledger), фильтр по статусу, пагинация
create or replace function public.journal_list(p_init_data text, p_status text default null,
  p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data', (
    select coalesce(jsonb_agg(to_jsonb(l) order by l.id desc), '[]'::jsonb)
    from (select * from deal_ledger
          where client_id=cid and (p_status is null or status=p_status)
          order by id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) l));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- journal_add — ручная сделка (валидация цены)
create or replace function public.journal_add(p_init_data text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text; v_id bigint; v_buy bigint;
begin
  cid := public.verify_initData(p_init_data);
  v_buy := nullif(p_payload->>'buy_price','')::bigint;
  if v_buy is null or v_buy < 0 then raise exception 'VALIDATION: buy_price required (>=0)'; end if;
  insert into deals (client_id, item_title, item_category, position_key, source_url, buy_price, bought_at,
                     cost_delivery, cost_repair, cost_fee, cost_travel, cost_other, note)
  values (cid, p_payload->>'item_title', p_payload->>'item_category', p_payload->>'position_key',
          p_payload->>'source_url', v_buy, coalesce(nullif(p_payload->>'bought_at','')::date, current_date),
          coalesce(nullif(p_payload->>'cost_delivery','')::bigint,0),
          coalesce(nullif(p_payload->>'cost_repair','')::bigint,0),
          coalesce(nullif(p_payload->>'cost_fee','')::bigint,0),
          coalesce(nullif(p_payload->>'cost_travel','')::bigint,0),
          coalesce(nullif(p_payload->>'cost_other','')::bigint,0),
          p_payload->>'note')
  returning id into v_id;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('id',v_id));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- journal_mark_sold — отметить продажу (только свою сделку), вернуть навар
create or replace function public.journal_mark_sold(p_init_data text, p_id bigint, p_sell_price bigint,
  p_sold_at date default null, p_channel text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text; v_navar bigint; v_margin numeric;
begin
  cid := public.verify_initData(p_init_data);
  if p_sell_price is null or p_sell_price < 0 then raise exception 'VALIDATION: sell_price required'; end if;
  update deals set sell_price=p_sell_price, sold_at=coalesce(p_sold_at,current_date),
                   sell_channel=coalesce(p_channel,sell_channel), status='sold', is_estimate=false
   where id=p_id and client_id=cid;
  if not found then raise exception 'NOT_FOUND: deal % not yours', p_id; end if;
  select навар, маржа_проц into v_navar, v_margin from deal_ledger where id=p_id;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('id',p_id,'навар',v_navar,'маржа_проц',v_margin));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- find_buy — завести сделку из находки (канон buy_lot: автозаполнение + идемпотентность)
create or replace function public.find_buy(p_init_data text, p_lot_id bigint, p_buy_price bigint default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text; v_id bigint; v_title text;
begin
  cid := public.verify_initData(p_init_data);
  v_id := public.buy_lot(cid, p_lot_id, p_buy_price);
  select item_title into v_title from deals where id=v_id;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('id',v_id,'item_title',v_title));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- права: звать может anon (mini-app/бот) и authenticated; секреты/чужое недоступны (verify + cid-фильтр внутри)
revoke all on function
  public.me(text), public.journal_dashboard(text), public.journal_list(text,text,int,int),
  public.journal_add(text,jsonb), public.journal_mark_sold(text,bigint,bigint,date,text),
  public.find_buy(text,bigint,bigint) from public;
grant execute on function
  public.me(text), public.journal_dashboard(text), public.journal_list(text,text,int,int),
  public.journal_add(text,jsonb), public.journal_mark_sold(text,bigint,bigint,date,text),
  public.find_buy(text,bigint,bigint) to anon, authenticated;
