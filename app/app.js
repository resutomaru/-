// Перекуп-помощник — mini-app, пилон 1 (каркас + онбординг + me()).
// Тонкий клиент: вся логика на сервере (RPC). Auth — план Б: initData на КАЖДЫЙ вызов, токен не храним.
'use strict';

const tg = window.Telegram && window.Telegram.WebApp ? window.Telegram.WebApp : null;
const { SUPABASE_URL, ANON_KEY } = window.APP_CONFIG;

// ── утилиты экранов ──────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const SCREENS = ['loading','outside','onboarding','home','finds','journal','settings'];
function show(id){ SCREENS.forEach(s => $(s).classList.toggle('hidden', s !== id)); }

// ── единый вызов RPC (план Б: p_init_data = подпись Telegram) ────────────────
async function rpc(fn, params = {}){
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_init_data: tg ? tg.initData : '', ...params })
  });
  let env;
  try { env = await r.json(); } catch { throw new Error('Сервер недоступен'); }
  if (env && env.ok === false) throw new Error((env.error && env.error.msg) || 'Ошибка сервера');
  if (env && env.ok === true)  return env.data;
  return env;   // некоторые RPC (verify) могут вернуть голое значение
}

// ── авто-тема под Telegram ───────────────────────────────────────────────────
function applyTheme(){
  if (!tg) return;
  document.body.style.background = 'var(--bg)';
  if (tg.setHeaderColor)     try { tg.setHeaderColor('bg_color'); } catch {}
  if (tg.setBackgroundColor) try { tg.setBackgroundColor('bg_color'); } catch {}
}

// ── навигация по вкладкам ────────────────────────────────────────────────────
function initTabs(){
  $('tabs').classList.remove('hidden');
  document.querySelectorAll('.tab').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(b => b.classList.toggle('active', b === btn));
      show(btn.dataset.screen);
      if (tg && tg.HapticFeedback) try { tg.HapticFeedback.selectionChanged(); } catch {}
    });
  });
}

// ── дайджест: приветствие + KPI журнала ──────────────────────────────────────
const MONEY = (n) => (n == null ? '—' : new Intl.NumberFormat('ru-RU').format(n) + ' ₽');
function renderHome(me, dash){
  const name = (me && me.client && (me.client.display_name || me.client.client_id)) || 'перекуп';
  $('hello').textContent = `Привет, ${name}`;
  // defensive: показываем то, что реально пришло
  const d = dash || {};
  const cards = [
    { k: 'навар всего',  v: MONEY(d['навар_всего']), green: true },
    { k: 'сделок',       v: d['сделок_всего'] ?? 0 },
    { k: 'в наличии',    v: d['в_наличии'] ?? 0 },
    { k: 'продано',      v: d['продано'] ?? 0 },
  ];
  $('kpis').innerHTML = cards.map(c =>
    `<div class="kpi"><div class="v ${c.green?'green':''}">${c.v}</div><div class="k">${c.k}</div></div>`
  ).join('');
}

// ── онбординг по инвайт-коду ─────────────────────────────────────────────────
function initOnboarding(){
  $('redeemBtn').addEventListener('click', async () => {
    const code = $('code').value.trim();
    $('onbErr').textContent = '';
    if (!code) { $('onbErr').textContent = 'Введи код'; return; }
    $('redeemBtn').disabled = true;
    try {
      await rpc('redeem_invite', { p_code: code });
      await boot();                       // привязка прошла → перезагружаем как вошедшего
    } catch (e) {
      $('onbErr').textContent = friendly(e.message);
      $('redeemBtn').disabled = false;
    }
  });
}
function friendly(msg){
  if (/BAD_CODE/.test(msg))    return 'Код не найден.';
  if (/CODE_USED/.test(msg))   return 'Код уже использован.';
  if (/BAD_SIGNATURE/.test(msg))return 'Не удалось подтвердить Telegram-подпись.';
  if (/EXPIRED/.test(msg))     return 'Сессия устарела — переоткрой приложение.';
  return msg;
}

// ── загрузка: кто я? → дайджест | онбординг | вне-Telegram ────────────────────
async function boot(){
  show('loading');
  if (!tg || !tg.initData) { show('outside'); return; }     // открыто не из Telegram
  try {
    const me = await rpc('me');                              // подпись валидна И есть личность
    let dash = null;
    try { dash = await rpc('journal_dashboard'); } catch {}  // дашборд не критичен для входа
    renderHome(me, dash);
    initTabs();
    show('home');
  } catch (e) {
    if (/NOT_INVITED/.test(e.message)) { show('onboarding'); }   // подпись ок, но не приглашён
    else { $('onbErr').textContent = friendly(e.message); show('onboarding'); }
  }
}

// ── старт ────────────────────────────────────────────────────────────────────
if (tg) { tg.ready(); tg.expand && tg.expand(); applyTheme();
  tg.onEvent && tg.onEvent('themeChanged', applyTheme); }
initOnboarding();
boot();
