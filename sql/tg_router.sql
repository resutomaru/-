-- tg_router — МОЗГ Telegram-бота журнала (spec §6.7/6.8). Вся логика в SQL; n8n — тонкая труба
--   (как ingest/push). Принимает СЫРОЙ Telegram update (jsonb) → возвращает готовый ответ.
-- Маршруты:
--   • callback 'buy:<lot_id>'            → buy_lot           (кнопка «Купил» на карточке находки)
--   • callback 'track:'/'skip:'          → подтверждение     (петля §6.8; «Слежу»/«Мимо»)
--   • '/журнал' (/journal,/start*,/help) → сводка deal_dashboard
--   • '/купил <id лота> [цена]'          → buy_lot
--   • '/продал <id сделки> <цена>'       → mark_sold (+навар)
--   • иначе                              → подсказка
-- chat_id → client_id через client_configs (RR-08). Неизвестный чат → вежливый отказ.
-- Возврат: (chat_id, reply, answer) — reply шлём sendMessage; answer (если есть) — answerCallbackQuery.
-- Захват — через канон buy_lot/mark_sold (формулу навара не дублируем, NEW-4). Зовётся n8n-нодой:
--   select * from tg_router($1::jsonb)   ($1 = JSON.stringify(update) из Telegram Trigger).

create or replace function public.tg_router(upd jsonb)
returns table(chat_id text, reply text, answer text)
language plpgsql as $$
declare
  v_chat   text;
  v_text   text;
  v_data   text;
  v_client text;
  v_cmd    text;
  v_args   text[];
  v_lot    bigint;
  v_deal   bigint;
  v_price  bigint;
  v_id     bigint;
  v_title  text;
  v_navar  bigint;
  v_margin numeric;
  v_instock bigint; v_money bigint; v_sold bigint; v_plus numeric; v_turn numeric;
begin
  v_chat := coalesce(upd #>> '{message,chat,id}', upd #>> '{callback_query,message,chat,id}');
  v_text := upd #>> '{message,text}';
  v_data := upd #>> '{callback_query,data}';
  chat_id := v_chat;
  answer  := null;

  select c.client_id into v_client from client_configs c where c.chat_id = v_chat;

  -- ── КНОПКИ (callback_query) ───────────────────────────────────────────────
  if v_data is not null then
    if v_client is null then
      reply := '⛔ Этот чат не привязан к клиенту.'; answer := 'Не привязан'; return next; return;
    end if;
    if v_data like 'buy:%' then
      begin
        v_lot := nullif(split_part(v_data, ':', 2), '')::bigint;
        v_id  := public.buy_lot(v_client, v_lot);
        select item_title into v_title from deals where id = v_id;
        reply := '✅ В журнал: ' || coalesce(v_title, 'сделка') || ' (#' || v_id || ')';
        answer := 'Записал ✅';
      exception when others then
        reply := '⛔ ' || sqlerrm; answer := 'Ошибка';
      end;
    elsif v_data like 'track:%' then
      reply := '👀 Ок, слежу.'; answer := 'Слежу';
    elsif v_data like 'skip:%' then
      reply := '🚫 Пропускаю.'; answer := 'Мимо';
    else
      reply := 'Неизвестная кнопка.'; answer := '';
    end if;
    return next; return;
  end if;

  -- ── КОМАНДЫ (message.text) ────────────────────────────────────────────────
  v_args := regexp_split_to_array(btrim(coalesce(v_text, '')), '\s+');
  v_cmd  := split_part(lower(coalesce(v_args[1], '')), '@', 1);   -- срезаем @botname

  if v_cmd in ('/start', '/help') then
    reply := E'Я веду журнал перекупа.\n'
          || E'/журнал — сводка (навар, в наличии, маржа)\n'
          || E'/купил <id лота> [цена] — завести покупку\n'
          || E'/продал <id сделки> <цена> — отметить продажу\n'
          || 'А на карточках находок жми «Купил».';
    return next; return;
  end if;

  if v_cmd in ('/журнал', '/journal') then
    if v_client is null then reply := '⛔ Этот чат не привязан к клиенту.'; return next; return; end if;
    select coalesce(навар_всего,0), coalesce(в_наличии,0), coalesce(деньги_в_товаре,0),
           coalesce(продано,0), coalesce(в_плюс_проц,0), coalesce(оборачиваемость_дней,0)
      into v_navar, v_instock, v_money, v_sold, v_plus, v_turn
      from deal_dashboard where client_id = v_client;
    if not found then
      reply := '📒 Журнал пуст. Жми «Купил» на находке или /купил <id лота>.';
    else
      reply := E'📒 Журнал «' || v_client || E'»\n'
            || '• Навар всего: '   || v_navar   || E' ₽\n'
            || '• В наличии: '      || v_instock || ' шт на ' || v_money || E' ₽\n'
            || '• Продано: '        || v_sold    || ', в плюс ' || v_plus || E'%\n'
            || '• Оборачиваемость: '|| v_turn    || ' дн';
    end if;
    return next; return;
  end if;

  if v_cmd in ('/купил', '/buy') then
    if v_client is null then reply := '⛔ Этот чат не привязан к клиенту.'; return next; return; end if;
    if v_args[2] is null or v_args[2] !~ '^\d+$' then
      reply := 'Формат: /купил <id лота> [цена]'; return next; return; end if;
    if v_args[3] is not null and v_args[3] !~ '^\d+$' then
      reply := 'Цена должна быть числом. Формат: /купил <id лота> [цена]'; return next; return; end if;
    begin
      v_lot   := v_args[2]::bigint;
      v_price := nullif(v_args[3], '')::bigint;
      v_id    := public.buy_lot(v_client, v_lot, v_price);
      select item_title into v_title from deals where id = v_id;
      reply := '✅ В журнал: ' || coalesce(v_title, 'сделка') || ' (#' || v_id || ')';
    exception when others then
      reply := '⛔ ' || sqlerrm;
    end;
    return next; return;
  end if;

  if v_cmd in ('/продал', '/sold') then
    if v_client is null then reply := '⛔ Этот чат не привязан к клиенту.'; return next; return; end if;
    if v_args[2] is null or v_args[2] !~ '^\d+$' or v_args[3] is null or v_args[3] !~ '^\d+$' then
      reply := 'Формат: /продал <id сделки> <цена>'; return next; return; end if;
    begin
      v_deal  := v_args[2]::bigint;
      v_price := v_args[3]::bigint;
      perform public.mark_sold(v_deal, v_price);
      select навар, маржа_проц into v_navar, v_margin from deal_ledger where id = v_deal;
      reply := '💰 Продано. Навар ' || coalesce(v_navar,0) || ' ₽ (маржа ' || coalesce(v_margin,0) || '%)';
    exception when others then
      reply := '⛔ ' || sqlerrm;
    end;
    return next; return;
  end if;

  reply := 'Не понял. /help — что я умею.';
  return next; return;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- СМОУК-ТЕСТ (выполнить отдельно; читает, НЕ мутирует — buy/sold проверь живым ботом).
-- Жди осмысленные reply: help-текст, сводку журнала, отказ для чужого чата, подсказку.
-- (Подставь СВОЙ chat_id вместо 111 там, где привязан клиент; 999 = заведомо чужой чат.)
-- select 'help'        as t, reply from tg_router('{"message":{"chat":{"id":111},"text":"/help"}}');
-- select 'журнал'      as t, reply from tg_router('{"message":{"chat":{"id":111},"text":"/журнал"}}');
-- select 'чужой чат'   as t, reply from tg_router('{"message":{"chat":{"id":999},"text":"/журнал"}}');
-- select 'мусор'       as t, reply from tg_router('{"message":{"chat":{"id":111},"text":"привет"}}');
-- ─────────────────────────────────────────────────────────────────────────────
