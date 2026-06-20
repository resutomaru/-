-- tg_poll — ОПРОС Telegram для локального n8n (вебхук требует публичный HTTPS, а n8n на localhost
--   недостижим извне → опрашиваем getUpdates сами, как ингест rest-app). Хранит offset (что уже
--   обработано), гоняет каждый апдейт через канон tg_router (NEW-4), возвращает ответы для отправки.
-- n8n-цепочка: Schedule → read bot_state.tg_offset → HTTP getUpdates(offset) → select * from tg_poll(result)
--   → Telegram sendMessage. Деплой: после sql/tg_router.sql.

create table if not exists bot_state (
  id        int    primary key default 1,
  tg_offset bigint not null   default 0,
  check (id = 1)
);
insert into bot_state (id, tg_offset) values (1, 0) on conflict (id) do nothing;

create or replace function public.tg_poll(updates jsonb)
returns table(chat_id text, reply text)
language plpgsql as $$
declare u jsonb; maxid bigint := 0; r record;
begin
  if updates is null or jsonb_typeof(updates) <> 'array' or jsonb_array_length(updates) = 0 then
    return;                                   -- нет апдейтов — тихо выходим (Telegram-нода ничего не шлёт)
  end if;
  for u in select value from jsonb_array_elements(updates) loop
    maxid := greatest(maxid, coalesce((u->>'update_id')::bigint, 0));
    for r in select * from public.tg_router(u) loop      -- роутинг — в каноне tg_router (не дублируем)
      if r.reply is not null and r.chat_id is not null then
        chat_id := r.chat_id; reply := r.reply; return next;
      end if;
    end loop;
  end loop;
  if maxid > 0 then
    update bot_state set tg_offset = maxid + 1 where id = 1;   -- подтверждаем обработанные (offset вперёд)
  end if;
end $$;

-- СМОУК (по желанию; сбрасывает offset обратно, чтобы не пропустить реальные апдейты):
-- select * from tg_poll('[{"update_id":1,"message":{"chat":{"id":111},"text":"/help"}}]'::jsonb);  -- ждём (111, help-текст)
-- update bot_state set tg_offset = 0 where id = 1;
