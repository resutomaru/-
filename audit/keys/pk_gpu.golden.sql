-- pk_gpu — golden / regression set + harness (закрывает E14 для ключей; проверяет E9-фикс).
-- Истина (expected) выведена из РЕАЛЬНОЙ gpu-выгрузки 2026-06-10 (266 строк) + синтетика на E9.
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
('Видеокарта rx 570 8gb',                        'AMD Radeon RX 580 8GB',                        'rx580_8g',          'model-first: продавец мис-тегнул (остаток E17, осознанно)'),
('AMD Radeon R3 512GB',                          null,                                           null,                'R3 не дискретка + guard объёма: 512GB не даёт мусор');

create or replace view gpu_key_eval as
  select g.*, pk_gpu(g.model, g.title) as predicted from gpu_key_golden g;

-- ВЕРДИКТ (норма: 0):
select count(*) filter (where predicted is distinct from expected) as mismatches from gpu_key_eval;
-- разбор несовпадений (если есть):
-- select title, model, expected, predicted from gpu_key_eval where predicted is distinct from expected;
