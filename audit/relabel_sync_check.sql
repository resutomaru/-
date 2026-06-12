-- relabel_sync_check — «база == словари?» (детектор недопрогнанного пересчёта).
-- Сверяет СОХРАНЁННУЮ разметку lots с тем, что выдали бы ЖИВЫЕ функции прямо сейчас.
-- Норма: все четыре счётчика = 0 → база эквивалентна полному пересчёту, шагов не требуется.
-- Если >0 → прогнать блок пересчёта (шаг 7 деплоя: категория → condition/is_component →
--   обнуление ключей → normalize_new_lots → snapshot_price_history) и перепроверить.
-- Запускать после каждого деплоя словарей, когда есть сомнение «применилось ли к старым строкам».
select
  count(*) filter (where item_category is distinct from public.lot_category(title, model))
    as категория_расходится,
  count(*) filter (where item_category in ('gpu','cpu','ram','mobo','ssd','psu')
                   and condition is distinct from public.lot_condition(title, description)
                   and not exists (select 1 from llm_verdicts v          -- LLM-вердикты (Ф4-добивка)
                                   where v.lot_id = lots.id and v.applied)) -- расходиться ИМ положено
    as состояние_расходится,
  count(*) filter (where item_category in ('gpu','cpu','ram','mobo','ssd','psu')
                   and is_component is distinct from public.lot_is_component(title))
    as сборка_расходится,
  count(*) filter (where item_category in ('gpu','cpu','ram','mobo','ssd','psu')
                   and position_key is distinct from case item_category
                     when 'cpu'  then coalesce(pk_cpu(model),  pk_cpu(title))
                     when 'ram'  then coalesce(pk_ram(model),  pk_ram(title))
                     when 'mobo' then pk_mobo(model, title)
                     when 'ssd'  then pk_ssd(title, brand)
                     when 'psu'  then coalesce(pk_psu(model),  pk_psu(title))
                     when 'gpu'  then pk_gpu(model, title)
                   end)
    as ключ_расходится
from lots;
