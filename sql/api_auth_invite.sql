-- api_auth_invite — ОНБОРДИНГ по инвайт-коду (фронт, пилон 1). backend-design §3.2 + решение владельца §12.
-- Рефактор (NEW-4 «один канон»): проверку ПОДПИСИ выносим в helper verify_initData_sig,
--   verify_initData становится тонкой обёрткой (подпись + поиск личности) — ПОВЕДЕНИЕ НЕ МЕНЯЕТСЯ.
--   redeem_invite переиспользует тот же helper (не дублируем HMAC).
-- ПРЕДУСЛОВИЕ: bot_token в Vault (как для пилона 1c). Деплой: прогнать файл, затем повторить самотест
--   verify_initData → ОЖИДАЕМ прежний результат (client = vovchik), логика подписи не тронута.

-- 1) HELPER: подпись initData → telegram user_id (RAISE при плохой подписи/протухании). БЕЗ привязки к клиенту.
--    Тело — ДОСЛОВНО прежняя верхняя часть verify_initData (до поиска личности).
create or replace function public.verify_initData_sig(init_data text)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  pair text; k text; v text; recv_hash text := '';
  parts text[] := '{}'; user_json text; auth_date_txt text;
  dcs text; bot_token text; secret_key bytea; computed text;
begin
  foreach pair in array string_to_array(coalesce(init_data,''), '&') loop
    if pair = '' then continue; end if;
    k := split_part(pair, '=', 1);
    v := public.url_decode(substr(pair, length(k) + 2));
    if    k = 'hash'      then recv_hash := v;
    elsif k = 'signature' then null;
    else  parts := parts || (k || '=' || v);
          if k = 'user'      then user_json := v; end if;
          if k = 'auth_date' then auth_date_txt := v; end if;
    end if;
  end loop;
  dcs := array_to_string(array(select unnest(parts) order by 1), E'\n');

  select decrypted_secret into bot_token from vault.decrypted_secrets where name = 'bot_token' limit 1;
  if bot_token is null then raise exception 'CONFIG: bot_token missing in vault'; end if;

  secret_key := hmac(bot_token, 'WebAppData', 'sha256');
  computed   := encode(hmac(convert_to(dcs,'utf8'), secret_key, 'sha256'), 'hex');
  if computed <> recv_hash then raise exception 'BAD_SIGNATURE'; end if;

  if auth_date_txt is null or auth_date_txt::bigint < extract(epoch from now())::bigint - 86400 then
    raise exception 'EXPIRED';
  end if;

  return (user_json::jsonb) ->> 'id';
end $$;

-- 2) verify_initData — теперь тонкая обёртка: подпись + личность (внешнее поведение прежнее).
create or replace function public.verify_initData(init_data text)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare tg_id text; v_client text;
begin
  tg_id := public.verify_initData_sig(init_data);
  select client_id into v_client from client_identities where provider='telegram' and external_id = tg_id;
  if v_client is null then raise exception 'NOT_INVITED: tg_id=%', tg_id; end if;
  return v_client;
end $$;

-- 3) redeem_invite — погасить код, создать/привязать личность. Конверт {ok,data}|{ok:false,error}.
--    Идемпотентно: уже привязанный tg_id просто возвращает своего клиента (двойной тап безопасен).
--    Код с client_id => привязка к нему; код без client_id => создаём нового клиента по самому коду.
create or replace function public.redeem_invite(p_init_data text, p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare tg_id text; v_code record; v_client text;
begin
  tg_id := public.verify_initData_sig(p_init_data);              -- подпись валидна → tg_id (иначе RAISE)

  -- уже привязан? (идемпотентность повторного входа/тапа)
  select client_id into v_client from client_identities where provider='telegram' and external_id = tg_id;
  if v_client is not null then
    return jsonb_build_object('ok',true,'data',jsonb_build_object('client_id',v_client,'status','already'));
  end if;

  select * into v_code from invite_codes where code = p_code for update;   -- lock против гонки редемпции
  if not found                   then raise exception 'BAD_CODE'; end if;
  if v_code.used_at is not null   then raise exception 'CODE_USED'; end if;

  v_client := v_code.client_id;                                  -- явный клиент в коде…
  if v_client is null then                                       -- …или создаём нового по коду
    v_client := 'c_' || lower(regexp_replace(p_code,'[^a-zA-Z0-9]','','g'));
    insert into clients (client_id, display_name) values (v_client, p_code)
      on conflict (client_id) do nothing;
    insert into client_configs (client_id, display_name, chat_id) values (v_client, p_code, 'TBD')
      on conflict (client_id) do nothing;
  end if;

  insert into client_identities (client_id, provider, external_id) values (v_client,'telegram',tg_id)
    on conflict (provider, external_id) do nothing;
  update invite_codes set used_by = tg_id, used_at = now() where code = p_code;

  return jsonb_build_object('ok',true,'data',jsonb_build_object('client_id',v_client,'status','redeemed'));
exception when others then
  return jsonb_build_object('ok',false,'error',jsonb_build_object('code','ERR','msg',sqlerrm));
end $$;

-- права: anon (mini-app до привязки) + authenticated; секреты/чужое недоступны (подпись + явные фильтры)
revoke all on function public.verify_initData_sig(text), public.redeem_invite(text,text) from public;
grant execute on function public.verify_initData_sig(text) to anon, authenticated;
grant execute on function public.redeem_invite(text,text)   to anon, authenticated;

-- ── ПРОВЕРКА после деплоя ────────────────────────────────────────────────────
-- 1) подпись не сломана: повторить самотест verify_initData (шапка sql/auth_telegram.sql) → client = vovchik
-- 2) выпустить тест-код:   insert into invite_codes (code, note) values ('PEREKUP-TEST', 'тест онбординга');
-- 3) redeem самотестом (подставь ЧУЖОЙ telegram id, которого нет в client_identities — НЕ vovchik):
-- with t as (select (select decrypted_secret from vault.decrypted_secrets where name='bot_token') bt,
--                   '{"id":555000111,"first_name":"New"}'::text uj, extract(epoch from now())::int::text ad)
-- select public.redeem_invite(
--   'auth_date='||ad||'&user='||public.url_encode(uj)||'&hash='||
--   encode(hmac(convert_to('auth_date='||ad||E'\n'||'user='||uj,'utf8'),hmac(bt,'WebAppData','sha256'),'sha256'),'hex'),
--   'PEREKUP-TEST') from t;        -- ОЖИДАЕМ {ok:true,...,status:redeemed}; повторный вызов → status:already
-- 4) откат теста: delete from client_identities where external_id='555000111';
--                 delete from clients where client_id='c_PEREKUPTEST'; delete from client_configs where client_id='c_PEREKUPTEST';
--                 delete from invite_codes where code='PEREKUP-TEST';
