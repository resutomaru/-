-- =============================================================================
-- Avito parser — position_key (pk_*) golden / regression set + harness
-- Audit artifact (E14, E7, E8, E12, NEW-2). Закрывает «у ключей нет сети» (§6)
--   для cpu/ram/mobo/ssd/psu. GPU покрыт отдельно — audit/keys/pk_gpu.golden.sql.
-- Прогон в Supabase SQL Editor, где развёрнуты pk_cpu/ram/mobo/ssd/psu/gpu.
--
-- Harness ДИСПАТЧИТ по category РОВНО как прод (normalize_new_lots):
--   cpu/ram/psu: coalesce(pk(model), pk(title));  mobo: pk(model,title);  ssd: pk(title,brand).
--
-- Метки source: 'regression' (зафиксированная истина — mismatch ДОЛЖНО быть 0),
--               'gap' (известная дыра — ожидаемо красная, бэклог), 'real' (ручная разметка).
-- danger=true — мис-ключ, который СВАЛИВАЕТ варианты в один бакет → отравляет медиану (E17/E7/E8).
-- ВАЖНО: expected = ИСТИНА (как ДОЛЖНО), а не вывод текущей функции. NULL = ключа быть не должно.
-- =============================================================================

create table if not exists key_golden (
  id        bigserial primary key,
  category  text not null check (category in ('cpu','ram','mobo','ssd','psu','gpu')),
  title     text,
  model     text,
  brand     text,
  expected  text,                              -- ground-truth position_key (NULL = no key)
  danger    boolean not null default false,    -- мис-ключ → отравленный бакет (E17/E7/E8)
  err       text,
  source    text not null default 'regression',
  note      text
);

delete from key_golden where source in ('regression','gap');

insert into key_golden (category, title, model, brand, expected, danger, err, source, note) values
-- ---- CPU --------------------------------------------------------------------
('cpu','Процессор AMD Ryzen 5 5600X','AMD Ryzen 5 5600X',null,'ryzen5-5600x',false,'baseline','regression','ryzen + суффикс x'),
('cpu','Процессор Ryzen 5 2600',null,null,'ryzen5-2600',false,'baseline','regression','ryzen без суффикса'),
('cpu','Intel Core i5-12400F','Intel Core i5-12400F',null,'i5-12400f',false,'baseline','regression','i5 дефисная форма'),
('cpu','Процессор Intel Core i5 11400F',null,null,'i5-11400f',false,'baseline','regression','i5 пробельная форма → тот же ключ'),
('cpu','Intel Xeon E5-2670 v3','Intel Xeon E5-2670 v3',null,'xeon-e5-2670v3',false,'baseline','regression','xeon e-серия + ревизия v3'),
('cpu','Intel Pentium G4560',null,null,'pentium-g4560',false,'baseline','regression','pentium'),
('cpu','Intel Celeron G1840',null,null,'celeron-g1840',false,'baseline','regression','celeron'),
('cpu','Intel Core 2 Duo E8400',null,null,'core2duo-e8400',false,'baseline','regression','core2 duo'),
('cpu','Процессор AMD FX-8350',null,null,'fx-8350',false,'baseline','regression','fx'),
('cpu','AMD Athlon 3000G',null,null,'athlon-3000g',false,'baseline','regression','athlon'),
('cpu','Intel Core Ultra 7 265K',null,null,'ultra7-265k',false,'baseline','regression','core ultra (новое поколение)'),
('cpu','Процессор Intel Xeon Gold 6248',null,null,null,false,'E11','regression','Scalable намеренно null (safe), низкий приоритет'),
('cpu','Процессор для игрового ПК, недорого',null,null,null,false,'baseline','regression','нет модели → null'),
('cpu','Intel Pentium Gold G7400',null,null,'pentium-g7400',false,'NEW-2','regression','закрыто 11.06: pentium допускает инфикс gold/silver'),
-- ---- RAM (model обычно пуст → парсим заголовок) ------------------------------
('ram','Оперативная память DDR4 16GB 3200MHz',null,null,'ddr4-16gb-3200',false,'baseline','regression','одиночный модуль'),
('ram','Kingston Fury Beast DDR5 32GB 6000',null,null,'ddr5-32gb-6000',false,'baseline','regression','ddr5'),
('ram','Оперативная память DDR4 2x8GB 3200 (комплект)',null,null,'ddr4-16gb-3200',true,'E7','regression','кит 2x8=16, НЕ 8 (E7-фикс)'),
('ram','DDR4 2x32GB 3600 Kingston',null,null,'ddr4-64gb-3600',true,'E7','regression','кит 2x32=64'),
('ram','Оперативная память DDR5 24GB 5600',null,null,'ddr5-24gb-5600',true,'E8','regression','24ГБ в allowlist (E8-фикс), иначе cap=null'),
('ram','DDR5 2x24GB 6000 G.Skill',null,null,'ddr5-48gb-6000',true,'E8','regression','кит-тотал 48 в allowlist'),
('ram','Оперативная память DDR3 8GB 1600',null,null,'ddr3-8gb-1600',false,'baseline','regression','ddr3'),
('ram','SODIMM DDR4 8GB 2666',null,null,'ddr4-8gb-2666-so',false,'baseline','regression','so-dimm суффикс'),
('ram','Оперативная память DDR4 (объём не указан)',null,null,'ddr4',false,'NEW-2','regression','gen-only слабый ключ — кандидат на null (решить в NEW-2)'),
-- ---- MOBO (pk_mobo(model,title)) --------------------------------------------
('mobo','Материнская плата ASUS Prime B450M-A','ASUS PRIME B450M-A',null,'b450',false,'baseline','regression','чипсет'),
('mobo','MSI Z370-A PRO LGA1151','MSI Z370-A PRO',null,'z370',false,'baseline','regression','чипсет раньше сокета'),
('mobo','Gigabyte B550 AORUS Elite V2','B550 AORUS ELITE V2',null,'b550',false,'baseline','regression','чипсет'),
('mobo','ASRock H110M-DGS R3.0',null,null,'h110',false,'baseline','regression','чипсет из заголовка'),
('mobo','Материнская плата AM4 micro-ATX',null,null,'am4',false,'baseline','regression','сокет-фолбэк (нет чипсета)'),
('mobo','Материнская плата LGA1700 DDR5 ATX',null,null,'lga1700',false,'baseline','regression','lga-фолбэк'),
('mobo','Материнская плата X99 Huananzhi LGA2011',null,null,'x99',false,'baseline','regression','серверный чипсет x99'),
('mobo','Материнская плата б/у рабочая',null,null,null,false,'baseline','regression','нет чипсета/сокета → null'),
-- ---- SSD (pk_ssd(title,brand)) ----------------------------------------------
('ssd','SSD Samsung 970 EVO 1TB NVMe',null,'Samsung','samsung-1tb-nvme',false,'baseline','regression','бренд+объём+nvme'),
('ssd','Kingston A400 240GB 2.5 SATA',null,'Kingston','kingston-240gb-sata',false,'baseline','regression','sata'),
('ssd','SSD WD Blue 1TB',null,'Western Digital','wd-1tb',false,'brand-norm','regression','western digital→wd, без интерфейса'),
('ssd','Твердотельный накопитель Samsung 870 EVO 500GB',null,null,'samsung-500gb',false,'baseline','regression','бренд из заголовка (brand пуст)'),
('ssd','Crucial MX500 500GB SATA',null,'Crucial','crucial-500gb-sata',false,'baseline','regression','crucial'),
('ssd','SSD накопитель 17TB',null,null,null,false,'E12','regression','17ТБ вне диапазона 1..16 → null (E12 sanity)'),
('ssd','SSD Samsung 970 EVO',null,'Samsung',null,false,'baseline','regression','без объёма → null'),
-- ---- PSU (coalesce(pk_psu(model),pk_psu(title))) ----------------------------
('psu','Блок питания Corsair RM650 650W 80+ Gold',null,null,'650w',false,'baseline','regression','явная мощность'),
('psu','БП DeepCool PK500D 500 Вт ATX',null,null,'500w',false,'baseline','regression','кирилл. «вт»'),
('psu','Power Supply Thermaltake 750W',null,null,'750w',false,'baseline','regression','англ. w'),
('psu','Блок питания DEEPCOOL PK650D',null,null,'650w',false,'bar-number','regression','мощность из модели (фолбэк бар-числа)'),
('psu','Блок питания 12V 333W индустриальный',null,null,null,false,'guard-%50','regression','333 не кратно 50 → null (анти-мусор)'),
('psu','Блок питания 500W 140x150x86 мм',null,null,'500w',false,'baseline','regression','явная мощность важнее размеров (AxB-гард)'),
('psu','Блок питания ATX, мощность не указана',null,null,null,false,'baseline','regression','нет мощности → null');

-- =============================================================================
-- HARNESS — диспатч к РАЗВЁРНУТЫМ pk_* ровно как normalize_new_lots()
-- =============================================================================
create or replace view key_golden_eval as
select g.*,
  case g.category
    when 'cpu'  then coalesce(pk_cpu(g.model),  pk_cpu(g.title))
    when 'ram'  then coalesce(pk_ram(g.model),  pk_ram(g.title))
    when 'mobo' then pk_mobo(g.model, g.title)
    when 'ssd'  then pk_ssd(g.title, g.brand)
    when 'psu'  then coalesce(pk_psu(g.model),  pk_psu(g.title))
    when 'gpu'  then pk_gpu(g.model, g.title)
  end as predicted
from key_golden g;

-- 1) РЕГРЕСС: несовпадения на зафиксированной истине — ДОЛЖНО быть 0
select count(*) as regression_mismatches_MUST_BE_0
from key_golden_eval where source='regression' and predicted is distinct from expected;

-- 2) ОТРАВЛЯЮЩИЕ медиану (E17/E7/E8): danger-строки с неверным ключом — ДОЛЖНО быть 0
select id, category, expected, predicted, title
from key_golden_eval where danger and predicted is distinct from expected;

-- 3) ОТКРЫТЫЕ ДЫРЫ (бэклог NEW-2): что сейчас красное из gap-строк
select id, category, err, expected, predicted, title
from key_golden_eval where source='gap' and predicted is distinct from expected order by err;

-- 4) полный дамп несовпадений (для разбора)
select id, category, err, source, expected, predicted, title
from key_golden_eval where predicted is distinct from expected order by source, category;

-- =============================================================================
-- ВЫБОРКА для ручной разметки (добавляй строки с source='real'):
-- select item_category category, left(title,90) title, model, brand, position_key as now_key
-- from lots where item_category in ('cpu','ram','mobo','ssd','psu')
-- order by item_category, random() limit 100;   -- глазами: верен ли position_key
-- =============================================================================
