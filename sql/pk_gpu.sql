-- pk_gpu — ключ позиции для GPU (base+suffix+_объём), §3.5 + §4.3/§4.4. ВЕРСИЯ v3.
-- АУДИТ 2026-06-10: инлайн §3.5 → ФУНКЦИЯ + фикс E9 + добор. v2: title-фолбэк базы, Arc, гард сборок.
-- v3 (2026-06-18, E17): СВЕРКА заголовок↔model. Зонд (60 расхождений) показал: продавцы мис-тегают
--   поле «Модель» (заголовок «RX 550», model «RX 580») → дешёвая карта падала в дорогой бакет (отрава
--   медианы, ось E17/E19). Лечение — НЕ «верить заголовку» (зонд: model часто чище), а ДЕТЕКТ КОНФЛИКТА:
--     • извлекаем карту отдельно из model-источника и из заголовка (общий helper pk_gpu_base);
--     • совпали ИЛИ отличие только в букве семейства (gtx/rtx-опечатка, rx/hd — число+вариант те же) →
--       одна карта → берём канон из model (как раньше, changed=0 на этих);
--     • разные по числу/варианту (rx550≠rx580, 3070≠3070ti, 1650≠1650super) → МИС-ТЕГ → null («молчим»,
--       «тихо лучше, чем ложно» — лот уходит из медианы, но НЕ травит бакет);
--     • одна сторона дала карту → она (model-first / title-фолбэк §4.4 — без изменений).
--   ВТОРОЙ ПОЯС (E17-b, отдельно): DeepSeek-проверяющий вернёт занулённые из-за конфликта в правильный
--     бакет (бинарный арбитраж A/B, применять только high+совпал с кандидатом). Здесь — безопасный пол.
-- НЕ покрываем НАМЕРЕННО (safe-null): «GeForce NNNN» без префикса; диапазон-догадка номер→семья (RR-03/RR-04).
-- E9: 'super' только \ysuper\y И номер из Super-линейки. tisuper — отдельный SKU 4070.
--
-- ДЕПЛОЙ (гейт, по порядку): (1) CREATE обе функции ниже; (2) ПРЕВЬЮ-дифф (запрос в конце файла) —
--   глянуть changed/emptied; (3) пересев audit/keys/pk_gpu.golden.sql → mismatches=0; (4) полный ре-ключ:
--   update lots set position_key = pk_gpu(model,title) where item_category='gpu';
--   (5) select snapshot_price_history();  (самочистка истории D4/E19 уберёт занулённые); (6) экзамен:
--   строка 20 (gpu) = 0; счётчик 93 (без ключа) подрастёт на число занулённых конфликтов (ожидаемо).
create or replace function public.pk_gpu_base(src text)
 returns text language plpgsql immutable
as $$
declare base text; suf text := ''; num text; m text[];
begin
  if coalesce(src,'') = '' then return null; end if;
  -- BASE (порядок важен: rtxa → rtx/gtx → arc → gts → gt → vega → hd → rx/radeon → r5/7/9 → p10x)
  if src ~ 'rtx\s*a\s*[0-9]{3,4}' then base := 'rtxa'||substring(src from 'rtx\s*a\s*([0-9]{3,4})'); end if;
  if base is null then
    m := regexp_match(src, '\y(rtx|gtx)\s*([0-9]{3,4})(?!\s*(?:mb|мб|gb|гб|tb|тб))');  -- P4: число+единица = объём, не модель
    if m is not null then base := m[1]||m[2]; end if;
  end if;
  if base is null then
    m := regexp_match(src, '\yarc\s*([ab])\s*([0-9]{3})');             -- Intel Arc (E11)
    if m is not null then base := 'arc'||m[1]||m[2]; end if;
  end if;
  if base is null and src ~ '\ygts\s*[0-9]{3}(?!\s*(?:mb|мб|gb|гб))'  then base := 'gts'||substring(src from '\ygts\s*([0-9]{3})(?!\s*(?:mb|мб|gb|гб))'); end if;
  if base is null and src ~ '\ygt\s*[0-9]{3,4}(?!\s*(?:mb|мб|gb|гб))' then base := 'gt' ||substring(src from '\ygt\s*([0-9]{3,4})(?!\s*(?:mb|мб|gb|гб))'); end if;
  if base is null and src ~ 'vega\s*[0-9]{2}'   then base := 'vega'||substring(src from 'vega\s*([0-9]{2})'); end if;
  if base is null and src ~ 'hd\s*[0-9]{4}(?!\s*(?:mb|мб|gb|гб))'     then base := 'hd' ||substring(src from 'hd\s*([0-9]{4})(?!\s*(?:mb|мб|gb|гб))'); end if;
  if base is null then
    m := regexp_match(src, '\y(?:rx|radeon)(?:\s*rx)?\s*([0-9]{3,4})(?!\s*(?:mb|мб|gb|гб|tb|тб))');
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
  if base is null then return null; end if;

  num := substring(base from '([0-9]+)$');   -- номер (хвост базы) для super-allowlist

  -- SUFFIX (xtx → ti+super → xt → ti → super[allowlist])
  if    src ~ 'xtx' then suf := 'xtx';
  elsif (src ~ '[0-9]ti\y' or src ~ '\yti\y') and src ~ '\ysuper\y' and num = '4070' then suf := 'tisuper';
  elsif src ~ '[0-9]xt\y' or src ~ '\yxt\y' then suf := 'xt';
  elsif src ~ '[0-9]ti\y' or src ~ '\yti\y' then suf := 'ti';
  elsif src ~ '\ysuper\y' and num in ('1650','1660','2060','2070','2080','4070','4080') then suf := 'super';
  end if;

  return base || suf;
end $$;

create or replace function public.pk_gpu(model text, title text)
 returns text language plpgsql immutable
as $$
declare s text; st text; bundle_t boolean; key_m text; key_t text; bs text; mem text;
begin
  if coalesce(model,'') = '' and coalesce(title,'') = '' then return null; end if;
  s  := translate(lower(coalesce(nullif(model,''), title)), 'хс', 'xc');  -- model-first источник
  st := translate(lower(coalesce(title,'')), 'хс', 'xc');                  -- заголовок

  -- E19 (глазной тест 20.06): мобильные/ноутбучные GPU ≠ десктопные (свой рынок, заметно дешевле) →
  --   НЕ в десктопный бакет. Safe-null (как E17-конфликт): лот уходит из медианы, бакет не травится.
  --   «3070m laptop» падало в rtx3070_8g (десктоп) и давало ложную скидку.
  if (s || ' ' || st) ~ '(laptop|ноутбу|мобильн|max-?q|\y[0-9]{3,4}\s*m\y)' then return null; end if;

  -- гард сборок (R6): бандл-заголовок не даёт базу (иначе зашьём «Комплект i5 + RX 590» как rx590)
  bundle_t := st ~ '(комплект|\yв сборе\y|\yсборка\y|с процессор|\+\s*(rx|rtx|gtx|\ygt|radeon|geforce|arc|ryzen|core|i[3-9]|\d+\s*(gb|гб)))';
  if nullif(model,'') is null and bundle_t then return null; end if;  -- бандл с пустым model

  key_m := public.pk_gpu_base(s);                                        -- из model (или title, если model пуст)
  key_t := case when bundle_t then null else public.pk_gpu_base(st) end; -- из заголовка (не из бандла)

  -- E17: сверка заголовок↔model, когда ОБА источника назвали карту и model непуст
  if nullif(model,'') is not null and key_m is not null and key_t is not null then
    if regexp_replace(key_m, '^[a-z]+', '') = regexp_replace(key_t, '^[a-z]+', '')
      then bs := key_m;   -- та же карта (отличие лишь в букве семейства, gtx/rtx, rx/hd) → канон из model
      else return null;   -- разные карты (мис-тег «Модель») → null («молчим», E17/E19)
    end if;
  elsif key_m is not null then bs := key_m;   -- model-first (или title, когда model пуст)
  elsif key_t is not null then bs := key_t;   -- title-фолбэк (§4.4: model не распарсилась)
  else return null;
  end if;

  -- MEMORY (model-first, title-фолбэк; guard [^0-9] чтобы "512gb" не дал "12")
  mem := coalesce(
    substring(s  from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'),
    substring(st from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'));

  return bs || coalesce('_'||mem||'g', '');
end $$;

-- ПРЕВЬЮ-ДИФФ (шаг 2 деплоя; НИЧЕГО не меняет — position_key ещё старый, считаем новый на лету):
-- with d as (select id, title, position_key as old_key, pk_gpu(model,title) as new_key
--            from lots where item_category='gpu')
-- select count(*) filter (where old_key is distinct from new_key)                      as changed,
--        count(*) filter (where old_key is not null and new_key is null)               as emptied,
--        count(*) filter (where old_key is null and new_key is not null)               as filled,
--        count(*) filter (where old_key is not null and new_key is not null
--                          and old_key <> new_key)                                     as remapped
-- from d;
-- глазами: select id, left(title,60), old_key, new_key from d where old_key is distinct from new_key order by old_key;
