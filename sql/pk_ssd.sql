-- pk_ssd — канон (= развёрнуто). Ключ = бренд+объём+интерфейс (§4.2).
-- ОТКРЫТО: E12 — нет валидации объёма (в отличие от pk_ram), может вытащить мусорный объём из партномера.
create or replace function public.pk_ssd(raw text, brand text)
 returns text language plpgsql immutable
as $$
declare s text; br text; cap text; iface text; m text[]; parts text[]:='{}';
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
  m := regexp_match(s,'(\d+)\s*(?:tb|тб)'); if m is not null then cap:=m[1]||'tb';
  else m := regexp_match(s,'(\d+)\s*(?:gb|гб)'); if m is not null then cap:=m[1]||'gb'; end if; end if;
  if s ~ 'nvme|m\.?2' then iface:='nvme'; elsif s ~ 'sata|2\.5' then iface:='sata'; end if;
  if cap is null then return null; end if;
  if br is not null then parts:=parts||br; end if;
  parts := parts||cap;
  if iface is not null then parts:=parts||iface; end if;
  return array_to_string(parts,'-');
end $$;
