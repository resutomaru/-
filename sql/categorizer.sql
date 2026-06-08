-- Категоризатор item_category — v2.3 (АУДИТ 2026-06-08, приёмник).
-- База = v2.2 (git-канон; поведение подтверждено на живых данных — все протечки воспроизвелись).
-- Изменения относительно v2.2 (по NEW-1 из выборки + превью-раунд-1):
--   + 0a:  + райзер/riser → other (фикс «DeepCool … райзер для видеокарты»→gpu).
--   + НОВ. ветка охлаждения (СЖО/водоблок/башня/водяное) → other, ПЕРЕД gpu
--          (фикс «Водяное охлаждение PCCooler GT360M»→gpu через \ygt\d).
--          Исключения щадят видеокарты, комплекты и «+»-сборки (там охлаждение — часть товара),
--          но НЕ щадят «СЖО для Ryzen/LGA» (это кулер → other).
--   + ssd: бренд-токены xpg/evo/qvo теперь требуют рядом объём (gb/тб) — фикс «Simagic Alpha Evo»→ssd
--          и «БП adata xpg pylon 650»→ssd; + исключения карт памяти/флешек/БП
--          (фикс «Карта памяти Samsung EVO micro SD 512Gb»→ssd — медиано-яд для 512ГБ-бакета).
--   + psu: + «80+»/«80 plus» в триггер (фикс «Seasonic focus 80+ Gold»→other);
--          + мак/эпл-зарядки в исключение (фикс «блок питания для Macbook»→psu).
-- ВНИМАНИЕ: это правка ПО превью-раунду-1. Перед деплоем ПЕРЕ-снять превью-дифф (запрос в чате):
--   переезжать должен только мусор; ни одна реальная gpu/cpu/ram/mobo/ssd/psu не должна уйти в other.
-- Применяется ко всем строкам (без WHERE) — заодно категоризует ~160 новых строк с item_category=null (E16).
update lots set item_category =
  case
    when coalesce(title,'') ~* '(\yмыш|клавиатур|гарнитур|наушник|джойстик|геймпад|веб[- ]?камер|вебкамер|райзер|\yriser\y)' then 'other'
    when coalesce(title,'') ~* '^(радиатор|крепление|кулер|подставка|кабель|переходник|сумка|коврик|корпус)' then 'other'
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
