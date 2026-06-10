-- normalize_new_lots — авто-нормализатор новых лотов (закрывает E16).
-- АУДИТ 2026-06-10 (приёмник): пайплайн категория→condition/is_component→ключи, ТОЛЬКО по
--   необработанным строкам (item_category/condition/position_key = null). Идемпотентен и безопасен:
--   уже размеченные строки не трогает; повторный прогон ничего не портит.
-- Расписание через pg_cron (раз в 2 мин, под ритм ингеста). НЕ путать с RR-18 (частота опроса
--   n8n→rest-app) — это DB-внутренний прогон, API не дёргает, на суточный лимит не влияет.

create or replace function public.normalize_new_lots() returns void language plpgsql as $$
begin
  -- 1) категория (только новые: item_category пуст)
  update lots set item_category = lot_category(title, model)
   where item_category is null;

  -- 2) раб/нераб + сборка (компоненты без метки)
  update lots set condition = lot_condition(title, description), is_component = lot_is_component(title)
   where item_category in ('gpu','cpu','ram','mobo','ssd','psu') and condition is null;

  -- 3) ключ позиции (компоненты без ключа)
  update lots set position_key = coalesce(pk_cpu(model),pk_cpu(title)) where item_category='cpu'  and position_key is null and coalesce(pk_cpu(model),pk_cpu(title)) is not null;
  update lots set position_key = coalesce(pk_ram(model),pk_ram(title)) where item_category='ram'  and position_key is null and coalesce(pk_ram(model),pk_ram(title)) is not null;
  update lots set position_key = pk_mobo(model,title)                  where item_category='mobo' and position_key is null and pk_mobo(model,title) is not null;
  update lots set position_key = pk_ssd(title,brand)                   where item_category='ssd'  and position_key is null and pk_ssd(title,brand) is not null;
  update lots set position_key = coalesce(pk_psu(model),pk_psu(title)) where item_category='psu'  and position_key is null and coalesce(pk_psu(model),pk_psu(title)) is not null;
  update lots set position_key = pk_gpu(model,title)                   where item_category='gpu'  and position_key is null and pk_gpu(model,title) is not null;
end $$;

-- расписание (pg_cron). Требует: create extension if not exists pg_cron;
-- select cron.schedule('normalize-new-lots', '*/2 * * * *', $$select public.normalize_new_lots();$$);
-- снять: select cron.unschedule('normalize-new-lots');
