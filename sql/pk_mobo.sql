-- pk_mobo — канон (= развёрнуто). Ключ = чипсет, иначе сокет (грубо — намеренно, §4.2).
create or replace function public.pk_mobo(model text, title text)
 returns text language plpgsql immutable
as $$
declare s text; m text[];
begin
  s := translate(lower(coalesce(model,'')||' '||coalesce(title,'')),'хс','xc');
  m := regexp_match(s,'(a320|a520|a620|b350|b450|b550|b650|b840|b850|x370|x470|x570|x670|x870|x299|h110|b150|h170|z170|b250|h270|z270|h310|b360|h370|z370|b365|z390|h410|b460|h470|z490|h510|b560|h570|z590|h610|b660|h670|z690|b760|h770|z790|b860|z890|x79|x99|g31|g41|p43|p45|h55|h57|h61|b75|h77|z77|h81|b85|h87|z87|h97|z97|a55|a58|a68|a75|a78|a88|x38|x48|x58|p35|p55|p67|h67|z68|q67|760g|770|780g|785g|790fx|790x|870|880g|890fx|890gx|970|990fx|990x|945|965|975)');
  if m is not null then return m[1]; end if;
  m := regexp_match(s,'lga ?(2011|1700|1366|1200|1156|1155|1151|1150|775)');
  if m is not null then return 'lga'||m[1]; end if;
  if s ~ '\yam4\y' then return 'am4'; end if;
  if s ~ '\yam5\y' then return 'am5'; end if;
  if s ~ '\yam3\y' then return 'am3'; end if;
  if s ~ '\yam2\y' then return 'am2'; end if;
  if s ~ '\y775\y' then return 'lga775'; end if;
  if s ~ '\yfm2\y' then return 'fm2'; end if;
  if s ~ '\yfm1\y' then return 'fm1'; end if;
  return null;
end $$;
