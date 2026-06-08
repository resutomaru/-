-- pk_ssd — ключ позиции для SSD (бренд-объём-интерфейс, §4.2).
-- АУДИТ 2026-06-08 (приёмник): E12 — добавлена sanity-проверка объёма ДИАПАЗОНОМ
--   (НЕ allowlist: объёмы SSD не степени двойки — 120/240/250/256/480/500/512/960…).
--   TB 1..16, GB 8..16384; иначе мусорное число из партномера → cap=null.
-- Severity низкая и это подтверждено живыми данными: регэксп требует литеральную единицу,
--   партномер вида S1201Y03480GP02512G00 уже даёт cap=null. Проверка — пояс на будущее.
-- Живое == git для pk_ssd подтверждено ДОСЛОВНО (pg_get_functiondef). НЕ деплоено приёмником.
create or replace function public.pk_ssd(raw text, brand text)
 returns text language plpgsql immutable
as $$
declare s text; br text; cap text; capn int; iface text; m text[]; parts text[]:='{}';
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  br := nullif(brand,'');
  if br is null then
    m := regexp_match(s,'\y(samsung|kingston|adata|crucial|western digital|wd|patriot|netac|silicon power|kingspec|smartbuy|goldenfir|compit|phison|intel|corsair|team|apacer|transcend|seagate|hikvision|digma)\y');
    if m is not null then br := m[1]; end if;
  end if;
  if br is not null then
    br := regexp_replace(lower(br),'[^a-z0-9]','','g');
    if br='westerndigital' then br:='wd'; elsif br='patriotmemory' then br:='patriot'; elsif br='siliconpower' then br:='sp'; end if;
  end if;
  -- объём + E12 sanity-диапазон
  m := regexp_match(s,'(\d+)\s*(?:tb|тб)');
  if m is not null then
    capn := m[1]::int;
    if capn between 1 and 16 then cap := capn||'tb'; end if;
  else
    m := regexp_match(s,'(\d+)\s*(?:gb|гб)');
    if m is not null then
      capn := m[1]::int;
      if capn between 8 and 16384 then cap := capn||'gb'; end if;
    end if;
  end if;
  if s ~ 'nvme|m\.?2' then iface:='nvme'; elsif s ~ 'sata|2\.5' then iface:='sata'; end if;
  if cap is null then return null; end if;
  if br is not null then parts:=parts||br; end if;
  parts := parts||cap;
  if iface is not null then parts:=parts||iface; end if;
  return array_to_string(parts,'-');
end $$;
