-- lot_category — категоризатор как ФУНКЦИЯ. ЕДИНСТВЕННЫЙ канон правил (sql/categorizer.sql — тонкая обёртка).
-- АУДИТ 2026-06-10: обёрнут в функцию для авто-нормализатора (pg_cron).
-- v2.4 (2026-06-11): +^-гард аксессуаров (кронштейн/держатель/бэкплейт/рамка/наклейка/термопрокладки/
--   термопаст) — закрывает NEW-1-протечки аксессуар→компонент (найдены category_golden). База — v2.3
--   (превью-дифф 639/0 + протечки E10). ПЕРЕД ДЕПЛОЕМ — превью-дифф: только мусор должен ехать в other.
create or replace function public.lot_category(title text, model text)
 returns text language sql immutable as $$
  select case
    when coalesce(title,'') ~* '(\yмыш|клавиатур|гарнитур|наушник|джойстик|геймпад|веб[- ]?камер|вебкамер|райзер|\yriser\y)' then 'other'
    when coalesce(title,'') ~* '^(радиатор|крепление|кулер|подставка|кабель|переходник|сумка|коврик|корпус|кронштейн|держател|б[эе]кплейт|рамка|наклейк|термопроклад|термопаст)' then 'other'
    when coalesce(title,'') ~* '(ноутбук|\yноут\y|в сборе|системн\w* блок|компьютер в сборе|моноблок)' then 'assembly'
    when coalesce(title,'') ~* '(водян\w*\s*охлажд|жидкостн\w*\s*охлажд|\yсжо\y|водоблок|башн\w*\s*охлажд)'
         and coalesce(title,'') !~* '(видеокарт|geforce|\yrtx\y|\ygtx\y|radeon|quadro|материнск|материнк|комплект|в сборе|\+)' then 'other'
    when coalesce(title,'') ~* '(видеокарт|geforce|\yrtx\y|\ygtx\y|radeon|\yrx ?\d{3,4}|\ygt ?\d{3,4}|quadro)' then 'gpu'
    when coalesce(title,'') ~* '(процессор|\ycpu\y|ryzen|core ?i[3579]|core ?2|core ?ultra|\yi[3579][ -]?\d{3,5}|xeon|pentium|celeron|\yathlon\y)'
         and coalesce(title,'') !~* '(кулер|охлажд|вентилятор|радиатор|термопаст|для процессора|материнск|motherboard)' then 'cpu'
    when coalesce(title,'') ~* '(материнск|материнк|motherboard|\yмать\y|\yam[345]\y|\ylga ?\d{3,4}|сокет|socket|чипсет|\y[bz][3-7][0-9]0|\yx[3-7]70|\yh[3-6]10)'
         and coalesce(title,'') !~* '(кулер|башня|jonsbo|водоблок|\yсжо\y)' then 'mobo'
    when coalesce(title,'') ~* '(оперативн|модул\w* памяти|\yозу\y|\yram\y|valueram|\yddr ?[2345]|\ydimm\y|sodimm|so-dimm|hyperx|мгц|mhz)' then 'ram'
    when coalesce(title,'') ~* '(\yssd\y|nvme|\ym\.?2\y|твердотел|((xpg|\yevo\y|\yqvo\y).*\d+\s*(gb|гб|tb|тб)|\d+\s*(gb|гб|tb|тб).*(xpg|\yevo\y|\yqvo\y)))'
         and coalesce(title,'') !~* '(внешний корпус|корпус для|\yбокс\y|карман|док[- ]?станц|enclosure|кейс для|карт\w* памяти|micro ?sd|microsd|\ysd ?xc\y|\ysdhc\y|флешк|usb[- ]?флеш|блок ?пит|\yбп\y|power supply)' then 'ssd'
    when coalesce(title,'') ~* '(блок ?пит|\yбп\y|\ypsu\y|power supply|80 ?plus|80 ?\+|\d{3,4} ?(вт|ватт))'
         and coalesce(title,'') !~* '(для монитор|для ноутбук|для роутер|для камер|для светодиод|\yадаптер|зарядн|macbook|imac|для apple|для мак\y)' then 'psu'
    when coalesce(model,'') ~* '(core ?2|core ?i[3579]|ryzen|xeon|pentium|celeron|athlon)' then 'cpu'
    else 'other'
  end;
$$;
