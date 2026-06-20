-- auth_telegram — ПИЛОН 1c (backend-design §3.3): проверка Telegram initData + выпуск Supabase JWT.
-- Вся логика в SQL (решение владельца «A»). Секреты (bot_token, jwt_secret) — в Supabase Vault.
-- Зовёт mini-app до авторизации (роль anon) → получает JWT с claim client_id → дальше RLS видит «своё».
-- ПРЕДПОСЫЛКА: в Vault лежат секреты 'bot_token' и 'jwt_secret' (см. инструкцию деплоя).

-- helper: percent-decode (UTF-8 safe) — initData приходит url-кодированным
create or replace function public.url_decode(input text) returns text
language plpgsql immutable as $$
declare b bytea := '\x'; i int := 1; c text;
begin
  while i <= length(input) loop
    c := substr(input, i, 1);
    if    c = '%' then b := b || decode(substr(input, i+1, 2), 'hex'); i := i + 3;
    elsif c = '+' then b := b || E'\\x20'::bytea;                      i := i + 1;
    else              b := b || convert_to(c, 'utf8');                 i := i + 1;
    end if;
  end loop;
  return convert_from(b, 'utf8');
end $$;

-- helper: percent-encode (нужен только для самотеста, чтобы собрать валидный initData)
create or replace function public.url_encode(input text) returns text
language plpgsql immutable as $$
declare out text := ''; i int; byte int; b bytea := convert_to(input,'utf8');
begin
  for i in 0 .. length(b)-1 loop
    byte := get_byte(b, i);
    if (byte between 48 and 57) or (byte between 65 and 90) or (byte between 97 and 122)
       or byte in (45,46,95,126) then out := out || chr(byte);              -- A-Z a-z 0-9 - . _ ~
    else out := out || '%' || upper(lpad(to_hex(byte),2,'0'));
    end if;
  end loop;
  return out;
end $$;

-- helper: base64url без паддинга (для JWT)
create or replace function public.b64url(data bytea) returns text
language sql immutable as $$
  select rtrim(translate(replace(encode(data,'base64'), E'\n',''), '+/', '-_'), '=');
$$;

-- ОСНОВНАЯ: проверка + выпуск JWT
create or replace function public.auth_telegram(init_data text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  pair text; k text; v text; recv_hash text := '';
  parts text[] := '{}'; user_json text; auth_date_txt text;
  dcs text; bot_token text; jwt_secret text; secret_key bytea; computed text;
  tg_id text; v_client text;
  header text; payload text; sig text; now_epoch int;
begin
  -- 1) распарсить query-string initData
  foreach pair in array string_to_array(coalesce(init_data,''), '&') loop
    if pair = '' then continue; end if;
    k := split_part(pair, '=', 1);
    v := public.url_decode(substr(pair, length(k) + 2));
    if    k = 'hash'      then recv_hash := v;
    elsif k = 'signature' then null;                       -- не входит в HMAC-строку
    else  parts := parts || (k || '=' || v);
          if k = 'user'      then user_json := v; end if;
          if k = 'auth_date' then auth_date_txt := v; end if;
    end if;
  end loop;

  -- 2) data_check_string: ключи по алфавиту, join '\n'
  dcs := array_to_string(array(select unnest(parts) order by 1), E'\n');

  -- 3) секреты из Vault
  select decrypted_secret into bot_token  from vault.decrypted_secrets where name = 'bot_token'  limit 1;
  select decrypted_secret into jwt_secret from vault.decrypted_secrets where name = 'jwt_secret' limit 1;
  if bot_token is null or jwt_secret is null then
    return jsonb_build_object('ok',false,'error',jsonb_build_object('code','CONFIG','msg','vault secrets missing'));
  end if;

  -- 4) проверка подписи (WebApp): secret = HMAC(key='WebAppData', msg=bot_token); hash = HMAC(key=secret, msg=dcs)
  secret_key := hmac(bot_token, 'WebAppData', 'sha256');
  computed   := encode(hmac(convert_to(dcs,'utf8'), secret_key, 'sha256'), 'hex');
  if computed <> recv_hash then
    return jsonb_build_object('ok',false,'error',jsonb_build_object('code','BAD_SIGNATURE','msg','initData hash mismatch'));
  end if;

  -- 5) свежесть (24ч)
  if auth_date_txt is null or auth_date_txt::bigint < extract(epoch from now())::bigint - 86400 then
    return jsonb_build_object('ok',false,'error',jsonb_build_object('code','EXPIRED','msg','auth_date too old'));
  end if;

  -- 6) telegram id → клиент
  tg_id := (user_json::jsonb) ->> 'id';
  select client_id into v_client from client_identities where provider='telegram' and external_id = tg_id;
  if v_client is null then
    return jsonb_build_object('ok',false,'error',jsonb_build_object('code','NOT_INVITED','msg','no client for telegram id'),'tg_id',tg_id);
  end if;

  -- 7) выпуск Supabase JWT (HS256), claim client_id (срок 7 дней)
  now_epoch := extract(epoch from now())::int;
  header  := public.b64url(convert_to('{"alg":"HS256","typ":"JWT"}','utf8'));
  payload := public.b64url(convert_to(jsonb_build_object(
               'role','authenticated','aud','authenticated',
               'client_id',v_client,'sub',v_client,
               'iat',now_epoch,'exp',now_epoch + 604800)::text,'utf8'));
  sig := public.b64url(hmac(header||'.'||payload, jwt_secret, 'sha256'));

  return jsonb_build_object('ok',true,'client_id',v_client,'token',header||'.'||payload||'.'||sig);
end $$;

-- права: звать может anon (mini-app до входа); напрямую секреты anon не видит — только через эту функцию
revoke all on function public.auth_telegram(text) from public;
grant execute on function public.auth_telegram(text) to anon, authenticated;

-- ── САМОТЕСТ (после установки секретов; ПОДСТАВЬ свой telegram id вместо 1969344253) ──
-- with t as (select (select decrypted_secret from vault.decrypted_secrets where name='bot_token') bt,
--                   '{"id":1969344253,"first_name":"Test"}'::text uj, extract(epoch from now())::int::text ad),
--      h as (select bt,uj,ad, encode(hmac(convert_to('auth_date='||ad||E'\n'||'user='||uj,'utf8'),
--                                         hmac(bt,'WebAppData','sha256'),'sha256'),'hex') hash from t)
-- select public.auth_telegram('auth_date='||ad||'&user='||public.url_encode(uj)||'&hash='||hash) from h;
-- ОЖИДАЕМ: {"ok":true,"client_id":"vovchik","token":"eyJ..."}
