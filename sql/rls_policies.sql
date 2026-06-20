-- rls_policies — ПИЛОН 1b: изоляция клиентов на уровне БД (backend-design §4).
-- Роль authenticated (клиентский API) видит ТОЛЬКО своё: client_id = current_client().
-- Завод (n8n/cron под postgres/service_role) RLS МИНУЕТ — ингест/пуш/нынешний бот не задеты.
-- RPC будут security definer (пилон 2) — RLS здесь второй пояс защиты.

-- ── включить RLS на клиентских таблицах ─────────────────────────────────────
alter table clients           enable row level security;
alter table client_identities enable row level security;
alter table client_configs    enable row level security;
alter table deals             enable row level security;
alter table sent_log          enable row level security;
alter table invite_codes      enable row level security;   -- без клиентской политики = только service_role

-- ── политики «только своё» (drop+create — идемпотентно) ─────────────────────
drop policy if exists own_clients on clients;
create policy own_clients on clients for all to authenticated
  using (client_id = current_client()) with check (client_id = current_client());

drop policy if exists own_identities on client_identities;
create policy own_identities on client_identities for all to authenticated
  using (client_id = current_client()) with check (client_id = current_client());

drop policy if exists own_configs on client_configs;
create policy own_configs on client_configs for all to authenticated
  using (client_id = current_client()) with check (client_id = current_client());

drop policy if exists own_deals on deals;
create policy own_deals on deals for all to authenticated
  using (client_id = current_client()) with check (client_id = current_client());

drop policy if exists own_sent on sent_log;
create policy own_sent on sent_log for all to authenticated
  using (client_id = current_client()) with check (client_id = current_client());

-- ── гранты роли authenticated (RLS фильтрует до своего; без гранта — нет доступа вовсе) ──
grant select, insert, update, delete on deals to authenticated;
grant select on clients, client_identities, client_configs, sent_log to authenticated;
-- invite_codes роли authenticated НЕ даём (онбординг — через service_role в auth-telegram).

-- ── ТЕСТ изоляции (RR-08) — выполнять ДВУМЯ отдельными прогонами ─────────────
-- A) свой видит своё:
-- begin; set local role authenticated; set local "request.jwt.claims"='{"client_id":"vovchik"}';
--   select count(*) as vovchik_видит_сделок from deals;  rollback;     -- ждём ≥1
-- B) чужой видит ноль:
-- begin; set local role authenticated; set local "request.jwt.claims"='{"client_id":"ghost"}';
--   select count(*) as ghost_видит_сделок from deals;    rollback;     -- ждём 0
