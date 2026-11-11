// lwk_calloutcreator: the editor. Everything here is plain data (a "doc"); the server checks it, writes the callout's
// Lua and loads it into c3r. Opened in a normal browser (not the game) it runs on a stand-in server, to try the UI.
// The game's browser can't open a <select> or a <datalist>, so every dropdown and picker here is drawn by hand.
'use strict';

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'lwk_calloutcreator';

// ─── talking to the game ──────────────────────────────────────────────────────────────────────────────────────

async function post(name, data) {
  if (!IN_GAME) return MOCK.post(name, data);
  const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
  return r.json();
}
async function req(action, data) {
  const r = await post('req', { action, req: data || {} });
  if (!r || !r.ok) throw new Error(r && typeof r.data === 'string' ? r.data : 'The server said no.');
  return r.data;
}

// per-viewer conveniences (the mode, whether the guide's been seen): never needed, so a blocked store is fine
const store = {
  get(k) { try { return localStorage.getItem('lwk_cc_' + k); } catch (e) { return null; } },
  set(k, v) { try { localStorage.setItem('lwk_cc_' + k, v); } catch (e) { /* (not kept) */ } },
};

// ─── state ────────────────────────────────────────────────────────────────────────────────────────────────────

const S = { view: 'home', list: null, pack: null, res: null, file: null, doc: null, was: null, tab: 'callout', story: 0, stab: 'people',
  dirty: false, adv: store.get('adv') === '1', testStory: '' };
const OPEN = new WeakSet(); // the cards opened up (never saved into the doc)

// Lua turns an empty list into {} or []: these are always lists.
const LISTS = new Set(['reports', 'points', 'locations', 'qsets', 'questions', 'card', 'stories', 'people', 'vehicles', 'clues', 'objectives', 'rules',
  'presets', 'ifs', 'actions', 'lines', 'answers', 'deny', 'admit', 'again', 'yes', 'no', 'set', 'needs', 'items', 'pockets', 'facts', 'after', 'blip', 'keys',
  'packs', 'callouts', 'others', 'files']);
function norm(v, key) {
  if (Array.isArray(v)) return v.map((x) => norm(x));
  if (v && typeof v === 'object') {
    if (LISTS.has(key) && Object.keys(v).length === 0) return [];
    const o = {};
    for (const k of Object.keys(v)) o[k] = norm(v[k], k);
    return o;
  }
  if (LISTS.has(key) && (v === undefined || v === null)) return [];
  return v;
}
const arr = (x) => (Array.isArray(x) ? x : []);
const clone = (x) => JSON.parse(JSON.stringify(x));
const ident = (s) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s || '');
const slug = (s) => (s || '').toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '').replace(/^(\d)/, '_$1').slice(0, 40);
const asFact = (s) => { s = slug(s); return s && !s.startsWith('c_') ? 'c_' + s : s; };
function unique(base, taken) {
  base = slug(base) || 'item';
  let id = base, n = 1;
  while (taken.includes(id)) id = base + ++n;
  return id;
}
const A = (el) => (S.adv ? el : null); // only in Advanced

// ─── building the page ────────────────────────────────────────────────────────────────────────────────────────

function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat(Infinity)) if (c !== null && c !== undefined && c !== false) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
}
const btn = (label, fn, cls, title) => h('button', { class: 'btn ' + (cls || ''), onclick: fn, title, type: 'button' }, label);
const icon = (label, fn, title) => h('button', { class: 'icon', onclick: (e) => { e.stopPropagation(); fn(); }, title, 'aria-label': title, type: 'button' }, label);
const help = (text) => h('p', { class: 'help' }, text);

function toast(text, bad, list) {
  const t = h('div', { class: 'toast' + (bad ? ' bad' : ''), role: 'status' }, text, list && list.length ? h('ul', {}, list.slice(0, 12).map((x) => h('li', {}, x))) : null);
  document.getElementById('toasts').append(t);
  setTimeout(() => t.remove(), bad ? 9000 : 4000);
}

function modal(title, body, actions, wide) {
  const m = document.getElementById('modal');
  closePop();
  m.innerHTML = '';
  const close = () => { m.hidden = true; m.innerHTML = ''; };
  m.append(h('div', { class: 'box' + (wide ? ' wide' : ''), role: 'dialog', 'aria-modal': 'true', 'aria-label': title }, h('h2', {}, title), body,
    h('div', { class: 'actions' }, actions.map(([label, fn, cls]) => btn(label, async () => { if ((await fn()) !== false) close(); }, cls)))));
  m.hidden = false;
  const first = m.querySelector('input, textarea, .dd, button');
  if (first) first.focus();
  return close;
}
const ask = (title, text, yes, cls) => new Promise((done) => modal(title, h('p', {}, text), [['Cancel', () => done(false)], [yes, () => done(true), cls || 'go']]));

let checkTimer = null;
function changed(rerender) {
  S.dirty = true;
  if (rerender) render();
  else { clearTimeout(checkTimer); checkTimer = setTimeout(renderTop, 400); }
}

function render() {
  closePop();
  const main = document.getElementById('main');
  const y = main.scrollTop;
  main.innerHTML = '';
  renderTop();
  main.append(S.view === 'home' ? home() : editor());
  main.scrollTop = y;
}

// ─── dropdowns and pickers (drawn here: the game's browser can't open <select> or <datalist>) ─────────────────

let POP = null; // { el, anchor }
function closePop() {
  if (!POP) return;
  POP.el.remove();
  if (POP.anchor) POP.anchor.setAttribute('aria-expanded', 'false');
  POP = null;
}
document.addEventListener('mousedown', (e) => { if (POP && !POP.el.contains(e.target) && !(POP.anchor && POP.anchor.contains(e.target))) closePop(); });
window.addEventListener('resize', closePop);

// A list under `anchor`: items = [[value, label, note?]]. filterInput: an input that already filters it (a picker), or
// none (a search box is added when the list is long). pick(value).
function openPop(anchor, items, cur, pick, filterInput) {
  closePop();
  const el = h('div', { class: 'pop', role: 'listbox' });
  const search = !filterInput && items.length > 9 ? h('input', { type: 'text', class: 'popsearch', placeholder: 'Search...', 'aria-label': 'Search' }) : null;
  const list = h('div', { class: 'popitems' });
  if (search) el.append(search);
  el.append(list);
  let shown = [], at = -1;
  const fill = () => {
    const q = ((search || filterInput || {}).value || '').toLowerCase();
    shown = items.filter(([v, l, n]) => !q || String(v).toLowerCase().includes(q) || String(l).toLowerCase().includes(q) || (n && n.toLowerCase().includes(q)));
    list.innerHTML = '';
    at = Math.max(0, shown.findIndex(([v]) => String(v) === String(cur)));
    if (filterInput) at = shown.length ? 0 : -1;
    shown.forEach(([v, l, n], i) => list.append(h('div', { class: 'opt' + (i === at ? ' at' : '') + (String(v) === String(cur) ? ' cur' : ''), role: 'option',
      'aria-selected': String(v) === String(cur) ? 'true' : 'false', onmousedown: (e) => { e.preventDefault(); closePop(); pick(v); } }, l, n ? h('span', { class: 'note' }, n) : null)));
    if (!shown.length) list.append(h('div', { class: 'opt empty' }, filterInput ? 'No match: what you typed is used as it is.' : 'Nothing here.'));
    const a = list.children[at];
    if (a && a.scrollIntoView) a.scrollIntoView({ block: 'nearest' });
  };
  const move = (d) => {
    if (!shown.length) return;
    at = (at + d + shown.length) % shown.length;
    [...list.children].forEach((c, i) => c.classList.toggle('at', i === at));
    list.children[at].scrollIntoView({ block: 'nearest' });
  };
  const key = (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
    else if (e.key === 'Enter' && shown[at]) { e.preventDefault(); const v = shown[at][0]; closePop(); pick(v); }
    else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closePop(); anchor.focus(); }
  };
  (search || filterInput || el).addEventListener('keydown', key);
  if (search) search.addEventListener('input', fill);
  document.body.append(el);
  const r = anchor.getBoundingClientRect();
  const below = window.innerHeight - r.bottom;
  el.style.left = Math.min(r.left, window.innerWidth - Math.max(r.width, 220) - 8) + 'px';
  el.style.minWidth = r.width + 'px';
  if (below < 260 && r.top > below) { el.style.bottom = (window.innerHeight - r.top + 4) + 'px'; el.style.maxHeight = Math.min(320, r.top - 12) + 'px'; }
  else { el.style.top = (r.bottom + 4) + 'px'; el.style.maxHeight = Math.min(320, below - 12) + 'px'; }
  POP = { el, anchor, fill, top: r.top };
  anchor.setAttribute('aria-expanded', 'true');
  fill();
  if (search) search.focus();
  return POP;
}
// (a scroll that moves what it hangs from closes it; re-setting the same scroll position doesn't)
document.addEventListener('scroll', (e) => {
  if (POP && !POP.el.contains(e.target) && Math.abs(POP.anchor.getBoundingClientRect().top - POP.top) > 2) closePop();
}, true);

// A dropdown: items [[value, label]]; pick(value).
function dropdown(items, cur, pick, label) {
  const found = items.find(([v]) => String(v) === String(cur ?? ''));
  const text = found ? found[1] : cur ? `${cur} (not there)` : '(pick one)';
  const b = h('button', { type: 'button', class: 'dd' + (found ? '' : ' none'), 'aria-haspopup': 'listbox', 'aria-expanded': 'false', 'aria-label': label,
    onclick: () => (POP && POP.anchor === b ? closePop() : openPop(b, items, cur ?? '', pick)),
    onkeydown: (e) => { if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openPop(b, items, cur ?? '', pick); } } },
  h('span', { class: 'ddtext' }, text), h('span', { class: 'caret', 'aria-hidden': 'true' }, '▾'));
  return b;
}

// A text box with suggestions: anything can be typed; the list narrows as you type. set(value, done).
function picker(value, items, set, placeholder) {
  const input = h('input', { type: 'text', value: value || '', placeholder: placeholder || '', spellcheck: 'false', autocomplete: 'off', role: 'combobox',
    'aria-expanded': 'false', 'aria-autocomplete': 'list' });
  const show = () => openPop(input, items, input.value, (v) => { input.value = v; set(v, true); }, input);
  input.addEventListener('focus', show);
  input.addEventListener('input', () => { set(input.value, false); if (POP && POP.anchor === input) POP.fill(); else show(); });
  input.addEventListener('change', () => set(input.value, true));
  const toggle = h('button', { type: 'button', class: 'ddbtn', 'aria-label': 'Show the list', tabindex: '-1',
    onclick: () => { if (POP && POP.anchor === input) closePop(); else { input.focus(); } } }, '▾');
  return h('div', { class: 'pick' }, input, toggle);
}

// ─── form fields ──────────────────────────────────────────────────────────────────────────────────────────────

// What a dropdown can offer, from the doc and the story being edited (ctx).
function options(type, ctx) {
  const d = S.doc, st = ctx && ctx.story;
  const opt = type.endsWith('?');
  const base = type.replace('?', '');
  let list = [];
  if (base === 'point') list = arr(d.points).map((p) => [p.name, p.name, p.text]);
  else if (base === 'person') list = arr(st && st.people).map((p) => [p.key, p.label || p.key, p.key]);
  else if (base === 'car') list = arr(st && st.vehicles).map((v) => [v.key, [v.color, v.make, v.name].filter(Boolean).join(' ') || v.model || v.key, v.key]);
  else if (base === 'clue') list = arr(st && st.clues).map((c) => [c.key, c.label || c.key, c.key]);
  else if (base === 'objective') list = objectivesOf(st).map((o) => [o.id, o.text || o.id, o.id]);
  else if (base === 'objective+clue') list = objectivesOf(st).map((o) => [o.id, o.text || o.id, 'objective']).concat(arr(st && st.clues).map((c) => [c.key, c.label || c.key, 'clue']));
  else if (base === 'story') list = arr(d.stories).map((s) => [s.id, s.id]);
  else if (base === 'qset') list = arr(d.qsets).map((q) => [q.id, q.id]);
  else if (base === 'question') list = questionsOf(st, ctx && ctx.who);
  return (opt || base === 'qset' ? [['', '(none)']] : []).concat(list);
}
function objectivesOf(st) { return arr(S.doc.card).concat(arr(st && st.objectives)); }
function qsetOf(p) { return arr(S.doc.qsets).find((q) => q.id === p.qset) || null; }
function questionsOf(st, who) {
  const p = arr(st && st.people).find((x) => x.key === who);
  const out = [];
  const qs = p ? arr((qsetOf(p) || {}).questions).concat(arr(p.questions)) : [];
  for (const q of qs) out.push([q.id, q.label || q.id, q.id]);
  if (!p) for (const s of arr(S.doc.qsets)) for (const q of arr(s.questions)) out.push([q.id, q.label || q.id, q.id]);
  for (const [id, label] of USUAL_Q) out.push([id, label, 'usual question']);
  return out;
}
function allFacts() {
  const found = new Set();
  JSON.stringify(S.doc, (k, v) => { if (typeof v === 'string' && /^c_[a-z0-9_]+$/i.test(v) && (k === 'fact' || k === 'id' || k === 'q')) found.add(v); return v; });
  return [...found].sort().map((f) => [f, f]);
}

// One field bound to obj[key]. type: text, long, num, bool, id, fact, sel (opts), point, person, car, clue, objective,
// question, qset, story, things, objectives, points, asset:<kind> (most with ? for "may be empty").
function field(obj, key, label, type, opts, ctx) {
  const wrap = (input, cls) => h('label', { class: 'f ' + (cls || '') }, h('span', {}, label), input);
  const set = (v, re) => { obj[key] = v; changed(re); };
  const cur = obj[key];
  if (type === 'bool') {
    return h('label', { class: 'f check' }, h('input', { type: 'checkbox', checked: cur === true, onchange: (e) => set(e.target.checked, true) }), h('span', {}, label));
  }
  if (type === 'num') {
    return wrap(h('input', { type: 'number', value: cur ?? '', placeholder: opts || '', onchange: (e) => set(e.target.value === '' ? undefined : Number(e.target.value), false) }));
  }
  if (type === 'long') return wrap(h('textarea', { oninput: (e) => set(e.target.value), rows: 2, placeholder: opts || '' }, cur || ''), 'wide');
  if (type === 'text' || type === 'id') {
    const fix = type === 'id' ? slug : (x) => x;
    return wrap(h('input', { type: 'text', value: cur || '', placeholder: opts || '', spellcheck: type === 'text' ? 'true' : 'false',
      oninput: (e) => { obj[key] = e.target.value; changed(false); },
      onchange: (e) => { const v = fix(e.target.value); e.target.value = v; set(v, type !== 'text'); } }));
  }
  if (type === 'fact') {
    return h('div', { class: 'f' }, h('span', {}, label), picker(cur, allFacts(), (v, done) => { obj[key] = done ? asFact(v) : v; changed(done); }, opts || 'c_something'));
  }
  if (type.startsWith('asset:')) {
    const kind = type.slice(6);
    return h('div', { class: 'f' }, h('span', {}, label), h('div', { class: 'withbtn' },
      picker(cur, (ASSETS[kind] || []).map((x) => [x, x]), (v, done) => { obj[key] = v.trim(); changed(false); }, opts || 'Type or pick a name'),
      btn('Preview', () => preview({ kind, name: obj[key] || '' }), 'small', 'See it in game, in front of you')));
  }
  if (type === 'things' || type === 'objectives' || type === 'points') {
    const st = ctx && ctx.story;
    let all;
    if (type === 'things') all = arr(st && st.people).map((p) => [p.key, p.label || p.key]).concat(arr(st && st.vehicles).map((v) => [v.key, v.name || v.key]), arr(st && st.clues).map((c) => [c.key, c.label || c.key]));
    else if (type === 'points') all = arr(S.doc.points).map((p) => [p.name, p.name]);
    else all = objectivesOf(st).filter((o) => o.id !== (ctx && ctx.self)).map((o) => [o.id, o.text || o.id]);
    const cur2 = arr(cur);
    return wrap(h('div', { class: 'chips' }, all.length ? all.map(([k, l]) => h('button', { type: 'button', class: 'chip' + (cur2.includes(k) ? ' on' : ''),
      'aria-pressed': cur2.includes(k) ? 'true' : 'false',
      onclick: () => { obj[key] = cur2.includes(k) ? cur2.filter((x) => x !== k) : cur2.concat(k); changed(true); } }, l)) : h('span', { class: 'muted' }, 'None yet.')), 'wide');
  }
  const list = type === 'sel' ? opts : options(type, ctx);
  return h('div', { class: 'f' }, h('span', {}, label), dropdown(list.map((x) => [x[0], x[1], x[2]]), cur, (v) => set(v, true), label));
}

// A list of things, each a card that opens. make() -> a new item; title(item) -> its header.
function cards(list, title, body, make, addLabel, opts) {
  opts = opts || {};
  const out = h('div', {});
  list.forEach((item, i) => {
    const open = OPEN.has(item);
    const head = h('div', { class: 'head', onclick: () => { open ? OPEN.delete(item) : OPEN.add(item); render(); }, role: 'button', tabindex: '0',
      'aria-expanded': open ? 'true' : 'false', onkeydown: (e) => { if (e.target === head && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); head.click(); } } },
      h('span', { class: 'tw', 'aria-hidden': 'true' }, open ? '▾' : '▸'), h('div', { class: 't' }, title(item, i)),
      A(i > 0 ? icon('↑', () => { list.splice(i - 1, 0, list.splice(i, 1)[0]); changed(true); }, 'Move up') : null),
      A(i < list.length - 1 ? icon('↓', () => { list.splice(i + 1, 0, list.splice(i, 1)[0]); changed(true); }, 'Move down') : null),
      opts.copy ? icon('⧉', () => { const c = opts.copy(item); list.splice(i + 1, 0, c); OPEN.add(c); changed(true); }, 'Copy') : null,
      icon('✕', () => { list.splice(i, 1); changed(true); }, 'Delete'));
    out.append(h('div', { class: 'card' + (open ? ' open' : '') }, head, open ? h('div', { class: 'body' }, body(item, i)) : null));
  });
  if (make) out.append(btn('+ ' + addLabel, () => { const x = make(); list.push(x); OPEN.add(x); changed(true); }, 'small add'));
  return out;
}

function strings(list, placeholder, addLabel, long) {
  return h('div', {}, list.map((s, i) => h('div', { class: 'row' },
    h('div', { class: 'grow' }, long ? h('textarea', { rows: 2, placeholder, oninput: (e) => { list[i] = e.target.value; changed(false); } }, s)
      : h('input', { type: 'text', value: s, placeholder, oninput: (e) => { list[i] = e.target.value; changed(false); } })),
    icon('✕', () => { list.splice(i, 1); changed(true); }, 'Delete'))),
  btn('+ ' + addLabel, () => { list.push(''); changed(true); }, 'small add'));
}

function factPairs(list, addLabel, valueLabel) {
  return h('div', {}, list.map((p, i) => h('div', { class: 'row' },
    h('div', { class: 'grow grid' }, field(p, 'fact', 'Fact', 'fact'), field(p, 'value', valueLabel || 'Value (empty: yes)', 'text')),
    icon('✕', () => { list.splice(i, 1); changed(true); }, 'Delete'))),
  btn('+ ' + addLabel, () => { list.push({ fact: '', value: '' }); changed(true); }, 'small add'));
}

// What someone says: answers (one is picked at random), each maybe giving a fact away.
function answers(list, addLabel, placeholder) {
  if (!list.length) list.push({ text: '', set: [] });
  return h('div', { class: 'answers' }, list.map((a, i) => h('div', { class: 'answer' },
    h('div', { class: 'row' }, h('textarea', { class: 'grow', rows: 2, placeholder: placeholder || 'What they say', 'aria-label': 'What they say',
      oninput: (e) => { a.text = e.target.value; changed(false); } }, a.text || ''), list.length > 1 ? icon('✕', () => { list.splice(i, 1); changed(true); }, 'Delete this answer') : null),
    arr(a.set).length ? h('div', { class: 'gives' }, h('span', { class: 'muted' }, 'Saying it gives away:'), factPairs(a.set = arr(a.set), 'Another fact'))
      : A(btn('+ Gives away a fact', () => { a.set = [{ fact: '', value: '' }]; changed(true); }, 'small link')))),
  btn('+ ' + (addLabel || 'Another way to say it'), () => { list.push({ text: '', set: [] }); changed(true); }, 'small link'));
}

// ─── home: the packs ──────────────────────────────────────────────────────────────────────────────────────────

function modeSwitch() {
  return h('div', { class: 'seg', role: 'group', 'aria-label': 'Editor mode' },
    [['Simple', false], ['Advanced', true]].map(([l, v]) => h('button', { type: 'button', class: S.adv === v ? 'on' : '', 'aria-pressed': S.adv === v ? 'true' : 'false',
      title: v ? 'Every option' : 'The options most callouts need', onclick: () => { S.adv = v; store.set('adv', v ? '1' : '0'); if (!v && S.tab === 'questions') S.tab = 'people'; render(); } }, l)));
}

function renderTop() {
  const top = document.getElementById('top');
  top.innerHTML = '';
  if (S.view === 'home') {
    top.append(h('div', {}, h('h1', {}, 'Callout Creator'), h('div', { class: 'sub' }, 'CODE3RESPONSE callouts, made without code')), h('div', { class: 'grow' }),
      modeSwitch(), btn('Guide', guide), btn('New pack', () => packForm()), btn('Close', closeAll));
    return;
  }
  const d = S.doc;
  const bad = checks(d).filter((x) => x.level === 'bad').length;
  const stories = [['', 'Any story']].concat(arr(d.stories).map((s) => [s.id, s.id]));
  if (!stories.some(([v]) => v === S.testStory)) S.testStory = '';
  top.append(...[icon('←', back, 'Back to the packs'),
    h('div', { class: 'title' }, h('h1', {}, d.name || 'Untitled'), h('div', { class: 'sub' }, `${S.res ? S.res : 'Pack ' + S.pack} · ${d.id}${S.dirty ? ' · not saved' : ''}`)),
    h('div', { class: 'grow' }), bad ? h('button', { type: 'button', class: 'tag bad', onclick: () => { S.tab = 'checks'; render(); } }, `${bad} to fix`) : null,
    modeSwitch(), btn('Guide', guide), btn('Save', () => save(false), 'go'),
    h('div', { class: 'testgrp' }, dropdown(stories, S.testStory, (v) => { S.testStory = v; renderTop(); }, 'Story to test'), btn('Test', test, '', 'Save, then start this call near you'))].filter(Boolean));
}

function home() {
  const L = S.list;
  if (!L) return h('p', { class: 'muted' }, 'Loading...');
  const out = h('div', { class: 'packs' });
  if (!L.c3r) out.append(h('p', { class: 'tag bad' }, 'c3r is not running: callouts save, but nothing loads or tests until it is.'));
  out.append(help('A pack is a set of callouts. Make one, add callouts to it, Test them in game, then Export the pack to share it: it runs on any c3r server, with or without the creator.'));
  for (const p of arr(L.packs)) {
    out.append(h('div', { class: 'card flat pack' },
      h('div', { class: 'head' }, h('div', { class: 't' }, h('b', {}, p.name), h('span', { class: 'muted' }, [p.version, p.author && 'by ' + p.author].filter(Boolean).join(' · '))),
        btn('+ Callout', () => newCallout(p.id), 'small go'), btn('Edit', () => packForm(p), 'small'), btn('Export', () => exportPack(p), 'small', 'Write it out as a resource to share'),
        p.callouts.length ? null : icon('✕', () => dropPack(p), 'Delete the pack')),
      p.description ? h('p', { class: 'help pad' }, p.description) : null,
      arr(p.callouts).map((c) => h('div', { class: 'callout' }, h('div', { class: 't' }, h('b', {}, c.name), h('span', { class: 'muted mono' }, ' ' + c.id),
        h('span', { class: 'tag' }, `${c.stories} stor${c.stories === 1 ? 'y' : 'ies'}`), h('span', { class: 'tag' + (c.locations ? '' : ' warn') }, `${c.locations} location${c.locations === 1 ? '' : 's'}`),
        c.loaded ? h('span', { class: 'tag ok' }, 'loaded') : h('span', { class: 'tag warn' }, 'not loaded'), c.edited ? h('span', { class: 'tag warn' }, 'edited by hand') : null),
      btn('Open', () => open({ pack: p.id, id: c.id }), 'small'), btn('Test', () => testFrom({ pack: p.id, id: c.id }), 'small'),
      icon('✕', () => deleteCallout(p, c), 'Delete the callout'))),
      p.callouts.length ? null : h('p', { class: 'help pad' }, 'No callouts yet: press + Callout.')));
  }
  if (arr(L.others).length) {
    out.append(h('h2', {}, 'Packs other resources carry'), help('Running packs with c3r_callout lines in their fxmanifest. Callouts made with the creator can be edited where they are.'));
    for (const o of L.others) {
      out.append(h('div', { class: 'card flat pack' }, h('div', { class: 'head' }, h('div', { class: 't' }, h('b', {}, o.res), h('span', { class: 'muted' }, [o.version, o.author && 'by ' + o.author].filter(Boolean).join(' · ')))),
        arr(o.files).map((f) => h('div', { class: 'callout' }, h('div', { class: 't' }, h('b', {}, f.name || f.file), h('span', { class: 'muted mono' }, ' ' + f.file),
          f.loaded ? h('span', { class: 'tag ok' }, 'loaded') : h('span', { class: 'tag warn' }, 'not loaded'), f.made ? null : h('span', { class: 'tag' }, 'hand-written'),
          f.edited && f.made ? h('span', { class: 'tag warn' }, 'edited by hand') : null),
        f.made ? btn('Open', () => open({ res: o.res, file: f.file }), 'small') : null, f.made ? btn('Test', () => testFrom({ res: o.res, file: f.file }), 'small') : null))));
    }
  }
  return out;
}

async function refresh() {
  try { S.list = norm(await req('list')); } catch (e) { toast(e.message, true); }
  render();
}

function packForm(p) {
  const m = { name: '', author: '', version: '1.0.0', description: '', licence: '' };
  if (p) for (const k of Object.keys(m)) m[k] = p[k] || '';
  const was = S.dirty;
  const body = h('div', { class: 'grid' }, field(m, 'name', 'Name', 'text'), field(m, 'author', 'Author', 'text'), field(m, 'version', 'Version', 'text'),
    field(m, 'licence', 'Licence (yours to choose)', 'text', 'e.g. CC BY-NC-SA 4.0'), field(m, 'description', 'What it is', 'long'));
  modal(p ? 'Edit pack' : 'New pack', body, [['Cancel', () => { S.dirty = was; }], [p ? 'Save' : 'Make it', async () => {
    try { await req('pack', { pack: p && p.id, meta: m }); } catch (e) { toast(e.message, true); return false; }
    S.dirty = was;
    refresh();
  }, 'go']]);
}

async function dropPack(p) {
  if (!(await ask('Delete pack', `Delete the empty pack "${p.name}"?`, 'Delete', 'bad'))) return;
  try { await req('droppack', { pack: p.id }); } catch (e) { toast(e.message, true); }
  refresh();
}

async function deleteCallout(p, c) {
  if (!(await ask('Delete callout', `Delete "${c.name}" from ${p.name}? It stops being offered at once, and can't be brought back here.`, 'Delete', 'bad'))) return;
  try { await req('delete', { pack: p.id, id: c.id }); toast('Deleted.'); } catch (e) { toast(e.message, true); }
  refresh();
}

async function exportPack(p) {
  try {
    const r = await req('export', { pack: p.id });
    modal('Exported', h('div', {}, h('p', {}, 'Written to:'), h('p', { class: 'mono' }, r.path),
      help(`Copy the ${r.name} folder into any c3r server's resources and add "ensure ${r.name}" after c3r. Nothing else is needed.`)), [['OK', () => {}, 'go']]);
  } catch (e) { toast(e.message, true); }
}

// ─── a callout ────────────────────────────────────────────────────────────────────────────────────────────────

function newStory(id, d) {
  const first = arr(d && d.points)[0];
  const at = first ? first.name : 'caller';
  return { id, weight: 1, needs: [],
    people: [{ key: 'caller', at, label: 'Caller', sex: 'random', qset: arr(d && d.qsets)[0] ? d.qsets[0].id : '', scene: { kind: 'scenario', name: 'WORLD_HUMAN_STAND_IMPATIENT' },
      lines: [], questions: [], items: [], pockets: [], facts: [] }],
    vehicles: [], clues: [], objectives: [],
    rules: [{ when: { event: 'ask', who: 'caller', q: 'c_what' }, ifs: [], actions: [{ kind: 'done', id: 'caller' }] }],
    presets: [], ending: { mode: 'heard', heard: 'caller', subject: '', decide: '', left: 15, lines: {} } };
}
function newDoc(id) {
  const d = { v: 1, id, name: 'New callout', priority: 2, weight: 1, enabled: true, service: 'police', alert: '',
    reports: [''], points: [{ name: 'caller', text: 'The caller, where they wait for police.', car: false, optional: false }], locations: [],
    qsets: [{ id: 'caller', questions: [{ id: 'c_what', label: 'What happened?', needs: [] }] }],
    card: [{ id: 'caller', text: 'Talk to the caller', hint: 'They called it in.', who: 'one', after: [], blip: ['caller'] }], stories: [] };
  d.stories.push(newStory('main', d));
  return d;
}

async function guard() { return !S.dirty || ask('Not saved', 'Leave without saving your changes?', 'Leave', 'bad'); }

// c3r's own callouts, as starting points (nui/templates.js, made by tools/make_templates.lua)
const TPL = typeof TEMPLATES !== 'undefined' ? TEMPLATES : [];

function newCallout(pack) {
  const taken = arr(S.list && S.list.packs).flatMap((p) => p.callouts.map((c) => c.id));
  const m = { name: '', from: '' };
  const body = () => {
    const t = TPL.find((x) => x.id === m.from);
    return h('div', {}, help('Start blank, or from one of CODE3RESPONSE\'s own callouts: its reports, places, people and what they say, cars, clues and card come with it, to change into your own.'),
      h('div', { class: 'grid' },
        h('div', { class: 'f wide' }, h('span', {}, 'Start from'), dropdown([['', 'A blank callout', 'a caller, one story']].concat(TPL.map((x) => [x.id, x.name, `${x.stories} stories`])),
          m.from, (v) => { m.from = v; again(); }, 'Start from')),
        field(m, 'name', 'Name (on the offer and the card)', 'text', t ? t.name + ' (my version)' : 'e.g. Shoplifting')),
      t ? help(`${t.name} has ${t.stories} stories. Its special scenes (fights, chases, tow trucks...) are code, so they don't come with it: the creator adds its standard rules, and you add Action scenes where you want them.`) : null);
  };
  const again = () => { const box = document.querySelector('#modal .box'); box.replaceChild(body(), box.children[1]); };
  modal('New callout', body(), [['Cancel', () => {}],
    ['Make it', () => {
      const t = TPL.find((x) => x.id === m.from);
      const name = (m.name || '').trim() || (t ? t.name + ' (my version)' : 'New callout');
      let id = unique(name, taken);
      if (id.startsWith('c_')) id = 'x' + id;
      const d = t ? norm(clone(t.doc)) : newDoc(id);
      d.id = id;
      d.name = name;
      Object.assign(S, { view: 'edit', pack, res: null, file: null, doc: d, was: null, tab: 'callout', story: 0, stab: 'people', dirty: true });
      if (t) {
        const n = fixAll(d);
        toast(`Started from ${t.name}. ${n} standard rule${n === 1 ? '' : 's'} and fixes added: look them over in each story's Rules.`);
      }
      render();
    }, 'go']]);
}

async function open(where) {
  try {
    const r = norm(await req('open', where));
    Object.assign(S, { view: 'edit', pack: where.pack || null, res: r.res || null, file: r.file || null, doc: norm(r.doc), was: r.doc.id, tab: 'callout', story: 0, stab: 'people', dirty: false });
    for (const k of ['reports', 'points', 'locations', 'qsets', 'card', 'stories']) S.doc[k] = arr(S.doc[k]);
    render();
    if (r.edited) toast('This file has been edited by hand since the creator saved it. Saving here will overwrite those changes.', true);
  } catch (e) { toast(e.message, true); }
}

async function back() {
  if (!(await guard())) return;
  Object.assign(S, { view: 'home', doc: null, dirty: false });
  refresh();
}

async function save(force) {
  const d = S.doc;
  try {
    const r = await req('save', { pack: S.pack, res: S.res, file: S.file, was: S.was, doc: d, force });
    if (r.errors) { toast('Not saved. Fix these first:', true, r.errors); return false; }
    if (r.edited) {
      if (await ask('Edited by hand', 'Someone has changed this callout\'s file by hand since the creator saved it. Saving overwrites their changes.', 'Overwrite', 'bad')) return save(true);
      return false;
    }
    S.was = d.id;
    S.dirty = false;
    if (r.loaded) toast('Saved, and loaded into c3r.');
    else toast('Saved, but c3r did not load it: ' + (r.why || 'see the server console.'), true);
    renderTop();
    return true;
  } catch (e) { toast(e.message, true); return false; }
}

async function test() {
  if (S.dirty && !(await save(false))) return;
  testFrom({ pack: S.pack, res: S.res, file: S.file, id: S.doc.id, story: S.testStory });
}
async function testFrom(where) {
  try {
    await req('test', where);
    toast('Call started near you.');
    closeAll(true);
  } catch (e) { toast(e.message, true); }
}

async function closeAll(keep) {
  if (keep !== true && S.view === 'edit' && !(await guard())) return;
  post('close');
}

async function hear(name) {
  if (!name) return toast("Type the clip's name first.", true);
  const r = await post('hear', { name });
  if (!r || !r.ok) toast(r && r.why ? r.why : `No clip called ${name}: looked for lwk_control_assets/nui/voice/${name}_1.ogg.`, true);
}

async function preview(d) {
  const r = await post('preview', d);
  if (!r || !r.ok) toast(`"${d.name || d.dict || 'that'}" isn't in the game${r && r.why ? ': ' + r.why : '.'} Check the name.`, true);
}

// ─── the editor ───────────────────────────────────────────────────────────────────────────────────────────────

function tabsNow() {
  return [['callout', '1. Basics'], ['points', '2. Places'], ['card', '3. Opening card'], ['stories', '4. Stories'], S.adv ? ['questions', 'Question lists'] : null,
    ['checks', 'Check']].filter(Boolean);
}

function editor() {
  const issues = checks(S.doc);
  if (!tabsNow().some(([id]) => id === S.tab)) S.tab = 'callout';
  const n = issues.filter((x) => x.level !== 'tip').length;
  const out = h('div', {});
  out.append(h('nav', { class: 'tabs', 'aria-label': 'Sections' }, tabsNow().map(([id, label]) => h('button', { type: 'button', class: S.tab === id ? 'on' : '',
    'aria-current': S.tab === id ? 'page' : null, onclick: () => { S.tab = id; render(); } }, label,
    id === 'checks' && n ? h('span', { class: 'count' }, n) : null))));
  out.append(({ callout: tabCallout, points: tabPoints, questions: tabQuestions, card: tabCard, stories: tabStories, checks: () => tabChecks(issues) })[S.tab]());
  return out;
}

function tabCallout() {
  const d = S.doc;
  return h('div', {},
    help('The call as dispatch puts it out. Then: where it happens (Places), the card officers start with, and the stories behind it.'),
    h('div', { class: 'grid' }, field(d, 'name', 'Name (on the offer and the card)', 'text'),
      field(d, 'priority', 'Priority', 'sel', [['1', '1: urgent'], ['2', '2: normal'], ['3', '3: routine']]),
      A(field(d, 'id', 'Id (/requestcall uses it)', 'id')),
      A(field(d, 'weight', 'How often it comes up (weight)', 'num', '1')),
      A(field(d, 'service', 'Who it\'s for', 'sel', [['police', 'Police'], ['ambulance', 'Medics (Ambulance service)']])),
      A(field(d, 'alert', 'Alert line (empty: "Incoming 911 call")', 'text')),
      field(d, 'enabled', 'Dispatch offers it by itself (off: only by Test or /requestcall)', 'bool')),
    h('h2', {}, 'What dispatch says'),
    h('div', { class: 'grid' }, h('div', { class: 'f wide' }, h('span', {}, "Dispatcher's voice line (empty: 'Incoming 911 call')"),
      h('div', { class: 'withbtn' }, h('input', { type: 'text', value: d.voice || '', placeholder: 'e.g. call_robbery, or custom/call_bridge', spellcheck: 'false',
        oninput: (e) => { d.voice = e.target.value.trim(); changed(false); } }), btn('Hear it', () => hear(d.voice), 'small')))),
    help("A clip's name. Your own go in lwk_control_assets/nui/voice/custom/ as call_bridge_1.ogg (more as _2, _3: one is picked at random), and dispatch follows it with: Your call is at, and the street. Or record call_bridge_to_1.ogg too, ending as it leads into the street (...on the bridge, at), and dispatch says the street straight after it. Then type custom/call_bridge. Setup keeps that folder when it updates."),
    h('h2', {}, 'What the caller says'),
    help('One of these is read out with the call. Every story shares them, so the report never gives the truth away.'),
    strings(d.reports, 'e.g. Store clerk reports a man left without paying.', 'Another way the caller might say it', true));
}

function tabPoints() {
  const d = S.doc;
  return h('div', {},
    h('h2', {}, 'Points'), help('The spots a location needs: where each person stands, where a car is parked, where a clue lies. The first is where the call is.'),
    cards(d.points, (p, i) => [h('b', {}, p.name), h('span', { class: 'muted' }, (i === 0 ? 'the scene · ' : '') + (p.car ? 'a car · ' : '') + (p.optional ? 'optional · ' : '') + (p.text || ''))],
      (p, i) => h('div', { class: 'grid' }, field(p, 'name', 'Name', 'id'), field(p, 'text', 'Where to stand, for whoever places it', 'long'),
        field(p, 'car', 'A car is parked here (sit in it to place it)', 'bool'), A(i > 0 ? field(p, 'optional', 'Optional (can be skipped at a location)', 'bool') : null)),
      () => ({ name: unique('point', d.points.map((p) => p.name)), text: '', car: false, optional: false }), 'Point'),
    h('h2', {}, 'Locations'), help('Each location is the points walked out somewhere on the map. Place a few: each call happens at one near the officer. You stand on each point in game and press E.'),
    d.locations.map((l, i) => h('div', { class: 'card flat' }, h('div', { class: 'head' }, h('div', { class: 't' }, h('b', {}, `${i + 1}. ${l.street || 'Unknown'}`),
      h('span', { class: 'muted' }, `${Object.keys(l.points || {}).length} of ${d.points.length} points`)),
    btn('Go there', () => { const f = l.points && l.points[d.points[0] && d.points[0].name]; if (f) post('goto', { at: f }); }, 'small'),
    btn('Place again', () => place(i), 'small'), icon('✕', () => { d.locations.splice(i, 1); changed(true); }, 'Delete')))),
    btn('Place a new location', () => place(null), 'go'));
}

async function place(i) {
  const d = S.doc;
  if (!d.points.length) return toast('Add a point first.', true);
  const r = await post('place', { points: d.points });
  if (!r || !r.ok) return toast('Placing cancelled: nothing changed.');
  if (i === null) d.locations.push(r.location); else d.locations[i] = r.location;
  toast('Location placed. Save to keep it.');
  changed(true);
}

function questionCard(list) {
  return cards(list, (q) => [h('b', {}, q.label || '(no words yet)'), h('span', { class: 'muted mono' }, q.id)], (q) => questionBody(q),
    () => ({ id: unique('c_question', list.map((q) => q.id)), label: '', needs: [] }), 'Question');
}
function questionBody(q) {
  return h('div', {}, h('div', { class: 'grid' }, field(q, 'label', 'What the officer asks', 'text'), field(q, 'id', 'Id', 'fact'),
    field(q, 'press', 'Asking again gets a fresh answer (pressing)', 'bool'), field(q, 'stress', 'Nerves show in the answer', 'bool')),
  h('h3', {}, 'Only shows once they know'), factPairs(q.needs = arr(q.needs), 'Needs a fact', 'Value (empty: any)'));
}

function tabQuestions() {
  const d = S.doc;
  return h('div', {}, help('Questions shared by people in different stories (the caller is asked the same things in every story, but answers differently). The answers go in each story, with the person.'),
    cards(d.qsets, (s) => [h('b', {}, s.id), h('span', { class: 'muted' }, `${arr(s.questions).length} questions`)],
      (s) => h('div', {}, h('div', { class: 'grid' }, field(s, 'id', 'Name', 'id')), questionCard(s.questions = arr(s.questions))),
      () => ({ id: unique('list', d.qsets.map((s) => s.id)), questions: [] }), 'Question list'));
}

function objectiveBody(o, ctx) {
  return h('div', { class: 'grid' }, field(o, 'text', 'On the card', 'text'), field(o, 'hint', 'Hint', 'text'),
    field(o, 'hidden', 'Hidden until a rule reveals it', 'bool'),
    A(field(o, 'id', 'Id', 'id')), A(field(o, 'who', 'Who holds it', 'sel', [['one', 'One unit'], ['all', 'Every unit']])),
    A(field(o, 'after', 'Locked until these are done', 'objectives', null, Object.assign({ self: o.id }, ctx))),
    ctx && ctx.story ? field(o, 'blip', 'Marks on the map', 'things', null, ctx) : null);
}
function objectiveTitle(o) { return [h('b', {}, o.text || '(no words yet)'), h('span', { class: 'muted' }, (o.hidden ? 'hidden' : 'on the card') + (o.who === 'all' ? ' · every unit' : ''))]; }

function tabCard() {
  const d = S.doc;
  const keysField = (o) => {
    const keys = [...new Set(d.stories.flatMap((s) => keysOf(s)))];
    const cur = arr(o.blip);
    return h('div', { class: 'f wide' }, h('span', {}, 'Marks on the map (from any story)'), h('div', { class: 'chips' }, keys.map((k) => h('button', { type: 'button',
      class: 'chip' + (cur.includes(k) ? ' on' : ''), 'aria-pressed': cur.includes(k) ? 'true' : 'false', onclick: () => { o.blip = cur.includes(k) ? cur.filter((x) => x !== k) : cur.concat(k); changed(true); } }, k))));
  };
  return h('div', {}, help('What every officer\'s card shows at the start, the same whatever the story, so it never gives the story away. About three that can be done at once is good. A story\'s own objectives go in the story, hidden until found.'),
    cards(d.card, objectiveTitle, (o) => h('div', {}, objectiveBody(o, { story: null }), keysField(o)),
      () => ({ id: unique('objective', objectivesOf(null).map((o) => o.id)), text: '', hint: '', who: 'one', after: [], blip: [] }), 'Objective'));
}

// ─── stories ──────────────────────────────────────────────────────────────────────────────────────────────────

function stabsNow() {
  return [['people', 'People'], ['cars', 'Cars'], ['clues', 'Clues'], ['objectives', 'Hidden objectives'], ['rules', 'Rules'], ['presets', 'Action scenes'],
    ['ending', 'Ending'], ['story', 'Settings']];
}

function tabStories() {
  const d = S.doc;
  if (!d.stories.length) d.stories.push(newStory('main', d));
  S.story = Math.min(S.story, d.stories.length - 1);
  const st = d.stories[S.story];
  const total = d.stories.reduce((a, s) => a + (Number(s.weight ?? 1) || 0), 0) || 1;
  const side = h('div', { class: 'side' }, help('What really happened. One is picked at random for each call, and the officer has to find out which.'),
    d.stories.map((s, i) => h('div', { class: 'item' + (i === S.story ? ' on' : ''), role: 'button', tabindex: '0', onclick: () => { S.story = i; render(); },
      onkeydown: (e) => { if (e.key === 'Enter') { S.story = i; render(); } } },
    h('span', { class: 't' }, s.id), h('span', { class: 'muted' }, Math.round(100 * (Number(s.weight ?? 1) || 0) / total) + '%'))),
    h('div', { class: 'row', style: 'margin-top: 8px' }, btn('+ New', () => { d.stories.push(newStory(unique('story', d.stories.map((s) => s.id)), d)); S.story = d.stories.length - 1; changed(true); }, 'small'),
      btn('Copy', () => { const c = clone(st); c.id = unique(st.id, d.stories.map((s) => s.id)); d.stories.splice(S.story + 1, 0, c); S.story++; changed(true); }, 'small', 'Copy this story, then change what differs')));
  const ctx = { story: st };
  if (!stabsNow().some(([id]) => id === S.stab)) S.stab = 'people';
  const body = ({ story: storyMain, people: storyPeople, cars: storyCars, clues: storyClues, objectives: storyObjectives, rules: storyRules, presets: storyPresets, ending: storyEnding })[S.stab](st, ctx);
  return h('div', { class: 'split' }, side, h('div', {}, h('nav', { class: 'tabs sub', 'aria-label': 'Story sections' }, stabsNow().map(([id, label]) => h('button', { type: 'button',
    class: S.stab === id ? 'on' : '', onclick: () => { S.stab = id; render(); } }, label))), body));
}

function storyMain(st) {
  const d = S.doc;
  return h('div', {}, h('div', { class: 'grid' }, field(st, 'id', 'Name', 'id'), field(st, 'weight', 'How often, against the other stories (weight)', 'num', '1'),
    A(field(st, 'needs', 'Only at locations that have these points', 'points'))),
  h('div', { class: 'row', style: 'margin-top: 14px' }, d.stories.length > 1 ? btn('Delete this story', async () => {
    if (!(await ask('Delete story', `Delete the story "${st.id}"?`, 'Delete', 'bad'))) return;
    d.stories.splice(S.story, 1); S.story = 0; changed(true);
  }, 'bad') : null));
}

const LINE_KINDS = [['pick', 'Says one of these'], ['cracks', 'Denies it, then gives in'], ['iffact', 'Depends on something they know']];

// one question and its answer, side by side
function lineEditor(l) {
  const kind = l.kind || 'pick';
  if (kind === 'cracks') {
    return h('div', {}, h('div', { class: 'grid' }, field(l, 'times', 'Gives in when asked this many times', 'num', '2')),
      h('h4', {}, 'Denies'), answers(l.deny = arr(l.deny), 'Another denial', 'e.g. What store?'), h('h4', {}, 'Then admits'),
      answers(l.admit = arr(l.admit), 'Another admission', 'e.g. ...Alright. I took it.'), h('h4', {}, 'Asked again after'), answers(l.again = arr(l.again), 'Another', 'e.g. I said. I took it.'));
  }
  if (kind === 'iffact') {
    return h('div', {}, h('div', { class: 'grid' }, field(l, 'fact', 'If they know', 'fact'), field(l, 'value', 'Value (empty: any)', 'text')),
      h('h4', {}, 'They say'), answers(l.yes = arr(l.yes)), h('h4', {}, 'Otherwise'), answers(l.no = arr(l.no)));
  }
  return answers(l.answers = arr(l.answers));
}

function qaSection(p, ctx) {
  const shared = qsetOf(p);
  const own = p.questions = arr(p.questions);
  const lines = p.lines = arr(p.lines);
  const lineFor = (id) => {
    let l = lines.find((x) => x.q === id);
    if (!l) { l = { q: id, kind: 'pick', answers: [] }; lines.push(l); }
    return l;
  };
  const pair = (q, list, isShared) => {
    const l = lineFor(q.id);
    return h('div', { class: 'qa' },
      h('div', { class: 'q' }, h('span', { class: 'who' }, 'Officer:'), h('input', { type: 'text', value: q.label || '', placeholder: 'The question, e.g. What happened?', 'aria-label': 'The question',
        oninput: (e) => { q.label = e.target.value; changed(false); } }),
      isShared ? h('span', { class: 'tag', title: 'This question is asked in every story that uses the list "' + shared.id + '": its words change everywhere.' }, 'shared') : null,
      A(icon('⚙', () => { OPEN.has(q) ? OPEN.delete(q) : OPEN.add(q); render(); }, 'Question options')),
      icon('✕', () => { list.splice(list.indexOf(q), 1); lines.splice(lines.indexOf(l), 1); changed(true); }, 'Delete the question')),
      S.adv && OPEN.has(q) ? h('div', { class: 'sect' }, questionBody(q)) : null,
      h('div', { class: 'a' }, h('span', { class: 'who' }, (p.label || 'They') + ':'), h('div', { class: 'grow' },
        S.adv ? h('div', { class: 'grid tight' }, field(l, 'kind', 'How they answer', 'sel', LINE_KINDS)) : null,
        S.adv || (l.kind || 'pick') === 'pick' ? lineEditor(l) : h('p', { class: 'help' }, 'This answer uses an Advanced kind (' + (LINE_KINDS.find(([k]) => k === l.kind) || [0, l.kind])[1] + '). Switch to Advanced to edit it.'))));
  };
  const out = h('div', {});
  if (shared) out.append(help(`Shared questions (the list "${shared.id}"): asked in every story that uses it, but answered here for this story.`), ...arr(shared.questions).map((q) => pair(q, shared.questions, true)));
  out.append(...own.map((q) => pair(q, own, false)));
  out.append(btn('+ Question and answer', () => { own.push({ id: unique('c_question', questionsOf(ctx.story, p.key).map(([id]) => id).concat(arr(S.doc.qsets).flatMap((s) => arr(s.questions).map((q) => q.id)))), label: '', needs: [] }); changed(true); }, 'small add'));
  if (S.adv) {
    const usual = lines.filter((l) => USUAL_Q.some(([id]) => id === l.q));
    out.append(h('h4', {}, 'Answers to the usual questions'), help('Where are you headed, do you live around here... Give them their own answer, or leave the usual one.'),
      cards(usual, (l) => [h('b', {}, (USUAL_Q.find(([id]) => id === l.q) || [0, l.q])[1])], (l) => h('div', {}, h('div', { class: 'grid' }, field(l, 'q', 'Question', 'sel', USUAL_Q.map(([id, label]) => [id, label])),
        field(l, 'kind', 'How they answer', 'sel', LINE_KINDS)), lineEditor(l)), null),
      btn('+ Answer to a usual question', () => { const q = (USUAL_Q.find(([id]) => !lines.some((x) => x.q === id)) || USUAL_Q[0])[0]; const l = { q, kind: 'pick', answers: [] }; lines.push(l); OPEN.add(l); changed(true); }, 'small add'));
  }
  return out;
}

function personBody(p, ctx) {
  const sc = p.scene = p.scene || { kind: 'none' };
  const age = p.age = p.age || {};
  return h('div', {},
    h('div', { class: 'grid' }, field(p, 'label', 'Who they are (Caller, Man, Clerk...)', 'text'), field(p, 'at', 'Stands at', 'point', null, ctx),
      field(p, 'sex', 'Sex', 'sel', [['random', 'Random'], ['male', 'Male'], ['female', 'Female']]),
      field(p, 'secret', 'Their hidden truth', 'sel', SECRETS), field(p, 'demeanor', 'Attitude', 'sel', DEMEANORS),
      A(field(p, 'key', 'Key (how rules name them)', 'id'))),
    h('h3', {}, 'Questions and answers'),
    help('What the officer can ask them under "The call", and what they say back in this story.'),
    qaSection(p, ctx),
    h('h3', {}, 'Looks and what they\'re doing'),
    h('div', { class: 'grid' }, field(p, 'model', 'Ped model (empty: an ordinary local)', 'asset:ped'),
      field(sc, 'kind', 'Doing', 'sel', [['none', 'Just standing'], ['scenario', 'A scenario (smoking, on the phone...)'], ['anim', 'An animation']]),
      sc.kind === 'scenario' ? field(sc, 'name', 'Scenario', 'asset:scenario') : null,
      sc.kind === 'anim' ? animField(sc) : null),
    h('h3', {}, 'Armed, hurt, on them'),
    h('div', { class: 'grid' }, field(p, 'weapon', 'Weapon, used if told to fight or aim', 'asset:weapon'),
      field(p, 'injured', 'On the ground hurt', 'bool'), A(field(p, 'dead', 'Found dead', 'bool')),
      p.injured ? field(p, 'vitals', 'What Check vitals says', 'text') : null),
    h('div', { class: 'f wide' }, h('span', {}, 'A search finds (evidence: add their weapon here too)'), strings(p.items = arr(p.items), 'e.g. Bag of pills', 'Evidence')),
    A(h('div', {}, h('h3', {}, 'More'),
      h('div', { class: 'grid' }, field(age, 'min', 'Age from', 'num'), field(age, 'max', 'Age to', 'num'),
        field(p, 'home', 'Lives', 'sel', [['', 'Somewhere else'], ['yes', "At the call's address"]].concat(arr(S.doc.points).map((x) => [x.name, `On ${x.name}'s street`]))),
        field(p, 'family', 'Family (shares a surname with the others)', 'bool'), field(p, 'wanted', 'Someone on file with a warrant', 'bool'),
        field(p, 'reach', 'Talked to from (m, up to 20: from cover)', 'num'), field(p, 'seated', 'Starts at the wheel of', 'car?', null, ctx),
        field(p, 'runs', 'Floors it if pulled over', 'bool'), field(p, 'qset', 'Shared question list', 'qset')),
      h('div', { class: 'f wide' }, h('span', {}, 'Everyday things in their pockets'), strings(p.pockets = arr(p.pockets), 'e.g. Gas station receipt', 'Pocket item')),
      h('div', { class: 'f wide' }, h('span', {}, 'Facts they start with'), factPairs(p.facts = arr(p.facts), 'Fact')))));
}

function animField(sc) {
  return [h('div', { class: 'f' }, h('span', {}, 'Common animations'), dropdown(ASSETS.anim.map(([d, a, l]) => [d + ' ' + a, l, d]), (sc.dict || '') + ' ' + (sc.anim || ''),
    (v) => { const [d, a] = v.split(' '); sc.dict = d; sc.anim = a; changed(true); }, 'Common animations')),
  A(field(sc, 'dict', 'Dictionary', 'text')), A(field(sc, 'anim', 'Name', 'text')),
  h('div', { class: 'f' }, h('span', {}, ' '), btn('Preview', () => preview({ kind: 'anim', dict: sc.dict, anim: sc.anim }), 'small'))];
}

function storyPeople(st, ctx) {
  return h('div', {}, help('Everyone in this story. They are real people: name checks, the MDT and searches all find them.'),
    cards(st.people, (p) => [h('b', {}, p.label || p.key), h('span', { class: 'muted' }, `at ${p.at || '?'}${p.secret ? ' · ' + (SECRETS.find(([k]) => k === p.secret) || [0, p.secret])[1].toLowerCase() : ''}${p.weapon ? ' · armed' : ''}`)],
      (p) => personBody(p, ctx), () => {
        const key = unique('person', keysOf(st));
        return { key, at: (arr(S.doc.points)[0] || {}).name || '', label: 'Person', sex: 'random', scene: { kind: 'none' }, lines: [], questions: [], items: [], pockets: [], facts: [] };
      }, 'Person', { copy: (p) => Object.assign(clone(p), { key: unique(p.key, keysOf(st)) }) }));
}
function keysOf(st) { return arr(st.people).map((p) => p.key).concat(arr(st.vehicles).map((v) => v.key), arr(st.clues).map((c) => c.key)); }

function storyCars(st, ctx) {
  return h('div', {}, help('Parked cars, on file: run the plate and it comes back registered to its owner.'),
    cards(st.vehicles, (v) => [h('b', {}, [v.color, v.make, v.name].filter(Boolean).join(' ') || v.model), h('span', { class: 'muted' }, `at ${v.at || '?'}${v.stolen ? ' · stolen' : ''}`)],
      (v) => h('div', { class: 'grid' }, field(v, 'at', 'Parked at', 'point', null, ctx), field(v, 'model', 'Model', 'asset:vehicle'),
        field(v, 'make', 'Make (the plate check says)', 'text', 'Declasse'), field(v, 'name', 'Model name', 'text', 'Asea'), field(v, 'color', 'Colour', 'text', 'Silver'),
        field(v, 'owner', 'Registered to', 'person?', null, ctx), field(v, 'stolen', 'Reported stolen', 'bool'),
        A(field(v, 'key', 'Key (how rules name it)', 'id')),
        A(field(v, 'paint', 'Paint', 'sel', [['', 'Any']].concat(PAINTS.map(([id, n]) => [String(id), n])))),
        A(field(v, 'damage', 'Damage', 'sel', DAMAGE)), A(field(v, 'label', 'Map label', 'text')),
        A(h('label', { class: 'f check' }, h('input', { type: 'checkbox', checked: v.locked !== false, onchange: (e) => { v.locked = e.target.checked; changed(true); } }), h('span', {}, 'Locked')))),
      () => ({ key: unique('car', keysOf(st)), at: (arr(S.doc.points).find((p) => p.car) || arr(S.doc.points)[0] || {}).name || '', model: 'asea', make: 'Declasse', name: 'Asea', color: 'Silver', paint: 4 }), 'Car'));
}

function storyClues(st, ctx) {
  return h('div', {}, help('Evidence. Up close, E Inspect shows what it says and puts it on every unit\'s MDT.'),
    cards(st.clues, (c) => [h('b', {}, c.label || c.key), h('span', { class: 'muted' }, `${c.on ? 'on ' + c.on : 'at ' + (c.at || '?')}${c.hidden ? ' · hidden' : ''}`)],
      (c) => h('div', { class: 'grid' }, field(c, 'label', 'What it is', 'text', 'e.g. Dropped bag'), field(c, 'at', 'Lies at', 'point?', null, ctx),
        field(c, 'text', 'What looking at it shows', 'long', 'e.g. Two packs of razor blades, security tags still on.'), field(c, 'prop', 'An object on the ground (empty: none)', 'asset:prop'),
        field(c, 'hidden', 'Hidden until a rule reveals it', 'bool'),
        A(field(c, 'key', 'Key (how rules name it)', 'id')),
        A(field(c, 'on', 'Or on (a car or person)', 'sel', [['', '(nothing: at the point)']].concat(arr(st.vehicles).map((v) => [v.key, 'car ' + v.key]), arr(st.people).map((p) => [p.key, p.label || p.key])))),
        A(field(c, 'drag', 'Can be dragged off the road', 'bool')), A(field(c, 'spikes', 'Bursts tyres within (m, empty: no)', 'num')),
        A(field(c.scatter = c.scatter || {}, 'model', 'More of it lying around (prop)', 'asset:prop')), A(field(c.scatter, 'count', 'How many', 'num', '6')), A(field(c.scatter, 'radius', 'Over (m)', 'num', '4'))),
      () => ({ key: unique('clue', keysOf(st)), at: (arr(S.doc.points)[0] || {}).name || '', label: '', text: '' }), 'Clue'));
}

function storyObjectives(st, ctx) {
  return h('div', {}, help('This story\'s own objectives, after the opening card. Keep them hidden until something the officer finds reveals them (a rule).'),
    cards(st.objectives, objectiveTitle, (o) => objectiveBody(o, ctx),
      () => ({ id: unique('objective', objectivesOf(st).map((o) => o.id)), text: '', hint: '', who: 'one', hidden: true, after: [], blip: [] }), 'Objective'));
}

// one rule: When / If / Do
const SIMPLE_EVENTS = ['contact', 'ask', 'fact', 'act', 'inspect', 'plate', 'near', 'timer', 'arrive', 'hail', 'stunned', 'dead', 'contact_ended'];
const SIMPLE_ACTIONS = ['done', 'reveal', 'say', 'dispatch', 'note', 'task', 'give', 'wait', 'finish'];
const SIMPLE_TASKS = ['flee', 'surrender', 'go', 'shoot', 'drive', 'scene'];

function specFields(obj, spec, ctx) {
  return spec.map(([k, l, t, o]) => {
    if (t === 'question') return field(obj, k, l, 'sel', questionsOf(ctx.story, obj.who || (ctx.rule && ctx.rule.when.who)), ctx);
    if (t === 'objective?') return field(obj, k, l, 'sel', [['', '(none)']].concat(options('objective', ctx)), ctx);
    return field(obj, k, l, t, o, ctx);
  });
}

function taskFields(a, ctx) {
  const need = { go: 'point', spray: 'point', shoot: 'point', aim: 'other', hold: 'other', brawl: 'other', drive: 'car' }[a.task];
  const tasks = S.adv ? TASKS : TASKS.filter(([k]) => SIMPLE_TASKS.includes(k) || k === a.task);
  return [field(a, 'who', 'Who (empty: them)', 'person?', null, ctx), field(a, 'task', 'What', 'sel', tasks),
    need === 'point' ? field(a, 'point', a.task === 'shoot' ? 'From (empty: where they stand)' : 'Point', a.task === 'shoot' ? 'point?' : 'point', null, ctx) : null,
    need === 'other' ? field(a, 'other', 'At / with', 'person', null, ctx) : null,
    need === 'car' ? [field(a, 'car', 'Car', 'car', null, ctx), field(a, 'point', 'Drives to (empty: just drives off)', 'point?', null, ctx), field(a, 'fast', 'Flat out', 'bool')] : null];
}

function pickList(all, simple, cur) {
  return Object.entries(all).filter(([k]) => S.adv || simple.includes(k) || k === cur).map(([k, v]) => [k, v.label]);
}

function ruleBody(r, ctx) {
  const w = r.when = r.when || { event: 'contact' };
  const rctx = Object.assign({}, ctx, { rule: r });
  const ev = EVENTS[w.event] || { f: [] };
  r.ifs = arr(r.ifs);
  r.actions = arr(r.actions);
  return h('div', {},
    h('h4', {}, 'When'), h('div', { class: 'grid' }, field(w, 'event', 'This happens', 'sel', pickList(EVENTS, SIMPLE_EVENTS, w.event)), specFields(w, ev.f, rctx),
      A(h('label', { class: 'f check' }, h('input', { type: 'checkbox', checked: r.once !== false, onchange: (e) => { r.once = e.target.checked; changed(true); } }), h('span', {}, 'Only the first time')))),
    S.adv ? [h('h4', {}, 'Only if (all of these)'),
      h('div', {}, r.ifs.map((c, i) => h('div', { class: 'row sect' }, h('div', { class: 'grow grid' },
        field(c, 'kind', 'Only if', 'sel', Object.entries(CONDS).map(([k, v]) => [k, v.label])), specFields(c, (CONDS[c.kind] || { f: [] }).f, rctx)),
      icon('✕', () => { r.ifs.splice(i, 1); changed(true); }, 'Delete'))), btn('+ Condition', () => { r.ifs.push({ kind: 'fact' }); changed(true); }, 'small add'))]
      : r.ifs.length ? help(`Only if ${r.ifs.length} condition${r.ifs.length === 1 ? '' : 's'} hold (Advanced to see them).`) : null,
    h('h4', {}, 'Do'),
    h('div', {}, r.actions.map((a, i) => h('div', { class: 'row sect' }, h('div', { class: 'grow grid' },
      field(a, 'kind', 'Then', 'sel', pickList(ACTIONS, SIMPLE_ACTIONS, a.kind)),
      a.kind === 'task' ? taskFields(a, rctx) : specFields(a, (ACTIONS[a.kind] || { f: [] }).f, rctx)),
    A(i > 0 ? icon('↑', () => { r.actions.splice(i - 1, 0, r.actions.splice(i, 1)[0]); changed(true); }, 'Move up') : null),
    icon('✕', () => { r.actions.splice(i, 1); changed(true); }, 'Delete'))), btn('+ And then', () => { r.actions.push({ kind: 'done' }); changed(true); }, 'small add')));
}

function nameOf(st, key) {
  const p = arr(st && st.people).find((x) => x.key === key) || arr(st && st.clues).find((x) => x.key === key);
  return p ? p.label || key : key;
}
function ruleTitle(r, st) {
  const w = r.when || {};
  const who = w.who || w.clue || w.car || '';
  const ev = (EVENTS[w.event] || { label: '?' }).label;
  const q = w.q && (questionsOf(st, w.who).find(([id]) => id === w.q) || [0, w.q])[1];
  return [h('b', {}, `When: ${ev}${who ? ' (' + nameOf(st, who) + ')' : ''}${q ? ': "' + q + '"' : ''}${w.fact ? ' ' + w.fact : ''}`),
    h('span', { class: 'muted' }, '→ ' + arr(r.actions).map((a) => (ACTIONS[a.kind] || { label: a.kind }).label.toLowerCase()).join(', then '))];
}

function storyRules(st, ctx) {
  return h('div', {}, help('How the story reacts: when something happens, do these things. Every objective needs a rule (or the ending, or an action scene) that marks it done, or the call can stick.'),
    cards(st.rules, (r) => ruleTitle(r, st), (r) => ruleBody(r, ctx), () => ({ when: { event: 'ask', who: (arr(st.people)[0] || {}).key || '' }, ifs: [], actions: [{ kind: 'done' }] }), 'Rule', { copy: clone }));
}

function storyPresets(st, ctx) {
  return h('div', {}, help('Ready-made scenes that need careful timing: a fight, a standoff, a shootout. Each one handles being told to drop it, tasers and giving up.'),
    cards(st.presets, (x) => [h('b', {}, (PRESETS[x.kind] || { label: x.kind }).label), h('span', { class: 'muted' }, nameOf(st, x.who) || '')],
      (x) => h('div', {}, h('div', { class: 'grid' }, field(x, 'kind', 'Scene', 'sel', Object.entries(PRESETS).map(([k, v]) => [k, v.label]))),
        help((PRESETS[x.kind] || {}).hint || ''), h('div', { class: 'grid' }, specFields(x, (PRESETS[x.kind] || { f: [] }).f, ctx))),
      () => ({ kind: 'standoff', who: (arr(st.people)[0] || {}).key || '', chance: 50 }), 'Action scene'));
}

function storyEnding(st, ctx) {
  const e = st.ending = st.ending || { mode: 'subject', lines: {} };
  if (Array.isArray(e.lines) || !e.lines) e.lines = {};
  const lines = S.adv ? END_LINES : END_LINES.filter(([k]) => ['arrested', 'cited', 'released', 'fled', 'left'].includes(k));
  return h('div', {}, help('When the call is over, and what every unit\'s MDT report ends with. Anyone arrested has to be taken in first.'),
    h('div', { class: 'grid' }, field(e, 'mode', 'It ends', 'sel', ENDINGS), e.mode !== 'arrests' ? field(e, 'subject', 'Who it\'s about', e.mode === 'subject' ? 'person' : 'person?', null, ctx) : null,
      field(e, 'heard', e.mode === 'heard' ? 'Heard means this objective is done' : 'Or, once this is done and every unit leaves', 'sel', [['', '(none)']].concat(options('objective', ctx))),
      A(field(e, 'decide', 'Marks this objective done as it ends', 'sel', [['', '(none)']].concat(options('objective', ctx)))),
      A(field(e, 'left', 'Seconds every unit is gone before it ends', 'num', '15'))),
    h('h3', {}, 'MDT summary'), help('{name} is the person it\'s about, {street} the call\'s street. Empty: a plain line ("{name} was arrested.").'),
    h('div', { class: 'grid' }, lines.map(([k, l]) => field(e.lines, k, l, 'long'))));
}

// ─── checks: what will go wrong, before it does ───────────────────────────────────────────────────────────────

const said = (l) => {
  if (!l) return false;
  const k = l.kind || 'pick';
  const any = (list) => arr(list).some((a) => (a.text || '').trim());
  return k === 'cracks' ? any(l.deny) && any(l.admit) : k === 'iffact' ? any(l.yes) || any(l.no) : any(l.answers);
};

// What a fix can stand someone on: the first point, or the first car point for a car.
const firstPoint = (d, car) => ((car && arr(d.points).find((p) => p.car)) || arr(d.points)[0] || {}).name || '';

// A rule that marks an objective done, from what it marks on the map: talking to them, looking at it, running the plate.
function doneRule(s, o) {
  const plate = /plate/i.test(o.text || ''); // ("Run the plate": the car's plate, not the clue that shares its name)
  for (const k of arr(o.blip)) {
    if (plate && arr(s.vehicles).some((v) => v.key === k)) return { when: { event: 'plate', car: k }, ifs: [], actions: [{ kind: 'done', id: o.id }] };
    if (arr(s.people).some((p) => p.key === k)) return { when: { event: 'contact', who: k }, ifs: [], actions: [{ kind: 'done', id: o.id }] };
    if (arr(s.clues).some((c) => c.key === k)) return { when: { event: 'inspect', clue: k }, ifs: [], actions: [{ kind: 'done', id: o.id }] };
    if (arr(s.vehicles).some((v) => v.key === k)) return { when: { event: 'plate', car: k }, ifs: [], actions: [{ kind: 'done', id: o.id }] };
  }
  return null;
}
// "Deal with them: arrest, ticket or warn": done when the call ends, not when they're found
const DECIDE = /arrest|deal with|decide|let (them|him|her) go|ticket|warn|serve/i;
function ruleSays(s, r) {
  const w = r.when;
  return w.event === 'contact' ? `an officer talks to ${nameOf(s, w.who)}` : w.event === 'inspect' ? `${nameOf(s, w.clue)} is looked at` : `${w.car}'s plate is run`;
}

// Who an ending is most likely about: someone armed, then someone with something to hide, then whoever was added last.
function likelySubject(s) {
  const ps = arr(s.people);
  return (ps.find((p) => p.weapon) || ps.find((p) => p.secret && p.secret !== 'clean') || ps[ps.length - 1] || {}).key;
}

// Every problem, and for most a fix: { label, run, auto } (auto: safe to run with the others in "Fix everything").
function checks(d) {
  if (!d) return [];
  const out = [];
  const add = (level, text, tab, story, stab, fix) => out.push({ level, text, tab, story, stab, fix });
  const auto = (label, run) => ({ label, run, auto: true });
  const taken = () => arr(S.list && S.list.packs).flatMap((p) => p.callouts.map((c) => c.id)).filter((id) => id !== S.was);
  if (!ident(d.id) || d.id.startsWith('c_')) add('bad', 'The callout id must be letters, numbers and _, not starting c_.', 'callout', undefined, undefined,
    auto('Make one from the name', () => { let id = unique(d.name || 'callout', taken()); if (id.startsWith('c_')) id = 'x' + id; d.id = id; }));
  if (!d.name) add('bad', 'The callout needs a name.', 'callout');
  if (!arr(d.reports).some((r) => (r || '').trim())) add('bad', 'Add a report: what the caller says.', 'callout');
  if (!arr(d.points).length) add('bad', 'Add a point: the first is where the call is.', 'points', undefined, undefined,
    auto('Add a "caller" point', () => d.points.push({ name: 'caller', text: 'The caller, where they wait for police.', car: false, optional: false })));
  if (!arr(d.locations).length) add('warn', 'No locations yet: place at least one (Places), or the call can never happen.', 'points', undefined, undefined,
    { label: 'Place one now', run: () => { S.tab = 'points'; place(null); } });
  if (arr(d.stories).length < 2) add('tip', 'One story: the call plays the same every time. Two or three different truths behind the same report make a good callout.', 'stories', undefined, undefined,
    { label: 'Copy it as a second story', run: () => { const c = clone(d.stories[0]); c.id = unique(d.stories[0].id, d.stories.map((x) => x.id)); d.stories.push(c); S.tab = 'stories'; S.story = d.stories.length - 1; } });
  const pointNames = arr(d.points).map((p) => p.name);
  const open = arr(d.card).filter((o) => !o.hidden).map((o) => o.id).join(',');
  const cardText = (id) => (arr(d.card).find((x) => x.id === id) || {}).text || id;
  d.stories.forEach((s, si) => {
    const where = `Story ${s.id}: `;
    const keys = keysOf(s);
    const sets = new Set();
    JSON.stringify(s, (k, v) => { if (k === 'set' && Array.isArray(v)) v.forEach((x) => sets.add(x.fact)); return v; });
    arr(s.people).forEach((p) => arr(p.facts).forEach((f) => sets.add(f.fact)));
    arr(s.rules).forEach((r) => arr(r.actions).forEach((a) => { if (a.kind === 'give') sets.add(a.fact); }));
    const completes = new Set(), reveals = new Set();
    arr(s.rules).forEach((r) => arr(r.actions).forEach((a) => { if (a.kind === 'done') completes.add(a.id); if (a.kind === 'reveal') reveals.add(a.id); }));
    arr(s.presets).forEach((x) => x.objective && completes.add(x.objective));
    if (s.ending && s.ending.decide) completes.add(s.ending.decide);
    for (const o of arr(d.card).concat(arr(s.objectives))) {
      if (!completes.has(o.id)) {
        const decide = !(s.ending && s.ending.decide) && DECIDE.test(o.text || '');
        const r = decide ? null : doneRule(s, o);
        add('warn', `${where}nothing marks "${o.text || o.id}" done, so the call can stick on it. Add a rule that does.`, 'stories', si, 'rules',
          r ? auto(`Done when ${ruleSays(s, r)}`, () => { s.rules = arr(s.rules); s.rules.push(r); })
            : decide ? auto('Done when the call ends', () => { s.ending = s.ending || { mode: 'subject', lines: {} }; s.ending.decide = o.id; }) : null);
      }
      if (o.hidden && !reveals.has(o.id)) {
        const after = (arr(d.card).find((x) => !x.hidden && x.id !== o.id) || {}).id;
        add('warn', `${where}"${o.text || o.id}" is hidden and nothing reveals it. Add a rule that does.`, 'stories', si, 'rules',
          after ? auto(`Reveal it once "${cardText(after)}" is done`, () => {
            s.rules = arr(s.rules);
            s.rules.push({ when: { event: 'timer', s: 1 }, ifs: [{ kind: 'done', objective: after }], actions: [{ kind: 'reveal', id: o.id }] });
          }) : null);
      }
    }
    const shown = arr(d.card).filter((o) => !o.hidden).map((o) => o.id).concat(arr(s.objectives).filter((o) => !o.hidden).map((o) => o.id)).join(',');
    if (shown !== open) add('warn', `${where}one of its own objectives is on the card from the start, so the card gives the story away. Make it hidden.`, 'stories', si, 'objectives',
      auto('Hide it', () => arr(s.objectives).forEach((o) => { o.hidden = true; })));
    arr(s.people).forEach((p) => {
      if (!pointNames.includes(p.at)) add('bad', `${where}${p.label || p.key} stands at "${p.at}", which isn't a point.`, 'stories', si, 'people',
        pointNames.length ? auto(`Stand them at ${firstPoint(d)}`, () => { p.at = firstPoint(d); }) : null);
      const qs = arr((arr(d.qsets).find((x) => x.id === p.qset) || {}).questions).concat(arr(p.questions));
      for (const q of qs) {
        if (!(q.label || '').trim()) add('bad', `${where}${p.label || p.key} has a question with no words.`, 'stories', si, 'people');
        else if (!said(arr(p.lines).find((l) => l.q === q.id))) add('tip', `${where}${p.label || p.key} has no answer to "${q.label}": they'll give a vague one.`, 'stories', si, 'people');
        for (const n of arr(q.needs)) {
          if (n.fact && !sets.has(n.fact)) add('warn', `${where}"${q.label}" only shows once ${n.fact} is known, and nothing in this story gives it away.`, 'stories', si, 'people',
            auto('Always show the question', () => { q.needs = arr(q.needs).filter((x) => x.fact !== n.fact); }));
        }
      }
    });
    arr(s.vehicles).forEach((v) => { if (!pointNames.includes(v.at)) add('bad', `${where}car ${v.key} is at "${v.at}", which isn't a point.`, 'stories', si, 'cars',
      pointNames.length ? auto(`Park it at ${firstPoint(d, true)}`, () => { v.at = firstPoint(d, true); }) : null); });
    arr(s.clues).forEach((c) => { if (!c.on && !pointNames.includes(c.at)) add('bad', `${where}clue "${c.label || c.key}" is at "${c.at}", which isn't a point.`, 'stories', si, 'clues',
      pointNames.length ? auto(`Put it at ${firstPoint(d)}`, () => { c.at = firstPoint(d); }) : null); });
    const e = s.ending = s.ending || { mode: 'subject', lines: {} };
    const who = likelySubject(s);
    const heard = (arr(d.card)[0] || {}).id;
    if ((e.mode || 'subject') === 'subject' && !keys.includes(e.subject)) add('bad', `${where}the ending needs who it's about.`, 'stories', si, 'ending',
      who ? auto(`Make it about ${nameOf(s, who)}`, () => { e.subject = who; }) : null);
    if (e.mode === 'heard' && !e.heard) add('bad', `${where}the ending needs the objective that means they've been heard.`, 'stories', si, 'ending',
      heard ? auto(`Use "${cardText(heard)}"`, () => { e.heard = heard; }) : null);
    if (!e.heard && e.mode !== 'heard') add('tip', `${where}if every unit just leaves, it only ends when time runs out. Set "Or, once this is done and every unit leaves".`, 'stories', si, 'ending',
      heard ? auto(`Use "${cardText(heard)}"`, () => { e.heard = heard; }) : null);
    arr(s.people).forEach((p) => {
      if (p.weapon && !arr(s.presets).some((x) => x.who === p.key) && !arr(s.rules).some((r) => arr(r.actions).some((a) => a.kind === 'task' && a.who === p.key))) {
        add('tip', `${where}${p.label || p.key} has a weapon but nothing tells them to use it (an action scene or a rule).`, 'stories', si, 'presets',
          { label: 'Add a shootout scene', run: () => { s.presets = arr(s.presets); s.presets.push({ kind: 'shootout', who: p.key, chance: 50, near: 18 }); S.tab = 'stories'; S.story = si; S.stab = 'presets'; } });
      }
    });
  });
  return out;
}

// Every fix that's safe to make without asking, over and over (a fix can need another: hiding an objective then needs a
// rule to reveal it). -> how many
function fixAll(d) {
  let n = 0;
  for (let pass = 0; pass < 5; pass++) {
    const todo = checks(d).filter((y) => y.fix && y.fix.auto && y.level !== 'tip');
    if (!todo.length) break;
    for (const x of todo) { x.fix.run(); n++; }
  }
  return n;
}

function fixOne(x) {
  x.fix.run();
  changed(true);
  toast('Done: ' + x.fix.label + '. Check it, then Save.');
}

function tabChecks(issues) {
  if (!issues.length) return h('p', {}, 'Nothing to fix. Save, then Test it in game.');
  const order = { bad: 0, warn: 1, tip: 2 };
  const autos = issues.filter((x) => x.fix && x.fix.auto && x.level !== 'tip');
  return h('div', {}, help('Red stops it saving. Amber will go wrong in game. Grey is advice. A fix button does the obvious thing for you: it can only guess, so check it afterwards.'),
    autos.length ? h('div', { class: 'row' }, btn(`Fix everything I can (${autos.length})`, () => {
      const n = fixAll(S.doc);
      changed(true);
      toast(`Fixed ${n} thing${n === 1 ? '' : 's'}. Check them over, then Save.`);
    }, 'go')) : null,
    h('ul', { class: 'issues' }, issues.sort((a, b) => order[a.level] - order[b.level]).map((x) => h('li', { class: x.level }, x.text,
      x.fix ? h('button', { type: 'button', class: 'btn small fixbtn', onclick: () => fixOne(x) }, x.fix.label) : null,
      h('button', { type: 'button', class: 'link', onclick: () => { S.tab = x.tab; if (x.story !== undefined) S.story = x.story; if (x.stab) S.stab = x.stab; render(); } }, 'Go')))));
}

// ─── the first-time guide ─────────────────────────────────────────────────────────────────────────────────────

const GUIDE = [
  ['Welcome to the Callout Creator', 'A callout is what a 911 caller reports, plus a few hidden stories of what really happened. Every story starts the same, so the officer has to talk to people, look around and work out which one it is. You build all of it here, then press Test to play it.'],
  ['1. Basics', 'Give it a name and write what the caller says. Write it so it fits every story: "A man left the shop without paying" works whether he stole something or not.'],
  ['2. Places', 'Points are the spots the call needs: where the caller waits, where a suspect is, where a car is parked. Then press Place a new location and walk them out in game: stand on each spot and press E. Place a few locations and calls happen at the nearest.'],
  ['3. Opening card', 'The objectives every officer starts with, like "Talk to the caller". They\'re the same in every story, so the card never gives the truth away.'],
  ['4. Stories', 'Each story is one version of the truth. Add the people in it, and under each person write the officer\'s questions and their answers. An answer can give away a fact, and a fact can open a new question: that\'s how a lie gets caught out. Copy a story to make the next one quickly.'],
  ['Rules and action scenes', 'Rules make the story react: when the caller is asked "What happened?", mark "Talk to the caller" done; when a clue is found, reveal a hidden objective; when a question is asked, make someone run or fight. Action scenes are ready-made fights, standoffs and shootouts.'],
  ['Ending, Check, Save and Test', 'Pick how the call ends and what the MDT summary says. The Check tab lists anything that will go wrong. Then Save, and Test starts it near you (be on duty). Switch to Advanced at the top for every option.'],
];

function guide() {
  let i = 0;
  const m = document.getElementById('modal');
  const show = () => {
    const [title, text] = GUIDE[i];
    m.innerHTML = '';
    m.append(h('div', { class: 'box guide', role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
      h('div', { class: 'steps', 'aria-hidden': 'true' }, GUIDE.map((_, j) => h('span', { class: j === i ? 'on' : '' }))),
      h('h2', {}, title), h('p', {}, text),
      h('div', { class: 'actions' }, btn('Skip', done), i > 0 ? btn('Back', () => { i--; show(); }) : null,
        btn(i < GUIDE.length - 1 ? 'Next' : 'Start', () => { if (i < GUIDE.length - 1) { i++; show(); } else done(); }, 'go'))));
    m.hidden = false;
    m.querySelector('.btn.go').focus();
  };
  const done = () => { m.hidden = true; m.innerHTML = ''; store.set('guided', '1'); };
  closePop();
  show();
}

// ─── the game's messages ──────────────────────────────────────────────────────────────────────────────────────

window.addEventListener('message', (e) => {
  const m = e.data || {};
  const app = document.getElementById('app');
  if (m.type === 'open') {
    app.hidden = false;
    if (S.view === 'home') refresh();
    if (!store.get('guided')) guide();
  } else if (m.type === 'close') { app.hidden = true; closePop(); }
  else if (m.type === 'peek') {
    document.body.classList.add('peeking');
    closePop();
    const p = document.getElementById('peek');
    p.hidden = false;
    let left = m.seconds || 6;
    p.textContent = `Preview · back in ${left} s`;
    const t = setInterval(() => { left--; p.textContent = `Preview · back in ${left} s`; if (left <= 0) clearInterval(t); }, 1000);
  } else if (m.type === 'unpeek') { document.body.classList.remove('peeking'); document.getElementById('peek').hidden = true; }
  else if (m.type === 'placing') {
    app.hidden = true;
    const p = document.getElementById('placing');
    p.hidden = false;
    p.innerHTML = '';
    p.append(h('b', {}, `Point ${m.i} of ${m.count}: ${m.name}`), h('div', {}, m.text || ''),
      h('div', { class: 'muted', style: 'margin-top: 6px' }, h('span', { class: 'k' }, 'E'), m.car ? 'sitting in the car, ' : 'standing there, facing their way, ', 'to set it · ',
        m.optional ? [h('span', { class: 'k' }, 'Z'), 'skip · '] : null, h('span', { class: 'k' }, '⌫'), 'back · ', h('span', { class: 'k' }, 'X'), 'cancel'));
  } else if (m.type === 'placing_warn') {
    const p = document.getElementById('placing');
    const w = p.querySelector('.warn') || p.appendChild(h('div', { class: 'warn' }));
    w.textContent = m.text;
  } else if (m.type === 'placed') { document.getElementById('placing').hidden = true; app.hidden = false; }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape' || e.defaultPrevented) return;
  if (POP) return closePop();
  const m = document.getElementById('modal');
  if (!m.hidden) { m.hidden = true; m.innerHTML = ''; return; }
  closeAll();
});

// ─── outside the game: a stand-in server, to try the editor in a browser ──────────────────────────────────────

const MOCK = {
  store: { packs: [{ id: 'example', name: 'Example pack', author: 'LWK DEVELOPMENT', version: '1.0.0', licence: 'CC BY-NC-SA 4.0', description: 'A pack to try things in.', callouts: [] }], docs: {} },
  async post(name, data) {
    if (name === 'close') { document.getElementById('app').hidden = true; setTimeout(() => window.postMessage({ type: 'open' }, '*'), 800); return {}; }
    if (name === 'preview') return { ok: !!(data.name || data.dict) };
    if (name === 'goto') return {};
    if (name === 'hear') return { ok: true };
    if (name === 'place') return { ok: true, location: { street: 'Test St', points: Object.fromEntries(arr(data.points).map((p, i) => [p.name, { x: 100 + i, y: 200, z: 30, h: 90 }])), streets: {} } };
    const r = data.req || {}, st = this.store;
    const pack = st.packs.find((p) => p.id === r.pack);
    switch (data.action) {
      case 'list': return { ok: true, data: { c3r: true, others: [], packs: st.packs.map((p) => Object.assign({}, p, { callouts: p.callouts.map((id) => ({ id, name: st.docs[id].name, stories: st.docs[id].stories.length, locations: st.docs[id].locations.length, loaded: true })) })) } };
      case 'open': return { ok: true, data: { doc: clone(st.docs[r.id]) } };
      case 'save': { const errs = checks(r.doc).filter((x) => x.level === 'bad').map((x) => x.text); if (errs.length) return { ok: true, data: { errors: errs } };
        st.docs[r.doc.id] = clone(r.doc); if (!pack.callouts.includes(r.doc.id)) pack.callouts.push(r.doc.id); return { ok: true, data: { saved: true, loaded: true } }; }
      case 'pack': { if (!pack) st.packs.push(Object.assign({ id: slug(r.meta.name), callouts: [] }, r.meta)); else Object.assign(pack, r.meta); return { ok: true, data: {} }; }
      case 'delete': pack.callouts = pack.callouts.filter((id) => id !== r.id); return { ok: true, data: {} };
      case 'droppack': st.packs = st.packs.filter((p) => p !== pack); return { ok: true, data: {} };
      case 'export': return { ok: true, data: { path: 'lwk_calloutcreator/export/c3rpack_' + r.pack, name: 'c3rpack_' + r.pack } };
      case 'test': return { ok: false, data: 'Go on duty first. (This is the browser stand-in.)' };
    }
    return { ok: false, data: 'unknown' };
  },
};

if (!IN_GAME) { document.body.classList.add('browser'); window.postMessage({ type: 'open' }, '*'); }
