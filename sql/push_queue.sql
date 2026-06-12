-- push_queue — Ф7: очередь пушей в Telegram (что отправить ПРЯМО СЕЙЧАС и кому). ТЕНЬ до E19.
-- Кодифицирует решения §9 и RR-07, ничего не изобретая:
--   • пуши ТОЛЬКО по зрелым бакетам (basis = 'K>20'); тонкие K8-20-low остаются в client_feed для глаз;
--   • дедуп отправок: sent_log (client_id, lot_id) — второй раз тому же клиенту не шлём (двухслойный дедуп плана);
--   • тихие часы 22–09 МСК (§9): ночью очередь ПУСТА (не копим спам — утром старое отсеет свежесть);
--   • свежесть пуша: лоты старше 6 часов не пушим (протухшее — не «находка»; поле конфига уточним с живым клиентом);
--   • плавкий предохранитель RR-07: максимум 6 пушей в час на клиента, лучшие по баллу первыми;
--   • светофор НЕ фильтруем (RR-06: красное не прячем — Ф7-карточка помечает ⚠️), фильтрует min_score клиента;
--   • клиенты без chat_id (TBD) не получают ничего.
-- Потребитель — n8n-воркфлоу n8n/push_workflow.json: select * from push_queue → формат → Telegram → sent_log.

create or replace view public.push_queue as
with ranked as (
  select f.*, c.chat_id,
         row_number() over (partition by f.client_id order by f.score desc, f.скидка_проц desc) as rn,
         (select count(*) from sent_log s
           where s.client_id = f.client_id and s.sent_at >= now() - interval '1 hour') as sent_last_hour
  from client_feed f
  join client_configs c using (client_id)
  where c.chat_id <> 'TBD'
    and f.basis = 'K>20'
    and f.posted_at >= now() - interval '6 hours'
    and extract(hour from now() at time zone 'Europe/Moscow') between 9 and 21
    and not exists (select 1 from sent_log s
                    where s.client_id = f.client_id and s.lot_id = f.id)
)
select client_id, chat_id, id as lot_id, title, url, price, median_price, sample_size,
       скидка_проц, item_category, position_key, condition, region, city, posted_at, trust, score
from ranked
where rn <= greatest(0, 6 - sent_last_hour)
order by client_id, score desc;
alter view public.push_queue set (security_invoker = on);

-- Для глаз: select * from push_queue;  (сейчас пусто: медиан нет, chat_id = TBD — двойная тень)
