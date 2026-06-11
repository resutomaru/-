-- lot_is_component — канон (= развёрнуто в БД). Детектор сборок/комплектов по ЗАГОЛОВКУ (§4.6).
-- false = сборка/комплект/лот/риг/ферма → НЕ отдельный компонент (исключается из медианы).
create or replace function public.lot_is_component(title text)
 returns boolean language plpgsql immutable
as $$
declare t text := lower(coalesce(title,''));
begin
  -- САМОАУДИТ D7: в '+'-альтернации не было GPU-слов → «Материнская плата + RX580» шла в медиану mobo
  --   ценой бандла. Добавлены rx/rtx/gtx/gt/radeon/geforce/видеокарт + форма «с RX 580».
  if t ~ 'комплект|в сборе|\y(сборка|лот|риг|ферма)\y|с процессором|с проц |с памятью|с видеокарт|с (rx|rtx|gtx)\s?\d|\+\s*(\d+\s*(gb|г|g)|ddr|i[3-9]|ryzen|cpu|проц|видеокарт|rx ?\d|rtx ?\d|gtx ?\d|gt ?\d{3}|radeon|geforce|[abhxz]\d{2,3}m?)'
     then return false; end if;
  return true;
end $$;
