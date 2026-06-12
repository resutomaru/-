-- lot_score / lot_trust — Ф6: балл 0–10 и светофор доверия как ФУНКЦИИ.
-- ЕДИНСТВЕННЫЙ канон правил скоринга (deal_preview — тонкая обёртка; вторую копию правил
--   не держим — урок NEW-4). Сеть: audit/score/score_golden.sql — правки весов без
--   mismatches=0 не катим (RR-12).
-- Входы примитивные и ДЕТЕРМИНИРОВАННЫЕ (age_hours вместо posted_at/now()) — чтобы golden
--   не «плыл» со временем.

create or replace function public.lot_trust(
  discount numeric, n_photos int, descr_len int, condition text
) returns text language sql immutable as $$
  select case
    when discount > 0.70 then 'red'        -- «слишком хорошо» = развод-подозрение (§9), не бонус
    when coalesce(n_photos,0) <= 1 then 'red'
    when coalesce(descr_len,0) < 40 then 'red'
    when condition = 'unknown' then 'yellow'
    when coalesce(n_photos,0) <= 3 then 'yellow'
    else 'green'
  end;
$$;

create or replace function public.lot_score(
  discount numeric, need_disc numeric, age_hours numeric, condition text, txt text
) returns numeric language sql immutable as $$
  select round(least(10, greatest(0,
      least((discount - need_disc) / nullif(0.70 - need_disc, 0), 1) * 4    -- глубина скидки 0..4 (кап на 70%)
    + case when age_hours <= 2  then 3
           when age_hours <= 6  then 2
           when age_hours <= 24 then 1 else 0 end                            -- свежесть 0..3
    + case when condition = 'working' then 2 else 0 end                      -- ясность раб/нераб 0..2
    + case when txt ~* '(срочн|переезд|сегодня отда)' then 0.5 else 0 end    -- срочность продавца
    + case when txt ~* '(запечатан|не вскрыв|на гарантии|\yчек\y)' then 0.5 else 0 end  -- новьё/гарантия
  ))::numeric, 1);
$$;
