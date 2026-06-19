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
('cpu','Процессор AMD Ryzen 5 5600X','AMD Ryzen 5 5600X',null,'ryzen-5600x',false,'baseline','regression','R6-cpu: ryzen без тира (4-знач. номер уникален)'),
('cpu','Процессор Ryzen 5 2600',null,null,'ryzen-2600',false,'baseline','regression','ryzen без суффикса/тира'),
('cpu','Intel Core i5-12400F','Intel Core i5-12400F',null,'i5-12400f',false,'baseline','regression','i5 дефисная форма'),
('cpu','Процессор Intel Core i5 11400F',null,null,'i5-11400f',false,'baseline','regression','i5 пробельная форма → тот же ключ'),
('cpu','Intel Xeon E5-2670 v3','Intel Xeon E5-2670 v3',null,'xeon-e5-2670v3',false,'baseline','regression','xeon e-серия + ревизия v3'),
('cpu','Intel Pentium G4560',null,null,'pentium-g4560',false,'baseline','regression','pentium'),
('cpu','Intel Celeron G1840',null,null,'celeron-g1840',false,'baseline','regression','celeron'),
('cpu','Intel Core 2 Duo E8400',null,null,'core2duo-e8400',false,'baseline','regression','core2 duo'),
('cpu','Процессор AMD FX-8350',null,null,'fx-8350',false,'baseline','regression','fx'),
('cpu','AMD Athlon 3000G',null,null,'athlon-3000g',false,'baseline','regression','athlon'),
('cpu','AMD Athlon II X2 245',null,null,'athlon-245',false,'R5','regression','R5: было семейство athlon-ii — теперь конкретный номер'),
('cpu','AMD Athlon X4 860K FM2+',null,null,'athlon-860k',false,'R5','regression','R5: x4-инфикс пропускается, ключ по модели'),
('cpu','Процессор AMD Athlon 64',null,null,null,false,'R5','regression','R5: голое семейство без номера → null (был слабый athlon-64)'),
('cpu','AMD Athlon 200GE AM4',null,null,'athlon-200ge',false,'R5','regression','R5: двухбуквенный хвост модели (ge) сохраняется'),
('cpu','Intel Core Ultra 7 265K',null,null,'ultra7-265k',false,'baseline','regression','core ultra (новое поколение)'),
('cpu','Процессор Intel Xeon Gold 6248',null,null,'xeon-gold-6248',false,'E11','regression','Scalable покрыт (probe C): gold/platinum/silver/bronze'),
('cpu','AMD Ryzen 5 PRO 4650G',null,null,'ryzen-4650g',false,'probeC','regression','PRO-инфикс; без тира (R6-cpu)'),
('cpu','Xeon X3460 4 ядра LGA1156',null,null,'xeon-x3460',true,'D2','regression','D2-fix2: «4 ядра» НЕ v4 — v-ревизия требует букву v (danger; поймала регресс)'),
('cpu','Intel Xeon E5-2660 8 ядер 2.2ГГц',null,null,'xeon-e5-2660',true,'D2','regression','D2-fix2: «8 ядер» НЕ v8 (E/W/L-ветка, danger)'),
('cpu','Xeon Platinum 8358P 32 ядра',null,null,'xeon-platinum-8358',false,'probeC','regression','Scalable platinum (суффикс p отброшен)'),
('cpu','Процессор Xeon 2680 v2 LGA2011',null,null,'xeon-2680v2',true,'D2','regression','самоаудит D2: v-суффикс у голого Xeon — без него поколения сливаются в один бакет (danger)'),
('cpu','Процессор для игрового ПК, недорого',null,null,null,false,'baseline','regression','нет модели → null'),
('cpu','Intel Pentium Gold G7400',null,null,'pentium-g7400',false,'NEW-2','regression','закрыто 11.06: pentium допускает инфикс gold/silver'),
('cpu','Процессор Ryzen 5600X (без тира в заголовке)',null,null,'ryzen-5600x',false,'R6cpu','regression','R6-cpu (18.06): безтировый «5600X» = тот же ключ, что «Ryzen 5 5600X» (был мусор ryzen5-600x)'),
('cpu','AMD Ryzen 5700X3D OEM',null,null,'ryzen-5700x3d',false,'R6cpu','regression','R6-cpu: безтировый 5700X3D (был ryzen5-700x3d)'),
('cpu','Intel Core i5 10600К (кириллица)',null,null,'i5-10600k',false,'cyrillic-k','regression','де-гомоглиф: кириллическая «К» суффикса → k (был i5-10600)'),
-- ---- RAM (model обычно пуст → парсим заголовок) ------------------------------
('ram','Оперативная память DDR4 16GB 3200MHz',null,null,'ddr4-16gb-3200',false,'baseline','regression','одиночный модуль'),
('ram','Kingston Fury Beast DDR5 32GB 6000',null,null,'ddr5-32gb-6000',false,'baseline','regression','ddr5'),
('ram','Оперативная память DDR4 2x8GB 3200 (комплект)',null,null,'ddr4-16gb-3200',true,'E7','regression','кит 2x8=16, НЕ 8 (E7-фикс)'),
('ram','DDR4 2x32GB 3600 Kingston',null,null,'ddr4-64gb-3600',true,'E7','regression','кит 2x32=64'),
('ram','Оперативная память DDR5 24GB 5600',null,null,'ddr5-24gb-5600',true,'E8','regression','24ГБ в allowlist (E8-фикс), иначе cap=null'),
('ram','DDR5 2x24GB 6000 G.Skill',null,null,'ddr5-48gb-6000',true,'E8','regression','кит-тотал 48 в allowlist'),
('ram','Оперативная память DDR3 8GB 1600',null,null,'ddr3-8gb-1600',false,'baseline','regression','ddr3'),
('ram','SODIMM DDR4 8GB 2666',null,null,'ddr4-8gb-2666-so',false,'baseline','regression','so-dimm суффикс'),
('ram','Оперативная память DDR4 (объём не указан)',null,null,null,true,'R5','regression','R5 (одобрено 11.06): gen-only ключ ЗАПРЕЩЁН — бакет ddr4 смешивал 4–128 ГБ (danger)'),
('ram','Оперативная память 16GB для ноутбука',null,null,null,true,'R5','regression','R5: объём БЕЗ поколения — смесь DDR3/DDR5 → null (danger)'),
('ram','Серверная память 32GB ECC REG 2133',null,null,null,true,'R5','regression','R5: даже с частотой, но без поколения — ключа нет (danger)'),
('ram','DDR5 32GB 7200 МГц',null,null,'ddr5-32gb-7200',false,'R3','regression','пакет №2: кириллическая частота + DDR5-скорость из расширенного allowlist'),
('ram','Оперативная память DDR4 8GB 3200мгц',null,null,'ddr4-8gb-3200',false,'R3','regression','пакет №2: склеенная кириллическая частота'),
('ram','Оперативная память HyperX ddr4 1x16 2666Hz',null,null,'ddr4-16gb-2666',false,'Hz-unit','regression','E19-чистка: частота с единицей Hz (не только MHz/МГц) — иначе no-speed бакет'),
-- ---- MOBO (pk_mobo(model,title)) --------------------------------------------
('mobo','Материнская плата ASUS Prime B450M-A','ASUS PRIME B450M-A',null,'b450',false,'baseline','regression','чипсет'),
('mobo','MSI Z370-A PRO LGA1151','MSI Z370-A PRO',null,'z370',false,'baseline','regression','чипсет раньше сокета'),
('mobo','Gigabyte B550 AORUS Elite V2','B550 AORUS ELITE V2',null,'b550',false,'baseline','regression','чипсет'),
('mobo','ASRock H110M-DGS R3.0',null,null,'h110',false,'baseline','regression','чипсет из заголовка'),
('mobo','Материнская плата AM4 micro-ATX',null,null,'am4',false,'baseline','regression','сокет-фолбэк (нет чипсета)'),
('mobo','Материнская плата LGA1700 DDR5 ATX',null,null,'lga1700',false,'baseline','regression','lga-фолбэк'),
('mobo','Материнская плата X99 Huananzhi LGA2011',null,null,'x99',false,'baseline','regression','серверный чипсет x99'),
('mobo','Материнская плата ASRock A58M-K','ASRock A58M-K',null,'a58',false,'probeC','regression','FM2+ чипсет A58'),
('mobo','MSI 990FXA-GD65','MSI 990FXA-GD65',null,'990fx',false,'probeC','regression','AM3+ 990FX (990fx, не 990x)'),
('mobo','Intel D945GCNL',null,null,null,false,'D1','regression','D1: голые числа-чипсеты убраны — ретро в осознанный null (яд опаснее ключа, RR-03)'),
('mobo','Материнская плата для i7-9700K, разгон',null,null,null,true,'D1','regression','D1: «970» НЕ должен выскочить из i7-9700K (danger)'),
('mobo','Материнская плата ASRock с RX580',null,null,null,true,'D1','regression','D1: «x58» НЕ должен выскочить из RX580 (danger)'),
('mobo','Материнская плата Gigabyte GA-X58A-UD3R',null,null,'x58',false,'D1','regression','x58 с буквой после — валиден (гард только на цифру)'),
('mobo','Материнская плата 880GM-E41',null,null,'880g',false,'probeC','regression','AM3 880G (в проде лежит в cpu — категорию чиним отдельно)'),
('mobo','Материнская плата LGA1366 X58 под Xeon',null,null,'x58',false,'probeC','regression','чипсет x58 находится раньше сокета'),
('mobo','Материнская плата б/у рабочая',null,null,null,false,'baseline','regression','нет чипсета/сокета → null'),
('mobo','Материнская плата ASRock, цена 775 руб',null,null,null,true,'R4','regression','пакет №2: «775 руб» — цена, не LGA775 (danger, класс D3)'),
('mobo','Материнская плата 775 сокет Core 2',null,null,'lga775',false,'R4','regression','пакет №2: настоящий 775 сокет остаётся'),
-- ---- SSD (pk_ssd(title,brand)) ----------------------------------------------
('ssd','SSD Samsung 970 EVO 1TB NVMe',null,'Samsung','samsung-1tb-nvme',false,'baseline','regression','бренд+объём+nvme'),
('ssd','Kingston A400 240GB 2.5 SATA',null,'Kingston','kingston-240gb-sata',false,'baseline','regression','sata'),
('ssd','SSD WD Blue 1TB',null,'Western Digital','wd-1tb',false,'brand-norm','regression','western digital→wd, без интерфейса'),
('ssd','Твердотельный накопитель Samsung 870 EVO 500GB',null,null,'samsung-500gb',false,'baseline','regression','бренд из заголовка (brand пуст)'),
('ssd','Crucial MX500 500GB SATA',null,'Crucial','crucial-500gb-sata',false,'baseline','regression','crucial'),
('ssd','SSD накопитель 17TB',null,null,null,false,'E12','regression','17ТБ вне диапазона 1..16 → null (E12 sanity)'),
('ssd','SSD Samsung 970 EVO',null,'Samsung',null,false,'baseline','regression','без объёма → null'),
('ssd','KingSpec SSD 480',null,null,'kingspec-480gb',false,'probeC','regression','объём без единицы из allowlist'),
('ssd','SSD M2 Samsung 1000G',null,null,'samsung-1000gb-nvme',false,'probeC','regression','голая g + m2→nvme'),
('ssd','Crucial MX500',null,'Crucial',null,true,'probeC','regression','НЕ путать модель MX500 с объёмом 500 (danger)'),
('ssd','Samsung 970 EVO 250GB',null,'Samsung','samsung-250gb',false,'probeC','regression','970=модель, объём=250 (контроль)'),
('ssd','SSD U.2 3,84TB Samsung PM963',null,'Samsung','samsung-3840gb',false,'decimal-tb','gap','дробные ТБ пока не парсим (редкий enterprise)'),
('ssd','SSD Kingston за 500р',null,'Kingston',null,true,'D3','regression','D3: цена в заголовке НЕ объём (danger)'),
-- ---- PSU (coalesce(pk_psu(model),pk_psu(title))) ----------------------------
('psu','Блок питания Corsair RM650 650W 80+ Gold',null,null,'650w',false,'baseline','regression','явная мощность'),
('psu','БП DeepCool PK500D 500 Вт ATX',null,null,'500w',false,'baseline','regression','кирилл. «вт»'),
('psu','Power Supply Thermaltake 750W',null,null,'750w',false,'baseline','regression','англ. w'),
('psu','Блок питания DEEPCOOL PK650D',null,null,'650w',false,'bar-number','regression','мощность из модели (фолбэк бар-числа)'),
('psu','Блок питания 12V 333W индустриальный',null,null,null,false,'guard-%50','regression','333 не кратно 50 → null (анти-мусор)'),
('psu','Блок питания 500W 140x150x86 мм',null,null,'500w',false,'baseline','regression','явная мощность важнее размеров (AxB-гард)'),
('psu','Блок питания Corsair HX1200',null,null,'1200w',false,'probeC','regression','мощность из модели HX1200 (гард x чинён)'),
('psu','Вентилятор для БП 120x120x25мм',null,null,null,true,'probeC','regression','размеры AxB НЕ мощность (danger)'),
('psu','Блок питания б/у 350р',null,null,null,true,'D3','regression','D3: цена НЕ мощность, даже кратная 50 (danger)'),
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
alter view key_golden_eval set (security_invoker = on);  -- NEW-5

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
-- COMPONENT_GOLDEN — мини-сеть детектора сборок lot_is_component (D7/D8; RR-12: у этого мозга сети не было).
-- true = одиночный товар (идёт в медиану), false = бандл/сборка (исключается).
-- =============================================================================
create table if not exists component_golden (
  id bigserial primary key, title text, expected boolean not null,
  err text, source text not null default 'regression', note text
);
delete from component_golden where source = 'regression';
insert into component_golden (title, expected, err, note) values
('Видеокарта RTX 3070 8GB',                          true,  'baseline', 'одиночный товар'),
('Компьютер в сборе i5 / RTX 3060',                  false, 'baseline', 'сборка'),
('Комплект i5 9400f +мат.плата + RX 590',            false, 'baseline', 'бандл'),
('Оперативная память DDR4 2x8GB 3200 (комплект)',    true,  'D8', 'RAM-кит — товар, тотал считает pk_ram (E7)'),
('Комплект памяти Kingston Fury 2x16GB',             true,  'D8', 'кит со словом «комплект» впереди'),
('Память DDR3 2+2 Гб',                               true,  'D8', 'кит через плюс — не бандл'),
('Видеокарта RTX 3070, полный комплект (коробка)',   true,  'D8', '«полный комплект» = коробка/документы'),
('Комплект памяти + процессор Ryzen',                false, 'D8', 'память + второй класс = бандл'),
('Память + SSD 500gb комплект',                      false, 'D8', 'память + ssd = бандл'),
('Материнская плата ASUS + RX580',                   false, 'D7', 'GPU-бандл через плюс'),
('Материнская плата с RX 580',                       false, 'D7', 'GPU-бандл через «с»'),
('Kingston Fury 2x8GB 3200MHz (комплект)',           true,  'R8', 'пакет №2: кит без слова «память» — опознан по mhz/hyperx'),
('Лот процессоров 17шт',                             false, 'P4', 'опт-лот: цена за 17 штук — вне медианы'),
('Серверная Samsung 64GB DDR4 2шт',                  false, 'P4', 'qty: «2шт» — цена за пару планок'),
('Оперативная память DDR4 16gb 10 штук',             false, 'P4', 'qty: 10 штук'),
('Видеокарта RTX 3060 12GB, 1 шт',                   true,  'P4', 'контроль: «1 шт» — одиночный товар, НЕ флагуем');

create or replace view component_golden_eval as
  select g.*, lot_is_component(g.title) as predicted from component_golden g;
alter view component_golden_eval set (security_invoker = on);  -- NEW-5
-- ВЕРДИКТ (норма 0): select count(*) from component_golden_eval where predicted is distinct from expected;

-- =============================================================================
-- ВЫБОРКА для ручной разметки (добавляй строки с source='real'):
-- select item_category category, left(title,90) title, model, brand, position_key as now_key
-- from lots where item_category in ('cpu','ram','mobo','ssd','psu')
-- order by item_category, random() limit 100;   -- глазами: верен ли position_key
-- =============================================================================
