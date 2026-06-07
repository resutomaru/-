# Передаточный бриф — Avito-парсер «сочных» лотов (АУДИТ-FIRST, v2)

> **Как использовать.** Отправь этот документ в новый чат-приёмник **вместе с исходным системным брифом**
> (`promtavitoparserispolnitel.md` — он был первым сообщением рабочего чата). Исходный бриф — это ПЛАН, а не код.
> Код Фаз 3–4 существует: (1) в git-ветке `claude/vigilant-dijkstra-HuerN` репозитория `resutomaru/-` (папки `sql/`, `audit/`),
> (2) в Supabase (развёрнут), (3) частично — только в Supabase-сниппетах (GPU-инлайн, единый нормализатор — в git их НЕТ).
> **Первая задача приёмника — НЕ продолжать сборку, а провести аудит §2 и переисправить. Только потом — фазы.**
>
> Дата передачи: 2026-06-07. Передаёт: рабочий чат-аудитор (опираюсь на переписку; где помечено «реконструкция» — не проверено).

---

## §0. Стартовый мандат приёмника

**Сначала аудит, не сборка.** Пройди §2 (реестр ошибок). По каждому пункту критически оцени: реально ли исправлено
или закрыто на словах. Сверяй с артефактами §3 **и с каноном в источниках** (git `sql/` + Supabase-сниппеты — см. §5),
потому что часть кода версионируется только в Supabase. Переисправь. **Не начинай ни одной фазы (5→8), пока аудит не закрыт.**

Пять предупреждений:
1. **Реестр §2 — это лиды, не полный список.** Я автор этой работы и склонен подавать её выгодно и считать свои фиксы
   рабочими. «Изменил» ≠ «починил». Перепроверяй по артефактам, а не по словам.
2. **Доказательство фикса = только наши совместные прогоны** (Алексей подтвердил: ничего, кроме тестов в этом и прошлом
   чате, не валидировалось). Где написано «подтверждено» — это значит «Алексей прогнал экзамен/превью и увидел результат»,
   а НЕ «проверено на исчерпывающем реальном корпусе».
3. **Намеренные решения §4 — НЕ баги.** Не «чини» грубые ключи `mobo/psu/ssd`, де-гомоглиф, один общий сбор, реализацию
   нормализатора как SQL — это осознанный выбор.
4. **Прямое требование заказчика (Алексей):** он считает Фазы 3 и 4 НЕ закрытыми и хочет их **на 100%**. В частности
   (его слова): «список слов нужно расширить до абсолютного исчерпывающего максимума и категоризатор усилить»; «думаю,
   много мусора лишнего в категориях». Это не починка конкретного бага, а планка готовности — см. §2 (NEW-1, NEW-2) и §7.
5. **Честный статус Фаз 3–4:** логика condition исправлена и проходит экзамен 18/0/0; категоризатор v2.2 закрыл виденные
   протечки. НО это **не делает фазы закрытыми на 100%**: открыты ключи позиции (E7/E8/E9/E12), словарь не исчерпывающий,
   working не перепроверен на новом масштабе, чистота категорий целенаправленно не аудитилась. Не считай Ф3/Ф4 готовыми.

---

## §1. Что строим + текущая точка + статус по фазам

**Что:** Telegram-бот мониторинга Авито на выгодные б/у комплектующие. Конвейер: **rest-app API → Postgres/Supabase →
категория → ключ позиции → раб/нераб → медиана → гейты → балл → Telegram**. Мульти-тенант (один общий сбор, фильтры на
клиента). Сейчас на **trial rest-app — цены случайные** → всё ценозависимое невалидируемо до оплаты.

**Текущая точка:** Аудит унаследованной передачи в разгаре. Закрыты и подтверждены экзаменом: кластер «раб/нераб»
(E1–E6, E18 частично) и протечки категоризатора (E10). Снят E13. Восстановлен бэкап (E21, частично). Разово разгребён
накопившийся ингест (E16). **НЕ закрыто:** ключи позиции (E7/E8/E9/E12), исчерпывающий словарь, чистота категорий,
position_key после разгреба, working на масштабе 410. Фазы 5–8 не начаты (блок: фейковые цены).

| Фаза | Готовность | Отклонение | Как проверено (в ЭТОМ чате) |
|---|---|---|---|
| 0. rest-app СТОП/ГО | **на вере** (унасл. ГО) | trial рандомит цены; ингест всё ещё на пробнике | механика ингеста подтв.; экономика/цены — нет |
| 1. Схема Postgres | подтв. | +таблица `condition_golden` (аудит) | таблицы видны в Supabase |
| 2. Ингест n8n | подтв., работает | токен в URL; не 24/7 (унасл.) | Executions зелёные, `lots` 904→1732 |
| 3. Нормализатор | **частично** | категоризатор как SQL (унасл.) | категория: фикс v2.2 подтв. (639/0+превью); **ключи: открыто** |
| 4. Раб/нераб + сборки | **частично** | де-гомоглиф; реархитектура негации | condition: экзамен 18/0/0 подтв.; working на 410 не дочёсан; LLM-добивка не начата |
| 5. Почасовая медиана | не начато | — | блок: цены trial фейковые |
| 6. Фильтр+скоринг+Sheets | не начато | приоритеты клиента собраны (вход) | — |
| 7. Telegram + дедуп | не начато | — | — |
| 8. Конфиг Sheets + 2-й клиент | не начато | — | — |

---

## §2. РЕЕСТР ОШИБОК И РИСКОВ (центр брифа — НЕ считать полным; новых фиксов НЕ предлагаю, описываю состояние)

Поля: **симптом · корень · что делали · доказательство · природа · происхождение · статус.**
Шкала статуса: `закрыто-подтверждено` / `исправлено-не-проверено` / `открыто` / `регресс` / `не тестировалось`.
Где есть гипотеза о причине/лечении — помечена как **гипотеза**, это не указание приёмнику.

**E1. Аудит condition не покрывал `working`.** Симптом: ложное «рабочее» на мёртвом невидимо в дампах dead. Корень:
методология. Что делали: прочесали `working` (167) + `unknown` (98) на реальных данных, нашли/закрыли 2 пропуска (см. WRK
в §3.14); построили экзамен. Доказательство: Алексей прогнал working-запросы и экзамен — подтв. на 167+98. **НО** после
разгреба `working` вырос до **410**, новые ~240 НЕ перечёсаны. Природа: процессная дыра (частично закрыта). Происхождение:
унасл.+признано. **Статус: частично закрыто; открыто на масштабе 410.**

**E2. «не исправ» (с пробелом) → working.** Корень: dead знал «неисправ» (без пробела), working знал «исправ». Что делали:
ШАГ 5 в `lot_condition` — вырезаем «не ?исправ», если не уцелел позитив → dead. Доказательство: экзамен 18/0/0 (Алексей
прогнал). Природа: **структурный** (реархитектура негации). Происхождение: латентный→признан. **Статус: закрыто-подтверждено
(на наборе; реальная инцидентность ~0).**

**E3. Прош. время «не работал(а/о)» → working.** Корень: dead знал только «не работает» (наст.). Что делали: ШАГ 5
«не ?работа\w*». Доказательство: экзамен 18/0/0. Природа: структурный. Происхождение: латентный→признан. **Статус:
закрыто-подтверждено (на наборе).**

**E4. «нерабоч» без соседнего существительного → working.** Корень: dead требовал существительное рядом / «в нерабочем».
Что делали: ШАГ 5 «нерабоч\w*»; override (уцелевший позитив) сохраняет E6-ценовой-хедж. Доказательство: экзамен 18/0/0.
Природа: структурный. Происхождение: регресс-риск от фикса E6 (унасл.)→закрыт. **Статус: закрыто-подтверждено (на наборе).**

**E5. Широкий гард «не работает … {0,18} вентил» спасал реально мёртвое.** Корень: lookahead-гард глушил dead, дальше
жадный позитив «работа» → working. Что делали: ШАГ 5 + override различает E5 (нет позитива → dead) и E6-fan («карта рабочая»
→ working). Доказательство: экзамен 18/0/0. Природа: структурный. Происхождение: регресс от ROG-гарда (унасл.)→закрыт.
**Статус: закрыто-подтверждено (на наборе).** Гипотеза-остаток: «не работает [подузел]» без позитива теперь уходит в dead —
может слегка пере-резать; на реальном дампе dead (26) ложных не видели.

**E6. Три ложных dead** («артефакты отсутствуют» / «по цене нерабочей» / «не работает 1 вентилятор»). Унасл. закрыто.
Что делали: держим регрессией — три кейса в экзамене обязаны остаться `working`. Доказательство: экзамен 18/0/0. Природа:
смесь. Происхождение: унасл. **Статус: закрыто-подтверждено (на наборе).**

**E7. `pk_ram`: кит «2x32gb» → 32 (а не 64).** Корень: ветка одиночного `(\d+)gb` стоит РАНЬШЕ ветки кита `N×M`, берёт M.
Что делали: **фикса не было** — только подтвердил по канону в git (`sql/pk_ram.sql`). Доказательство: н/п. Природа:
**гипотеза фикса** (кит первым) — не применена. Происхождение: латентный→подтв. по канону. **Статус: открыто.**

**E8. `pk_ram`: allowlist объёмов без 24/48/96 ГБ** (1,2,4,8,16,32,64,128,256) → совр. DDR5 → cap=null. Что делали: фикса
не было. Природа: гипотеза (расширить набор). Происхождение: латентный→подтв. **Статус: открыто.**

**E9. `pk_gpu` (GPU-инлайн): голый `super` без якоря к цифре** → «EVGA SuperClocked» пометит Super-версией. Что делали:
фикса не было; по чтению канона (§3.5). Доказательство: в виденных 48 заголовках (унасл.) не стреляло. **Важно:
GPU-инлайн в ЭТОМ чате против канона НЕ сверялся** (он не в git; канон — Supabase-сниппет). Природа: гипотеза
(`[0-9] ?super`). Происхождение: латентный. **Статус: открыто.**

**E10. Категоризатор: протечки аксессуаров в компоненты.** Симптом: кулер «Jonsbo … lga1700»→`mobo`; мышь HyperX→`ram`;
внешний корпус SSD→`ssd`; адаптер «блок питания для монитора»→`psu`. Корень: гард аксессуаров был привязан к НАЧАЛУ строки
(`^`) — аксессуар с брендом впереди + компонент-словом утекал. Что делали: **v2.2** (`sql/categorizer.sql`): ветка-0
периферия→other; исключения кулеров в `mobo`, боксов в `ssd`, адаптеров в `psu`. Доказательство: реконструкция = канон
(639/0); превью-дифф = 6 аксессуаров→other, 0 потерь компонентов; развёрнуто; backlog разгребён — Алексей прогнал, подтв.
Природа: **смесь** (по веткам структурно, но списки слов — заплаточно, НЕ исчерпывающе). Происхождение: признано.
**Статус: закрыто-подтверждено для ВИДЕННЫХ протечек; ОТКРЫТО как «усилить/исчерпать» (см. NEW-1, NEW-2).**

**E11. `pk_gpu`/`pk_cpu`: пробелы покрытия** (Intel Arc; Xeon Scalable Platinum/Gold). Что делали: фикса не было.
Происхождение: латентный. **Статус: открыто (низкий приоритет).**

**E12. `pk_ssd`: нет валидации объёма** (в отличие от `pk_ram`) → может вытащить мусорный объём из партномера. Что делали:
фикса не было; подтв. по канону (`sql/pk_ssd.sql`). Природа: гипотеза. Происхождение: латентный→подтв. **Статус: открыто.**

**E13. JS↔Postgres паритет / кириллица в `\y`.** Корень: поведение границы слова `\y`/`\w` на кириллице зависит от локали БД.
Что делали: прямой тест — `\y` на кириллице работает (`'ноут'~'\yноут\y'`=true, `'ноутбук'`=false), локаль `en_US.UTF-8`;
плюс прод SQL-only (JS-прототипа в проде нет). Доказательство: Алексей прогнал тест — подтв. Природа: снят. Происхождение:
аудит. **Статус: закрыто-подтверждено.**

**E14. Золотой/регресс-набор.** Что делали: построил `condition_golden` (18 кейсов) + harness (`sql/.../golden_set.sql`).
Доказательство: используется как экзамен (18/0/0). **НО** для категоризатора и ключей золотого набора НЕТ (категоризатор
валидирован разовым diff-ом, не набором). Происхождение: аудит. **Статус: закрыто для condition; открыто для
категоризатора/ключей.**

**E15. Крошечные выборки.** Что делали: working прочёсан на реальных 167 (не на 410); экзамен 18 — синтетика; реального
размеченного «золотого» набора из сотен лотов НЕТ. Происхождение: аудит. **Статус: открыто (статистически слабо;
Алексей хочет 100%).**

**E16. Свежий ингест копится необработанным.** Симптом: нормализатор/condition ручные, не на расписании. Что делали:
разовый разгреб (категоризатор v2.2 + condition на все 1732 → `без_категории`=0, `компоненты_без_метки`=0). Доказательство:
Алексей прогнал, снимок подтв. **НО** расписание НЕ сделано → будет копиться снова; и **position_key в разгребе НЕ
прогонялся** (см. NEW-3). Природа: операционное. Происхождение: признано. **Статус: разово закрыто; расписание открыто.**

**E17. [Источник ложных #1] Бакеты: варианты в один бакет** (3070 vs 3070 Ti). На уровне КАТЕГОРИИ — валидировано
(639/0 + превью). На уровне КЛЮЧА/варианта — **в этом чате НЕ валидировал** (GPU-разделение унасл. на 48 заголовках; RAM
имеет открытый дефект кита E7). Происхождение: унасл.+аудит. **Статус: категория закрыта; ключ/вариант — не тестировалось
в этом чате.**

**E18. [Источник ложных #2] Метка мёртвое↔рабочее.** `dead` — валидировано (экзамен + реальный дамп 26 строк, выглядели
верно). `working` — частично (167 строк; на 410 не перепроверено). Происхождение: унасл.+аудит. **Статус: dead-направление
подтв.; working-направление частично, открыто на масштабе.**

**E19. [Источник ложных #3] Перепутанный вариант → ложное «ниже рынка».** Доказательство: **не тестировалось** — медиан
нет (Ф5), цены trial фейковые. Происхождение: из плана. **Статус: не тестировалось / заблокировано до оплаты.**

**E20. [Развилка Ф0 СТОП/ГО].** Механика ингеста подтв. (данные текут, прогоны зелёные). Экономика — тариф/суточный
лимит/реальность цен — **на вере**. Алексей подтвердил: **ингест всё ещё на пробнике, нужно менять**. Новое: ~58%
вытянутых строк — не наши категории (источник `category_id=101` широкий) → при оплате жжёт лимит. **Статус: не тестировалось
(экономика); открыто.**

**E21. Артефакты в version control.** Симптом был: репо пустой, push давал 403. Корень: GitHub-app `Claude` был
**suspended**. Что делали: Алексей нажал Unsuspend → push заработал; запушены `audit/` + `sql/` (7 функций + категоризатор
v2.2 + golden). Доказательство: пуши прошли (ветка `claude/vigilant-dijkstra-HuerN`). Природа: операционное.
**Статус: закрыто-подтверждено ЧАСТИЧНО** — в git НЕ попали **GPU-инлайн** и **единый нормализатор** (канон только в
Supabase-сниппетах); работа на feature-ветке, не в `main`.

**NEW-1. «Много мусора в категориях» (подозрение заказчика).** Симптом: Алексей считает, что в категориях остаётся
неверно отнесённое (сверх виденных протечек E10). Корень: не установлен (категоризатор по ключевым словам груб; v2.2 закрыл
известное, но не исчерпывающе). Что делали: целенаправленного аудита чистоты категорий НЕ было. Доказательство: не
проверялось. Происхождение: признано Алексеем в этом чате. **Статус: открыто (нужен целевой аудит: выборка по каждой
категории глазами).**

**NEW-2. Словарь не исчерпывающий (требование заказчика).** Симптом: и condition, и категоризатор основаны на списках слов;
новые формулировки проскакивают. Что делали: расширил condition (перестал/слом/надо шить) и категоризатор (v2.2) — но НЕ до
исчерпания. Доказательство: на наборе/превью, не на исчерпывающем корпусе. Природа: **заплатка/словарь** (по сути).
Происхождение: признано (Алексей: «расширить до абсолютного максимума»; фрагильность фиксов «отпустил под мой контроль»).
**Статус: открыто (расширить до максимума + усилить категоризатор).**

**NEW-3. position_key после разгреба, вероятно, дырявый.** Симптом: в разовом разгребе прогонял только категорию+condition,
**ключи НЕ перепрогонял** → у ~1000 новых строк `position_key` вероятно NULL. Корень: операционное (намеренно отложил, т.к.
ключи нужны только для медиан Ф5, а E7/E8/E9/E12 открыты). Доказательство: **не замерял — реконструкция.** Происхождение:
признано в этом чате. **Статус: открыто / точное покрытие не установлено (нужен замер).**

**NEW-4. Несколько сниппетов `lot_condition` в Supabase = риск отката.** Симптом: запуск старого сниппета молча вернул бы
багованную функцию (уже случалось — стояла старая версия). Что делали: Алексей удалил **только конкретно названные мной**
старые condition-сниппеты. Доказательство: со слов Алексея. Природа: операционное. Происхождение: признано. **Статус:
снижено; остаточный риск — прочие сниппеты-функции остаются; канон в git.**

**NEW-5. `condition_golden_eval` — security-definer view, публично доступна через API** (Supabase-линт). Данные синтетика
→ безвредно. **Статус: открыто-косметика** (прибрать/ограничить, когда условие добьётся).

---

## §3. ТЕКУЩИЕ АРТЕФАКТЫ (дословно)

> Статусы источника: **git-канон** = дословно из ветки `claude/vigilant-dijkstra-HuerN`, развёрнуто и проверено;
> **восстановлено-из-унасл-брифа** = копия из прошлой передачи, в git НЕТ, канон в Supabase/n8n — **СВЕРИТЬ из источника**.

### 3.1 Схема Postgres — восстановлено-из-унасл-брифа (канон: Supabase Table Editor). + добавлена `condition_golden` (§3.14).

```sql
create table if not exists lots (
  id bigint primary key,
  avito_id text, url text, title text not null,
  price bigint,
  posted_at timestamptz,
  region text, city text, district text, region_id text, city_id text,
  avito_category_id int, avito_subcat_id int, query_category_id int,
  seller_name text, seller_type text,
  description text, images text, lat double precision, lng double precision,
  cond_raw text, brand text, model text,
  item_category text, position_key text, condition text, is_component boolean,
  raw jsonb not null, fetched_at timestamptz not null default now()
);
create index if not exists lots_posted_at_idx on lots (posted_at);
create index if not exists lots_position_idx  on lots (position_key);
create index if not exists lots_cat_posted_idx on lots (item_category, posted_at);
create index if not exists lots_fetched_idx   on lots (fetched_at);

create table if not exists price_history (
  id bigserial primary key, lot_id bigint,
  position_key text not null, item_category text,
  price bigint not null, condition text not null default 'unknown',
  observed_at timestamptz not null, region text,
  created_at timestamptz not null default now());
create index if not exists ph_position_idx on price_history (position_key, observed_at);
create index if not exists ph_cat_idx      on price_history (item_category, observed_at);

create table if not exists medians (
  position_key text primary key, item_category text,
  median_price bigint not null, sample_size int not null,
  basis text not null, window_days int not null default 30,
  computed_at timestamptz not null default now());

create table if not exists seen_ids (
  lot_id bigint primary key, first_seen timestamptz not null default now());
create index if not exists seen_first_idx on seen_ids (first_seen);

create table if not exists sent_log (
  id bigserial primary key, client_id text not null, lot_id bigint not null,
  score numeric(4,1), sent_at timestamptz not null default now(),
  unique (client_id, lot_id));
create index if not exists sent_client_idx on sent_log (client_id, sent_at);

create table if not exists client_configs (
  client_id text primary key, display_name text, chat_id text not null,
  categories text[] default '{}'::text[],
  discount_pct jsonb not null default '{}'::jsonb,
  include_keywords text[] default '{}'::text[], stop_words text[] default '{}'::text[],
  regions text[] default '{}'::text[], cities text[] default '{}'::text[],
  freshness_min int default 2, min_score numeric(4,1) default 0,
  active boolean not null default true, synced_at timestamptz,
  updated_at timestamptz not null default now());
```

### 3.2 n8n Code-нода ингеста — восстановлено-из-унасл-брифа (канон: n8n export). Не менялась.

```javascript
// Режим: Run Once for All Items. Объявление Avito -> строка lots. Тянем Производитель/Модель/Состояние из params[].
const QUERY_CATEGORY_ID = 101;
function param(params, names){ if(!Array.isArray(params)) return null;
  for(const p of params){ if(names.includes((p.name||'').trim())){ const v=(p.value??'').toString().trim(); return v||null; } } return null; }
function mskToIso(t){ if(!t) return null; return t.trim().replace(' ','T')+'+03:00'; }
return $input.all().map(({ json: a }) => ({ json: {
  id: Number(a.Id), avito_id: a.avito_id||null, url: a.url||null, title: a.title||null,
  price: (a.price===''||a.price==null)?null:Number(a.price),
  posted_at: mskToIso(a.time),
  region: a.region||null, city: a.city||null, district: a.district||null,
  region_id: a.region_Id||null, city_id: a.city_Id||null,
  avito_category_id: a.category_Id!=null?Number(a.category_Id):null,
  avito_subcat_id: a.subcategory_Id!=null?Number(a.subcategory_Id):null,
  query_category_id: QUERY_CATEGORY_ID,
  seller_name: a.name||null, seller_type: a.postfix||null,
  description: a.description||null, images: a.images||null,
  lat: a.coords?a.coords.lat:null, lng: a.coords?a.coords.lng:null,
  cond_raw: param(a.params,['Состояние']),
  brand: param(a.params,['Производитель','Бренд']),
  model: param(a.params,['Модель']),
  raw: JSON.stringify(a),
}}));
```

### 3.3 n8n ингест — цепочка/подключение — восстановлено-из-унасл-брифа.

```
Цепочка: [Manual Trigger] + [Schedule Trigger 2 мин] → [HTTP Request GET] → [Split Out: data] → [Code (JS, §3.2)] → [Postgres Insert, Skip on Conflict = ON]
HTTP URL: https://rest-app.net/api/ads?login=${RESTAPP_LOGIN}&token=${RESTAPP_TOKEN}&category_id=101&last_m=30   (реальные login/token — в исходном брифе и в credential n8n)
Postgres credential: Session pooler aws-1-eu-central-1.pooler.supabase.com:5432, db=postgres, user=postgres.yvexucophefvlorgpacj, SSL «Ignore SSL Issues»=ON
Запуск: локально localhost:5678, Published, автостарт при включении ПК (НЕ 24/7). rest-app — TRIAL, цены случайные.
```

### 3.4 Категоризатор `item_category` v2.2 — **git-канон** (`sql/categorizer.sql`). Развёрнуто-и-прогнано. Отменяет v2.1 из унасл.-брифа.

```sql
-- Категоризатор item_category — v2.2 (фикс E10: протечки аксессуаров).
-- База = канон v2.1 (сверено: 639/0 против развёрнутого). Изменения относительно v2.1:
--   + ветка 0: периферия (мышь/клава/гарнитура/…) → other (фикс «мышь HyperX»→ram).
--   + mobo: исключение кулеров (фикс «Jonsbo кулер … lga1700»→mobo). «радиатор» НЕ исключаем (легит у плат).
--   + ssd:  исключение внешних корпусов/боксов (фикс «внешний корпус SSD»→ssd).
--   + psu:  исключение адаптеров «для монитора/ноутбука» (фикс «блок питания для монитора»→psu).
-- Проверять превью-диффом перед деплоем. Применяется ко всем строкам (без WHERE).
update lots set item_category =
  case
    when coalesce(title,'') ~* '(\yмыш|клавиатур|гарнитур|наушник|джойстик|геймпад|веб[- ]?камер|вебкамер)' then 'other'
    when coalesce(title,'') ~* '^(радиатор|крепление|кулер|подставка|кабель|переходник|сумка|коврик|корпус)' then 'other'
    when coalesce(title,'') ~* '(ноутбук|\yноут\y|в сборе|системн\w* блок|компьютер в сборе|моноблок)' then 'assembly'
    when coalesce(title,'') ~* '(видеокарт|geforce|\yrtx\y|\ygtx\y|radeon|\yrx ?\d{3,4}|\ygt ?\d{3,4}|quadro)' then 'gpu'
    when coalesce(title,'') ~* '(процессор|\ycpu\y|ryzen|core ?i[3579]|core ?2|core ?ultra|\yi[3579][ -]?\d{3,5}|xeon|pentium|celeron|\yathlon\y)'
         and coalesce(title,'') !~* '(кулер|охлажд|вентилятор|радиатор|термопаст|для процессора|материнск|motherboard)' then 'cpu'
    when coalesce(title,'') ~* '(материнск|материнк|motherboard|\yмать\y|\yam[345]\y|\ylga ?\d{3,4}|сокет|socket|чипсет|\y[bz][3-7][0-9]0|\yx[3-7]70|\yh[3-6]10)'
         and coalesce(title,'') !~* '(кулер|башня|jonsbo|водоблок|\yсжо\y)' then 'mobo'
    when coalesce(title,'') ~* '(оперативн|модул\w* памяти|\yозу\y|\yram\y|valueram|\yddr ?[2345]|\ydimm\y|sodimm|so-dimm|hyperx|мгц|mhz)' then 'ram'
    when coalesce(title,'') ~* '(\yssd\y|nvme|\ym\.?2\y|твердотел|xpg|\yevo\y|\yqvo\y)'
         and coalesce(title,'') !~* '(внешний корпус|корпус для|\yбокс\y|карман|док[- ]?станц|enclosure|кейс для)' then 'ssd'
    when coalesce(title,'') ~* '(блок ?пит|\yбп\y|\ypsu\y|power supply|80 ?plus|\d{3,4} ?(вт|ватт))'
         and coalesce(title,'') !~* '(для монитор|для ноутбук|для роутер|для камер|для светодиод|\yадаптер|зарядн)' then 'psu'
    when coalesce(model,'') ~* '(core ?2|core ?i[3579]|ryzen|xeon|pentium|celeron|athlon)' then 'cpu'
    else 'other'
  end;
```

### 3.5 GPU-инлайн `position_key` — восстановлено-из-унасл-брифа. **НЕ в git; в этом чате против канона НЕ сверялся.** Канон: Supabase-сниппет «GPU position_key extractor». Содержит баг E9 (`super` без якоря). **Приёмник: бери из источника, сверь.**

```sql
with src as (
  select id, translate(lower(coalesce(nullif(model,''),title)),'хс','xc') as s,
              translate(lower(coalesce(title,'')),'хс','xc') as st
  from lots where item_category='gpu'),
ex as (select *, regexp_match(s,'\y(rtx|gtx)\s*([0-9]{3,4})') as rg,
                 regexp_match(s,'\yp([0-9]{3})[\s-]+([0-9]{2,3})') as pg from src),
parts as (
  select id,
    coalesce(
      case when s ~ 'rtx\s*a\s*[0-9]{3,4}' then 'rtxa'||substring(s from 'rtx\s*a\s*([0-9]{3,4})') end,
      case when rg is not null then rg[1]||rg[2] end,
      case when s ~ '\ygt\s*[0-9]{3,4}' then 'gt'||substring(s from '\ygt\s*([0-9]{3,4})') end,
      case when s ~ 'vega\s*[0-9]{2}' then 'vega'||substring(s from 'vega\s*([0-9]{2})') end,
      case when s ~ 'hd\s*[0-9]{4}' then 'hd'||substring(s from 'hd\s*([0-9]{4})') end,
      case when s ~ '\y(rx|radeon)' then 'rx'||substring(s from '\y(?:rx|radeon)(?:\s*rx)?\s*([0-9]{3,4})') end,
      case when pg is not null then 'p'||pg[1]||pg[2] end) as base,
    case when s ~ 'xtx' then 'xtx' when s ~ '[0-9]xt\y' or s ~ '\yxt\y' then 'xt'
         when s ~ '[0-9]ti\y' or s ~ '\yti\y' then 'ti' when s ~ 'super' then 'super' else '' end as suf,
    coalesce(substring(s from '([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)'),
             substring(st from '([0-9]{1,2})\s*(?:gb|гб|g\y|г\y)')) as mem
  from ex)
update lots l set position_key = parts.base||parts.suf||coalesce('_'||parts.mem||'g','')
from parts where l.id=parts.id and parts.base is not null;
```

### 3.6 `pk_cpu` — **git-канон** (`sql/pk_cpu.sql`). Развёрнуто.

```sql
create or replace function public.pk_cpu(raw text)
 returns text language plpgsql immutable
as $$
declare s text; m text[];
begin
  if raw is null then return null; end if;
  s := translate(lower(raw), 'хс', 'xc');
  m := regexp_match(s,'ryzen\s*([3579])\s*([0-9]{3,4})\s*(x3d|xt|ge|gt|x|g|f)?');
    if m is not null then return 'ryzen'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'core\s*ultra\s*([3579])\s*([0-9]{3})\s*(kf|ks|k|f|hx|h)?');
    if m is not null then return 'ultra'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'core\s*2\s*(duo|quad)\s*([a-z]?[0-9]{4})');
    if m is not null then return 'core2'||m[1]||'-'||m[2]; end if;
  m := regexp_match(s,'\yi([3579])[\s-]*([0-9]{3,5})\s*(kf|ks|k|f|qm|t|x)?');
    if m is not null then return 'i'||m[1]||'-'||m[2]||coalesce(m[3],''); end if;
  m := regexp_match(s,'xeon\s*(e[357])?[\s-]*([0-9]{4})\s*v?\s*([0-9])?');
    if m is not null then return 'xeon-'||coalesce(m[1]||'-','')||m[2]||case when m[3] is not null then 'v'||m[3] else '' end; end if;
  m := regexp_match(s,'pentium\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'pentium-'||m[1]; end if;
  m := regexp_match(s,'celeron\s*([a-z]?[0-9]{3,4})'); if m is not null then return 'celeron-'||m[1]; end if;
  m := regexp_match(s,'athlon\s*([a-z0-9]+)');         if m is not null then return 'athlon-'||m[1]; end if;
  m := regexp_match(s,'\yfx[\s-]*([0-9]{4})');         if m is not null then return 'fx-'||m[1]; end if;
  return null;
end $$;
```

### 3.7 `pk_ram` — **git-канон** (`sql/pk_ram.sql`). Развёрнуто. **Содержит E7 (кит) и E8 (объёмы).**

```sql
create or replace function public.pk_ram(raw text)
 returns text language plpgsql immutable
as $$
declare s text; gen text; cap int; spd text; so text; m text[]; parts text[]:='{}';
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  if    s ~ 'ddr ?5'  then gen:='ddr5';
  elsif s ~ 'ddr ?4'  then gen:='ddr4';
  elsif s ~ 'ddr ?3l' then gen:='ddr3l';
  elsif s ~ 'ddr ?3'  then gen:='ddr3';
  elsif s ~ 'ddr ?2'  then gen:='ddr2'; end if;
  cap := coalesce( (regexp_match(s,'(\d+)\s*(?:gb|гб)'))[1],
                   (regexp_match(s,'(\d+)\s*g\y'))[1] )::int;
  if cap is null then m:=regexp_match(s,'(\d+)\s*x\s*(\d+)'); if m is not null then cap:=m[1]::int*m[2]::int; end if; end if;
  if cap is null then m:=regexp_match(s,'(\d+)\s*mb');        if m is not null then cap:=round(m[1]::numeric/1024)::int; end if; end if;
  if cap is not null and cap not in (1,2,4,8,16,32,64,128,256) then cap:=null; end if;
  spd := coalesce( (regexp_match(s,'(\d{3,4})\s*mhz'))[1],
                   (regexp_match(s,'\y(1066|1333|1600|1866|2133|2400|2666|2800|2933|3000|3200|3333|3466|3600|3733|4000|4266|4800|5200|5600|6000|6400)\y'))[1] );
  if s ~ 'so[\s-]?dimm' then so:='so'; end if;
  if cap is null and gen is null then return null; end if;
  if gen is not null then parts:=parts||gen; end if;
  if cap is not null then parts:=parts||(cap||'gb'); end if;
  if spd is not null then parts:=parts||spd; end if;
  if so  is not null then parts:=parts||so;  end if;
  return array_to_string(parts,'-');
end $$;
```

### 3.8 `pk_mobo` — **git-канон** (`sql/pk_mobo.sql`). Развёрнуто. Ключ = чипсет/сокет (грубо — намеренно, §4).

```sql
create or replace function public.pk_mobo(model text, title text)
 returns text language plpgsql immutable
as $$
declare s text; m text[];
begin
  s := translate(lower(coalesce(model,'')||' '||coalesce(title,'')),'хс','xc');
  m := regexp_match(s,'(a320|a520|a620|b350|b450|b550|b650|b840|b850|x370|x470|x570|x670|x870|x299|h110|b150|h170|z170|b250|h270|z270|h310|b360|h370|z370|b365|z390|h410|b460|h470|z490|h510|b560|h570|z590|h610|b660|h670|z690|b760|h770|z790|b860|z890|x79|x99|g31|g41|p43|p45|h55|h57|h61|b75|h77|z77|h81|b85|h87|z87|h97|z97)');
  if m is not null then return m[1]; end if;
  m := regexp_match(s,'lga ?(1700|1200|1156|1155|1151|1150|775)');
  if m is not null then return 'lga'||m[1]; end if;
  if s ~ '\yam4\y' then return 'am4'; end if;
  if s ~ '\yam5\y' then return 'am5'; end if;
  if s ~ '\yam3\y' then return 'am3'; end if;
  if s ~ '\y775\y' then return 'lga775'; end if;
  if s ~ '\yfm2\y' then return 'fm2'; end if;
  return null;
end $$;
```

### 3.9 `pk_ssd` — **git-канон** (`sql/pk_ssd.sql`). Развёрнуто. **Содержит E12 (нет валидации объёма).**

```sql
create or replace function public.pk_ssd(raw text, brand text)
 returns text language plpgsql immutable
as $$
declare s text; br text; cap text; iface text; m text[]; parts text[]:='{}';
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  br := nullif(brand,'');
  if br is null then
    m := regexp_match(s,'\y(samsung|kingston|adata|crucial|western digital|wd|patriot|netac|silicon power|kingspec|smartbuy|goldenfir|compit|phison|intel|corsair|team|apacer|transcend|seagate|hikvision|digma)\y');
    if m is not null then br := m[1]; end if;
  end if;
  if br is not null then
    br := regexp_replace(lower(br),'[^a-z0-9]','','g');
    if br='westerndigital' then br:='wd'; elsif br='patriotmemory' then br:='patriot'; elsif br='siliconpower' then br:='sp'; end if;
  end if;
  m := regexp_match(s,'(\d+)\s*(?:tb|тб)'); if m is not null then cap:=m[1]||'tb';
  else m := regexp_match(s,'(\d+)\s*(?:gb|гб)'); if m is not null then cap:=m[1]||'gb'; end if; end if;
  if s ~ 'nvme|m\.?2' then iface:='nvme'; elsif s ~ 'sata|2\.5' then iface:='sata'; end if;
  if cap is null then return null; end if;
  if br is not null then parts:=parts||br; end if;
  parts := parts||cap;
  if iface is not null then parts:=parts||iface; end if;
  return array_to_string(parts,'-');
end $$;
```

### 3.10 `pk_psu` — **git-канон** (`sql/pk_psu.sql`). Развёрнуто. Ключ = мощность (грубо — намеренно, §4).

```sql
create or replace function public.pk_psu(raw text)
 returns text language plpgsql immutable
as $$
declare s text; w int; m text[];
begin
  if raw is null then return null; end if;
  s := translate(lower(raw),'хс','xc');
  m := regexp_match(s,'(\d{3,4})\s*(?:вт|ватт|w)');                 -- явная мощность
  if m is null then m := regexp_match(s,'(?:^|[^0-9x])(\d{3,4})(?![0-9x])'); end if;  -- бар-число, не часть AxB
  if m is null then return null; end if;
  w := m[1]::int;
  if w < 200 or w > 1600 or w % 50 <> 0 then return null; end if;
  return w||'w';
end $$;
```

### 3.11 `lot_condition` — **git-канон** (`sql/lot_condition.sql`). Развёрнуто-и-прогнано (экзамен 18/0/0). **Отменяет §3.12 унасл.-брифа.**

```sql
create or replace function lot_condition(title text, descr text) returns text
language plpgsql immutable as $$
declare n text; pos_src text;
begin
  n := translate(lower(coalesce(title,'')||' . '||coalesce(descr,'')), 'aeopcxykmthb','аеорсхукмтнв');

  -- 1) ЖЁСТКО мёртвое (позитив не спасает)
  if n ~ 'на запчаст|на з/ч|неисправ|не запуск|не стартует|не выводит изображ|отвал|под восстановл|для разбирающ|нет изображени|артефач|сгорел|дохл|не видит|\yдонор\y'
     or n ~ 'перестал\w*\s+включа|не подаёт призн|не подает призн'
     then return 'dead'; end if;

  -- 2) КАНОН: «не работает/не включается», но не про мелкую часть
  if n ~ '(не работает|не включа\w*)(?![^.!?]{0,18}(вентил|кулер|подсветк|argb|rgb|разъ|\yпорт|кнопк|лопаст|колодк))' then return 'dead'; end if;

  -- 3) КАНОН: «нерабоч» рядом с предметом
  if n ~ '(не ?рабоч|нерабоч)\w*\s*(видеокарт|карт|плат|памят|проц|накопит|ssd|диск|сост)|(видеокарт|карт|плат|памят|проц)\w*\s+(не ?рабоч|нерабоч)|в не ?рабочем|полностью не ?рабоч' then return 'dead'; end if;

  -- 4) КАНОН: явное «не знаю»
  if n ~ 'не тестир|не провер|не могу провер|не знаю' then return 'unknown'; end if;

  -- 4b) НОВОЕ: требует прошивки → не готов к работе → unknown
  if n ~ 'надо шить|нужно шить|требует прошивк|нужна прошивк|под прошивк|на прошивк|на перепрошивк' then return 'unknown'; end if;

  -- 5) МЯГКО мёртвое: dead, ЕСЛИ после вырезания «не …»/«перестал …»-форм не уцелел сильный позитив
  if n ~ 'не ?исправ\w*|не ?работа\w*|не ?рабоч\w*|нерабоч\w*|перестал\w*\s+(работа|запуска|стартова|функц)\w*|сломан|сломал|\yслом\y' then
    pos_src := regexp_replace(n, 'не ?исправ\w*|не ?работа\w*|не ?рабоч\w*|нерабоч\w*|перестал\w*\s+(работа|запуска|стартова|функц)\w*', ' ', 'g');
    if pos_src !~ 'полностью рабоч|полностью исправ|100\s*%?\s*рабоч|на гаранти|гаранти[яйюе]|чеки|пломб|проверен|провер[ке]|идеальн\w* состоян|отличн\w* состоян|хорош\w* состоян|отлично работает|\yисправ|\yрабоч|\yработа' then
      return 'dead';
    end if;
  end if;

  -- 6) КАНОН: позитив
  if n ~ 'полностью рабоч|полностью исправ|100\s*%?\s*рабоч|на гаранти|гаранти[яйюе]|чеки|пломб|проверен|провер[ке]|идеальн\w* состоян|отличн\w* состоян|хорош\w* состоян|отлично работает|исправ|рабоч|работа' then return 'working'; end if;

  return 'unknown';
end $$;
```

### 3.12 `lot_is_component` — **git-канон** (`sql/lot_is_component.sql`). Развёрнуто. Детектор сборок по ЗАГОЛОВКУ (§4).

```sql
create or replace function public.lot_is_component(title text)
 returns boolean language plpgsql immutable
as $$
declare t text := lower(coalesce(title,''));
begin
  if t ~ 'комплект|в сборе|\y(сборка|лот|риг|ферма)\y|с процессором|с проц |с памятью|с видеокарт|\+\s*(\d+\s*(gb|г|g)|ddr|i[3-9]|ryzen|cpu|проц|[abhxz]\d{2,3}m?)'
     then return false; end if;
  return true;
end $$;
```

### 3.13 Применение Фазы 4 (condition + is_component) + ключи (pk_*). Развёрнуто-и-прогнано (condition прогнан на все 1732). GPU-ключи и pk_* в РАЗГРЕБЕ НЕ перепрогонялись (см. NEW-3).

```sql
-- condition + is_component (прогнано на все компоненты при разгребе backlog)
update lots set condition = lot_condition(title, description), is_component = lot_is_component(title)
where item_category in ('gpu','cpu','ram','mobo','ssd','psu');

-- ключи pk_* (восстановлено-из-унасл-брифа §3.11; в разгребе НЕ запускались — position_key у новых строк вероятно NULL)
update lots set position_key = coalesce(pk_cpu(model),pk_cpu(title)) where item_category='cpu'  and coalesce(pk_cpu(model),pk_cpu(title))  is not null;
update lots set position_key = coalesce(pk_ram(model),pk_ram(title)) where item_category='ram'  and coalesce(pk_ram(model),pk_ram(title))  is not null;
update lots set position_key = pk_mobo(model,title)                  where item_category='mobo' and pk_mobo(model,title)                   is not null;
update lots set position_key = pk_ssd(title,brand)                   where item_category='ssd'  and pk_ssd(title,brand)                    is not null;
update lots set position_key = coalesce(pk_psu(model),pk_psu(title)) where item_category='psu'  and coalesce(pk_psu(model),pk_psu(title))  is not null;
-- (GPU-ключ — инлайн §3.5; reset «update lots set position_key=null;» перед полным прогоном)
```

### 3.14 Золотой/регресс-набор condition + harness — **git-канон** (`audit/condition/golden_set.sql`). Это «экзамен» (18 кейсов). Прогон Алексеем: 18/0/0.

```sql
-- =============================================================================
-- Avito parser — condition classifier: golden / regression set + harness
-- Audit artifact (E14, E18). Run in Supabase SQL Editor where lot_condition() is deployed.
-- IMPORTANT: `expected` = GROUND TRUTH, NOT a prediction of the current function.
-- =============================================================================
create table if not exists condition_golden (
  id        bigserial primary key,
  title     text,
  descr     text,
  expected  text    not null check (expected in ('working','dead','unknown')),
  danger    boolean not null default false,   -- truth is dead but text tempts -> working (E1/E18)
  err       text,
  source    text    not null default 'regression', -- 'regression' | 'real'
  note      text
);
delete from condition_golden where source = 'regression';
insert into condition_golden (title, descr, expected, danger, err, note) values
('Видеокарта RTX 3060',          'На запчасти, не включается, нет изображения',                 'dead',    true,  'baseline', 'явное мёртвое'),
('Видеокарта RTX 3060',          'Неисправна, ремонт не делал',                                 'dead',    true,  'baseline', 'неисправ БЕЗ пробела — контроль к E2'),
('Видеокарта RTX 3070',          'Полностью рабочая, на гарантии, чек сохранён',                'working', false, 'baseline', 'явное рабочее'),
('Видеокарта RTX 3070',          'Не тестировал, нет возможности проверить',                    'unknown', false, 'baseline', 'явное неясно'),
('Видеокарта RTX 3070',          'После майнинга, полностью рабочая',                           'working', false, 'baseline', 'майнинг = износ-штраф в БАЛЛЕ, метка рабочее'),
('Видеокарта GTX 1660',          'Карта не исправна, требует ремонта',                          'dead',    true,  'E2', 'пробельная форма проскакивает в working'),
('Материнская плата B450',       'Перестала включаться, не работала уже месяц',                 'dead',    true,  'E3', 'dead-regex ловит только «не работает» (наст.)'),
('Видеокарта RX 580',            'Не работала после последнего запуска',                        'dead',    true,  'E3', 'прош. время -> «работа» ловит working'),
('Видеокарта RTX 2060',          'Состояние: нерабочее',                                        'dead',    true,  'E4', 'нет соседнего существительного и не «в нерабочем»'),
('Оперативная память DDR4 16gb', 'Продаю нерабочую',                                            'dead',    true,  'E4', 'регресс от фикса ценового хеджа E6'),
('Видеокарта RTX 3080',          'Не работает, вентилятор просто крутится',                     'dead',    true,  'E5', 'гард «вентил» в окне 18 симв. гасит реальное мёртвое'),
('Видеокарта RTX 3070',          'Дефектов нет, артефакты отсутствуют, полностью рабочая',      'working', false, 'E6', 'артефакт+отсутствуют НЕ должно быть dead'),
('Видеокарта RTX 3070',          'Отдаю по цене нерабочей, но карта полностью рабочая',         'working', false, 'E6', 'ценовой хедж НЕ должен быть dead'),
('Видеокарта RTX 3070',          'Карта рабочая, не работает 1 вентилятор из двух',             'working', false, 'E6', 'легитимный кейс гарда — прямой контраст к E5'),
('Блок питания 700w deepcool слом','На пломбе, отработал около года, перестал включаться, защита не разрешает запуск', 'dead', true, 'WRK', 'мёртвый БП утекал в working через «пломб»/«отработал»'),
('Видеокарта',                   'Перестала работать, ничего не помогло',                        'dead',    true,  'WRK', 'целиком мёртвая, без позитива'),
('Видеокарта',                   'Карта рабочая, вентиляторы перестали работать, исправил',      'working', false, 'WRK', 'подузел перестал — но «рабочая» уцелевает'),
('Видеокарта RX 570',            'Хдми работают, карты надо шить, продажа от 10 шт',             'unknown', false, 'WRK', 'майнинг-перепрошивка → не turnkey → unknown');

create or replace view condition_golden_eval as
select g.*, lot_condition(g.title, g.descr) as predicted from condition_golden g;

-- ВЕРДИКТ (норма: оба 0):
select count(*) filter (where expected='dead' and predicted='working') as dead_to_working_MUST_BE_0,
       count(*) filter (where predicted is distinct from expected)     as mismatches
from condition_golden_eval;
```

> Прочие аудит-артефакты в git (не критичны, для справки): `audit/condition/labeling_guide.md` (правила разметки истины),
> `audit/condition/missed_dead_probe.sql` (ловушка пропущенного-мёртвого в working/unknown),
> `audit/condition/lot_condition.canon.sql` (старый до-фиксовый канон для диффа), `audit/README.md` (журнал-ledger).

---

## §4. Журнал НАМЕРЕННЫХ решений и отклонений (НЕ баги — не «чинить»)

1. **Нормализатор реализован как SQL-функции/UPDATE в Supabase**, а не нода n8n. Причина: парсинг чище и проверяемее в SQL.
2. **Грубые ключи позиции:** `mobo`=чипсет/сокет, `psu`=мощность, `ssd`=бренд+объём+интерфейс. Причина: размер выборки для
   медианы (точнее = реже набирается бакет). Осознанное огрубление.
3. **`gpu`/`ram` включают объём памяти в ключ** (`rtx3070_8g`, `ddr4-16gb`). Причина: реально разные SKU/цены.
4. **model-first, заголовок-фолбэк** (gpu/cpu). У ram/ssd `model` почти всегда пуст → парсим заголовок (+brand для ssd).
5. **Де-гомоглиф (латиница→кириллица) в `lot_condition`** (`translate(... 'aeopcxykmthb','аеорсхукмтнв')`). Причина:
   продавцы маскируют слова (`Heиспpaвные`).
6. **Детектор сборок (`is_component`) — по ЗАГОЛОВКУ, не описанию.** Причина: в описаниях «полный комплект» → ложные combo.
7. **condition: dead-first, консервативно.** Явные сигналы → dead/working; остальное → unknown (проходит гейт со штрафом).
8. **`cond_raw` (Новое/Б-у) НЕ используется для раб/нераб** — это новизна, не функциональность.
9. **`subcat_id` НЕ используется для категории** — в данных константа; категория по заголовку.
10. **Реархитектура негации в condition (ШАГ 5, новое в этом чате):** вместо точечных заплаток — общий приём «вырезать
    «не …»-форму, и если уцелел сильный позитив → не dead». Причина: точечные заплатки давали регрессы (E4 был регрессом от
    фикса E6). Override на «пломб/отработал» НЕ срабатывает для жёстких сигналов (ШАГ 1: «перестал включа») — намеренно.
11. **Категоризатор v2.2: исключения по веткам + ветка-0 периферия (новое в этом чате).** Причина: фикс протечек E10.
    «радиатор» намеренно НЕ исключён из `mobo` (легит у плат с радиатором M.2/VRM).
12. **Добавлены аудит-объекты:** таблица `condition_golden` + view `condition_golden_eval` (экзамен). Это обвязка аудита,
    не продуктовая логика.
13. **Унаследованные (в силе):** дедуп через PK `lots` + ON CONFLICT (`seen_ids` создана, не используется); «дельта» =
    окно `last_m=30` (не курсор); batch-сид отложен; токен в URL ноды.

---

## §5. Реальное состояние сейчас (из ответов Алексея и наших прогонов)

- **Supabase** (проект `yvexucophefvlorgpacj`, eu-central-1): `lots` = **1732** строки (растёт, ингест капает). Таблицы:
  `client_configs, lots, medians, price_history, seen_ids, sent_log` + добавленная `condition_golden`.
  `medians/price_history/sent_log` — пустые. Функции развёрнуты: `lot_condition` (исправленная), `lot_is_component`,
  `pk_cpu/ram/mobo/ssd/psu`. Распределение (снимок): категории — components 676 (gpu 204, ram 169, cpu 99, mobo 82, ssd 64,
  psu 58), other 1007, assembly 54; condition по компонентам — **working 410 / unknown 240 / dead 26**;
  `без_категории`=0, `компоненты_без_метки`=0. **position_key — НЕ перепрогонян после разгреба (вероятно дыры).**
- **n8n:** один воркфлоу «My workflow» (ингест), Published, локально (localhost:5678), НЕ 24/7. Executions зелёные,
  каждые 2 мин, ~46 объяв/прогон. Нормализатор/condition — ручной SQL, не в n8n, **без расписания.**
- **rest-app:** TRIAL, цены случайные. **Ингест всё ещё на пробнике — Алексей подтвердил, нужно переключить на оплаченный**
  (ключ у него есть). Суточный лимит не измерен. ~58% вытянутых строк — не наши категории (источник `category_id=101` широк).
- **Google Sheets / Telegram-бот / chat_id:** нет.
- **Ручных правок БД/данных вне переписки:** нет (Алексей подтвердил).
- **Git:** ветка `claude/vigilant-dijkstra-HuerN` репо `resutomaru/-`, последний коммит ~`cf84d57` + коммит этого брифа.
  В git: `sql/` (7 функций + `categorizer.sql` v2.2) и `audit/` (golden_set, labeling_guide, missed_dead_probe, README,
  lot_condition.canon). **НЕ в git:** GPU-инлайн, единый нормализатор (канон — Supabase-сниппеты). Работа НЕ в `main`.
- **Старые сниппеты condition:** Алексей удалил только конкретно названные мной; прочие сниппеты-функции остаются.

---

## §6. Открытые пункты / в ожидании (НЕ про возможные дефекты — те в §2)

- **Расширить словари до исчерпывающего максимума + усилить категоризатор** (прямое требование Алексея). Касается и
  condition, и категоризатора. Делать против реального корпуса, не из головы.
- **Расписание нормализатора** (n8n-cron / `pg_cron`) — чтобы свежий ингест обрабатывался сам (иначе копится, E16).
- **Оплата rest-app → переключить ингест с пробника** → измерить суточный лимит, сузить запрос (не тянуть 58% мусора),
  получить реальные цены (разблокирует Ф5).
- **LLM-добивка `unknown`** (гибрид по плану): дешёвый LLM на спорные unknown с содержательным описанием. Нужен API-ключ.
- **Перепрогнать position_key** (после фиксов ключей) на всех строках.
- **Построить золотой/регрессионный набор для ключей и категорий** (для condition есть).
- **24/7 хостинг** (облако/VPS вместо ПК) — для непрерывного сбора и валидной медианы.
- **Токен → secret/credential** (убрать из URL ноды).
- **Закоммитить GPU-инлайн и единый нормализатор в git** (сейчас канон только в Supabase).
- **batch-сид истории цен** — после оплаты.
- **Прибрать `condition_golden_eval`** (security-definer public, косметика).

---

## §7. Следующие шаги (сначала аудит)

1. **АУДИТ (§0):** пройти §2, сверить с §3 и канон-источниками (git `sql/` + Supabase-сниппеты), критически оценить
   реальность каждого фикса. Особое внимание (требование Алексея — закрыть Ф3/Ф4 на 100%):
   - **переисправить ключи позиции:** E7 (RAM кит N×M), E8 (RAM 24/48/96), E9 (GPU `super`), E12 (SSD валидация объёма);
   - **расширить словари до максимума и усилить категоризатор** (NEW-1, NEW-2); целевой аудит чистоты категорий (мусор);
   - **дочесать working на масштабе 410** (E1/E18) — прогнать `missed_dead_probe.sql` на текущем working, разметить выборку;
   - сверить GPU-инлайн с каноном (он не в git) и проверить E9.
2. **Догнать данные:** перепрогнать position_key (GPU-инлайн + pk_*) на всех 1732 (NEW-3); проверить покрытие.
3. **Поставить расписание** нормализатора (E16) — чтобы не копилось.
4. **Переключить rest-app на оплаченный**, сузить запрос, измерить лимит → разблокировать реальные цены.
5. **Фаза 5 (медиана):** каскад (model+brand≥8 → model, working-only, исключая `is_component=false`, отсечка выбросов).
   Значения валидировать только после оплаты.
6. **Фазы 6–8:** гейты+скоринг (приоритеты клиента Вовчика уже собраны: верх — дата/цена/раб-нераб; вниз — рейтинг/описание;
   локация — вторично) с чтением Sheets; Telegram + дедуп; конфиг Sheets + 2-й клиент. Перед живыми клиентами — теневой режим.

---

## §8. Что остаётся в силе из исходного брифа

**Все зафиксированные решения и анти-цели исходного брифа в силе, КРОМЕ изменённого в §4 и сломанного/открытого в §2.**
Приёмник **НЕ должен переоткрывать/переделывать:**

- **Фазы 0–2** (rest-app как источник, схема, ингест-воркфлоу) — развёрнуты, см. §1/§5 (но Ф0-экономика — на вере, E20).
- **Зафиксированное:** источник = rest-app (свой скрейпер НЕ писать); бенчмарк = медиана по СВОИМ данным (без DNS/Я.Маркета);
  тяжёлые данные в Postgres, конфиг в Google Sheets; **один общий сбор** на всех; жёсткие гейты; N% по категориям
  (видео/проц/память/мать = 40%, SSD/БП = 55% «только аномалии»); веса скоринга; набор категорий (видео/проц/память/мать +
  SSD/БП по аномалии; НЕ берём HDD/корпуса/кулеры/периферию/сборки/ноуты); гибридный классификатор раб/нераб (regex →
  дешёвый LLM на спорное).
- **Намеренные решения §4** — не разбирать как баги.

**Три источника ложных результатов держать в фокусе всего аудита:** (E17) бакеты не должны валить варианты в один — на уровне
ключа НЕ валидировано; (E18) классификатор не должен метить мёртвое рабочим — working на масштабе 410 не дочёсан; (E19)
перепутанный вариант → ложное «ниже рынка» — не тестировалось, ждёт медианы и реальных цен.
