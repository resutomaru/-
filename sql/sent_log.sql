-- sent_log — журнал отправленных пушей. ДВА предохранителя Ф7 держатся на нём:
--   • дедуп: один лот клиенту не шлём дважды (push_queue: not exists в sent_log);
--   • лимит ≤6/час: push_queue считает sent_at за последний час.
-- БАГ (29.06): таблицы не было в git, живая версия разошлась с insert'ом push-воркфлоу
--   (`insert ... (client_id, lot_id, score) on conflict (client_id, lot_id)`), insert падал на каждом
--   прогоне → sent_log пустой → оба предохранителя мертвы → спам одним лотом по кругу.
-- Этот файл — КАНОН таблицы. Идемпотентен: создаёт, если нет; добивает недостающее, если завели криво.

create table if not exists sent_log (
  client_id text   not null,
  lot_id    bigint not null,
  score     numeric,
  sent_at   timestamptz not null default now()
);

-- добить недостающие колонки (если таблица уже была заведена руками без них):
alter table sent_log add column if not exists score   numeric;
alter table sent_log add column if not exists sent_at timestamptz not null default now();

-- снять возможные дубли ПЕРЕД уникальным индексом (нужен для on conflict в воркфлоу):
delete from sent_log a using sent_log b
 where a.ctid < b.ctid and a.client_id = b.client_id and a.lot_id = b.lot_id;

-- уникальный ключ (client_id, lot_id) — без него `on conflict` бросает ошибку, insert не проходит:
create unique index if not exists sent_log_client_lot_uniq on sent_log (client_id, lot_id);

-- ПРОВЕРКА: после прогона спам прекращается на следующем тике — каждый лот уходит РОВНО раз.
--   select count(*) from sent_log;                          -- должно расти после первых отправок
--   select lot_id, count(*) from sent_log group by lot_id having count(*)>1;  -- ДОЛЖНО быть пусто
