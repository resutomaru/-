-- auth (план Б) — ПИЛОН 1c, без JWT-секрета. backend-design §3.3 (ревизия 20.06).
-- Причина: project JWT-секрет в новой версии Supabase недоступен (нет в app.settings.jwt_secret, спрятан в UI).
-- Решение: НЕ минтим сессию-JWT. Проверяем Telegram-подпись на КАЖДОМ вызове RPC.
--   verify_initData(init_data) → client_id (или RAISE при невалидной подписи/протухании/не-приглашён).
--   Нужен только секрет bot_token в Vault. RLS (пилон 1b) остаётся вторым поясом.
-- RPC (пилон 2) будут принимать init_data и звать verify_initData внутри (security definer).

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

-- helper: percent-encode (нужен только для самотеста — собрать валидный initData)
create or replace function public.url_encode(input text) returns text
language plpgsql immutable as $$
declare out text := ''; i int; byte int; b bytea := convert_to(input,'utf8');
begin
  for i in 0 .. length(b)-1 loop
    byte := get_byte(b, i);
    if (byte between 48 and 57) or (byte between 65 and 90) or (byte between 97 and 122)
       or byte in (45,46,95,126) then out := out || chr(byte);
    else out := out || '%' || upper(lpad(to_hex(byte),2,'0'));
    end if;
  end loop;
  return out;
end $$;

-- ОСНОВНАЯ: проверка подписи initData → client_id (RAISE при провале)
create or replace function public.verify_initData(init_data text)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  pair text; k text; v text; recv_hash text := '';
  parts text[] := '{}'; user_json text; auth_date_txt text;
  dcs text; bot_token text; secret_key bytea; computed text;
  tg_id text; v_client text;
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

  tg_id := (user_json::jsonb) ->> 'id';
  select client_id into v_client from client_identities where provider='telegram' and external_id = tg_id;
  if v_client is null then raise exception 'NOT_INVITED: tg_id=%', tg_id; end if;

  return v_client;
end $$;

revoke all on function public.verify_initData(text) from public;
grant execute on function public.verify_initData(text) to anon, authenticated;

-- ── САМОТЕСТ (после bot_token в Vault; ПОДСТАВЬ свой telegram id вместо 1969344253) ──
-- with t as (select (select decrypted_secret from vault.decrypted_secrets where name='bot_token') bt,
--                   '{"id":1969344253,"first_name":"Test"}'::text uj, extract(epoch from now())::int::text ad),
--      h as (select bt,uj,ad, encode(hmac(convert_to('auth_date='||ad||E'\n'||'user='||uj,'utf8'),
--                                         hmac(bt,'WebAppData','sha256'),'sha256'),'hex') hash from t)
-- select public.verify_initData('auth_date='||ad||'&user='||public.url_encode(uj)||'&hash='||hash) as client from h;
-- ОЖИДАЕМ: client = vovchik
