-- pk_ram — канон (= развёрнуто).
-- ОТКРЫТЫЕ БАГИ:
--   E7: кит N×M считается неверно — одиночный «(\d+)gb» срабатывает РАНЬШЕ ветки кита,
--       поэтому «2x32gb» → 32 вместо 64 (берёт M, а не N×M).
--   E8: allowlist объёмов (1,2,4,8,16,32,64,128,256) без 24/48/96 ГБ → совр. DDR5-модули → cap=null.
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
  cap := coalesce( (regexp_match(s,'(\d+)\s*(?:gb|гб)'))[1],
                   (regexp_match(s,'(\d+)\s*g\y'))[1] )::int;
  if cap is null then m:=regexp_match(s,'(\d+)\s*x\s*(\d+)'); if m is not null then cap:=m[1]::int*m[2]::int; end if; end if;
  if cap is null then m:=regexp_match(s,'(\d+)\s*mb');        if m is not null then cap:=round(m[1]::numeric/1024)::int; end if; end if;
  if cap is not null and cap not in (1,2,4,8,16,32,64,128,256) then cap:=null; end if;
  spd := coalesce( (regexp_match(s,'(\d{3,4})\s*mhz'))[1],
                   (regexp_match(s,'\y(1066|1333|1600|1866|2133|2400|2666|2800|2933|3000|3200|3333|3466|3600|3733|4000|4266|4800|5200|5600|6000|6400)\y'))[1] );
  if s ~ 'so[\s-]?dimm' then so:='so'; end if;
  if cap is null and gen is null then return null; end if;
  if gen is not null then parts:=parts||gen; end if;
  if cap is not null then parts:=parts||(cap||'gb'); end if;
  if spd is not null then parts:=parts||spd; end if;
  if so  is not null then parts:=parts||so;  end if;
  return array_to_string(parts,'-');
end $$;
