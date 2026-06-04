-- missed-dead probe — охота на МЁРТВОЕ, спрятавшееся в working/unknown (E1/E18).
-- Не вердикт, а ловушка: ищем разговорные сигналы неисправности, которых НЕТ в
-- словаре lot_condition. Результат смотрим глазами; что реально мёртвое — добавляем в функцию.
select condition, item_category, title, left(coalesce(description,''),220) d
from lots
where condition in ('working','unknown')
  and item_category in ('gpu','cpu','ram','mobo','ssd','psu')
  and translate(lower(coalesce(title,'')||' '||coalesce(description,'')),'aeopcxykmthb','аеорсхукмтнв')
      ~ 'сломан|сломал|битый|\yбьёт|глюч|глюк|перестал|погорел|выгорел|артефакт|полос[аиы]|полосит|зависа|вылета|синий экран|bsod|не пашет|\yтруп|мёртв|\yмертв|на детал|прогрев|перегрев|не определя|не грузит|чинил|ремонтир|восстановлен|троит'
order by condition, item_category;
