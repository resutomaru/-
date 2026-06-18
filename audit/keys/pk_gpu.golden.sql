-- pk_gpu — golden / regression set + harness (закрывает E14 для ключей; E9 + v2-добор + v3 E17-сверка).
-- Истина (expected) из РЕАЛЬНЫХ gpu-выгрузок 2026-06-10 + зонд E17 18.06 (60 расхождений model↔title) + синтетика E9.
-- Прогон в Supabase SQL Editor, где развёрнута pk_gpu(). Норма: mismatches = 0.
-- ВАЖНО: expected = ИСТИНА (ground truth), а не предсказание текущей функции.
create table if not exists gpu_key_golden (
  id       bigserial primary key,
  title    text,
  model    text,
  expected text,
  note     text
);
delete from gpu_key_golden;
insert into gpu_key_golden (title, model, expected, note) values
-- v1: формат, суффиксы, порядок ветвей, E9
('Видеокарта Radeon rx 570 4gb',                 'PULSE Radeon RX 570 4GB',                      'rx570_4g',          'база'),
('Видеокарта gtx 1070ti 8GB',                    'GeForce GTX 1070 Ti JetStream 8GB',            'gtx1070ti_8g',      'суффикс ti'),
('Игровая видеокарта RX 6800хt 16гб',            'AMD Radeon RX 6800 XT 16GB',                   'rx6800xt_16g',      'xt + де-гомоглиф х/гб'),
('Видеокарта RX 7900 XTX gaming OC',             'AMD Radeon RX 7900 XTX AORUS ELITE 24GB',      'rx7900xtx_24g',     'xtx раньше xt'),
('Видеокарта gtx 1660 super 6gb Colorful',       'GeForce GTX 1660 SUPER 6GB',                   'gtx1660super_6g',   'super из allowlist (1660)'),
('Видеокарта rtx 2060 super 8gb msi',            'GeForce RTX 2060 SUPER VENTUS OC 8GB',         'rtx2060super_8g',   'super из allowlist (2060)'),
('Видеокарта EVGA RTX 3070 SuperClocked 8GB',    null,                                           'rtx3070_8g',        'E9: SuperClocked НЕ super (3070 не в allowlist + \ysuper\y)'),
('Видеокарта Palit GTX 1070 Super JetStream 8GB',null,                                           'gtx1070_8g',        'E9: Super JetStream НЕ super (1070 не Super-линейка)'),
('Видеокарта RTX 4070 Ti Super 16GB',            null,                                           'rtx4070tisuper_16g','отдельный SKU: ti+super'),
('Asrock radeon rx vega 56',                     'AMD Radeon RX Vega 56 Phantom Gaming X 8GB',   'vega56_8g',         'vega раньше rx'),
('Видеокарта msi r6970 lightning на з/ч',        'Radeon HD 6970 2GB',                           'hd6970_2g',         'hd раньше rx/radeon'),
('Видеокарта p106 100 6gb',                      'P106-100 6GB',                                 'p106100_6g',        'майнинг P106-100'),
('Видеокарта/ nvidia RTX A1000 PCIe 8GB gddr6 128bit, BLK', null,                               'rtxa1000_8g',       'pro RTX A-series; 128bit не объём'),
('Видеокарта rtx 3050',                          'GeForce RTX 3050 Dual',                        'rtx3050',           'без объёма → голый ключ'),
('Неисправная видеокарта AMD r9 370 4gb 256 bit gddr', 'Radeon R9 370 4Gb',                     'r9370_4g',          'покрытие: AMD R9'),
('Видеокарта gts 450 1gb ggr5',                  'GeForce GTS 450 1GB',                          'gts450_1g',         'покрытие: nVidia GTS'),
('Видеокарта rx 570 8gb',                        'AMD Radeon RX 580 8GB',                        null,                'E17 v3: rx570≠rx580 (мис-тег model) → конфликт → null (было rx580_8g)'),
('AMD Radeon R3 512GB',                          null,                                           null,                'R3 не дискретка + guard объёма: 512GB не даёт мусор'),
-- v2: base-фолбэк на заголовок (§4.4), Intel Arc (E11), гард сборок, намеренный safe-null
('Видеокарта gt210 1gb ddr3',                    'NVIDIA GeForce 210 1GB',                       'gt210_1g',          'v2 title-fallback: model «GeForce 210» без GT, в заголовке gt210'),
('Видеокарта gtx 1050 ti 4gb',                   'GeForce 1050 Ti Dual OC 4GB',                  'gtx1050ti_4g',      'v2 title-fallback: model «GeForce 1050 Ti» без GTX'),
('Видеокарта Intel arc b580 icraft',             'Intel Arc B580 iCraft 12GB',                   'arcb580_12g',       'v2: Intel Arc (E11)'),
('Комплект i5 9400f +мат.плата + RX 590',        'Core i5-9400F',                                null,                'v2: гард сборок — НЕ ключим бандл даже фолбэком'),
('Видеокарта затычка с hdmi',                    'GeForce 210 1GB',                              null,                'намеренный safe-null: префикса нет нигде, диапазон-догадка небезопасна'),
-- пакет №2 (R6): бандл-гард на PRIMARY-пути (model пуст)
('Комплект пк: мат.плата + i5 + RX 590 8gb',     null,                                           null,                'R6: бандл с ПУСТЫМ model не ключуется и primary-путём'),
-- пакет №4 (зонд №1): объём ≠ номер модели
('Видеокарта GeForce GT 512MB DDR2',             null,                                           null,                'P4: «512MB» — объём, не модель → мусор-ключ gt512 запрещён'),
('Видеокарта GT 710 1GB',                        null,                                           'gt710_1g',          'P4-контроль: настоящий GT-номер рядом с объёмом живёт'),
-- v3 (зонд E17 18.06): конфликт числа/варианта → null; опечатка ПРЕФИКСА (то же число+вариант) → ключ из model
('Видеокарта Afox RX 550 8gb',                   'AMD Radeon RX 580 8GB',                        null,                'E17: rx550≠rx580 (named-кейс) → молчим'),
('Видеокарта rx480 8gb sapphire',                'AMD Radeon RX 580 8GB',                        null,                'E17: rx480≠rx580 → молчим'),
('Видеокарта rtx 3070',                          'GeForce RTX 3070 Ti 8GB',                      null,                'E17: вариант 3070≠3070ti (false-source #1 плана) → молчим'),
('Gtx 1650 super msi',                           'GeForce GTX 1650 VENTUS XS OC 4G',             null,                'E17: 1650super≠1650 → молчим'),
('Видеокарта MSI GeForce RTX 3080 Ti',           'GeForce GTX 550 Ti 1GB',                       null,                'E17: грубый мис-тег 3080ti vs 550ti → молчим'),
('Видеокарта rtx 1080ti Gaming X',               'GeForce GTX 1080 Ti GAMING X 11GB',            'gtx1080ti_11g',     'E17-контроль: опечатка префикса rtx/gtx, число+вариант те же → ключ из model'),
('Видеокарта radeon 7870 2gb с водоблоком',      'Radeon HD 7870 2GB',                           'hd7870_2g',         'E17-контроль: title даёт несуществующий rx7870, model hd7870 — та же карта → model');

create or replace view gpu_key_eval as
  select g.*, pk_gpu(g.model, g.title) as predicted from gpu_key_golden g;
alter view gpu_key_eval set (security_invoker = on);  -- NEW-5

-- ВЕРДИКТ (норма: 0):
select count(*) filter (where predicted is distinct from expected) as mismatches from gpu_key_eval;
-- разбор несовпадений (если есть):
-- select title, model, expected, predicted from gpu_key_eval where predicted is distinct from expected;
