-- llm_gpu_keys — E17-b: DeepSeek-арбитраж конфликтов GPU-ключа (заголовок↔model). ТЕНЬ (workflow active:false).
-- Контекст: E17-a (pk_gpu v3) зануляет лоты, где заголовок и поле «Модель» называют РАЗНЫЕ карты
--   (мис-тег продавца) — безопасно, но теряет ~37 восстановимых лотов из медианы. Здесь — ВТОРОЙ ПОЯС:
--   дешёвый LLM как БИНАРНЫЙ арбитр выбирает, какой из ДВУХ кандидатов реальный, и возвращает лот в бакет.
-- РЕЖИМ (владелец 18.06, вариант A): скрипт = первое решение; DeepSeek = второй проверяющий, широко.
--
-- ГАРАНТИЯ БЕЗОПАСНОСТИ («не допускать плохие пункты»):
--   • LLM выбирает ТОЛЬКО из двух уже названных кандидатов (A=заголовок, B=model) — НЕ выдумывает третий;
--   • применяем ТОЛЬКО при confidence=high И выборе A/B; low/unsure → лот остаётся null (как после E17-a);
--   • пишем ключ ТОЛЬКО поверх position_key IS NULL — не перетираем уверенный ключ скрипта;
--   • асимметрия в промпте: сомнение/два товара/нехватка данных → unsure. Худший исход LLM = «остался null».
--   • снизу прежние пояса: snapshot working-only/K>20/IQR, светофор, теневой режим, ручное ревью батчей.
--
-- ДЕПЛОЙ: (1) этот SQL; (2) n8n — клонировать llm_workflow.json: Postgres-нода → select * from llm_gpu_queue,
--   DeepSeek-нода → промпт ниже (ProxyAPI/OpenRouter, t=0, JSON), apply-нода → select apply_llm_gpu_verdict(...);
--   (3) РУЧНОЙ прогон 1-2 батчей (Execute workflow) → РЕВЬЮ choices глазами (запрос «для глаз» внизу) →
--   только потом Active. Гейт: в ревью нет явно неверных A/B; экзамен строка 58 = 0.

create table if not exists llm_gpu_verdicts (
  lot_id      bigint primary key,
  choice      text not null check (choice in ('title','model','unsure')),
  confidence  text not null check (confidence in ('high','low')),
  key_title   text,            -- кандидат из заголовка (снимок pk_gpu(title,title) на момент арбитража)
  key_model   text,            -- кандидат из поля «Модель» (снимок pk_gpu(model,model))
  key_applied text,            -- какой ключ записан в lots (null, если не применяли)
  reason      text,
  model       text,            -- какая LLM-модель ответила
  applied     boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ОЧЕРЕДЬ: gpu-лоты, занулённые E17-a из-за конфликта (оба источника дали РАЗНЫЕ карты по базе+варианту).
--   Кандидаты считаем единым источником: pk_gpu(title,title) и pk_gpu(model,model) (та же логика, без конфликта).
create or replace view public.llm_gpu_queue as
with c as (
  select l.id as lot_id, l.title, coalesce(l.model,'') as model, l.description,
         pk_gpu(l.title, l.title) as key_title,
         pk_gpu(l.model, l.model) as key_model
  from lots l
  where l.item_category = 'gpu'
    and l.position_key is null        -- занулён (в т.ч. конфликтом E17-a)
    and coalesce(l.model,'') <> ''
)
select lot_id,
       left(title,200)                    as title,
       left(model,120)                    as model,
       left(coalesce(description,''),1500) as descr,
       key_title, key_model
from c
where key_title is not null and key_model is not null
  -- конфликт по базе+варианту (без префикса семейства и без _объёма): rx550≠rx580, 3070≠3070ti, 1650super≠1650
  and regexp_replace(key_title,'(^[a-z]+|_[0-9]+g$)','','g')
      is distinct from regexp_replace(key_model,'(^[a-z]+|_[0-9]+g$)','','g')
  and not exists (select 1 from llm_gpu_verdicts v where v.lot_id = c.lot_id)
  and (select count(*) from llm_gpu_verdicts where created_at >= date_trunc('day',now())) < 50  -- RR-02 бюджет
order by lot_id
limit 25;
alter view public.llm_gpu_queue set (security_invoker = on);

-- ПРИМЕНЕНИЕ: пишем ключ ТОЛЬКО при high + конкретный выбор + кандидат существует + лот ещё без ключа.
create or replace function public.apply_llm_gpu_verdict(
    p_lot_id bigint, p_choice text, p_confidence text, p_reason text, p_model text)
 returns void language plpgsql as $$
declare kt text; km text; chosen text; n int := 0;
begin
  select pk_gpu(title,title), pk_gpu(model,model) into kt, km from lots where id = p_lot_id;  -- снимок кандидатов

  insert into llm_gpu_verdicts (lot_id, choice, confidence, key_title, key_model, reason, model)
  values (p_lot_id, p_choice, p_confidence, kt, km, left(p_reason,300), p_model)
  on conflict (lot_id) do nothing;

  if p_confidence = 'high' and p_choice in ('title','model') then
    chosen := case p_choice when 'title' then kt when 'model' then km end;  -- ТОЛЬКО один из двух кандидатов
    if chosen is not null then
      update lots set position_key = chosen
       where id = p_lot_id and position_key is null;     -- не перетираем уверенный ключ скрипта
      get diagnostics n = row_count;
      update llm_gpu_verdicts set applied = (n>0), key_applied = case when n>0 then chosen end
       where lot_id = p_lot_id;
    end if;
  end if;
end $$;

-- ПРОМПТ для DeepSeek-ноды (system + user; t=0, JSON-режим, max_tokens ~120):
--   Ты — эксперт по видеокартам. В объявлении с Авито ЗАГОЛОВОК и поле «Модель» ПРОТИВОРЕЧАТ — называют
--   РАЗНЫЕ карты. Определи, какая РЕАЛЬНО продаётся.
--     A (из заголовка): {{key_title}}
--     B (из «Модель»):  {{key_model}}
--     Заголовок: {{title}}
--     Поле «Модель»: {{model}}
--     Описание: {{descr}}
--   Ответь СТРОГО JSON: {"choice":"A"|"B"|"unsure","confidence":"high"|"low","reason":"кратко"}.
--   Выбирай A или B ТОЛЬКО если из текста ЯСНО, какая карта настоящая. Любое сомнение, два разных товара
--   в одном лоте, нехватка данных → "unsure". Ошибка дороже пропуска: неверный выбор отравит цену.
-- В apply-ноде: choice A→'title', B→'model'; вызвать select apply_llm_gpu_verdict(lot_id, choice, confidence, reason, 'deepseek/deepseek-chat').

-- ДЛЯ ГЛАЗ (ОБЯЗАТЕЛЬНОЕ ревью перед Active): что LLM навыбирал —
-- select lot_id, left(title,55) as title, left(model,35) as model, choice, confidence,
--        key_title, key_model, key_applied, applied, left(reason,60) as reason
-- from llm_gpu_verdicts order by created_at desc;
