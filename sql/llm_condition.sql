-- llm_condition — Ф4-добивка (гибрид из плана): дешёвая LLM дочитывает СПОРНУЮ середину unknown,
--   где regex бессилен (опечатки «нерабоьущая», эллипсис «какие-то работают, какие-то нет»,
--   числовые несоответствия «в биосе 16 вместо 32»). Потребитель — n8n/llm_workflow.json (DeepSeek).
-- ПРЕДОХРАНИТЕЛИ (RR-02/RR-05):
--   • только unknown-компоненты с содержательным описанием (≥40 симв), по одному разу (llm_verdicts);
--   • жёсткий потолок 150 лотов/день (правится цифрой в llm_queue) + limit 25 за прогон;
--   • вердикт применяется к lots.condition ТОЛЬКО при confidence='high' и ТОЛЬКО если лот всё ещё
--     unknown (regex-dead никогда не перетирается); applied ставится по ФАКТУ апдейта;
--   • check-констрейнты отбивают мусорный ответ модели (кривой JSON просто не применится).
-- ВАЖНО для будущих пересчётов condition: блоки «update lots set condition = lot_condition(...)»
--   обязаны исключать применённые LLM-вердикты (см. relabel_sync_check и комментарий в экзамене);
--   экзамен-инвариант 57 ловит молчаливое перетирание.

create table if not exists llm_verdicts (
  lot_id     bigint primary key,
  verdict    text not null check (verdict in ('working','dead','unknown')),
  confidence text not null check (confidence in ('high','low')),
  reason     text,
  model      text,
  applied    boolean not null default false,
  created_at timestamptz not null default now()
);

-- Очередь на дочитку (читает n8n)
create or replace view public.llm_queue as
select l.id as lot_id,
       left(coalesce(l.title,''), 200)        as title,
       left(coalesce(l.description,''), 1500) as descr
from lots l
where l.item_category in ('gpu','cpu','ram','mobo','ssd','psu')
  and l.condition = 'unknown'
  and length(coalesce(l.description,'')) >= 40
  and not exists (select 1 from llm_verdicts v where v.lot_id = l.id)
  and (select count(*) from llm_verdicts where created_at >= date_trunc('day', now())) < 150
order by l.posted_at desc nulls last
limit 25;
alter view public.llm_queue set (security_invoker = on);

-- Применение вердикта (зовёт n8n после ответа модели)
create or replace function public.apply_llm_verdict(
  p_lot_id bigint, p_verdict text, p_confidence text, p_reason text, p_model text
) returns void language plpgsql as $$
declare n int := 0;
begin
  insert into llm_verdicts (lot_id, verdict, confidence, reason, model)
  values (p_lot_id, p_verdict, p_confidence, left(p_reason, 300), p_model)
  on conflict (lot_id) do nothing;

  if p_verdict in ('working','dead') and p_confidence = 'high' then
    update lots set condition = p_verdict
     where id = p_lot_id and condition = 'unknown';   -- regex-dead не перетираем никогда
    get diagnostics n = row_count;
    update llm_verdicts set applied = (n > 0) where lot_id = p_lot_id;
  end if;
end $$;

-- Для глаз: свежие вердикты (выполнять отдельно):
-- select v.lot_id, v.verdict, v.confidence, v.applied, v.reason, left(l.title,60) title
-- from llm_verdicts v join lots l on l.id = v.lot_id
-- order by v.created_at desc limit 30;
