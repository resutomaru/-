-- pk_gpu — ключ позиции для GPU (base+suffix+_объём), §3.5 + §4.3/§4.4. ВЕРСИЯ v2.
-- АУДИТ 2026-06-10 (приёмник): инлайн §3.5 (Supabase-only) → ФУНКЦИЯ (канон в git) + фикс E9 + добор.
-- v2 относительно v1 (добор по аудиту 22 непокрытых gpu-строк; всё ADDITIVE — старые ключи НЕ меняются):
--   + base-ФОЛБЭК НА ЗАГОЛОВОК, когда model не распарсилась. Это и есть §4.4 «model-first, заголовок-
--     фолбэк» (раньше фолбэк работал только для объёма). Ловит «GeForce 1050 Ti» (model без GTX) → gtx1050ti
--     и «gt210» (model без GT). С ГАРДОМ сборок (комплект/в сборе/«+ компонент») — чтобы не зашить бандл
--     (напр. «Комплект i5 + RX 590» НЕ должен стать rx590).
--   + ветка Intel Arc A/B (E11): «Intel Arc B580» → arcb580.
--   суффикс берём из ТОГО ЖЕ источника, что дал базу → сохраняет model-first 1-в-1 (changed=0 на старых).
-- НЕ покрываем НАМЕРЕННО (safe-null): «GeForce NNNN» совсем без префикса (GeForce 210 и т.п.) — диапазонная
--   догадка номер→семья ненадёжна (GT 1030 vs GTX 1050) → null безопаснее кривого ключа (RR-03/RR-04).
-- E9 (из v1): 'super' только слово целиком (\ysuper\y — не «superclocked») И номер из Super-линейки
--   (1650/1660/2060/2070/2080/4070/4080). Гипотеза брифа `[0-9] ?super` — негодна.
-- НЕ деплоено: гейт = golden (mismatches=0, см. audit/keys/pk_gpu.golden.sql) + превью-дифф (changed=0,
--   emptied=0), затем реран position_key.
create or replace function public.pk_gpu(model text, title text)
 returns text language plpgsql immutable
as $$
declare s text; st text; src text; base text; suf text := ''; num text; mem text; m text[]; srcs text[];
begin
  if coalesce(model,'') = '' and coalesce(title,'') = '' then return null; end if;
  s  := translate(lower(coalesce(nullif(model,''), title)), 'хс', 'xc');  -- model-first
  st := translate(lower(coalesce(title,'')), 'хс', 'xc');                  -- заголовок

  -- R6 (11.06, пакет №2): бандл-гард и для PRIMARY-пути — при ПУСТОМ model заголовок-сборка не
  --   ключуется (раньше гард стоял только на фолбэке; снапшот и так не пускает is_component=false —
  --   это второй пояс защиты, RR-03/RR-04)
  if nullif(model,'') is null
     and st ~ '(комплект|\yв сборе\y|\yсборка\y|с процессор|\+\s*(rx|rtx|gtx|\ygt|radeon|geforce|arc|ryzen|core|i[3-9]|\d+\s*(gb|гб)))'
  then return null; end if;

  -- источники базы: model-first; заголовок — фолбэк (§4.4), но НЕ для сборок (иначе зашьём бандл)
  if nullif(model,'') is not null
     and st !~ '(комплект|\yв сборе\y|\yсборка\y|с процессор|\+\s*(rx|rtx|gtx|\ygt|radeon|geforce|arc|ryzen|core|i[3-9]|\d+\s*(gb|гб)))'
  then srcs := array[s, st];
  else srcs := array[s];
  end if;

  foreach src in array srcs loop
    -- BASE (порядок важен: rtxa → rtx/gtx → arc → gts → gt → vega → hd → rx/radeon → r5/7/9 → p10x)
    if src ~ 'rtx\s*a\s*[0-9]{3,4}' then base := 'rtxa'||substring(src from 'rtx\s*a\s*([0-9]{3,4})'); end if;
    if base is null then
      m := regexp_match(src, '\y(rtx|gtx)\s*([0-9]{3,4})');
      if m is not null then base := m[1]||m[2]; end if;
    end if;
    if base is null then
      m := regexp_match(src, '\yarc\s*([ab])\s*([0-9]{3})');             -- NEW v2: Intel Arc (E11)
      if m is not null then base := 'arc'||m[1]||m[2]; end if;
    end if;
    if base is null and src ~ '\ygts\s*[0-9]{3}'  then base := 'gts'||substring(src from '\ygts\s*([0-9]{3})'); end if;
    if base is null and src ~ '\ygt\s*[0-9]{3,4}' then base := 'gt' ||substring(src from '\ygt\s*([0-9]{3,4})'); end if;
    if base is null and src ~ 'vega\s*[0-9]{2}'   then base := 'vega'||substring(src from 'vega\s*([0-9]{2})'); end if;
    if base is null and src ~ 'hd\s*[0-9]{4}'     then base := 'hd' ||substring(src from 'hd\s*([0-9]{4})'); end if;
    if base is null then
      m := regexp_match(src, '\y(?:rx|radeon)(?:\s*rx)?\s*([0-9]{3,4})');
      if m is not null then base := 'rx'||m[1]; end if;
    end if;
    if base is null then
      m := regexp_match(src, '\yr([579])\s*([0-9]{3})');                 -- AMD R5/R7/R9
      if m is not null then base := 'r'||m[1]||m[2]; end if;
    end if;
    if base is null then
      m := regexp_match(src, '\yp([0-9]{3})[\s-]+([0-9]{2,3})');         -- майнинг P106-100
      if m is not null then base := 'p'||m[1]||m[2]; end if;
    end if;
    exit when base is not null;
  end loop;
  if base is null then return null; end if;

  num := substring(base from '([0-9]+)$');   -- номер (хвост базы) для super-allowlist

  -- SUFFIX из ТОГО ЖЕ src, что дал базу (xtx → ti+super → xt → ti → super[allowlist])
  if    src ~ 'xtx' then suf := 'xtx';
  elsif (src ~ '[0-9]ti\y' or src ~ '\yti\y') and src ~ '\ysuper\y' and num = '4070' then suf := 'tisuper';
  elsif src ~ '[0-9]xt\y' or src ~ '\yxt\y' then suf := 'xt';
  elsif src ~ '[0-9]ti\y' or src ~ '\yti\y' then suf := 'ti';
  elsif src ~ '\ysuper\y' and num in ('1650','1660','2060','2070','2080','4070','4080') then suf := 'super';
  end if;

  -- MEMORY (model-first, title-фолбэк; guard [^0-9] чтобы "512gb" не дал "12")
  mem := coalesce(
    substring(s  from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'),
    substring(st from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'));

  return base || suf || coalesce('_'||mem||'g', '');
end $$;
