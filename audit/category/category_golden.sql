-- =============================================================================
-- Avito parser — item_category classifier: golden / regression set + harness
-- Audit artifact (E14, NEW-1, NEW-2). Закрывает «у категорий нет сети» (§6).
-- Прогон в Supabase SQL Editor, где развёрнута lot_category(title, model).
--
-- Назначение
--   1) REGRESSION (source='regression') — фиксирует ИСПРАВЛЕННЫЕ протечки E10 (аксессуары→
--      компоненты) + позитивы по каждой категории + намеренные решения (combo→assembly,
--      водоблок→other). Любая будущая правка словаря проверяется против них. mismatches ДОЛЖНО = 0.
--   2) GAP (source='gap') — известные ОТКРЫТЫЕ дыры (NEW-1 мусор / NEW-2 неполный словарь).
--      Ожидаемо красные — это БЭКЛОГ на «расширить до максимума», а не тревога.
--   3) REAL (source='real') — твоя ручная разметка реальных лотов (см. запрос-выборку внизу).
--
-- ВАЖНО: expected = ИСТИНА (как ДОЛЖНО), а не предсказание текущей функции.
-- =============================================================================

create table if not exists category_golden (
  id        bigserial primary key,
  title     text,
  model     text,
  expected  text    not null check (expected in ('gpu','cpu','ram','mobo','ssd','psu','assembly','other')),
  danger    boolean not null default false,   -- аксессуар, который соблазняет уйти в компонент (ось E10/NEW-1)
  err       text,                             -- что гардит строка (E10 / v2.3 / NEW-1 / NEW-2 / baseline)
  source    text    not null default 'regression', -- 'regression' | 'gap' | 'real'
  note      text
);

-- Идемпотентный пересев синтетики; ручную разметку (source='real') НЕ трогаем.
delete from category_golden where source in ('regression','gap');

insert into category_golden (title, model, expected, danger, err, source, note) values
-- ---- ПОЗИТИВЫ: каждая категория обязана опознаваться -------------------------
('Видеокарта Nvidia RTX 3070 8GB',                null, 'gpu',      false, 'baseline',   'regression', 'rtx'),
('GeForce GTX 1660 Super 6GB Palit',              null, 'gpu',      false, 'baseline',   'regression', 'gtx/geforce'),
('AMD Radeon RX 580 8GB Sapphire',                null, 'gpu',      false, 'baseline',   'regression', 'radeon / rx 580'),
('Процессор Intel Core i5-12400F',                null, 'cpu',      false, 'baseline',   'regression', 'core i5, не исключён кулером'),
('AMD Ryzen 7 5800X3D',                           null, 'cpu',      false, 'baseline',   'regression', 'ryzen'),
('Материнская плата ASUS Prime B450M-A',          null, 'mobo',     false, 'baseline',   'regression', 'материнск + b450'),
('MSI Z370-A PRO LGA1151',                        null, 'mobo',     false, 'baseline',   'regression', 'чипсет z370 (\y[bz][3-7][0-9]0)'),
('Оперативная память DDR4 16GB 3200',             null, 'ram',      false, 'baseline',   'regression', 'оперативн / ddr4'),
('Kingston HyperX Fury DDR4 16GB',                null, 'ram',      false, 'baseline',   'regression', 'hyperx-память (контраст к мыши HyperX ниже)'),
('SSD Samsung 970 EVO Plus 1TB NVMe',             null, 'ssd',      false, 'baseline',   'regression', 'ssd + nvme'),
('Kingston A400 480GB 2.5 SATA SSD',              null, 'ssd',      false, 'baseline',   'regression', 'ssd + sata'),
('Блок питания Corsair RM650x 650W 80+ Gold',     null, 'psu',      false, 'baseline',   'regression', 'блок пит'),
('БП DeepCool PK500D 500 Вт',                     null, 'psu',      false, 'baseline',   'regression', 'бп + 500 вт'),
('Ноутбук ASUS TUF Gaming F15',                   null, 'assembly', false, 'baseline',   'regression', 'ноутбук'),
('Компьютер в сборе Ryzen 5 5600 / RTX 3060',     null, 'assembly', false, 'baseline',   'regression', 'в сборе — НЕ gpu, хотя есть RTX'),
('Игровой системный блок Core i5 / GTX 1060',     null, 'assembly', false, 'baseline',   'regression', 'системн блок раньше gpu (порядок веток)'),
('Продам срочно, недорого',                       'Intel Core i5-9400F', 'cpu', false, 'baseline', 'regression', 'model-фолбэк: заголовок пуст, model=cpu'),
-- ---- E10 + v2.3: ИСПРАВЛЕННЫЕ протечки аксессуаров (danger) ------------------
('Игровая мышь HyperX Pulsefire Haste',           null, 'other',    true,  'E10',        'regression', 'мышь HyperX утекала в ram'),
('Клавиатура механическая Redragon',              null, 'other',    true,  'E10',        'regression', 'периферия'),
('Кулер Jonsbo CR-1400 LGA1700',                  null, 'other',    true,  'E10',        'regression', 'кулер с LGA утекал в mobo (^кулер + гард mobo)'),
('Внешний корпус для SSD USB 3.0 M.2 NVMe',       null, 'other',    true,  'E10',        'regression', 'бокс утекал в ssd (гард «внешний корпус»)'),
('Блок питания для монитора 19V 4.7A',            null, 'other',    true,  'E10',        'regression', 'адаптер утекал в psu (гард «для монитор»)'),
('Райзер для видеокарты PCIe x16 ver009s',        null, 'other',    true,  'v2.3',       'regression', 'майнинг-райзер (добавлен в периферию v2.3)'),
('Водоблок для процессора EK-Quantum',            null, 'other',    true,  'v2.3',       'regression', 'СЖО-ветка → other, НЕ cpu'),
('СЖО DeepCool LS520 240мм',                      null, 'other',    true,  'v2.3',       'regression', 'жидкостное охлаждение → other'),
('Радиатор для M.2 SSD алюминиевый',              null, 'other',    true,  'E10',        'regression', '^радиатор → other (не ssd)'),
-- ---- Намеренные/граничные (lock) --------------------------------------------
('Видеокарта RTX 3070, на запчасти не включается',null, 'gpu',      false, 'baseline',   'regression', 'мёртвая карта всё равно категория gpu (condition отдельно)'),
('Кулер процессорный DeepCool AK620',             null, 'other',    true,  'E10',        'regression', '^кулер → other, НЕ cpu (есть «процессорный»)'),
-- ---- ЗАКРЫТО v2.4: ^-гард аксессуаров (были gap → теперь регресс-гарды) -------
('Кронштейн для видеокарты вертикальный',         null, 'other',    true,  'NEW-1',      'regression', 'закрыто v2.4: ^кронштейн'),
('Термопрокладки для видеокарты 2мм 12шт',        null, 'other',    true,  'NEW-1',      'regression', 'закрыто v2.4: ^термопроклад'),
('Рамка сокета LGA 1700 для процессора',          null, 'other',    true,  'NEW-1',      'regression', 'закрыто v2.4: ^рамка'),
('Бэкплейт для видеокарты усиленный',             null, 'other',    true,  'NEW-1',      'regression', 'закрыто v2.4: ^б[эе]кплейт'),
-- ---- GAP: открытые дыры (ожидаемо красные; бэклог реальной выборки) -----------
('Накопитель Crucial MX500 500GB',                null, 'ssd',      false, 'NEW-2',      'gap', 'SSD-модель без слова ssd/nvme/evo → other; словарь моделей — из реальной выборки');

-- =============================================================================
-- HARNESS — зовёт РАЗВЁРНУТУЮ lot_category(title, model)
-- =============================================================================
create or replace view category_golden_eval as
select g.*, lot_category(g.title, g.model) as predicted
from category_golden g;

-- 1) матрица ошибок
select expected, predicted, count(*) n
from category_golden_eval group by expected, predicted order by expected, predicted;

-- 2) РЕГРЕСС: несовпадения на зафиксированной истине — ДОЛЖНО быть 0
select count(*) as regression_mismatches_MUST_BE_0
from category_golden_eval where source='regression' and predicted is distinct from expected;

-- 3) ОТКРЫТЫЕ ДЫРЫ (бэклог NEW-1/NEW-2): что сейчас красное из gap-строк
select id, err, expected, predicted, title
from category_golden_eval where source='gap' and predicted is distinct from expected order by err;

-- 4) АКСЕССУАР-ПРОТЕЧКИ: danger-строки, уехавшие в компонент (не other/assembly)
select id, expected, predicted, title
from category_golden_eval
where danger and predicted not in ('other','assembly') order by predicted;

-- =============================================================================
-- ВЫБОРКА для ручной разметки (добавляй строки с source='real').
-- Прогони, глазами проверь item_category, верное запиши как новый insert выше.
-- =============================================================================
-- А) ~20 случайных на категорию — общая чистота:
-- select item_category, left(title,90) title, model
-- from lots where item_category in ('gpu','cpu','ram','mobo','ssd','psu','assembly','other')
-- order by item_category, random() limit 160;
--
-- Б) ЦЕЛЕВОЙ зонд протечек (NEW-1): 'other' с компонент-словами + компоненты с аксессуар-словами:
-- select item_category, left(title,90) title from lots
-- where (item_category='other' and title ~* '(видеокарт|процессор|материнск|\yssd\y|блок ?пит|оперативн)')
--    or (item_category in ('gpu','cpu','mobo','ssd','psu','ram')
--        and title ~* '(кронштейн|держатель|подставк|термопрокладк|термопаст|наклейк|бэкплейт|рамка|переходник|кабел|сумк|чехол|кронш)')
-- order by item_category limit 120;
