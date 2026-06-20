-- pk_ram — ключ позиции для RAM (gen-объём-частота[-so][-prem]).
-- АУДИТ 2026-06-08 (приёмник): переисправлены E7 и E8. Оба подтверждены в ЖИВЫХ данных
--   («Оперативная память ddr4 2x4gb»→cap 4 вместо 8; «ddr4 8x2gb»→cap 2 вместо 16).
-- Изменения относительно канона:
--   E7: кит N×M считаем РАНЬШЕ одиночного «(\d+)gb» и берём как валидный тотал
--       («2x32gb»→64, «2x4gb»→8). Одиночный gb — фолбэк, если кита нет или кит дал невалид.
--   E8: allowlist объёмов расширен под DDR5 (24/48/96) и тоталы китов (48/64/96/128/192/256).
--   R5 (2026-06-11, ОДОБРЕНО Алексеем): слабые ключи запрещены — gen И cap ОБЯЗАТЕЛЬНЫ.
--   R3 (11.06, пакет №2): частота понимает кириллицу (МГц/МТ/с); +DDR5 6800–8400.
--   PREM-ТИР (2026-06-20, owner ПЕРЕОТКРЫЛ §4): премиум/игровые линейки (XPG/HyperX/Corsair/
--     Vengeance/Trident/Viper/IRDM/T-Force…) при том же объёме стоят кратно дороже дженерика
--     (зонд: ddr4-16gb смешивал 1000↔12000 → медиана 6490 → ложные «ниже рынка»). Решение —
--     БИНАРНЫЙ тир «-prem» (не per-brand, чтобы бакеты зрели): премиум-линейка → отдельный бакет.
--     Остаток (безымянный/спорный премиум, бренд без линейки) — ВТОРОЙ ПОЯС DeepSeek (как E17-b у GPU).
--   ДЕПЛОЙ: CREATE OR REPLACE → пересев audit/keys/key_golden.sql → ре-ключ ram:
--       update lots set position_key = coalesce(pk_ram(model),pk_ram(title)) where item_category='ram';
--     (НЕ трогаем condition → LLM-вердикты целы) → snapshot_price_history() → compute_medians() →
--     consolidated_exam: keys 30/31 = 0, weak-keys 80–83 = 0.
create or replace function public.pk_ram(raw text)
 returns text language plpgsql immutable
as $$
declare s text; gen text; cap int; spd text; so text; prem boolean; m text[]; parts text[]:='{}';
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
  spd := coalesce( (regexp_match(s,'(\d{3,4})\s*(?:mhz|мгц|mt/?s|мт/?с|hz|гц)'))[1],
                   (regexp_match(s,'\y(1066|1333|1600|1866|2133|2400|2666|2800|2933|3000|3200|3333|3466|3600|3733|4000|4266|4800|5200|5600|6000|6400|6800|7000|7200|7400|7600|8000|8400)\y'))[1] );
  if s ~ 'so[\s-]?dimm' then so:='so'; end if;
  -- PREM-тир: премиум/игровые линейки (≠ per-brand; см. шапку). Безымянный премиум добьёт DeepSeek.
  prem := s ~ '(hyperx|fury|predator|savage|renegade|\ybeast\y|xpg|spectrix|gammix|corsair|vengeance|dominator|g\.?skill|ripjaws|trident|\ysniper\y|ballistix|\yviper\y|irdm|t-?force|vulcan|xtreem|toughram|xlr8|ocpc|\yrgb\y|royal)';
  -- R5: и поколение, и объём обязательны — иначе бакет смешивает разноценовые товары (яд медианы)
  if cap is null or gen is null then return null; end if;
  if gen is not null then parts:=parts||gen; end if;
  if cap is not null then parts:=parts||(cap||'gb'); end if;
  if spd is not null then parts:=parts||spd; end if;
  if so  is not null then parts:=parts||so;  end if;
  if prem            then parts:=parts||'prem'; end if;
  return array_to_string(parts,'-');
end $$;
