-- pk_gpu — ключ позиции для GPU (base+suffix+_объём), §3.5 + §4.3.
-- АУДИТ 2026-06-10 (приёмник): инлайн §3.5 (Supabase-only) ПОРТИРОВАН в ФУНКЦИЮ — канон теперь
--   в git (закрывает дыру «gpu не в git»). Формат ключа 1-в-1 с инлайном: перепрогон НЕ должен
--   дробить уже заполненные бакеты — это проверяется превью-диффом и golden-набором
--   (audit/keys/pk_gpu.golden.sql) ПЕРЕД деплоем.
-- Изменения относительно инлайна §3.5 (выведены из реальной gpu-выгрузки, 266 строк):
--   E9 (super без якоря): 'super' ставим ТОЛЬКО если это слово целиком (\ysuper\y — не цепляет
--       "superclocked") И номер из реальной Super-линейки (1650/1660/2060/2070/2080/4070/4080).
--       Иначе "GTX 1070 Super JetStream" (Palit, НЕ super) и "RTX 3070 SuperClocked" (EVGA)
--       дробили бы бакет. Гипотеза брифа `[0-9] ?super` негодна — ложит на "0 super" в "...3070 super".
--   + 'tisuper' для RTX 4070 Ti Super (отдельный SKU; ti-ветка стояла раньше super и съедала его).
--   + покрытие: AMD R5/R7/R9 (r9370…) и nVidia GTS (gts450…) — раньше уходили в null.
--   + guard объёма (?:^|[^0-9]): "Radeon R3 512GB" больше не отдаёт мусорный _12g.
-- model-first, title — фолбэк для объёма (§4.4). De-гомоглиф х/с→x/c (§4.5).
-- НЕ деплоено приёмником: сперва golden (mismatches=0) и превью-дифф (changed=0, emptied=0).
create or replace function public.pk_gpu(model text, title text)
 returns text language plpgsql immutable
as $$
declare s text; st text; base text; suf text := ''; num text; mem text; m text[];
begin
  if coalesce(model,'') = '' and coalesce(title,'') = '' then return null; end if;
  s  := translate(lower(coalesce(nullif(model,''), title)), 'хс', 'xc');  -- model-first
  st := translate(lower(coalesce(title,'')), 'хс', 'xc');                  -- title (фолбэк объёма)

  -- ===== BASE (порядок ветвей важен: rtxa → rtx/gtx → gts → gt → vega → hd → rx/radeon → r5/7/9 → p10x) =====
  if s ~ 'rtx\s*a\s*[0-9]{3,4}' then
    base := 'rtxa' || substring(s from 'rtx\s*a\s*([0-9]{3,4})');          -- pro RTX A-series
  end if;
  if base is null then
    m := regexp_match(s, '\y(rtx|gtx)\s*([0-9]{3,4})');
    if m is not null then base := m[1] || m[2]; num := m[2]; end if;
  end if;
  if base is null and s ~ '\ygts\s*[0-9]{3}' then
    base := 'gts' || substring(s from '\ygts\s*([0-9]{3})');               -- NEW: GTS 250/450…
  end if;
  if base is null and s ~ '\ygt\s*[0-9]{3,4}' then
    base := 'gt' || substring(s from '\ygt\s*([0-9]{3,4})');
  end if;
  if base is null and s ~ 'vega\s*[0-9]{2}' then
    base := 'vega' || substring(s from 'vega\s*([0-9]{2})');               -- раньше rx (в строке есть "rx vega")
  end if;
  if base is null and s ~ 'hd\s*[0-9]{4}' then
    base := 'hd' || substring(s from 'hd\s*([0-9]{4})');                   -- раньше rx/radeon
  end if;
  if base is null then
    m := regexp_match(s, '\y(?:rx|radeon)(?:\s*rx)?\s*([0-9]{3,4})');
    if m is not null then base := 'rx' || m[1]; num := m[1]; end if;
  end if;
  if base is null then
    m := regexp_match(s, '\yr([579])\s*([0-9]{3})');                       -- NEW: AMD R5/R7/R9 (не ловит rx/radeon)
    if m is not null then base := 'r' || m[1] || m[2]; end if;
  end if;
  if base is null then
    m := regexp_match(s, '\yp([0-9]{3})[\s-]+([0-9]{2,3})');               -- майнинг P106-100
    if m is not null then base := 'p' || m[1] || m[2]; end if;
  end if;
  if base is null then return null; end if;

  -- ===== SUFFIX (xtx → ti+super → xt → ti → super[allowlist]) =====
  if    s ~ 'xtx' then suf := 'xtx';
  elsif (s ~ '[0-9]ti\y' or s ~ '\yti\y') and s ~ '\ysuper\y' and num = '4070' then suf := 'tisuper';
  elsif s ~ '[0-9]xt\y' or s ~ '\yxt\y' then suf := 'xt';
  elsif s ~ '[0-9]ti\y' or s ~ '\yti\y' then suf := 'ti';
  elsif s ~ '\ysuper\y' and num in ('1650','1660','2060','2070','2080','4070','4080') then suf := 'super';
  end if;

  -- ===== MEMORY (1-2 цифры перед gb/гб/g; guard [^0-9] чтобы "512gb" не дал "12") =====
  mem := coalesce(
    substring(s  from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'),
    substring(st from '(?:^|[^0-9])([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'));

  return base || suf || coalesce('_' || mem || 'g', '');
end $$;
