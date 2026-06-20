# Backend-design «Перекуп-помощник» — чертёж (v1, draft)

> **Цель.** Превратить рабочий прототип в продукт, который не стыдно вывести в массы: настоящая
> аутентификация, изоляция клиентов на уровне БД, единая API-поверхность, крепкий домен, наблюдаемость.
> Сначала ЭТОТ чертёж (утверждаем форму) → потом реализация пилон за пилоном, без переделок.
> Фронт (TG mini-app + Google Sheets + приятный бот) — ОТДЕЛЬНЫЙ этап, поверх этого API.
>
> **Что НЕ трогаем.** «Завод» (ингест → категория → ключ → condition → медиана → скоринг) — живой и
> остаётся как есть. Бэкенд-слой добавляется СВЕРХУ. Все §4-решения и аудит-каноны в силе.

---

## 0. Принципы бэкенда
1. **Изоляция на уровне БД, а не «на честном слове».** Клиент физически не может прочитать чужое — RLS, не фильтр в коде.
2. **Один канон на каждую операцию.** Бот, mini-app и Sheets зовут ОДНИ и те же RPC. Никаких копий логики (NEW-4).
3. **Никаких голых id и молчаливых сбоев.** Каждый вызов возвращает явный результат или явную ошибку с кодом.
4. **Секреты — только на сервере.** Bot-token, JWT-secret, service-key — в Edge Functions / env, не в клиенте и не в git.
5. **Завод и помощник раздельны.** Завод пишет служебной ролью (минует RLS); клиентский слой — только через API под RLS.

---

## 1. Архитектура одним экраном

```
              ┌─────────────────────────── SUPABASE ───────────────────────────┐
ЗАВОД (как есть)│  Postgres:                                                     │
 rest-app→n8n──┼─▶ lots, price_history, medians   (SHARED, пишет service-role)   │
 pg_cron       │   ↓ (view)                                                       │
               │   finds  ← склад находок (контракт §4), read-only клиенту        │
               │                                                                  │
ПОМОЩНИК        │   clients, client_identities, client_configs, deals, sent_log   │
               │   └─ RLS: client видит ТОЛЬКО своё (client_id = current_client())│
               │                                                                  │
               │  RPC (PostgREST):  me / journal_* / finds_* / config_*           │
               │  Edge Functions:   auth-telegram (проверка initData → JWT)        │
               │  Auth:             Supabase Auth (веб) + TG initData (mini-app)   │
               └──────────────────────────────────────────────────────────────────┘
                         ▲ JWT (client_id в claim)            ▲ service-role
        ┌────────────────┼───────────────┬───────────────────┘
   TG mini-app      Бот (n8n)        Google Sheets (Мост)        Веб-кабинет
   (богатый UI)   (уведомления +    (двусторонний синк            (позже)
                   быстрые команды)   поверх API)
```

**Идея:** «две двери — одни данные». Все клиенты (mini-app/бот/Sheets/веб) ходят через **одну API-поверхность**
под **одной системой прав (RLS)**. Завод — отдельный контур, пишет служебной ролью, RLS его не касается.

---

## 2. Стек — менять не нужно
Supabase закрывает весь нужный бэкенд:
- **Postgres + RLS** — данные и изоляция.
- **PostgREST** — авто-API над RPC-функциями (`POST /rest/v1/rpc/journal_add`).
- **Edge Functions (Deno)** — серверная логика с секретами (проверка Telegram `initData`, выпуск JWT).
- **Auth** — сессии/JWT для веб-кабинета.
- **Storage** — статика mini-app (или внешний хост — решим на этапе фронта).
n8n остаётся для ингеста и бота. **Новый стек не вводим.**

> Тариф: сейчас Supabase Free. Перед массовым запуском — оценить лимиты Auth/Egress, возможно Pro (отдельно).

---

## 3. Идентичность и аутентификация

### 3.1 Бизнес-ключ клиента
`client_id` остаётся **человекочитаемым слугом** (`'vovchik'`) — он уже PK в `client_configs` и FK по всей базе
(`deals`, `sent_log`). UUID не вводим (лишняя миграция без выгоды). Слуг стабилен и читаем в логах/Sheets.

### 3.2 Связка «внешняя личность → клиент»
Новая таблица:
```
client_identities(
  id           bigserial pk,
  client_id    text not null references clients(client_id),
  provider     text not null check (provider in ('telegram','supabase')),
  external_id  text not null,                 -- telegram user_id ИЛИ supabase auth uid
  created_at   timestamptz default now(),
  unique(provider, external_id)
)
```
Один клиент может иметь и TG-личность, и веб-логин — обе указывают на один `client_id`.

### 3.3 TG mini-app — аутентификация через `initData`
Telegram отдаёт mini-app подписанную строку `initData`. Проверяем подпись СЕРВЕРНО (нужен bot-token = секрет):
- **Edge Function `auth-telegram`**: принимает `initData` → считает `secret = HMAC_SHA256(bot_token,"WebAppData")`,
  `hash = HMAC_SHA256(data_check_string, secret)`, сверяет с присланным; проверяет свежесть `auth_date`.
- Валидно → берём `telegram user_id` → ищем `client_identities` → `client_id` (нет записи → онбординг, §12).
- Выпускаем **Supabase JWT** (подписан JWT-secret проекта) с claim `client_id` (+ `role='authenticated'`).
- mini-app кладёт JWT как сессию Supabase → все RPC несут его → RLS читает claim.

### 3.4 Веб-кабинет (в scope СРАЗУ)
Тот же web-app, что mini-app, но открытый в браузере. Авторизация — **Telegram Login Widget** (та же
телеграм-личность, что и в mini-app → один `client_id`, единый провайдер `'telegram'`). Edge Function
`auth-telegram` проверяет И `initData` (mini-app), И данные Login-Widget (веб) — обе подписаны bot-token'ом
→ один JWT с `client_id`. Email/Supabase-Auth — опционально позже.

### 3.5 `current_client()` — кто звонит
SQL-функция, источник истины прав для RLS и RPC:
```
create function current_client() returns text language sql stable as $$
  select coalesce(
    auth.jwt() ->> 'client_id',                                  -- mini-app (claim)
    (select client_id from client_identities                     -- веб (supabase uid)
       where provider='supabase' and external_id = auth.uid()::text)
  );
$$;
```
Спуфить нельзя: claim внутри подписанного JWT; uid выдаёт Supabase Auth.

---

## 4. RLS — модель изоляции

| Таблица | Видимость | Политика |
|---|---|---|
| `clients` | своя строка | `client_id = current_client()` |
| `client_identities` | свои | `client_id = current_client()` |
| `client_configs` | своя | `client_id = current_client()` |
| `deals` | свои | select/insert/update/delete: `client_id = current_client()` |
| `sent_log` | свои | `client_id = current_client()` |
| `lots` / `finds` | **общие, read-only** | authenticated → `select` (склад общий; фильтр по конфигу делает RPC) |
| `price_history`, `medians` | служебные | клиенту НЕ доступны напрямую (только через `finds`/RPC) |

- RLS **включается** на клиентских таблицах. Завод (n8n/cron) пишет **service-role** → RLS его минует (ингест не ломается).
- Запись `deals.client_id` всегда = `current_client()` (проставляет RPC/триггер), клиент не может подсунуть чужой id.
- `find_buy` создаёт сделку под текущего клиента — источник (склад) общий, результат (сделка) приватный.

---

## 5. Модель данных (изменения)

**Новое / переименование:**
- `clients` — каноническая сущность клиента: `client_id text pk, display_name, status('active'|'paused'), created_at`.
  (Выделяем «личность» из нынешнего `client_configs`; конфиг-фильтры остаются в `client_configs`.)
- `client_identities` — §3.2.
- На `deals` — RLS + констрейнты валидации (цены ≥ 0, дата продажи ≥ даты покупки и т.п.).

**Остаётся как есть (домен уже собран в прототипе):**
- `deals` + `deal_ledger` (навар — единый канон) + дашборды (`deal_dashboard/by_category/cashflow`).
- `buy_lot`/`mark_sold` — станут внутренностями RPC (`find_buy`/`journal_mark_sold`), не зовутся напрямую.

**Контракт «склад находок» (`finds`)** — view по §4 спеки (то, что помощник читает):
```
finds = lots ⋈ medians, только показываемые поля:
  id, source, url, posted_at, region, city,
  item_category, model, position_key, id_confidence,
  price, typical_price (median), discount_pct, price_status('надёжно'|'мало данных'|'устарела'|'тест'),
  condition, trust, trust_reasons[]
```
`finds` — общий read-only; персональную выдачу (фильтр+скоринг клиента) даёт RPC `finds_list` поверх `client_feed`.

---

## 6. API-поверхность (RPC)

Все — `security definer`, внутри опираются на `current_client()`; RLS — второй пояс. Возврат — **единый конверт**:
`{ "ok": true, "data": … }` либо `{ "ok": false, "error": { "code": "...", "msg": "..." } }`.
Валидация → `app_error('VALIDATION','...')`. Ниже — контракт (имя · вход · выход):

**Профиль/конфиг**
- `me()` → `{client, config}` — текущий клиент + его настройки.
- `config_get()` → конфиг (категории, N%, регионы, стоп-слова, тихие часы…).
- `config_update(p jsonb)` → валидирует и сохраняет (RR-09: диапазоны).

**Журнал (сделки)**
- `journal_list(p jsonb)` `{status?,limit?,offset?,sort?}` → массив сделок (из `deal_ledger`, RLS-scoped).
- `journal_get(id)` → одна сделка с разбором навара.
- `journal_add(p jsonb)` → ручная сделка (валидация полей) → `{id}`.
- `journal_update(id, p jsonb)` → частичное редактирование (всё правится, RR-10).
- `journal_delete(id)` → удалить (или мягко — `status='archived'`; решим).
- `journal_mark_sold(id, p jsonb)` `{sell_price,sold_at?,channel?}` → отметить продажу, вернуть навар/маржу.
- `journal_dashboard()` → сводка (прибыль, в плюс %, маржа, оборотка, оборачиваемость, топ-категории, кэшфлоу).

**Склад находок**
- `finds_list(p jsonb)` `{category?,min_score?,limit?,offset?}` → персональная выдача (фильтр+скоринг клиента).
- `find_get(id)` → карточка находки (контракт §4 + «что спросить»).
- `find_buy(id, p jsonb)` `{buy_price?}` → завести сделку из находки (автозаполнение; идемпотентно по client+lot).

**Аутентификация** (Edge Function, не RPC)
- `auth-telegram(init_data)` → проверка подписи → Supabase JWT с `client_id`.

**Контракт ошибок (коды):** `AUTH` (не аутентифицирован), `FORBIDDEN` (чужое), `NOT_FOUND`,
`VALIDATION` (плохой вход), `CONFLICT` (идемпотентность/дубль), `RATE_LIMIT`, `INTERNAL`. PostgREST отдаёт их 4xx/5xx.

---

## 7. Домен — правила

- **Сделка — жизненный цикл:** `in_stock → sold | returned | repairing | written_off`. Переходы валидируются.
  Навар считается ТОЛЬКО для `sold` (иначе NULL — не угадываем, RR-10). Всё редактируемо.
- **Находка → сделка (`find_buy`):** автозаполнение из `lots` (товар/категория/ключ/url/цена), цена правится.
  Идемпотентность: одна находка (client_id, lot_id) в журнал дважды не кладётся (partial unique).
- **Флаги риска несут смысл дальше:** `id_confidence`=низкая ИЛИ `price_status`≠надёжно ИЛИ `condition`=dead →
  находка НЕ может уйти как «зелёная выгода» (fail-safe §4 спеки), максимум — в список с пометкой.
- **Идемпотентность записи** — ключ операции (client+lot, или клиентский `request_id`) против двойных тапов.

---

## 8. Синхронизация Google Sheets (Мост)
- Sheets — **витрина+редактор поверх API**, не прямой доступ к таблицам.
- Поток: коннектор (n8n или Apps Script) под сервис-личностью клиента читает `journal_list`/`config_get` → пишет
  в лист; правки в листе → `journal_update`/`config_update`. Расписание-синк (RR-09: валидация на входе,
  сломанный лист → последние хорошие настройки + сигнал).
- Конфликты: `updated_at`-сравнение, «последняя правда — у того, кто позже» + лог расхождений.
- **Двойная польза:** тот же Мост — это и конфиг клиента (Ф8), и журнал в привычной перекупу таблице.

---

## 9. Наблюдаемость и безопасность
- **Ошибки видны:** каждый RPC — явный конверт; бот/mini-app показывают `error.msg`. Никаких «молчит».
- **Лог операций:** `app_events(client_id, action, ok, error_code, meta, at)` — для датчиков (risk-register).
- **Метрики-датчики:** dead→working=0, доля ложных «ниже рынка», спам-рейт, расход LLM/запросов, аптайм, лаг.
- **Лимиты/бюджеты:** rate-limit на запись (RR-07), потолок LLM/запросов (RR-02), тихие часы пушей.
- **Секреты:** bot-token/JWT-secret/service-key — в env Edge Functions; в git и клиенте их нет (RR-14).

---

## 10. Роль бота и n8n в новой схеме
- **Бот — ПОЛНОЦЕННЫЙ (решение владельца), но через кнопки/визарды:** умеет всё (находки, журнал, продажа,
  правки) — НЕ голыми командами `/продал 1 7000`, а инлайн-кнопками и пошаговыми диалогами (иначе вернётся
  хрупкость — причина нынешнего «молчит»). + кнопка «Открыть приложение» для богатого экрана. Зовёт те же RPC.
- **n8n:** ингест (как есть) + опросный мост бота (Telegram getUpdates → вызов RPC, не сырой SQL) + Sheets-синк.
- Бот/mini-app зовут **те же RPC** — один канон.

---

## 11. Миграция — как переходим, не ломая завод
Пилон за пилоном; завод всё время живой:
1. **Фундамент:** `clients` + `client_identities` + `current_client()`; включить **RLS** на `deals`/configs/sent_log
   (service-role завода не задет). Проверка изоляции: «второй клиент видит ДРУГОЕ» (RR-08).
2. **Auth:** Edge Function `auth-telegram` (проверка initData → JWT). Тест на себе (shadow).
3. **API-поверхность:** RPC `me/journal_*/finds_*/config_*` + единый конверт ошибок + `app_events`.
4. **Домен-крепость:** валидация, жизненный цикл сделки, контракт `finds`, идемпотентность.
5. **Sheets-мост** поверх API.
6. **Наблюдаемость:** датчики/лимиты.
→ затем **ФРОНТ** (отдельный чертёж): TG mini-app, веб-кабинет, приятный бот.

Каждый пилон: код → golden/тест → деплой → проверка. Принцип «тихо лучше, чем ложно» в силе.

---

## 12. Решения владельца (приняты 20.06)
1. **Онбординг — по приглашению/коду** (`invite_codes`): чужой не зайдёт. Контроль доступа.
2. **Бот — полноценный**, но интерфейс — кнопки/визарды, не голые id-команды (см. §10). На сам бэкенд не влияет
   (те же RPC) — добавляет работы на этапе фронта.
3. **Веб-кабинет — в scope СРАЗУ** (тот же web-app, что mini-app; единый вход через Telegram, §3.4).

Остаточные (дефолты, не блок): удаление сделки — **мягкое** (`status='archived'`, восстановимо); хостинг web-app
(mini-app + кабинет) — решим в начале фронт-этапа (Supabase Storage / Vercel / GitHub Pages).

---

## Лог
- 2026-06-20 — чертёж v1 заведён + **решения владельца приняты** (§12: онбординг по коду, бот полноценный
  через кнопки/визарды, веб-кабинет сразу на единой телеграм-личности). Чертёж закрыт, старт пилона 1.
