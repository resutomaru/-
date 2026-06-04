-- =============================================================================
-- Avito parser — condition classifier: golden / regression set + harness
-- Audit artifact (E14, E18). Run in Supabase SQL Editor where lot_condition()
-- is deployed.
--
-- Purpose
--   1) REGRESSION SEED — encodes known condition bugs E2–E6 as fixed
--      expectations, so any future edit to lot_condition() is checked against
--      them. (E4 was a silent regress from the E6 fix; this set exists to stop
--      that recurring — see передаточный бриф §2/E14.)
--   2) REAL GOLDEN ROWS — insert hand-labeled real lots (see labeling_guide.md,
--      source='real') to measure the TRUE error rate (E15). Zero tolerance for
--      dead -> working (E18).
--
-- IMPORTANT: `expected` is GROUND TRUTH (how it SHOULD be classified), NOT a
-- prediction of what the current function returns. The harness measures the
-- deployed function's reality against this truth — it does not assume it.
-- =============================================================================

create table if not exists condition_golden (
  id        bigserial primary key,
  title     text,
  descr     text,
  expected  text    not null check (expected in ('working','dead','unknown')),
  danger    boolean not null default false,   -- truth is dead but text tempts -> working (E1/E18 axis)
  err       text,                             -- which bug this row guards (E2..E6 / baseline)
  source    text    not null default 'regression', -- 'regression' (synthetic) | 'real' (hand-labeled lots)
  note      text
);

-- Idempotent reseed of synthetic rows; preserves any source='real' rows.
delete from condition_golden where source = 'regression';

insert into condition_golden (title, descr, expected, danger, err, note) values
-- ---- baselines (must already pass; anchor the matrix) -----------------------
('Видеокарта RTX 3060',          'На запчасти, не включается, нет изображения',                 'dead',    true,  'baseline', 'явное мёртвое'),
('Видеокарта RTX 3060',          'Неисправна, ремонт не делал',                                 'dead',    true,  'baseline', 'неисправ БЕЗ пробела — контроль к E2'),
('Видеокарта RTX 3070',          'Полностью рабочая, на гарантии, чек сохранён',                'working', false, 'baseline', 'явное рабочее'),
('Видеокарта RTX 3070',          'Не тестировал, нет возможности проверить',                    'unknown', false, 'baseline', 'явное неясно'),
('Видеокарта RTX 3070',          'После майнинга, полностью рабочая',                           'working', false, 'baseline', 'майнинг = износ-штраф в БАЛЛЕ, метка рабочее (§4.7)'),
-- ---- E2: «не исправ» с пробелом должно быть dead ----------------------------
('Видеокарта GTX 1660',          'Карта не исправна, требует ремонта',                          'dead',    true,  'E2', 'пробельная форма проскакивает в working'),
-- ---- E3: прошедшее время «не работал(а/о)» должно быть dead -----------------
('Материнская плата B450',       'Перестала включаться, не работала уже месяц',                 'dead',    true,  'E3', 'dead-regex ловит только «не работает» (наст.)'),
('Видеокарта RX 580',            'Не работала после последнего запуска',                        'dead',    true,  'E3', 'прош. время -> «работа» ловит working'),
-- ---- E4: «нерабочую/нерабочее» без соседнего существительного -> dead --------
('Видеокарта RTX 2060',          'Состояние: нерабочее',                                        'dead',    true,  'E4', 'нет соседнего существительного и не «в нерабочем»'),
('Оперативная память DDR4 16gb', 'Продаю нерабочую',                                            'dead',    true,  'E4', 'регресс от фикса ценового хеджа E6'),
-- ---- E5: широкий гард {0,18} спасает реально мёртвую карту -------------------
('Видеокарта RTX 3080',          'Не работает, вентилятор просто крутится',                     'dead',    true,  'E5', 'гард «вентил» в окне 18 симв. гасит реальное мёртвое'),
-- ---- E6: три ложных dead — ДОЛЖНЫ остаться не-dead (фикс закрыт, держим) -----
('Видеокарта RTX 3070',          'Дефектов нет, артефакты отсутствуют, полностью рабочая',      'working', false, 'E6', 'артефакт+отсутствуют НЕ должно быть dead'),
('Видеокарта RTX 3070',          'Отдаю по цене нерабочей, но карта полностью рабочая',         'working', false, 'E6', 'ценовой хедж НЕ должен быть dead'),
('Видеокарта RTX 3070',          'Карта рабочая, не работает 1 вентилятор из двух',             'working', false, 'E6', 'легитимный кейс гарда — прямой контраст к E5'),
-- ---- из working-выгрузки: реальные пропуски опасной стороны -----------------
('Блок питания 700w deepcool слом','На пломбе, отработал около года, перестал включаться, защита не разрешает запуск', 'dead', true, 'WRK', 'мёртвый БП утекал в working через «пломб»/«отработал» — нужен жёсткий «перестал включа»'),
('Видеокарта',                   'Перестала работать, ничего не помогло',                        'dead',    true,  'WRK', 'целиком мёртвая, без позитива'),
('Видеокарта',                   'Карта рабочая, вентиляторы перестали работать, исправил',      'working', false, 'WRK', 'подузел перестал — но «рабочая» уцелевает (контраст к мёртвому БП)'),
('Видеокарта RX 570',            'Хдми работают, карты надо шить, продажа от 10 шт',             'unknown', false, 'WRK', 'майнинг-перепрошивка → не turnkey → unknown, не working');

-- =============================================================================
-- HARNESS — calls the DEPLOYED lot_condition(title, descr)
-- =============================================================================

create or replace view condition_golden_eval as
select g.*, lot_condition(g.title, g.descr) as predicted
from condition_golden g;

-- 1) матрица ошибок (expected x predicted)
select expected, predicted, count(*) n
from condition_golden_eval
group by expected, predicted
order by expected, predicted;

-- 2) КАРДИНАЛЬНЫЙ ГРЕХ (E18): мёртвое предсказано рабочим — ДОЛЖНО быть 0
select count(*) as dead_called_working_MUST_BE_0
from condition_golden_eval
where expected = 'dead' and predicted = 'working';

-- 3) ШИРОКАЯ УТЕЧКА: мёртвое НЕ помечено dead (working ИЛИ unknown оба проходят гейт)
select count(*) as dead_not_dropped
from condition_golden_eval
where expected = 'dead' and predicted <> 'dead';

-- 4) полный дамп несовпадений (danger сверху)
select id, err, expected, predicted, danger, title, left(coalesce(descr,''),120) descr
from condition_golden_eval
where predicted is distinct from expected
order by danger desc, err;

-- cleanup (optional): drop view condition_golden_eval;
