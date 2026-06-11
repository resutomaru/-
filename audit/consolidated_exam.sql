-- =============================================================================
-- КОНСОЛИДИРОВАННЫЙ ЭКЗАМЕН — все 5 сетей + инварианты истории/медиан ОДНОЙ таблицей.
-- Восстановлен в git (находка R0 ре-аудита 2026-06-11): прежде скрипт жил только в чате —
--   артефакт вне версионирования (класс E21). Теперь канон здесь.
-- Формат по ПРОЦЕСС-0: Supabase SQL Editor показывает только ПОСЛЕДНИЙ select →
--   весь вердикт = ОДИН select (union-таблица). Только чтение, данных не меняет.
-- ПРЕДУСЛОВИЕ: засеяны сети и созданы eval-вью (файлы: audit/condition/golden_set.sql,
--   audit/keys/pk_gpu.golden.sql, audit/keys/key_golden.sql, audit/category/category_golden.sql).
--   Если какой-то вью нет — сначала прогнать соответствующий файл сети.
-- НОРМА: у всех строк с norm='0' observed = 0 (verdict ✓). 'ℹ' — справочные счётчики
--   (gap-бэклог ожидаемо 2: MX500-словарь, дробные ТБ — осознанный бэклог).
-- =============================================================================
select ord, net, what, observed, norm,
       case when norm = '0' and observed = 0 then '✓'
            when norm = '0'                  then '✗ ПРОВАЛ'
            else 'ℹ' end as verdict
from (
  -- 1) CONDITION (рабочее/мёртвое/неясно)
  select 10 as ord, 'condition' as net, 'dead→working (кардинальный грех, E18)' as what,
         (select count(*) from condition_golden_eval where expected='dead' and predicted='working')::bigint as observed,
         '0' as norm
  union all
  select 11, 'condition', 'несовпадения всего (synthetic + real)',
         (select count(*) from condition_golden_eval where predicted is distinct from expected), '0'
  -- 2) GPU-КЛЮЧИ
  union all
  select 20, 'gpu-keys', 'несовпадения (вкл. E9/v2)',
         (select count(*) from gpu_key_eval where predicted is distinct from expected), '0'
  -- 3) КЛЮЧИ cpu/ram/mobo/ssd/psu
  union all
  select 30, 'keys', 'регресс на зафиксированной истине (без gap)',
         (select count(*) from key_golden_eval where source='regression' and predicted is distinct from expected), '0'
  union all
  select 31, 'keys', 'danger-мис-ключи (отрава бакета, E17/E7/E8)',
         (select count(*) from key_golden_eval where danger and predicted is distinct from expected), '0'
  -- 4) КАТЕГОРИИ
  union all
  select 40, 'category', 'регресс на зафиксированной истине (без gap)',
         (select count(*) from category_golden_eval where source='regression' and predicted is distinct from expected), '0'
  union all
  select 41, 'category', 'danger-аксессуары, утёкшие в компонент',
         (select count(*) from category_golden_eval where danger and predicted not in ('other','assembly')), '0'
  -- 5) ДЕТЕКТОР СБОРОК
  union all
  select 50, 'is_component', 'несовпадения (D7/D8)',
         (select count(*) from component_golden_eval where predicted is distinct from expected), '0'
  -- 6) ИНВАРИАНТЫ ИСТОРИИ ЦЕН (самосинк D4 обязан держать нули)
  union all
  select 60, 'history', 'рассинхрон с lots (ключ/категория/condition)',
         (select count(*) from price_history ph join lots l on l.id = ph.lot_id
           where (ph.position_key, ph.item_category, ph.condition)
                 is distinct from (l.position_key, l.item_category, coalesce(l.condition,'unknown'))), '0'
  union all
  select 61, 'history', 'строки негодных лотов (не компонент / сборка / без ключа)',
         (select count(*) from price_history ph join lots l on l.id = ph.lot_id
           where l.item_category not in ('gpu','cpu','ram','mobo','ssd','psu')
              or l.is_component = false or l.position_key is null), '0'
  union all
  select 62, 'history', 'дубли lot_id (грань: одна строка на лот)',
         (select count(*) - count(distinct lot_id) from price_history), '0'
  union all
  select 63, 'history', 'сироты (lot_id, которого нет в lots)',
         (select count(*) from price_history ph where not exists (select 1 from lots l where l.id = ph.lot_id)), '0'
  -- 7) ИНВАРИАНТЫ МЕДИАН (каркас Ф5; сейчас medians может быть пустой — нули валидны)
  union all
  select 70, 'medians', 'строки с выборкой <8 после отсечки (RR-04)',
         (select count(*) from medians where sample_size < 8), '0'
  union all
  select 71, 'medians', 'неизвестный basis (не K>20 / K8-20-low)',
         (select count(*) from medians where basis not in ('K>20','K8-20-low')), '0'
  -- 8) СПРАВОЧНО (не блокирует; для глаз и динамики)
  union all
  select 90, 'gap-бэклог', 'открытые дыры gap-строк (ожидаемо 2: MX500, дробные ТБ)',
         (select count(*) from key_golden_eval where source='gap' and predicted is distinct from expected)
       + (select count(*) from category_golden_eval where source='gap' and predicted is distinct from expected), 'ℹ'
  union all
  select 91, 'инфо', 'наблюдений в price_history',
         (select count(*) from price_history), 'ℹ'
  union all
  select 92, 'инфо', 'медиан (бакетов с n≥8 после отсечки)',
         (select count(*) from medians), 'ℹ'
  union all
  select 93, 'инфо', 'компонентов без position_key (NEW-3-остаток: словарные нули)',
         (select count(*) from lots
           where item_category in ('gpu','cpu','ram','mobo','ssd','psu') and position_key is null), 'ℹ'
  -- 9) WEAK KEYS (R5-пакет, одобрен 11.06; реестр: audit/keys/weak_keys.md).
  --    ПОСЛЕ деплоя пакета все четыре = 0. ДО деплоя ожидаемо >0 (фиксы лежат в git) —
  --    это маркер «пакет ещё не раскатан», не тревога.
  union all
  select 80, 'weak-keys', 'ram gen-only в lots (''ddr4'' без объёма; 0 после деплоя R5)',
         (select count(*) from lots where item_category='ram'
           and position_key in ('ddr2','ddr3','ddr3l','ddr4','ddr5')), '0'
  union all
  select 81, 'weak-keys', 'ram gen-only в price_history (0 после деплоя R5 — самочистка D4)',
         (select count(*) from price_history
           where position_key in ('ddr2','ddr3','ddr3l','ddr4','ddr5')), '0'
  union all
  select 82, 'weak-keys', 'ram объём-без-поколения (''16gb…''; 0 после деплоя R5)',
         (select count(*) from lots where item_category='ram' and position_key ~ '^[0-9]+gb'), '0'
  union all
  select 83, 'weak-keys', 'cpu athlon-семейства без номера модели (0 после деплоя R5)',
         (select count(*) from lots where item_category='cpu'
           and position_key ~ '^athlon-(64|ii|pro|x[0-9]|xp)$'), '0'
) t
order by ord;

-- =============================================================================
-- НИЖЕ — ОТДЕЛЬНЫЕ запросы (выполнять ПО ОДНОМУ, ПРОЦЕСС-0). Раскомментировать нужный.
-- =============================================================================

-- (B) ЖИВЫЕ ТЕЛА ФУНКЦИЙ — Download CSV и отдать в чат для ДОСЛОВНОГО диффа с git-каноном
--     (гейт №1 ре-аудита: live==git дословно подтверждён только для pk_ssd):
-- select p.proname, p.prosrc
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname in
--   ('lot_condition','lot_category','lot_is_component','pk_cpu','pk_ram','pk_mobo',
--    'pk_ssd','pk_psu','pk_gpu','normalize_new_lots','snapshot_price_history','compute_medians')
-- order by p.proname;

-- (C) pg_cron: список джобов (ожидаем 3: normalize */2, snapshot */5, medians '3 * * * *'):
-- select jobid, jobname, schedule, active, command from cron.job order by jobid;

-- (D) pg_cron: последние 20 запусков — ловим ТИХИЕ падения (status/return_message):
-- select j.jobname, d.status, d.return_message, d.start_time
-- from cron.job_run_details d join cron.job j using (jobid)
-- order by d.start_time desc limit 20;

-- (E) окружение (локаль/версия — контекст E13):
-- select version();
