-- =============================================================================
-- score_golden — сеть Ф6: балл (lot_score) и светофор (lot_trust).
-- Назначение: правки весов/порогов без mismatches=0 не катим (RR-12); red-обязанность
--   (скидка >70%, фото ≤1, пустое описание) закреплена danger-кейсами (RR-06).
-- ВАЖНО: expected_* посчитаны ВРУЧНУЮ от зафиксированной формулы-решения — это истина,
--   а не вывод текущего кода. Входы детерминированные (age_hours), сеть не «плывёт».
-- Прогон в Supabase, где развёрнут sql/lot_score.sql.
-- =============================================================================
create table if not exists score_golden (
  id bigserial primary key,
  discount  numeric not null, need_disc numeric not null, age_hours numeric not null,
  condition text    not null, n_photos  int     not null, descr_len int     not null,
  txt       text    not null default '',
  expected_score numeric not null, expected_trust text not null,
  danger boolean not null default false, err text,
  source text not null default 'regression', note text
);
delete from score_golden where source = 'regression';
insert into score_golden (discount, need_disc, age_hours, condition, n_photos, descr_len, txt,
                          expected_score, expected_trust, danger, err, note) values
(0.55, 0.40,  1, 'working', 5, 200, '',                            7.0, 'green',  false, 'baseline', 'скидка 2.0 + свежесть 3 + ясность 2'),
(0.40, 0.40, 30, 'unknown', 5, 100, '',                            0.0, 'yellow', false, 'baseline', 'ровно на пороге, старый, неясный — низ шкалы; unknown=yellow'),
(0.80, 0.40,  1, 'working', 8, 300, '',                            9.0, 'red',    true,  'RR-06',    '>70% — red ОБЯЗАН; скидочная часть капится на 4 (не бонусируем глубже)'),
(0.60, 0.55,  3, 'working', 4, 120, '',                            5.3, 'green',  false, 'baseline', 'аномальная категория (ssd/psu): порог 55%; 1.33+2+2'),
(0.50, 0.40,  1, 'working', 6, 150, 'Срочно, переезд, на гарантии',7.3, 'green',  false, 'baseline', '1.33+3+2 +0.5 срочность +0.5 гарантия'),
(0.45, 0.40,  1, 'working', 1, 200, '',                            5.7, 'red',    true,  'RR-06',    'фото ≤1 — red ОБЯЗАН, балл не спасает'),
(0.42, 0.40, 10, 'unknown', 5,  20, '',                            1.3, 'red',    false, 'RR-06',    'описание <40 симв — red'),
(0.50, 0.40, 30, 'working', 2, 100, '',                            3.3, 'yellow', false, 'baseline', '2 фото — yellow; 1.33+0+2'),
(0.72, 0.55,  1, 'working', 5, 100, '',                            9.0, 'red',    true,  'RR-06',    'аномальная категория >70% — тоже red; 4+3+2');

-- HARNESS
create or replace view score_golden_eval as
select g.*,
       public.lot_score(g.discount, g.need_disc, g.age_hours, g.condition, g.txt) as predicted_score,
       public.lot_trust(g.discount, g.n_photos, g.descr_len, g.condition)         as predicted_trust
from score_golden g;
alter view score_golden_eval set (security_invoker = on);  -- NEW-5

-- ВЕРДИКТ (норма: оба 0):
select count(*) filter (where predicted_score is distinct from expected_score) as score_mismatches,
       count(*) filter (where predicted_trust is distinct from expected_trust) as trust_mismatches
from score_golden_eval;

-- разбор несовпадений (если есть):
-- select id, err, expected_score, predicted_score, expected_trust, predicted_trust, note
-- from score_golden_eval
-- where predicted_score is distinct from expected_score or predicted_trust is distinct from expected_trust;
