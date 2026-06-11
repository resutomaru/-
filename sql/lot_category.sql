-- lot_category — категоризатор как ФУНКЦИЯ. ЕДИНСТВЕННЫЙ канон правил (sql/categorizer.sql — тонкая обёртка).
-- АУДИТ 2026-06-10: обёрнут в функцию для авто-нормализатора (pg_cron).
-- v2.4 (2026-06-11): +^-гард аксессуаров (кронштейн/держатель/бэкплейт/рамка/наклейка/термопрокладки/
--   термопаст) — закрывает NEW-1-протечки аксессуар→компонент (найдены category_golden). База — v2.3.
-- v2.5 (2026-06-11): RTX/GTX через \yrtx/\ygtx (граница слева) — ловит и «RTX3060» склеенный, и «RTX Pro
--   6000»/«RTX A6000»/«GTX Titan» с инфиксом (превью поймал регресс от слишком узкого \yrtx ?\d).
--   Явное «материнск» → mobo даже при упоминании кулера (был over-exclude «мать + кулер»→other). Зонд B.
-- v2.6 (самоаудит D5): явной mobo-ветке возвращён УЗКИЙ гард водоблок/СЖО («Водоблок … материнской
--   платы» — аксессуар, не плата). «кулер» в гард НЕ возвращаем — это был over-exclude (зонд B).
-- v2.7 (зонд A, D6): ^-гард += охлажден|систем*охлажден|адаптер|вентилятор («Система охлаждения …
--   RTX 3070» / «Охлаждение для памяти» / «Адаптер M.2» — аксессуары). Якорь ^ бережёт живые карты
--   («…с охлаждением» в середине не выталкивает); «системный блок» не матчится (нужен «охлажден» следом).
--   Бандлы в cpu/mobo («Комплект Z790 + i5») НАМЕРЕННО не перекатегоризуем: гейт is_component=false
--   уже исключает их из медианы, категория бандла вторична.
-- v2.8 (пакет №2, R10): чипсет-словарь догоняет pk_mobo — [bzh][2-8][0-9]0 (+h-серии 2xx–7xx, +AMD
--   800-серия b840/b850/b860/z890), x[3-8]70 (+x870); h[3-6]10 поглощён новым классом. В негатив ветки
--   добавлен psu-гард: «Блок питания Deepcool B650/B750» — модель БП, не чипсет → psu.
create or replace function public.lot_category(title text, model text)
 returns text language sql immutable as $$
  select case
    when coalesce(title,'') ~* '(\yмыш|клавиатур|гарнитур|наушник|джойстик|геймпад|веб[- ]?камер|вебкамер|райзер|\yriser\y)' then 'other'
    when coalesce(title,'') ~* '^(радиатор|крепление|кулер|подставка|кабель|переходник|сумка|коврик|корпус|кронштейн|держател|б[эе]кплейт|рамка|наклейк|термопроклад|термопаст|охлажден|систем\w*\s+охлажден|адаптер|вентилятор)' then 'other'
    when coalesce(title,'') ~* '(ноутбук|\yноут\y|в сборе|системн\w* блок|компьютер в сборе|моноблок)' then 'assembly'
    when coalesce(title,'') ~* '(водян\w*\s*охлажд|жидкостн\w*\s*охлажд|\yсжо\y|водоблок|башн\w*\s*охлажд)'
         and coalesce(title,'') !~* '(видеокарт|geforce|\yrtx|\ygtx|radeon|quadro|материнск|материнк|комплект|в сборе|\+)' then 'other'
    when coalesce(title,'') ~* '(видеокарт|geforce|\yrtx|\ygtx|radeon|\yrx ?\d{3,4}|\ygt ?\d{3,4}|quadro)' then 'gpu'
    when coalesce(title,'') ~* '(процессор|\ycpu\y|ryzen|core ?i[3579]|core ?2|core ?ultra|\yi[3579][ -]?\d{3,5}|xeon|pentium|celeron|\yathlon\y)'
         and coalesce(title,'') !~* '(кулер|охлажд|вентилятор|радиатор|термопаст|для процессора|материнск|motherboard)' then 'cpu'
    when coalesce(title,'') ~* '(материнск|материнк|motherboard|\yмать\y)'
         and coalesce(title,'') !~* '(\yводоблок|\yсжо\y)' then 'mobo'
    when coalesce(title,'') ~* '(\yam[345]\y|\ylga ?\d{3,4}|сокет|socket|чипсет|\y[bzh][2-8][0-9]0|\yx[3-8]70)'
         and coalesce(title,'') !~* '(кулер|башня|jonsbo|водоблок|\yсжо\y|блок ?пит|\yбп\y|power supply|\d{3,4}\s*(вт|ватт|\yw\y))' then 'mobo'
    when coalesce(title,'') ~* '(оперативн|модул\w* памяти|\yозу\y|\yram\y|valueram|\yddr ?[2345]|\ydimm\y|sodimm|so-dimm|hyperx|мгц|mhz)' then 'ram'
    when coalesce(title,'') ~* '(\yssd\y|nvme|\ym\.?2\y|твердотел|((xpg|\yevo\y|\yqvo\y).*\d+\s*(gb|гб|tb|тб)|\d+\s*(gb|гб|tb|тб).*(xpg|\yevo\y|\yqvo\y)))'
         and coalesce(title,'') !~* '(внешний корпус|корпус для|\yбокс\y|карман|док[- ]?станц|enclosure|кейс для|карт\w* памяти|micro ?sd|microsd|\ysd ?xc\y|\ysdhc\y|флешк|usb[- ]?флеш|блок ?пит|\yбп\y|power supply)' then 'ssd'
    when coalesce(title,'') ~* '(блок ?пит|\yбп\y|\ypsu\y|power supply|80 ?plus|80 ?\+|\d{3,4} ?(вт|ватт))'
         and coalesce(title,'') !~* '(для монитор|для ноутбук|для роутер|для камер|для светодиод|\yадаптер|зарядн|macbook|imac|для apple|для мак\y)' then 'psu'
    when coalesce(model,'') ~* '(core ?2|core ?i[3579]|ryzen|xeon|pentium|celeron|athlon)' then 'cpu'
    else 'other'
  end;
$$;
