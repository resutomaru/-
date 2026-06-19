-- pk_cpu — канон (= развёрнуто). Ключ позиции для CPU (model-first, заголовок-фолбэк зовётся снаружи).
-- Паритет с JS-эталоном сверялся ранее (превью). Открытых багов не зафиксировано (E11 — низкий приоритет: Xeon Scalable Platinum/Gold).
create or replace function public.pk_cpu(raw text)
 returns text language plpgsql immutable
as $$
declare s text; m text[];
begin
  if raw is null then return null; end if;
  s := translate(lower(raw), 'хск', 'xck');  -- де-гомоглиф: +кириллическая к→k (суффикс «10600К» терял k)
  -- R6-cpu (18.06): ТИР выкинут из ключа — 4-значный номер уникален («5600X» — всегда Ryzen 5 5600X).
  --   Безтировый «Ryzen 5600X» больше НЕ дробится в ryzen5-600x; «Ryzen 5 5600X» даёт тот же ryzen-5600x.
  --   Опц. тир [3579]+пробел съедается, чтобы 4-значную модель не путать с тиром. (PRO-инфикс сохранён.)
  m := regexp_match(s,'ryzen\s*(?:pro\s*)?(?:[3579]\s+)?(?:pro\s*)?([0-9]{4})\s*(x3d|xt|ge|gt|x|g|f)?');
    if m is not null then return 'ryzen-'||m[1]||coalesce(m[2],''); end if;
  m := regexp_match(s,'core\s*ultra\s*([3579])\s*([0-9]{3})\s*(kf|ks|k|f|hx|h)?');
    if m is not null then return 'ultra'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'core\s*2\s*(duo|quad)\s*([a-z]?[0-9]{4})');
    if m is not null then return 'core2'||m[1]||'-'||m[2]; end if;
  m := regexp_match(s,'\yi([3579])[\s-]*([0-9]{3,5})\s*(kf|ks|k|f|qm|t|x)?');
    if m is not null then return 'i'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'xeon\s*(platinum|gold|silver|bronze)\s*([0-9]{4})');               -- Scalable (probe C)
    if m is not null then return 'xeon-'||m[1]||'-'||m[2]; end if;
  m := regexp_match(s,'xeon\s*([ewl][357])[\s-]*([0-9]{4})(?:\s*v\s*([0-9]))?');            -- E/W/L-серия (v-ревизия ТРЕБУЕТ букву v)
    if m is not null then return 'xeon-'||m[1]||'-'||m[2]||case when m[3] is not null then 'v'||m[3] else '' end; end if;
  m := regexp_match(s,'xeon\s*([a-z])?\s*([0-9]{4})(?:\s*v\s*([0-9]))?');                    -- X-серия/голый номер; v-ревизия ТРЕБУЕТ букву v (D2-fix2: «4 ядра» — это НЕ v4)
    if m is not null then return 'xeon-'||coalesce(m[1],'')||m[2]||case when m[3] is not null then 'v'||m[3] else '' end; end if;
  m := regexp_match(s,'pentium\s*(?:gold|silver)?\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'pentium-'||m[1]; end if;  -- gold/silver-инфикс (key_golden gap)
  m := regexp_match(s,'celeron\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'celeron-'||m[1]; end if;
  -- R5-cpu (2026-06-11): старый '([a-z0-9]+)' брал СЕМЕЙСТВО ('athlon ii'→'athlon-ii', 'x4', голый '64')
  --   → слабый бакет смешивал поколения. Теперь инфиксы 64/ii/pro/x2-x4 пропускаем, ключ ТОЛЬКО по
  --   номеру модели ('II X2 245'→athlon-245, 'X4 860K'→athlon-860k, '200GE'→athlon-200ge); нет номера → null.
  m := regexp_match(s,'athlon\s*(?:64\s*)?(?:ii\s*)?(?:pro\s*)?(?:x[234]\s*)?([a-z]?[0-9]{3,4}[a-z]{0,2})');
    if m is not null then return 'athlon-'||m[1]; end if;
  m := regexp_match(s,'\yfx[\s-]*([0-9]{4})');         if m is not null then return 'fx-'||m[1]; end if;
  return null;
end $$;
