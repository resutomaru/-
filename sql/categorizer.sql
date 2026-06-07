-- Категоризатор item_category — v2.2 (фикс E10: протечки аксессуаров).
-- База = канон v2.1 (сверено: 639/0 против развёрнутого). Изменения относительно v2.1:
--   + ветка 0: периферия (мышь/клава/гарнитура/…) → other (фикс «мышь HyperX»→ram).
--   + mobo: исключение кулеров (фикс «Jonsbo кулер … lga1700»→mobo). «радиатор» НЕ исключаем (легит у плат).
--   + ssd:  исключение внешних корпусов/боксов (фикс «внешний корпус SSD»→ssd).
--   + psu:  исключение адаптеров «для монитора/ноутбука» (фикс «блок питания для монитора»→psu).
-- Проверять превью-диффом перед деплоем (см. чат). Применяется ко всем строкам (без WHERE).
update lots set item_category =
  case
    when coalesce(title,'') ~* '(\yмыш|клавиатур|гарнитур|наушник|джойстик|геймпад|веб[- ]?камер|вебкамер)' then 'other'
    when coalesce(title,'') ~* '^(радиатор|крепление|кулер|подставка|кабель|переходник|сумка|коврик|корпус)' then 'other'
    when coalesce(title,'') ~* '(ноутбук|\yноут\y|в сборе|системн\w* блок|компьютер в сборе|моноблок)' then 'assembly'
    when coalesce(title,'') ~* '(видеокарт|geforce|\yrtx\y|\ygtx\y|radeon|\yrx ?\d{3,4}|\ygt ?\d{3,4}|quadro)' then 'gpu'
    when coalesce(title,'') ~* '(процессор|\ycpu\y|ryzen|core ?i[3579]|core ?2|core ?ultra|\yi[3579][ -]?\d{3,5}|xeon|pentium|celeron|\yathlon\y)'
         and coalesce(title,'') !~* '(кулер|охлажд|вентилятор|радиатор|термопаст|для процессора|материнск|motherboard)' then 'cpu'
    when coalesce(title,'') ~* '(материнск|материнк|motherboard|\yмать\y|\yam[345]\y|\ylga ?\d{3,4}|сокет|socket|чипсет|\y[bz][3-7][0-9]0|\yx[3-7]70|\yh[3-6]10)'
         and coalesce(title,'') !~* '(кулер|башня|jonsbo|водоблок|\yсжо\y)' then 'mobo'
    when coalesce(title,'') ~* '(оперативн|модул\w* памяти|\yозу\y|\yram\y|valueram|\yddr ?[2345]|\ydimm\y|sodimm|so-dimm|hyperx|мгц|mhz)' then 'ram'
    when coalesce(title,'') ~* '(\yssd\y|nvme|\ym\.?2\y|твердотел|xpg|\yevo\y|\yqvo\y)'
         and coalesce(title,'') !~* '(внешний корпус|корпус для|\yбокс\y|карман|док[- ]?станц|enclosure|кейс для)' then 'ssd'
    when coalesce(title,'') ~* '(блок ?пит|\yбп\y|\ypsu\y|power supply|80 ?plus|\d{3,4} ?(вт|ватт))'
         and coalesce(title,'') !~* '(для монитор|для ноутбук|для роутер|для камер|для светодиод|\yадаптер|зарядн)' then 'psu'
    when coalesce(model,'') ~* '(core ?2|core ?i[3579]|ryzen|xeon|pentium|celeron|athlon)' then 'cpu'
    else 'other'
  end;
