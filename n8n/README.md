# n8n — ингест-воркфлоу (канон в git)

`ingest_workflow.json` — экспорт боевого воркфлоу «My workflow» (12.06.2026), **обезличенный**:
в URL HTTP-ноды реальные `login`/`token` заменены на `${RESTAPP_LOGIN}`/`${RESTAPP_TOKEN}`
(секреты в git не кладём, RR-14). При импорте подставить реальные значения и привязать
Postgres-credential (Session pooler Supabase, SSL Ignore = ON).

## Цепочка
Manual Trigger + Schedule Trigger → HTTP Request (rest-app, `category_id=101`, **`last_m=15`** ✓ RR-18)
→ Split Out `data` → Code (JS-маппинг объявления → строка `lots`) → Postgres Insert (**Skip on Conflict** ✓).

## Замечания аудита (12.06)

1. **N8N-1 (рекомендация):** Insert-нода жёстко проставляет `is_component = false` каждой новой строке
   (артефакт настройки маппинга). Сейчас безвредно: авто-нормализатор (*/2) перезаписывает поле для всех
   шести компонент-категорий честной функцией, у other/assembly поле не используется. Но это ловушка на
   будущее — при случае убрать константу из маппинга колонок (Insert-нода → колонка `is_component` →
   очистить значение), пусть приходит NULL.
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
