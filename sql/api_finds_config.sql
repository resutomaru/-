-- api_finds_config — ПИЛОН 2b (backend-design §6): добиваем API-поверхность.
-- finds_list/find_get (находки клиента), config_get/config_update (фильтры), journal_update/journal_delete.
-- Мягкое удаление: status='archived' (решение §12). Та же схема: verify_initData → cid → только своё → конверт.

-- 0) схема: статус 'archived' (мягкое удаление) + дашборд его не считает
alter table deals drop constraint if exists deals_status_check;
alter table deals add constraint deals_status_check
  check (status in ('in_stock','sold','returned','repairing','written_off','archived'));

create or replace view public.deal_dashboard as
select client_id,
       count(*)                                                       as сделок_всего,
       count(*) filter (where status='in_stock')                      as в_наличии,
       count(*) filter (where status='sold')                          as продано,
       coalesce(sum(навар)           filter (where status='sold'),0)        as навар_всего,
       coalesce(sum(sell_price)      filter (where status='sold'),0)        as выручка,
       coalesce(sum(деньги_в_товаре) filter (where status='in_stock'),0)    as деньги_в_товаре,
       round(100.0*count(*) filter (where status='sold' and навар>0)
             /nullif(count(*) filter (where status='sold'),0),0)            as в_плюс_проц,
       round(avg(маржа_проц)     filter (where status='sold'),1)            as маржа_сред_проц,
       round(avg(дней_в_обороте) filter (where status='sold'),0)            as оборачиваемость_дней
from deal_ledger
where status <> 'archived'
group by client_id;
alter view public.deal_dashboard set (security_invoker = on);

-- 1) finds_list — персональная выдача находок (фильтр+скоринг клиента, поверх client_feed)
create or replace function public.finds_list(p_init_data text, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data', (
    select coalesce(jsonb_agg(to_jsonb(f) order by f.score desc), '[]'::jsonb)
    from (select * from client_feed where client_id=cid
          order by score desc, скидка_проц desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) f));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 2) find_get — карточка одной находки (или null, если не в выдаче клиента)
create or replace function public.find_get(p_init_data text, p_lot_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data',
    coalesce((select to_jsonb(f) from client_feed f where f.client_id=cid and f.id=p_lot_id), 'null'::jsonb));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 3) config_get — настройки клиента
create or replace function public.config_get(p_init_data text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data',(select to_jsonb(cc) from client_configs cc where cc.client_id=cid));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 4) config_update — править фильтры (валидация диапазонов, RR-09)
create or replace function public.config_update(p_init_data text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  if p_payload ? 'min_score' and ((p_payload->>'min_score')::numeric < 0 or (p_payload->>'min_score')::numeric > 10)
    then raise exception 'VALIDATION: min_score 0..10'; end if;
  update client_configs set
    categories       = case when p_payload ? 'categories'       then array(select jsonb_array_elements_text(p_payload->'categories'))       else categories end,
    discount_pct     = coalesce(p_payload->'discount_pct', discount_pct),
    include_keywords = case when p_payload ? 'include_keywords' then array(select jsonb_array_elements_text(p_payload->'include_keywords')) else include_keywords end,
    stop_words       = case when p_payload ? 'stop_words'       then array(select jsonb_array_elements_text(p_payload->'stop_words'))       else stop_words end,
    regions          = case when p_payload ? 'regions'          then array(select jsonb_array_elements_text(p_payload->'regions'))          else regions end,
    cities           = case when p_payload ? 'cities'           then array(select jsonb_array_elements_text(p_payload->'cities'))           else cities end,
    freshness_min    = coalesce(nullif(p_payload->>'freshness_min','')::int,     freshness_min),
    min_score        = coalesce(nullif(p_payload->>'min_score','')::numeric,     min_score),
    active           = coalesce((p_payload->>'active')::boolean,                 active),
    updated_at       = now()
   where client_id = cid;
  return jsonb_build_object('ok',true,'data',(select to_jsonb(cc) from client_configs cc where cc.client_id=cid));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 5) journal_list — обновлено: по умолчанию скрывает archived
create or replace function public.journal_list(p_init_data text, p_status text default null,
  p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  return jsonb_build_object('ok',true,'data', (
    select coalesce(jsonb_agg(to_jsonb(l) order by l.id desc), '[]'::jsonb)
    from (select * from deal_ledger
          where client_id=cid and (case when p_status is null then status <> 'archived' else status = p_status end)
          order by id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) l));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 6) journal_update — частичная правка сделки (только своей; меняются лишь переданные поля)
create or replace function public.journal_update(p_init_data text, p_id bigint, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  update deals set
    item_title    = case when p_payload ? 'item_title'    then p_payload->>'item_title'                else item_title end,
    item_category = case when p_payload ? 'item_category' then p_payload->>'item_category'             else item_category end,
    buy_price     = case when p_payload ? 'buy_price'     then (p_payload->>'buy_price')::bigint       else buy_price end,
    bought_at     = case when p_payload ? 'bought_at'     then (p_payload->>'bought_at')::date         else bought_at end,
    cost_delivery = case when p_payload ? 'cost_delivery' then (p_payload->>'cost_delivery')::bigint   else cost_delivery end,
    cost_repair   = case when p_payload ? 'cost_repair'   then (p_payload->>'cost_repair')::bigint     else cost_repair end,
    cost_fee      = case when p_payload ? 'cost_fee'      then (p_payload->>'cost_fee')::bigint        else cost_fee end,
    cost_travel   = case when p_payload ? 'cost_travel'   then (p_payload->>'cost_travel')::bigint     else cost_travel end,
    cost_other    = case when p_payload ? 'cost_other'    then (p_payload->>'cost_other')::bigint      else cost_other end,
    sell_price    = case when p_payload ? 'sell_price'    then nullif(p_payload->>'sell_price','')::bigint else sell_price end,
    sold_at       = case when p_payload ? 'sold_at'       then nullif(p_payload->>'sold_at','')::date  else sold_at end,
    sell_channel  = case when p_payload ? 'sell_channel'  then p_payload->>'sell_channel'              else sell_channel end,
    status        = case when p_payload ? 'status'        then p_payload->>'status'                    else status end,
    note          = case when p_payload ? 'note'          then p_payload->>'note'                      else note end,
    is_estimate   = case when p_payload ? 'is_estimate'   then (p_payload->>'is_estimate')::boolean    else is_estimate end
   where id=p_id and client_id=cid;
  if not found then raise exception 'NOT_FOUND: deal % not yours', p_id; end if;
  return jsonb_build_object('ok',true,'data',(select to_jsonb(l) from deal_ledger l where l.id=p_id));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- 7) journal_delete — мягкое удаление (archived; восстановимо через journal_update status)
create or replace function public.journal_delete(p_init_data text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare cid text;
begin
  cid := public.verify_initData(p_init_data);
  update deals set status='archived' where id=p_id and client_id=cid;
  if not found then raise exception 'NOT_FOUND: deal % not yours', p_id; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('id',p_id,'status','archived'));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- права
revoke all on function
  public.finds_list(text,int,int), public.find_get(text,bigint), public.config_get(text),
  public.config_update(text,jsonb), public.journal_list(text,text,int,int),
  public.journal_update(text,bigint,jsonb), public.journal_delete(text,bigint) from public;
grant execute on function
  public.finds_list(text,int,int), public.find_get(text,bigint), public.config_get(text),
  public.config_update(text,jsonb), public.journal_list(text,text,int,int),
  public.journal_update(text,bigint,jsonb), public.journal_delete(text,bigint) to anon, authenticated;
