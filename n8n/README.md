# n8n — ингест-воркфлоу (канон в git)

`ingest_workflow.json` — экспорт боевого воркфлоу «My workflow» (12.06.2026), **обезличенный**:
в URL HTTP-ноды реальные `login`/`token` заменены на `${RESTAPP_LOGIN}`/`${RESTAPP_TOKEN}`
(секреты в git не кладём, RR-14). При импорте подставить реальные значения и привязать
Postgres-credential (Session pooler Supabase, SSL Ignore = ON).

## Цепочка
Manual Trigger + Schedule Trigger → HTTP Request (rest-app, `category_id=101`, **`last_m=15`** ✓ RR-18)
→ Split Out `data` → Code (JS-маппинг объявления → строка `lots`) → Postgres Insert (**Skip on Conflict** ✓).

## Замечания аудита (12.06)

1. **N8N-1 — СНЯТ ПРОВЕРКОЙ (12.06, живая база):** Insert-нода хранит в маппинге константу
   `is_component = false`, но в режиме Map Automatically n8n её ИГНОРИРУЕТ — свежие не-компонентные
   строки за 2 дня: NULL = 726, false = 0. Мёртвый осадок в JSON, чистка не требуется; вспомнить,
   только если когда-нибудь переключим ноду в режим Map Each Column Manually.
2. **Schedule Trigger:** экспорт не содержит явного `minutesInterval` (n8n не сохраняет значения,
   равные дефолту; дефолт = 5 мин — совпадает с решением RR-18). Фактический темп подтверждается
   утренним счётчиком rest-app: ~6.6к/сут = 5 минут; ~33к/сут (упор в лимит) = случайно стоит 1 минута.
3. **RR-14 в силе:** токен живёт в URL ноды. При переезде на 24/7-хостинг (RR-13) вынести в
   env/credential.

Этим файлом закрыт последний кусок E21: весь канон системы (SQL-функции, сети, экзамены, ингест)
теперь версионируется в git.

---

# push_workflow.json — Ф7: доставка находок в Telegram (выключен, active:false)

Цепочка: Manual + Schedule (*/5, ЯВНЫЙ minutesInterval) → Postgres `select * from push_queue`
(вся логика «что/кому/сколько/когда» — в SQL: дедуп sent_log, тихие часы 22–09 МСК, лимит 6/час,
basis K>20, свежесть 6ч) → Code (карточка: балл, светофор с ⚠️ на red, % ниже медианы, ссылка)
→ Telegram sendMessage → Postgres insert sent_log (дедуп-отметка).

## Подключение (когда Алексей готов)
1. **BotFather** в Telegram: `/newbot` → имя → получить **токен**. Токен НИКУДА не вставлять,
   кроме n8n: Credentials → New → Telegram API → вставить. (В git токен не попадает.)
2. **chat_id для теста**: напиши своему боту любое сообщение, затем открой в браузере
   `https://api.telegram.org/bot<ТОКЕН>/getUpdates` — в ответе `"chat":{"id": ЧИСЛО}`. Это твой id.
3. В Supabase: `update client_configs set chat_id='ЧИСЛО' where client_id='vovchik';`
   (для начала — ТВОЙ id, теневой тест на себе; Вовчику переключим после E19, RR-08.)
4. Импорт: n8n → Workflows → Import from File → выбрать push_workflow.json → в нодах Telegram и
   Postgres выбрать свои credentials.
5. **Тест трубы (до медиан!):** вручную вставить тест-строку в sent_log не нужно — проще: временно
   подменить query первой Postgres-ноды на
   `select 'vovchik' client_id, 'ЧИСЛО' chat_id, 0 lot_id, 'ТЕСТ: труба доставки' title, 'https://example.com' url, 1000 price, 2000 median_price, 21 sample_size, 50 "скидка_проц", 'working' condition, 'Москва' region, 'Москва' city, 'green' trust, 9.9 score`
   → Manual test run → карточка должна прийти в Telegram → вернуть query обратно.
6. Воркфлоу оставить **ВЫКЛЮЧЕННЫМ** (active=false) до глазного теста E19 — включим вместе.

Предохранители уже внутри: дедуп (повторно не шлёт), тихие часы, ≤6 пушей/час на клиента,
только зрелые бакеты K>20, только свежие лоты ≤6ч, chat_id='TBD' = клиент молчит.

---

# llm_workflow.json — Ф4-добивка: LLM дочитывает спорные «неясные» (выключен, active:false)

Цепочка: Manual + Schedule (раз в 2 часа) → Postgres `llm_queue` (только unknown-компоненты с
содержательным описанием, по одному разу, ≤150/день, 25 за прогон) → Code (промпт-классификатор,
JSON-режим, температура 0) → HTTP DeepSeek → Code (парс; кривой ответ → unknown/low, к данным не
применяется) → Postgres `apply_llm_verdict` (high working/dead → lots.condition; regex-dead не
перетирается; applied по факту апдейта).

## Подключение
1. SQL: прогнать `sql/llm_condition.sql` (таблица llm_verdicts + очередь + функция).
2. Импорт llm_workflow.json. В ноде **DeepSeek**: Credential → Create new **Header Auth**:
   Name = `Authorization`, Value = `Bearer sk-ВАШ_КЛЮЧ` (ключ только в credential!).
   В нодах Postgres выбрать «Postgres account».
   ⚠️ ЭНДПОИНТ: ключ через посредника **ProxyAPI** (Россия, ₽). DeepSeek у них НЕ нативный провайдер
   (нативны только OpenAI/Anthropic/Gemini) — идёт через их **OpenRouter**:
   URL ноды = `https://api.proxyapi.ru/openrouter/v1/chat/completions`,
   модель в Build request = `deepseek/deepseek-chat` (OpenRouter-неймспейс, с префиксом провайдера).
   Источник: proxyapi.ru/docs/openrouter. Если переедешь на ПРЯМОЙ ключ deepseek.com —
   URL `https://api.deepseek.com/chat/completions`, модель `deepseek-chat` (без префикса).
3. Первый прогон — ВРУЧНУЮ (Execute workflow), затем выгрузка вердиктов на ревью
   (запрос «для глаз» в конце llm_condition.sql). Active включать только после ревью вердиктов.
4. Бюджет (RR-02): потолок 150 лотов/день зашит в llm_queue; модель deepseek-chat, t=0,
   max_tokens 120 → порядок цены: доли цента за лот.

---

# E17-b — DeepSeek-арбитраж GPU-ключа (заголовок↔model). ВЫКЛ (active:false) до ревью.

Не отдельный воркфлоу с нуля — **клон `llm_workflow.json`** (та же труба ProxyAPI/OpenRouter, t=0, JSON):
1. SQL: прогнать `sql/llm_gpu_keys.sql` (таблица `llm_gpu_verdicts` + вью `llm_gpu_queue` + `apply_llm_gpu_verdict`).
2. Postgres-нода очереди: `select * from llm_gpu_queue` (вместо `llm_queue`).
3. DeepSeek-нода: промпт БИНАРНОГО арбитража — целиком в шапке `sql/llm_gpu_keys.sql` (A=заголовок, B=model,
   иначе unsure). Эндпоинт/credential — те же, что у condition-трубы.
4. Парс-нода: `A→'title'`, `B→'model'`, иначе `'unsure'`.
5. Apply-нода: `select apply_llm_gpu_verdict({{lot_id}}, '{{choice}}', '{{confidence}}', '{{reason}}', 'deepseek/deepseek-chat');`
6. **ОБЯЗАТЕЛЬНО:** ручной прогон 1-2 батчей → ревью глазами (запрос «для глаз» внизу `llm_gpu_keys.sql`) →
   только потом Active. Гейт: нет явно неверных A/B; экзамен строка 58 = 0.

Безопасность: применяется ТОЛЬКО `high`+конкретный выбор+ключ-кандидат+`position_key IS NULL` (не перетирает
скрипт, не выдумывает третью карту). Бюджет: ≤50/день (зашит в `llm_gpu_queue`), 25/прогон.

---

# journal_bot_workflow.json — «Помощник·Журнал»: Telegram-бот (выключен, active:false)

Тонкая труба (вся логика — в SQL `tg_router`, как ingest/push): **Telegram Trigger** (message +
callback_query) → **Postgres** `select * from tg_router($1::jsonb)` (мозг: роутинг команд/кнопок,
`buy_lot`/`mark_sold`, дашборд `deal_dashboard`, привязка chat_id→client_id) → **Telegram** sendMessage
(`{{$json.reply}}` в `{{$json.chat_id}}`). Команды: `/журнал`, `/купил <id лота> [цена]`,
`/продал <id сделки> <цена>`, `/help`. Кнопка «Купил» на пуш-карточке (`buy:<lot_id>`) — добавим в
push-карточку при go-live (бот её уже понимает).

## Подключение (после деплоя sql/deals.sql, sql/journal_capture.sql, sql/tg_router.sql)
1. **BotFather** → `/newbot` → токен. Токен только в n8n: Credentials → Telegram API → вставить (в git НЕ кладём).
   Можно переиспользовать тот же бот-аккаунт, что и для пушей (push_workflow.json).
2. **Свой chat_id**: напиши боту любое сообщение → открой `https://api.telegram.org/bot<ТОКЕН>/getUpdates`
   → `"chat":{"id": ЧИСЛО}`. Пропиши его клиенту:
   `update client_configs set chat_id='ЧИСЛО' where client_id='vovchik';`
   (теневой тест на себе; Вовчику — после go-live, RR-08.)
3. **Импорт**: n8n → Import from File → journal_bot_workflow.json → в нодах Telegram и Postgres выбрать
   свои credentials.
4. **Активировать** воркфлоу (active=ON — боту нужен живой вебхук, чтобы принимать сообщения).
5. **Тест**: напиши боту `/help` → должен ответить списком команд; `/журнал` → сводка (или «журнал пуст»);
   `/купил <реальный id из lots>` → «✅ В журнал…»; `/продал <id сделки> <цена>` → «💰 Навар…».

Безопасность: чужой chat_id (не в `client_configs`) → вежливый отказ (RR-08). Захват — через канон
`buy_lot`/`mark_sold` (формула навара не дублируется, NEW-4). Параметр в Postgres-ноду уходит связанным
($1::jsonb) — без склейки строк (инъекции нет).
