-- auth_foundation — ПИЛОН 1 бэкенда (backend-design §3, §5): идентичность + доступ.
-- АДДИТИВНО: новые таблицы, ничего существующего не ломаем. Завод (ингест/cron) и текущий бот не задеты.
-- client_configs (фильтры) ОСТАЁТСЯ как есть — его читает завод (client_feed/push_queue).
-- Дальше: RLS-политики (пилон 1b) и Edge Function auth-telegram (пилон 1c).

-- 1) clients — каноническая личность/статус клиента (слуг client_id остаётся, §3.1).
create table if not exists clients (
  client_id    text primary key,
  display_name text,
  status       text not null default 'active' check (status in ('active','paused','blocked')),
  created_at   timestamptz not null default now()
);

-- 2) client_identities — связка внешней личности (Telegram) с клиентом (§3.2).
--    Веб-кабинет тоже через Telegram Login → один провайдер 'telegram', одна личность на оба входа.
create table if not exists client_identities (
  id          bigserial primary key,
  client_id   text not null references clients(client_id) on delete cascade,
  provider    text not null check (provider in ('telegram')),
  external_id text not null,                         -- telegram user_id
  created_at  timestamptz not null default now(),
  unique (provider, external_id)
);

-- 3) invite_codes — онбординг ТОЛЬКО по коду (решение владельца). Редемпция — в auth-telegram (пилон 1c).
create table if not exists invite_codes (
  code        text primary key,
  client_id   text references clients(client_id),   -- привязать к этому клиенту; NULL = создать нового при редемпции
  note        text,
  used_by     text,                                  -- telegram external_id активировавшего
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- 4) current_client() — КТО звонит (источник прав для RLS и RPC). Читает claim client_id из JWT.
--    Без JWT (напр. в SQL-редакторе под postgres) вернёт NULL — это правильно (под RLS = нет доступа).
create or replace function public.current_client() returns text
language sql stable as $$
  select nullif((current_setting('request.jwt.claims', true))::jsonb ->> 'client_id', '');
$$;

-- 5) Сиды из текущего client_configs (vovchik) — аддитивно, идемпотентно.
insert into clients (client_id, display_name)
  select client_id, display_name from client_configs
  on conflict (client_id) do nothing;

insert into client_identities (client_id, provider, external_id)
  select client_id, 'telegram', chat_id from client_configs
  where chat_id is not null and chat_id <> 'TBD'
  on conflict (provider, external_id) do nothing;

-- ── Проверка (выполнить отдельно) ───────────────────────────────────────────
-- select * from clients;                         -- ждём строку vovchik
-- select * from client_identities;               -- ждём vovchik + его telegram id (если chat_id проставлен)
-- select public.current_client();                -- в SQL-редакторе вернёт NULL (нет JWT) — это норма
-- Пример выпуска инвайт-кода для НОВОГО клиента (на будущее):
-- insert into invite_codes (code, client_id, note) values ('PEREKUP-2026', null, 'тест-приглашение');
