-- pk_psu — канон (= развёрнуто). Ключ = мощность в ваттах (грубо — намеренно, §4.2).
create or replace function public.pk_psu(raw text)
 returns text language plpgsql immutable
as $$
declare s text; w int; m text[];
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  m := regexp_match(s,'(\d{3,4})\s*(?:вт|ватт|w)');                 -- явная мощность
  if m is null then m := regexp_match(s,'(?:^|[^0-9x])(\d{3,4})(?![0-9x])'); end if;  -- бар-число, не часть AxB
  if m is null then return null; end if;
  w := m[1]::int;
  if w < 200 or w > 1600 or w % 50 <> 0 then return null; end if;
  return w||'w';
end $$;
