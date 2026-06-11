-- pk_ram — ключ позиции для RAM (gen-объём-частота[-so]).
-- АУДИТ 2026-06-08 (приёмник): переисправлены E7 и E8. Оба подтверждены в ЖИВЫХ данных
--   («Оперативная память ddr4 2x4gb»→cap 4 вместо 8; «ddr4 8x2gb»→cap 2 вместо 16).
-- Изменения относительно канона:
--   E7: кит N×M считаем РАНЬШЕ одиночного «(\d+)gb» и берём как валидный тотал
--       («2x32gb»→64, «2x4gb»→8). Одиночный gb — фолбэк, если кита нет или кит дал невалид.
--   E8: allowlist объёмов расширен под DDR5 (24/48/96) и тоталы китов (48/64/96/128/192/256).
--   R5 (2026-06-11, ОДОБРЕНО Алексеем): слабые ключи запрещены — gen И cap ОБЯЗАТЕЛЬНЫ.
--     Было: 'ddr4' (без объёма, смесь 4–128 ГБ) и '16gb' (без поколения, смесь DDR3/DDR5) шли
--     в price_history и зрели в ядовитые бакеты медианы. Теперь обе формы → null («не уверен — молчим»).
--   ДЕПЛОЙ R5-ПАКЕТА (после гейта №1 — дословного prosrc-диффа): CREATE OR REPLACE pk_ram + pk_cpu →
--     пересев audit/keys/key_golden.sql → полный ре-ключ:
--       update lots set position_key = null where item_category in ('ram','cpu');
--       select public.normalize_new_lots();
--     (история самосинхронизируется/самочистится снапшотом, D4) → consolidated_exam: weak-keys 80–83 = 0.
-- НЕ деплоено приёмником. Перед CREATE OR REPLACE сверить с живой версией (pk_ram live==git
--   подтверждён по поведению, дословно — нет; см. audit/reaudit-2026-06-08.md).
create or replace function public.pk_ram(raw text)
 returns text language plpgsql immutable
as $$
declare s text; gen text; cap int; spd text; so text; m text[]; parts text[]:='{}';
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  if    s ~ 'ddr ?5'  then gen:='ddr5';
  elsif s ~ 'ddr ?4'  then gen:='ddr4';
  elsif s ~ 'ddr ?3l' then gen:='ddr3l';
  elsif s ~ 'ddr ?3'  then gen:='ddr3';
  elsif s ~ 'ddr ?2'  then gen:='ddr2'; end if;
  -- E7: кит-тотал (N×M) ПЕРВЫМ; принимаем, если он валиден по allowlist (это валидный тотал)
  m := regexp_match(s,'(\d+)\s*x\s*(\d+)');
  if m is not null then cap := m[1]::int * m[2]::int; end if;
  -- одиночный объём — фолбэк, если кита нет ИЛИ кит дал невалид
  if cap is null or cap not in (1,2,4,8,16,24,32,48,64,96,128,192,256) then
    cap := coalesce( (regexp_match(s,'(\d+)\s*(?:gb|гб)'))[1],
                     (regexp_match(s,'(\d+)\s*g\y'))[1] )::int;
  end if;
  if cap is null then
    m := regexp_match(s,'(\d+)\s*mb'); if m is not null then cap := round(m[1]::numeric/1024)::int; end if;
  end if;
  -- E8: финальный allowlist — модули + тоталы китов, вкл. DDR5 24/48/96
  if cap is not null and cap not in (1,2,4,8,16,24,32,48,64,96,128,192,256) then cap := null; end if;
  spd := coalesce( (regexp_match(s,'(\d{3,4})\s*mhz'))[1],
                   (regexp_match(s,'\y(1066|1333|1600|1866|2133|2400|2666|2800|2933|3000|3200|3333|3466|3600|3733|4000|4266|4800|5200|5600|6000|6400)\y'))[1] );
  if s ~ 'so[\s-]?dimm' then so:='so'; end if;
  -- R5: и поколение, и объём обязательны — иначе бакет смешивает разноценовые товары (яд медианы)
  if cap is null or gen is null then return null; end if;
  if gen is not null then parts:=parts||gen; end if;
  if cap is not null then parts:=parts||(cap||'gb'); end if;
  if spd is not null then parts:=parts||spd; end if;
  if so  is not null then parts:=parts||so;  end if;
  return array_to_string(parts,'-');
end $$;
