-- pk_cpu — канон (= развёрнуто). Ключ позиции для CPU (model-first, заголовок-фолбэк зовётся снаружи).
-- Паритет с JS-эталоном сверялся ранее (превью). Открытых багов не зафиксировано (E11 — низкий приоритет: Xeon Scalable Platinum/Gold).
create or replace function public.pk_cpu(raw text)
 returns text language plpgsql immutable
as $$
declare s text; m text[];
begin
  if raw is null then return null; end if;
  s := translate(lower(raw), 'хс', 'xc');
  m := regexp_match(s,'ryzen\s*(?:pro\s*)?([3579])\s*(?:pro\s*)?([0-9]{3,4})\s*(x3d|xt|ge|gt|x|g|f)?');  -- pro-инфикс (probe C)
    if m is not null then return 'ryzen'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'core\s*ultra\s*([3579])\s*([0-9]{3})\s*(kf|ks|k|f|hx|h)?');
    if m is not null then return 'ultra'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'core\s*2\s*(duo|quad)\s*([a-z]?[0-9]{4})');
    if m is not null then return 'core2'||m[1]||'-'||m[2]; end if;
  m := regexp_match(s,'\yi([3579])[\s-]*([0-9]{3,5})\s*(kf|ks|k|f|qm|t|x)?');
    if m is not null then return 'i'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'xeon\s*(platinum|gold|silver|bronze)\s*([0-9]{4})');               -- Scalable (probe C)
    if m is not null then return 'xeon-'||m[1]||'-'||m[2]; end if;
  m := regexp_match(s,'xeon\s*([ewl][357])[\s-]*([0-9]{4})\s*v?\s*([0-9])?');              -- E/W/L-серия
    if m is not null then return 'xeon-'||m[1]||'-'||m[2]||case when m[3] is not null then 'v'||m[3] else '' end; end if;
  m := regexp_match(s,'xeon\s*([a-z])?\s*([0-9]{4})\s*v?\s*([0-9])?');                      -- X-серия / голый номер (probe C); v-суффикс ОБЯЗАТЕЛЕН (самоаудит D2: поколения v1/v2/v3 не смешивать)
    if m is not null then return 'xeon-'||coalesce(m[1],'')||m[2]||case when m[3] is not null then 'v'||m[3] else '' end; end if;
  m := regexp_match(s,'pentium\s*(?:gold|silver)?\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'pentium-'||m[1]; end if;  -- gold/silver-инфикс (key_golden gap)
  m := regexp_match(s,'celeron\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'celeron-'||m[1]; end if;
  m := regexp_match(s,'athlon\s*([a-z0-9]+)');         if m is not null then return 'athlon-'||m[1]; end if;
  m := regexp_match(s,'\yfx[\s-]*([0-9]{4})');         if m is not null then return 'fx-'||m[1]; end if;
  return null;
end $$;
