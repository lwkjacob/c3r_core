// lwk_mdt NUI: every record shown here came from c3r or another player, so all of it goes through h().

// In game the page talks to the game client (NUI callbacks). Popped out into a browser, it is served by
// the FiveM server at /lwk_mdt/?t=<link token> and talks to the server directly.
const WEB = !window.GetParentResourceName;
const RES = WEB ? (location.pathname.split('/')[1] || 'lwk_mdt') : window.GetParentResourceName();
const TOKEN = new URLSearchParams(location.search).get('t') || '';
const $ = (s, el = document) => el.querySelector(s);
const view = $('#view');

function post(cb, data) {
    const json = (r) => r.json();
    if (!WEB) {
        return fetch(`https://${RES}/${cb}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
            .then(json).catch(() => ({ error: 'No answer from the game.' }));
    }
    if (cb === 'close') return Promise.resolve({});
    const body = cb === 'run' ? { name: 'run', args: data } : { name: data.name, args: data.args };
    return fetch(`/${RES}/api`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ t: TOKEN, ...body }) })
        .then(json).then((r) => { if (r && r.expired) toast(r.error, 0); return r || {}; })
        .catch(() => ({ error: 'No answer from the server.' }));
}
const req = (name, args) => post('req', { name, args });

const h = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const arr = (v) => (Array.isArray(v) ? v : []); // Lua sends an empty table as {}
const money = (n) => '$' + Number(n || 0).toLocaleString();
const pad = (n) => String(n).padStart(2, '0');
const clock = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const when = (t) => (t ? new Date(t * 1000).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }) : '');
const hhmm = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };

let init = { forms: {}, calls: [], units: [], drafts: [] };
let chargeCache = null;
const chargeList = async () => (chargeCache ??= arr(await req('charges')));
const chargeId = (c) => `${c.code} ${c.section}`;
const GROUPS = { PC: 'Penal Code', HS: 'Health & Safety Code', VC: 'Vehicle Code' };
const CLASS = { F: 'FEL', M: 'MISD', I: 'INF' };
let skew = 0; // server clock - local clock, so ages are measured on the server's clock
const now = () => Date.now() / 1000 + skew;

// Age the way a CAD shows it: 12.4m, 22.0H, 1.9d
function age(t) {
    if (!t) return '';
    const s = Math.max(0, now() - t);
    if (s < 3600) return (s / 60).toFixed(1) + 'm';
    if (s < 86400) return (s / 3600).toFixed(1) + 'H';
    return (s / 86400).toFixed(1) + 'd';
}

function toast(text, ms = 2800) { // ms = 0 keeps it up
    const t = $('#toast');
    t.textContent = text;
    t.style.display = 'block';
    clearTimeout(toast.timer);
    if (ms) toast.timer = setTimeout(() => (t.style.display = 'none'), ms);
}

// ─── navigation (Back / Forward like a browser) ──────────────────────────────

let cur = null, seq = 0;
const hist = [], fwd = [];

function go(render) {
    if (cur) hist.push(cur);
    if (hist.length > 40) hist.shift();
    fwd.length = 0;
    show(render);
}
function show(render) { closeCharges(); cur = render; seq++; render(seq); navButtons(); }
function goBack() { if (hist.length) { fwd.push(cur); show(hist.pop()); } }
function goFwd() { if (fwd.length) { hist.push(cur); show(fwd.pop()); } }
const rerender = () => cur && show(cur);
const stale = (token) => token !== seq; // a newer screen replaced this one while it loaded

let CIV = false; // true while the Citizen Portal is open (player not on duty)

const isCad = () => document.body.classList.contains('cad');
let lastScreen = '';
function setTitle(screen) {
    lastScreen = screen;
    if (isCad()) return ($('#title').textContent = screen === 'All Calls and All Units' ? 'CAD' : screen);
    $('#title').textContent = CIV ? `lwk Citizen Portal | [${screen}]`
        : `lwk Message Center | [MDT : ${screen} : Last Updated at ${clock(new Date())}]`;
}

// ─── toolbar ─────────────────────────────────────────────────────────────────

const ICONS = {
    back: '<path d="M15 5l-7 7 7 7"/>', fwd: '<path d="M9 5l7 7-7 7"/>',
    home: '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
    query: '<circle cx="10" cy="10" r="6"/><path d="M15 15l6 6"/>',
    reports: '<rect x="5" y="3" width="14" height="18" rx="1"/><path d="M8 8h8M8 12h8M8 16h5"/>',
    drafts: '<path d="M4 20l4-1 11-11-3-3L5 16z"/><path d="M14 6l3 3"/>',
    new: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M12 8v8M8 12h8"/>',
    stats: '<path d="M5 20v-7M12 20V5M19 20v-11"/>',
    popout: '<path d="M14 4h6v6"/><path d="M20 4l-9 9"/><path d="M18 14v6H4V6h6"/>',
    people: '<circle cx="9" cy="8" r="3.5"/><path d="M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14c2 .8 3 2.8 3 6"/>',
    car: '<path d="M5 15l1.5-5h11L19 15"/><rect x="3" y="14" width="18" height="4" rx="1"/><circle cx="7.5" cy="19" r="1.5"/><circle cx="16.5" cy="19" r="1.5"/>',
    phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1z"/>',
    close: '<path d="M6 6l12 12M18 6L6 18"/>',
};
const CAD_LABEL = { fwd: 'Previous', home: 'CAD', query: 'Search' }; // the CAD style's names for the same tools
// the CAD style's icons: arrows and solid glyphs (cut-outs in the tile's colour)
const CAD_ICON = {
    back: '<path d="M20 12H5M11 5l-7 7 7 7"/>', fwd: '<path d="M4 12h15M13 5l7 7-7 7"/>',
    home: '<path fill="currentColor" stroke="none" fill-rule="evenodd" d="M4 4h16v12H4zM6 6v8h12V6zM1 18h22v2H1z"/>',
    query: '<circle cx="10" cy="10" r="6"/><path d="M15 15l6 6" stroke-width="3.4"/>',
    reports: '<path fill="currentColor" stroke="none" d="M2 5h20v14H2z"/><path stroke="#234074" stroke-width="1.8" d="M2.5 6l9.5 7 9.5-7"/>',
    drafts: '<path fill="currentColor" stroke="none" d="M6 1h9l6 6v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1z"/><path stroke="#234074" stroke-width="1.8" d="M8 12h9M8 16h9M8 8h5"/>',
    new: '<path fill="currentColor" stroke="none" d="M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path stroke="#234074" stroke-width="2.6" d="M12 7v10M7 12h10"/>',
    stats: '<path fill="currentColor" stroke="none" d="M3 13h4.5v8H3zM9.75 3h4.5v18h-4.5zM16.5 8H21v13h-4.5z"/>',
};

const TOOLS = [
    { id: 'back', label: 'Back', key: 'Alt+Left', run: goBack },
    { id: 'fwd', label: 'Forward', key: 'Alt+Right', run: goFwd },
    { id: 'home', label: 'Home', key: 'Alt+Home', run: () => go(homeScreen) },
    'sep',
    { id: 'query', label: 'Query', key: 'Ctrl+J', run: () => go(queryScreen) },
    { id: 'reports', label: 'Reports', key: 'Ctrl+R', run: () => go((t) => reportsScreen(t, 'mine')) },
    { id: 'drafts', label: 'Drafts', key: 'Ctrl+D', run: () => go((t) => reportsScreen(t, 'drafts')) },
    { id: 'new', label: 'New Report', key: 'Ctrl+N', run: () => newReport({}) },
    { id: 'stats', label: 'Stats', key: 'Ctrl+T', run: () => go(statsScreen) },
    'sep',
    { id: 'popout', label: 'Pop Out', key: 'Ctrl+O', run: popOut },
    { id: 'close', label: 'Close', key: 'Esc', run: close },
];

const CIV_TOOLS = [
    { id: 'back', label: 'Back', key: 'Alt+Left', run: goBack },
    { id: 'fwd', label: 'Forward', key: 'Alt+Right', run: goFwd },
    'sep',
    { id: 'people', label: 'Characters', key: 'Alt+Home', run: () => go(civCharsScreen) },
    { id: 'car', label: 'Vehicles', key: 'Ctrl+K', run: () => go(civVehiclesScreen) },
    { id: 'reports', label: 'My Record', key: 'Ctrl+R', run: () => go(civRecordScreen) },
    { id: 'phone', label: 'Call 911', key: 'Ctrl+9', run: () => go(civ911Screen) },
    'sep',
    { id: 'close', label: 'Close', key: 'Esc', run: close },
];
// A medic's MDT (on shift as Ambulance in c3r): calls and units, patients by name, patient care reports.
const EMS_TOOLS = [
    { id: 'back', label: 'Back', key: 'Alt+Left', run: goBack },
    { id: 'fwd', label: 'Forward', key: 'Alt+Right', run: goFwd },
    { id: 'home', label: 'Home', key: 'Alt+Home', run: () => go(homeScreen) },
    'sep',
    { id: 'query', label: 'Patients', key: 'Ctrl+J', run: () => go(queryScreen) },
    { id: 'reports', label: 'Reports', key: 'Ctrl+R', run: () => go((t) => reportsScreen(t, 'mine')) },
    { id: 'drafts', label: 'Drafts', key: 'Ctrl+D', run: () => go((t) => reportsScreen(t, 'drafts')) },
    { id: 'new', label: 'New PCR', key: 'Ctrl+N', run: () => newReport({}) },
    'sep',
    { id: 'popout', label: 'Pop Out', key: 'Ctrl+O', run: popOut },
    { id: 'close', label: 'Close', key: 'Esc', run: close },
];
let tools = TOOLS;

// the CAD style's round badge: our own (LWK DEVELOPMENT), no agency's seal
const SEAL = `<svg class="seal" viewBox="0 0 64 64" aria-hidden="true"><defs><path id="sealring" d="M32 32m-24 0a24 24 0 1 1 48 0a24 24 0 1 1-48 0"/></defs>
    <circle cx="32" cy="32" r="31" fill="#0c2e62" stroke="#d8b65a" stroke-width="2"/><circle cx="32" cy="32" r="18" fill="#1a478b" stroke="#d8b65a"/>
    <text font-size="6.6" font-weight="700" fill="#f1e2b0" letter-spacing=".6"><textPath href="#sealring" textLength="148">LWK DEVELOPMENT ★ CODE3RESPONSE ★</textPath></text>
    <text x="32" y="36" text-anchor="middle" font-size="11" font-weight="800" fill="#fff">LWK</text></svg>`;

function buildToolbar() {
    const cad = isCad() && !CIV;
    $('#toolbar').innerHTML = tools.map((t) => {
        if (t === 'sep') return '<span class="tsep"></span>';
        const label = (cad && tools !== EMS_TOOLS && CAD_LABEL[t.id]) || t.label;
        return `<button class="tile" id="t-${t.id}" title="${label} (${t.key})"><svg viewBox="0 0 24 24">${(cad && CAD_ICON[t.id]) || ICONS[t.id]}</svg>
           <span>${label}</span><small>${t.key}</small></button>`;
    }).join('') + `<div class="brand"><b>lwk</b><small>${CIV ? 'CITIZEN PORTAL' : tools === EMS_TOOLS ? 'EMS DATA' : 'MOBILE DATA'}</small>${SEAL}</div>`;
    tools.forEach((t) => t !== 'sep' && ($(`#t-${t.id}`).onclick = t.run));
}
buildToolbar();

function navButtons() {
    $('#t-back').disabled = !hist.length;
    $('#t-fwd').disabled = !fwd.length;
}

const ACTIONS = {
    close, home: () => go(homeScreen), query: () => go(queryScreen), settings: () => openSettings(),
    reports: () => go((t) => reportsScreen(t, 'mine')), drafts: () => go((t) => reportsScreen(t, 'drafts')),
};
document.querySelectorAll('[data-act]').forEach((b) => (b.onclick = ACTIONS[b.dataset.act]));
$('#mycall').onclick = () => init.current && go((t) => reportScreen(t, init.current.id));

function setQuick(list) {
    list = arr(list);
    $('#quick').innerHTML = list.map((q, i) => `<button class="sbtn" data-q="${i}"><i style="--c:#5aa25a"></i>${h(q.label)}</button>`).join('');
    $('#quick').querySelectorAll('button').forEach((b) => {
        b.onclick = () => {
            post('run', { intent: list[b.dataset.q].intent });
            toast(`${list[b.dataset.q].label}: sent to dispatch`);
            setTimeout(async () => { // show the new status now, not at the next 5 s refresh
                const token = seq;
                await refresh();
                if (cur === homeScreen) renderBoard(token);
            }, 600);
        };
    });
}

// ─── status bar ──────────────────────────────────────────────────────────────

let myStatus = null;

function me() { return arr(init.units).find((u) => u.unit === init.officer); }

function statusBar() {
    if (CIV) {
        const a = arr(civ.characters).find((c) => c.key === civ.active);
        $('#sstatus').textContent = 'CIVILIAN';
        $('#sclock').textContent = clock(new Date());
        $('#sunit').textContent = `Active: ${a ? `${a.first} ${a.last}` : 'none'}`;
        return;
    }
    const u = me();
    const code = u ? u.status : (myStatus || 'OFFDT');
    $('#sstatus').textContent = myStatus && u && u.status === 'AVL' ? `${code} (${myStatus})` : code;
    $('#sdot').className = 'dot' + (code === 'AVL' ? '' : ' busy');
    const since = u ? Math.max(0, now() - u.since) : 0;
    $('#ssince').textContent = `${pad(Math.floor(since / 3600))}:${pad(Math.floor(since / 60) % 60)}:${pad(Math.floor(since) % 60)}`;
    $('#scall').textContent = init.current ? `Active Call #${init.current.id}` : 'No Active Call';
    $('#sclock').textContent = clock(new Date());
    $('#sdrafts').textContent = `Drafts: ${arr(init.drafts).length}`;
    $('#sunits').textContent = `Units: ${arr(init.units).length}`;
    $('#sunit').textContent = `Unit: ${init.officer || '-'}`;
    $('#mycall').disabled = !init.current;
}

async function refresh() {
    const res = await req('init');
    if (res.error) return;
    init = res;
    const want = CIV ? tools : init.medic ? EMS_TOOLS : TOOLS; // (going on or off shift as a medic swaps the toolbar)
    if (want !== tools) { tools = want; buildToolbar(); navButtons(); }
    if (res.now) skew = res.now - Date.now() / 1000;
    statusBar();
}

// ─── grids ───────────────────────────────────────────────────────────────────

// cols: [label, width]; rows: { open: 'report:12', cls: 'row class', cells: [[text, class]] }
function grid(cols, rows, empty) {
    const head = `<colgroup><col style="width:24px">${cols.map(([, w]) => `<col${w ? ` style="width:${w}"` : ''}>`).join('')}</colgroup>
        <thead><tr><th class="rh">All</th>${cols.map(([l]) => `<th>${h(l)}</th>`).join('')}</tr></thead>`;
    const body = rows.length ? rows.map((r) => `<tr tabindex="0"${r.cls ? ` class="${r.cls}"` : ''} ${r.open ? `data-open="${h(r.open)}"` : ''}><td class="rh"></td>${
        r.cells.map(([v, c]) => `<td class="${c || ''}" title="${h(v)}">${h(v)}</td>`).join('')}</tr>`).join('')
        : `<tr class="empty"><td class="rh"></td><td colspan="${cols.length}">${h(empty || 'No records.')}</td></tr>`;
    return `<table class="grid">${head}<tbody>${body}</tbody></table>`;
}

// Click selects a row; double-click or Enter opens it, like the desktop CAD.
// Small sounds, made here (no files): a query coming back, a report saved or signed.
const sfx = (() => {
    let ctx;
    const tone = (hz, at, len, vol) => {
        ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
        const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime + at;
        o.frequency.value = hz;
        g.gain.setValueAtTime(vol, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + len);
        o.connect(g).connect(ctx.destination);
        o.start(t);
        o.stop(t + len);
    };
    const play = (f) => { try { f(); } catch { /* no audio: nothing lost */ } };
    return {
        ran: () => play(() => { tone(880, 0, 0.07, 0.05); tone(1175, 0.08, 0.09, 0.05); }),
        saved: () => play(() => tone(660, 0, 0.1, 0.05)),
        signed: () => play(() => { tone(660, 0, 0.08, 0.05); tone(880, 0.09, 0.08, 0.05); tone(1320, 0.18, 0.14, 0.05); }),
    };
})();

function wire(el) {
    el.querySelectorAll('tbody tr[tabindex]').forEach((tr) => {
        tr.onclick = () => { el.querySelectorAll('tr.sel').forEach((x) => x.classList.remove('sel')); tr.classList.add('sel'); };
        if (!tr.dataset.open) return;
        const go = () => (tr.dataset.open.startsWith('join:') ? joinCall(tr.dataset.open.slice(5)) : openItem(tr.dataset.open));
        tr.ondblclick = go;
        tr.onkeydown = (e) => e.key === 'Enter' && go();
    });
}

function openItem(s) {
    const i = s.indexOf(':'), kind = s.slice(0, i), key = s.slice(i + 1);
    if (kind === 'query') { remember(key); go((t) => queryScreen(t, key)); } // its own screen, so Back steps through queries
    if (kind === 'report') go((t) => reportScreen(t, key));
    if (kind === 'char') go((t) => civCharForm(t, key));
    if (kind === 'civrec') go((t) => civReportScreen(t, Number(key)));
    if (kind === 'person') go((t) => personScreen(t, key));
    if (kind === 'vehicle') go((t) => vehicleScreen(t, key));
}

const STATUS = { pending: ['PEND', 'rd'], open: ['ACTV', 'ye'], draft: ['DRFT', ''], signed: ['SGND', 'gy'] };
const UNIT_COLOR = { AVL: '', ENRT: 'ye', ONSC: 'gn', STOP: 'rd', PURS: 'rd', CNTC: 'or', BUSY: 'or' };

// "Strawberry Ave / Davis Ave, Davis" -> ["Strawberry Ave / Davis Ave", "Davis"]
function splitLoc(loc) {
    loc = loc || '';
    const i = loc.lastIndexOf(', ');
    return i < 0 ? [loc, ''] : [loc.slice(0, i), loc.slice(i + 2)];
}

function callRows(list) {
    return arr(list).map((c) => {
        const [loc, zone] = splitLoc(c.location);
        const [st, sc] = STATUS[c.status] || [c.status, ''];
        const old = c.status === 'open' && now() - c.started > 3600;
        return { open: `report:${c.id}`, cls: `st-${st}`, cells: [[c.id, 'cy'], [(c.title || c.kind || '').toUpperCase(), 'cy'], [loc], [zone], [c.priority ?? ''],
            [st, sc], [age(c.started), old || c.status !== 'open' ? 'rd' : ''], [c.officer]] };
    });
}

// c3r's calls: double-click one to attach to it, whoever's on it, popup or not.
function c3rRows(list) {
    return arr(list).filter((c) => !c.joined).map((c) => ({ open: `join:${c.id}`, cls: c.units ? 'st-ACTV' : 'st-OPEN', cells: [['C' + c.id, 'cy'], [String(c.name || '').toUpperCase(), 'cy'],
        [c.street || ''], [''], [c.priority ?? ''], [c.units ? `${c.units} ON` : 'OPEN', 'ye'], [''], ['Double-click to attach']] }));
}

async function joinCall(id) {
    const r = await req('joinCall', { id });
    if (r.error) return toast(r.error);
    toast('Attached to the call.');
    await refresh();
    rerender();
}

const CALL_COLS = [['Call#', '58px'], ['Nature', '22%'], ['Location', ''], ['Zone', '12%'], ['P', '26px'], ['Status', '62px'], ['Time', '58px'], ['Units', '12%']];
// the CAD style: a dispatch board's names and widths for the same columns
const CAD_CALL_COLS = [['Call#', '64px'], ['Nature', '10%'], ['Location', '23%'], ['City', '17%'], ['Pr.', '28px'], ['Status', '7%'], ['Time', '12%'], ['Units', '']];

// ─── home: all calls + all units ─────────────────────────────────────────────

function homeScreen(token) {
    setTitle('All Calls and All Units');
    view.innerHTML = `<div class="split"><div class="pane" id="calls"></div><div class="splitter"></div><div class="pane" id="units"></div></div>`;
    renderBoard(token);
}

function renderBoard(token) {
    if (stale(token) || !$('#calls')) return;
    const keep = (id) => $(`#${id} tr.sel`)?.dataset.open; // keep the selection across refreshes
    const selCall = keep('calls'), selUnit = keep('units');
    const cad = isCad();
    $('#calls').innerHTML = grid(cad ? CAD_CALL_COLS : CALL_COLS, [...c3rRows(init.c3r), ...callRows(init.calls)], 'No active calls.');
    const units = arr(init.units).map((u) => {
        const [loc, zone] = splitLoc(u.location);
        const c = UNIT_COLOR[u.status] || '';
        const desc = u.call ? `${u.kind || ''}${u.title ? ' - ' + u.title : ''}` : '(MDT)';
        return cad ? { open: u.call ? `report:${u.call}` : null, cls: `st-${u.status}`, cells: [[u.name || u.unit], [u.unit], [u.status], [u.call ?? ''],
                [age(u.since)], [loc || zone], [u.call ? `(MDT) ON CALL ${u.call}: ${desc}` : '(MDT) LOGGED IN']] }
            : { open: u.call ? `report:${u.call}` : null, cells: [[u.unit, c], [u.status, c], [age(u.since), now() - u.since > 1800 ? 'rd' : ''],
                [u.call ?? ''], [zone], [loc], [desc, c]] };
    });
    $('#units').innerHTML = cad ? grid([['Officer', '8.5%'], ['Unit', '7.5%'], ['Status', '6%'], ['Call#', '6%'], ['Time', '6.5%'], ['Location', '20%'], ['Description', '']], units, 'No units on duty.')
        : grid([['Unit', '13%'], ['Status', '62px'], ['Time', '58px'], ['Call#', '58px'], ['Zone', '12%'], ['Location', '22%'], ['Description', '']], units, 'No units on duty.');
    for (const [id, sel] of [['calls', selCall], ['units', selUnit]]) {
        if (sel) $(`#${id} tr[data-open="${CSS.escape(sel)}"]`)?.classList.add('sel');
        wire($(`#${id}`));
    }
    setTitle('All Calls and All Units');
}

// ─── query ───────────────────────────────────────────────────────────────────

// Last query and recent queries live in the page's own storage, so they survive a resource restart.
const store = {
    get(k, d) { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* storage off: this session only */ } },
};
let lastQuery = String(store.get('lwk_mdt.last', ''));
let recent = arr(store.get('lwk_mdt.recent', []));

// A query counts once it's submitted or one of its results is opened (not every keystroke).
function remember(q) {
    q = String(q || '').trim();
    if (!q) return;
    recent = [{ q, t: Date.now() / 1000 }, ...recent.filter((r) => r.q.toLowerCase() !== q.toLowerCase())].slice(0, 25);
    store.set('lwk_mdt.recent', recent);
    renderRecent();
}

function renderRecent() {
    const el = $('#recent');
    if (!el) return;
    el.innerHTML = grid([['Time', '50px'], ['Query', '']],
        recent.map((r) => ({ open: `query:${r.q}`, cells: [[hhmm(r.t), 'gy'], [r.q.toUpperCase(), 'cy']] })), 'No queries yet.');
    wire(el);
}

// shown = the query this screen was opened with; Back returns to it, not to whatever was typed last.
function queryScreen(token, shown = lastQuery) {
    lastQuery = shown;
    setTitle('Query');
    view.innerHTML = `<div class="qwrap"><div class="qmain">
            <fieldset><legend>Query</legend><form class="query" id="qf">
                <label for="q">Name / Plate:</label><input class="txt" id="q" autocomplete="off" spellcheck="false">
                <button class="btn default" type="submit">Search</button>
            </form><div class="hint">Last name, first name or plate. Double-click a registered owner on a vehicle return to run them.</div></fieldset>
            <div id="results"></div></div>
        <div class="qside"><div class="sect">Recent Queries <span class="grow"></span><button class="sbtn" id="qclear">Clear</button></div>
            <div class="pane" id="recent"></div></div></div>`;
    if (init.medic) {
        $('label[for=q]').textContent = 'Name:';
        $('#qf').nextElementSibling.textContent = 'Last name, first name. A patient shows their earlier patient care reports.';
    }
    const q = $('#q');
    q.value = lastQuery;
    q.focus();
    q.select();
    let timer;
    q.oninput = () => { clearTimeout(timer); timer = setTimeout(() => runQuery(token, q.value), 250); };
    $('#qf').onsubmit = (e) => {
        e.preventDefault();
        clearTimeout(timer);
        const v = q.value;
        remember(v);
        if (v.trim() && v !== shown) go((t) => queryScreen(t, v)); // a new query is a new screen
        else runQuery(token, v);
    };
    // opening a result also files the query (the row's own handler navigates)
    $('#results').ondblclick = () => remember(lastQuery);
    $('#results').onkeydown = (e) => e.key === 'Enter' && remember(lastQuery);
    $('#qclear').onclick = () => { recent = []; store.set('lwk_mdt.recent', recent); renderRecent(); };
    renderRecent();
    runQuery(token, lastQuery);
}

async function runQuery(token, q) {
    lastQuery = q;
    store.set('lwk_mdt.last', q);
    if (!q.trim()) return ($('#results').innerHTML = '');
    const res = await req('search', { q });
    if (stale(token) || $('#q')?.value !== q) return;
    sfx.ran();
    const vehicles = arr(res.vehicles), people = arr(res.people);
    if (init.medic) {
        $('#results').innerHTML = `<div class="sect">Patients (${people.length}) <small>double-click to open</small></div>
            <div class="pane">${grid([['Name', '34%'], ['DOB', '120px'], ['Sex', '80px'], ['Last seen', '']],
                people.map((p) => ({ open: `person:${p.key}`, cells: [[`${p.last || ''}, ${p.first || ''}`.toUpperCase(), 'cy'], [p.dob], [p.gender],
                    [p.last_seen ? when(p.last_seen) : '']] })), 'No patients by that name.')}</div>`;
        return wire($('#results'));
    }
    $('#results').innerHTML = `<div class="sect">Vehicles (${vehicles.length}) <small>double-click to open</small></div>
        <div class="pane">${grid([['Plate', '90px'], ['Year', '52px'], ['Color', '12%'], ['Make', '14%'], ['Model', '14%'], ['Owner', ''], ['Flags', '22%']],
            vehicles.map((v) => ({ open: `vehicle:${v.plate}`, cells: [[v.plate, 'cy'], [v.year], [v.color], [v.make], [v.model], [v.owner],
                [vehicleFlags(v).join(' '), 'rd']] })), 'No vehicles.')}</div>
        <div class="sect">Persons (${people.length})</div>
        <div class="pane">${grid([['Name', '24%'], ['DOB', '96px'], ['Sex', '60px'], ['Licence', '12%'], ['Flags', ''], ['Contacts', '70px']],
            people.map((p) => ({ open: `person:${p.key}`, cells: [[`${p.last || ''}, ${p.first || ''}`.toUpperCase(), 'cy'], [p.dob], [p.gender],
                [p.dl, p.dl_valid === false ? 'ye' : ''], [arr(p.flags).join(', '), 'rd'], [arr(p.contacts).length]] })), 'No persons.')}</div>`;
    wire($('#results'));
}

function vehicleFlags(v) {
    return [v.stolen && 'STOLEN', v.bolo && 'BOLO', v.reg_valid === false && 'REG INVALID', v.ins_valid === false && 'UNINSURED'].filter(Boolean);
}

// ─── query returns ───────────────────────────────────────────────────────────

const up = (v) => String(v ?? '').toUpperCase();
const field = (k, v, w = 0) => (v === undefined || v === null || v === '' ? '' : `${k}/${up(v)}`.padEnd(w));
const line = (cls, text) => `<span class="${cls}">${h(text)}</span>`;

function returnPane(head, lines, alerts) {
    const stamp = new Date().toLocaleString();
    return `<div class="pane"><pre class="return">${line('cy', head.padEnd(48) + stamp)}
${lines.filter((l) => l.trim()).map((l) => h(l.trimEnd())).join('\n')}

${alerts.length ? alerts.map(([cls, t]) => line(cls, `*** ${up(t)} ***`)).join('\n') : line('gn', '-- NO WANTS, WARRANTS OR FLAGS ON FILE --')}
${line('gy', '-- END OF RETURN --')}</pre></div>`;
}

function recordBar(title, onNew, attachArgs) {
    view.innerHTML = `<div class="formbar"><h2>${h(title)}</h2><span class="grow"></span>
        <button class="btn" id="attach" ${init.current ? '' : 'disabled title="You have no open incident"'}>Add to Incident</button>
        <button class="btn" id="newr">New Report</button></div><div id="rec"></div>`;
    $('#newr').onclick = onNew;
    $('#attach').onclick = async () => {
        const r = await req('attach', attachArgs);
        if (r.error) return toast(r.error);
        toast(`Added to incident #${r.id}.`);
        await refresh();
    };
}

function contactsGrid(list) {
    list = arr(list);
    if (init.medic) return `<div class="sect">Patient Care Reports (${list.length}) <small>double-click to open</small></div>
        <div class="pane">${grid([['PCR#', '58px'], ['Complaint', '34%'], ['Medic', ''], ['Date', '130px']],
            list.map((r) => ({ open: `report:${r.id}`, cells: [[r.id, 'cy'], [up(r.title || '')], [r.officer], [when(r.started)]] })),
            'No earlier patient care reports.')}</div>`;
    return `<div class="sect">Prior Contacts (${list.length}) <small>double-click to open</small></div>
        <div class="pane">${grid(CALL_COLS, callRows(list), 'No prior contacts.')}</div>`;
}

async function personScreen(token, key) {
    const res = await req('person', { key });
    if (stale(token)) return;
    if (!res.record) return toast('Record not found.');
    const p = res.record;
    if (init.medic) { // (who they are and their care history: nothing police hold)
        setTitle('Patient');
        view.innerHTML = `<div class="formbar"><h2>Patient: ${h(up(p.last))}, ${h(up(p.first))}</h2><span class="grow"></span>
            <button class="btn" id="newpcr">New PCR</button></div><div id="rec"></div>`;
        $('#newpcr').onclick = () => newReport({ person: p.key });
        $('#rec').innerHTML = returnPane('PATIENT', [
            field('NAM', `${p.last || ''}, ${p.first || ''}`, 34) + field('DOB', p.dob, 18) + field('SEX', p.gender),
            field('ADR', p.address), field('LAST SEEN', when(p.last_seen)),
        ], []) + contactsGrid(res.contacts);
        return wire(view);
    }
    setTitle('Person Return');
    recordBar(`Person: ${up(p.last)}, ${up(p.first)}`, () => newReport({ person: p.key }), { person: p.key });
    $('#rec').innerHTML = returnPane('QUERY RESPONSE - PERSON', [
        field('NAM', `${p.last || ''}, ${p.first || ''}`, 34) + field('DOB', p.dob, 18) + field('SEX', p.gender),
        field('ADR', p.address),
        field('OLN', p.dl, 26) + field('STATUS', p.dl_valid === false ? 'INVALID' : p.dl_valid === true ? 'VALID' : ''),
        field('LAST CONTACT', when(p.last_seen), 34) + field('CONTACTS', arr(p.contacts).length),
    ], arr(res.findings).map((f) => [/licence/i.test(f) ? 'ye' : 'rd', f])) + contactsGrid(res.contacts);
    wire(view);
}

async function vehicleScreen(token, plate) {
    const res = await req('vehicle', { key: plate });
    if (stale(token)) return;
    if (!res.record) return toast('Record not found.');
    const v = res.record;
    setTitle('Vehicle Return');
    recordBar(`Vehicle: ${v.plate}`, () => newReport({ plate: v.plate }), { plate: v.plate });
    $('#rec').innerHTML = returnPane('QUERY RESPONSE - VEHICLE', [
        field('LIC', v.plate, 14) + field('VYR', v.year, 10) + field('VMA', v.make, 18) + field('VMO', v.model, 20) + field('VCO', v.color),
        field('REG OWNER', v.owner),
        field('REG', v.reg_valid === false ? 'INVALID' : v.reg_valid === true ? 'VALID' : '', 16)
            + field('INS', v.ins_valid === false ? 'UNINSURED' : v.ins_valid === true ? 'VALID' : ''),
        field('LAST CONTACT', when(v.last_seen)),
    ], arr(res.findings).map((f) => [/stolen|bolo/i.test(f) ? 'rd' : 'ye', /^stolen$/i.test(f) ? 'STOLEN VEHICLE' : f])) + contactsGrid(res.contacts);
    // the registered owner: double-click runs them (their person return)
    const pre = $('#rec pre.return'), own = v.owner && h(`REG OWNER/${up(v.owner)}`);
    if (pre && own && pre.innerHTML.includes(own)) {
        pre.innerHTML = pre.innerHTML.replace(own, `<span class="runlink" id="runowner" title="Double-click to run this name">${own}</span>`);
        $('#runowner').ondblclick = async () => {
            const r = await req('owner', { plate: v.plate });
            if (!r || !r.key) return toast('No record of the owner on file.');
            remember(`${up(v.owner)}`);
            go((t) => personScreen(t, r.key));
        };
    }
    wire(view);
}

async function newReport(args) {
    const res = await req('new', args);
    if (res.id) go((t) => reportScreen(t, res.id));
}

// ─── reports ─────────────────────────────────────────────────────────────────

async function reportsScreen(token, filter) {
    const names = { all: 'All Reports', mine: 'My Reports', drafts: 'Drafts', signed: 'Signed' };
    setTitle(names[filter]);
    view.innerHTML = `<div class="formbar">${Object.entries(names).map(([k, l]) =>
        `<button class="btn${k === filter ? ' default' : ''}" data-f="${k}">${l}</button>`).join('')}
        <span class="grow"></span><button class="btn" id="deldrafts">${init.admin ? 'Delete All Drafts' : 'Delete My Drafts'}</button></div>
        <div class="pane" style="flex:1" id="rlist"></div>`;
    view.querySelectorAll('[data-f]').forEach((b) => (b.onclick = () => go((t) => reportsScreen(t, b.dataset.f))));
    if ($('#deldrafts')) $('#deldrafts').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = init.admin ? 'Confirm: delete every draft' : 'Confirm: delete all my drafts'; return; }
        const r = await req('deleteDrafts');
        if (r.error) return toast(r.error);
        toast(`${r.count} draft${r.count === 1 ? '' : 's'} deleted.`);
        await refresh();
        rerender();
    };
    const list = arr(await req('reports', { filter }));
    if (stale(token)) return;
    if (init.medic) {
        $('#rlist').innerHTML = grid([['PCR#', '58px'], ['Complaint', '22%'], ['Status', '62px'], ['Patient', ''], ['Location', '20%'], ['Medic', '12%'], ['Date', '120px']],
            list.map((r) => {
                const [st, sc] = STATUS[r.status] || [r.status, ''];
                return { open: `report:${r.id}`, cells: [[r.id, 'cy'], [up(r.title || ''), 'cy'], [st, sc], [arr(r.people).join(', ') || 'Unidentified'],
                    [r.location || ''], [r.officer], [when(r.started)]] };
            }), 'No patient care reports.');
        return wire($('#rlist'));
    }
    $('#rlist').innerHTML = grid([['Call#', '58px'], ['Type', '14%'], ['Nature', '18%'], ['Form', '17%'], ['Status', '62px'], ['Involved', ''], ['Officer', '12%'], ['Date', '120px'], ['Total', '70px']],
        list.map((r) => {
            const [st, sc] = STATUS[r.status] || [r.status, ''];
            return { open: `report:${r.id}`, cells: [[r.id, 'cy'], [r.kind], [up(r.title || ''), 'cy'], [r.form], [st, sc],
                [[...arr(r.people), ...arr(r.plates)].join(', ')], [r.officer], [when(r.started)], [r.total ? money(r.total) : '']] };
        }), 'No reports.');
    wire($('#rlist'));
}

// ─── stats ───────────────────────────────────────────────────────────────────

const STAT_COLS = [['Officer', 'name', ''], ['Stops', 'stops', '7%'], ['Contacts', 'contacts', '8%'], ['Citations', 'citations', '8%'],
    ['Warnings', 'warnings', '8%'], ['Arrests', 'arrests', '7%'], ['Pursuits won', 'pursuits_won', '9%'], ['Pursuits lost', 'pursuits_lost', '9%'],
    ['Callouts', 'callouts', '7%'], ['Assists', 'assists', '7%'], ['On duty', 'seconds', '9%']];
const dutyTime = (s) => `${Math.floor(s / 3600)}h ${String(Math.floor(s / 60) % 60).padStart(2, '0')}m`;

// Every officer on the server; a column heading sorts by it.
async function statsScreen(token, sort = 'seconds') {
    setTitle('Officer Stats');
    view.innerHTML = '<div class="pane" style="flex:1" id="rlist"></div>';
    const r = await req('stats');
    if (stale(token)) return;
    const up_first = sort === 'name' ? (a, b) => String(a.name).localeCompare(String(b.name)) : (a, b) => b[sort] - a[sort];
    const rows = arr(r.list).slice().sort(up_first).map((o) => ({ cells: STAT_COLS.map(([, k]) =>
        k === 'name' ? [o.you ? `${o.name} (you)` : o.name, o.you ? 'cy' : ''] : [k === 'seconds' ? dutyTime(o[k]) : o[k]]) }));
    $('#rlist').innerHTML = grid(STAT_COLS.map(([l, , w]) => [l, w]), rows, r.error || (r.off ? 'Stats are only available in game, with c3r running.' : 'No stats yet.'));
    wire($('#rlist'));
    $('#rlist').querySelectorAll('thead th:not(.rh)').forEach((th, i) => {
        th.style.cursor = 'pointer';
        th.onclick = () => show((t) => statsScreen(t, STAT_COLS[i][1]));
    });
}

// What's been picked or typed on a report but not saved yet, by report id: it stays through leaving the screen or
// closing the MDT, until saved or deleted.
const unsaved = {};

// A patient care report, on the same paper as the police forms: who, the call, the vitals, what was found, every
// treatment with its time, the disposition, and the narrative (CHART, from the care log until edited). No charges.
const STAR_OF_LIFE = '<span class="flogo">EMS</span>';

function pcrScreen(r) {
    const s = r.summary, ro = !r.can_edit, pc = r.pcr || {};
    const draft = !ro && unsaved[s.id];
    let auto = draft ? draft.auto : r.auto, dirty = !!draft;
    const signed = s.status === 'signed';
    const p = arr(r.people)[0] || {};
    const [addr, addrCity] = splitLoc(p.address);
    const [loc, zone] = splitLoc(s.location);
    const at = (t) => (t ? hhmm(t) : '');
    const contact = pc.contact || s.started;
    setTitle(`Patient Care Report #${s.id}`);
    const vit = (label, v) => v && `<tr><td>${h(label)}</td><td>${at(v.t)}</td><td>${h(v.hr ?? '-')}</td><td>${h(v.sys ? `${v.sys}/${v.dia}` : '---')}</td>
        <td>${h(v.spo2 != null ? `${v.spo2}%` : '-')}</td><td>${h(v.rr ?? '-')}</td><td>${h(v.etco2 ?? '-')}</td><td>${h(v.gcs ?? '-')}</td><td>${h(up(v.rhythm || ''))}</td></tr>`;

    view.innerHTML = `<div class="fdesk">
        <aside class="fside"><div class="fsidehead">All Forms</div>
            <button class="fpick on" disabled>${STAR_OF_LIFE}<span>Patient Care Report</span></button></aside>
        <section class="fmain">
            <div class="ftabs"><span class="ftab" id="ftab"></span></div>
            <div class="fqa"><b>Quick Actions</b><span class="grow"></span>
                ${ro ? '' : `<button class="fbtn" id="rebuild" title="Replace the narrative with a fresh draft from the care log">Rebuild Narrative</button>
                    <button class="fbtn" id="del">Delete</button>
                    <button class="fbtn" id="save">${signed ? 'Save Changes' : 'Save'}</button>
                    ${signed ? '' : '<button class="fbtn go" id="sign">Sign</button>'}`}</div>
            <div class="fscroll"><div class="paper">
                <div class="stamp ${h(s.status)}">${h(DONE_STAMP[s.status] || up(s.status))}</div>
                <div class="ftop">${STAR_OF_LIFE}<div><u>${h(up(init.agency || 'San Andreas Emergency Medical Services'))}</u><h3>PATIENT CARE REPORT</h3></div></div>
                ${ro ? '<div class="fro">Read only: only the author or a supervisor can change this report.</div>' : ''}
                <div class="fr"><div style="grid-column:span 6"></div>${fbox('PCR Number', s.id, 3, 'big')}${fbox('Chief Complaint', up(pc.complaint || s.title), 3)}</div>
                ${fhead('Patient')}
                ${frow(fbox('Name: First', up(p.first), 5), fbox('Middle', '', 3), fbox('Last', up(p.last || (p.first ? '' : 'UNIDENTIFIED')), 4))}
                ${frow(fbox('Date of Birth', p.dob, 3), fbox('Gender', up(p.gender), 2), fbox('Weight', '', 2), fbox('Allergies', '', 5))}
                ${frow(fbox('Residential Address', up(addr), 5), fbox('City', up(addrCity), 3), fbox('State', p.address ? 'SA' : '', 1), fbox('Phone Number', '', 3))}
                ${arr(r.people).length ? ptable(['Type', 'Patient on file (double-click to open)', 'DOB', 'Gender'], arr(r.people).map((x) => `<tr tabindex="0" data-open="person:${h(x.key)}">
                    <td>PATIENT</td><td>${h(up(`${x.last || ''}, ${x.first || ''}`))}</td><td>${h(x.dob || '')}</td><td>${h(up(x.gender || ''))}</td></tr>`), '') : ''}
                ${fhead('Incident')}
                ${frow(fbox('Date', contact ? new Date(contact * 1000).toLocaleDateString() : '', 2), fbox('Patient Contact', at(contact), 2),
                    fbox('Left Scene', at(pc.left_scene), 2), fbox('Call Closed', at(pc.ended), 2), fbox('Medic', s.officer, 4))}
                ${frow(fbox('Location', up(loc), 7), fbox('City / Zone', up(zone), 3), fbox('County', '', 2))}
                ${pc.says ? frow(fbox('Patient Statement', `"${pc.says}"`, 12)) : ''}
                ${fhead('Vital signs')}
                ${ptable(['Set', 'Time', 'HR', 'BP', 'SpO2', 'RR', 'EtCO2', 'GCS', 'Rhythm'], [vit('Initial', pc.first), vit('Final', pc.last)].filter(Boolean), 'No monitor readings.')}
                ${fhead('Assessment / findings')}
                ${ptable(['Area', 'Finding', 'Status'], arr(pc.findings).map((f) => `<tr><td>${h(up(f.part || ''))}</td><td>${h(f.text)}</td>
                    <td class="${f.treated ? '' : 'flag'}">${f.treated ? 'TREATED' : 'OPEN'}</td></tr>`), 'Nothing found.')}
                ${fhead('Treatment given')}
                ${ptable(['Time', 'Treatment'], arr(pc.care).map((e) => `<tr><td>${at(e.t)}</td><td>${h(e.text)}</td></tr>`), 'Nothing logged.')}
                ${fhead('Disposition')}
                <div class="fr"><div class="fb" style="grid-column:span 7"><span>Outcome</span><b class="cks">${tick(pc.outcome === 'transported', 'Transported')}
                    ${tick(pc.outcome === 'pronounced', 'Pronounced dead')}${tick(!pc.outcome, 'Not recorded')}</b></div>
                    ${fbox('Destination', up(pc.hospital), 5)}</div>
                <div class="fr"><div class="fb" style="grid-column:span 12"><span>Cardiac Arrest</span><b class="cks">${tick(pc.arrested, 'Yes')}${tick(!pc.arrested, 'No')}
                    ${tick(pc.rosc, 'ROSC achieved')}</b></div></div>
                ${fhead(`Narrative (CHART)${auto ? ': auto, written from the care log until edited' : ''}`)}
                <textarea class="fnarr" id="narr" aria-label="Narrative" spellcheck="true" ${ro ? 'readonly' : ''}></textarea>
                <div class="fcert">I certify that the care described above was given by me or under my direction, and that this report is true and correct.</div>
                <div class="fr fsig">${fbox('Medic Signature', r.signed_by || '', 6, 'sig')}${fbox('Date Signed', r.signed_at ? when(r.signed_at) : '', 3)}${fbox('Unit', s.officer, 3)}</div>
                <div class="ffoot">${h(up(init.agency || 'San Andreas Emergency Medical Services'))} &middot; FORM PCR-${h(s.id)} &middot; LWK DEVELOPMENT</div>
            </div></div>
        </section></div>`;
    const narr = $('#narr');
    narr.value = draft ? draft.narrative : r.narrative || '';
    wire(view);
    const tab = () => ($('#ftab').textContent = `Patient Care Report${dirty ? '*' : ''} - ${s.id} (${(STATUS[s.status] || [s.status])[0]})`);
    tab();
    if (ro) return;
    const keep = () => { dirty = true; unsaved[s.id] = { form: 'pcr', charges: [], narrative: narr.value, auto }; tab(); };
    narr.oninput = () => { auto = false; keep(); };
    const save = async (sign) => {
        const res = await req('save', { id: s.id, form: 'pcr', charges: [], narrative: narr.value, auto, sign });
        if (res.error) return toast(res.error);
        delete unsaved[s.id];
        (sign ? sfx.signed : sfx.saved)();
        toast(sign ? `Patient care report #${s.id} signed.` : `Patient care report #${s.id} saved.`);
        await refresh();
        rerender();
    };
    $('#save').onclick = () => save(false);
    if ($('#sign')) $('#sign').onclick = () => save(true);
    $('#rebuild').onclick = () => { auto = true; save(false); };
    $('#del').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm Delete'; return; }
        const res = await req('delete', { id: s.id });
        if (res.error) return toast(res.error);
        delete unsaved[s.id];
        toast(`Patient care report #${s.id} deleted.`);
        await refresh();
        show(hist.length ? hist.pop() : homeScreen);
        fwd.length = 0;
        navButtons();
    };
}

// A report is a paper form on a desk: the forms down the left, the open form's tab, its actions, then the page.
// Everything on the page comes from the incident (c3r's people, vehicles and timeline); the officer picks the
// form, the charges and writes the narrative.
const FORM_TITLE = { citation: 'Traffic Citation and Notice to Appear', warning: 'Written Warning', arrest: 'Arrest Report', incident: 'Incident Report' };
const BADGE = '<span class="flogo">POLICE</span>'; // plain text, no agency's badge
const fbox = (label, value, span, cls = '') => `<div class="fb ${cls}" style="grid-column:span ${span}"><span>${h(label)}</span><b>${h(value ?? '')}</b></div>`;
const frow = (...boxes) => `<div class="fr">${boxes.join('')}</div>`;
const fhead = (text, id) => `<div class="fh"${id ? ` id="${id}"` : ''}>${h(text)}</div>`;
const tick = (on, label) => `<em><i class="ck${on ? ' on' : ''}"></i>${h(label)}</em>`;
const ptable = (cols, rows, empty) => `<table class="ft"><thead><tr>${cols.map((c) => `<th>${h(c)}</th>`).join('')}</tr></thead><tbody>${rows.length ? rows.join('')
    : `<tr><td colspan="${cols.length}" class="none">${h(empty)}</td></tr>`}</tbody></table>`;
const DONE_STAMP = { signed: 'SIGNED', pending: 'PENDING', open: 'OPEN', draft: 'DRAFT' };

async function reportScreen(token, id, presetForm) {
    const r = await req('report', { id: Number(id) });
    if (stale(token)) return;
    if (r && r.pcr) return pcrScreen(r);
    if (!r || !r.summary) return toast('Report not found.');
    const list = await chargeList();
    if (stale(token)) return;
    const s = r.summary, ro = !r.can_edit;
    const draft = !ro && unsaved[s.id];
    let form = presetForm || (draft ? draft.form : r.form), auto = draft ? draft.auto : r.auto, dirty = !!draft;
    const picked = new Set(draft ? draft.charges : arr(r.charges).map((c) => c.id));
    const dis = ro ? 'disabled' : '';
    // signed: what's on it goes to the top, where it's seen at a glance (the sort is stable: code order within)
    const signed = s.status === 'signed';
    const rows = list.map((c, i) => ({ c, i, on: picked.has(chargeId(c)) }));
    if (signed) rows.sort((a, b) => b.on - a.on);
    const groupOf = (x) => (signed && x.on ? 'ON' : x.c.code);
    const groupName = (g) => (g === 'ON' ? 'On this report' : GROUPS[g] || g);
    const formLabel = (f) => (arr(init.forms).find((x) => x.id === f) || {}).label || f;
    setTitle(`Incident #${s.id}`);

    const p = arr(r.people)[0] || {}, v = arr(r.vehicles)[0] || {};
    const [addr, addrCity] = splitLoc(p.address);
    const [loc, zone] = splitLoc(s.location);
    const started = s.started ? new Date(s.started * 1000) : null;
    const parties = [
        ...arr(r.people).map((x) => `<tr tabindex="0" data-open="person:${h(x.key)}"><td>PERSON</td><td>${h(up(`${x.last || ''}, ${x.first || ''}`))}</td>
            <td>${h(x.dob ? `DOB ${x.dob}` : '')}</td><td class="flag">${h([...arr(x.flags), x.dl_valid === false ? 'LICENCE ' + up(x.dl || 'INVALID') : ''].filter(Boolean).join(', '))}</td></tr>`),
        ...arr(r.vehicles).map((x) => `<tr tabindex="0" data-open="vehicle:${h(x.plate)}"><td>VEHICLE</td><td>${h(x.plate)}</td>
            <td>${h(up([x.year, x.color, x.make, x.model].filter(Boolean).join(' ')))}</td><td class="flag">${h(vehicleFlags(x).join(', '))}</td></tr>`),
    ];

    view.innerHTML = `<div class="fdesk">
        <aside class="fside"><div class="fsidehead">All Forms</div>${arr(init.forms).map(({ id: k, label: l }) =>
            `<button class="fpick${k === form ? ' on' : ''}" data-form="${h(k)}" ${dis}>${BADGE}<span>${h(l)}</span></button>`).join('')}</aside>
        <section class="fmain">
            <div class="ftabs"><span class="ftab" id="ftab"></span></div>
            <div class="fqa"><b>Quick Actions</b><span class="grow"></span>
                ${r.coords ? '<button class="fbtn" id="wp">Set Waypoint</button>' : ''}
                ${s.status === 'pending' ? '<button class="fbtn" id="respond">Respond</button>' : ''}
                ${ro ? '' : `<button class="fbtn" id="mch">Manage Charges</button>
                    <button class="fbtn" id="rebuild" title="Replace the narrative with a fresh draft from the timeline">Rebuild Narrative</button>
                    <button class="fbtn" id="del">Delete</button>
                    <button class="fbtn" id="save">${signed ? 'Save Changes' : 'Save'}</button>
                    ${signed ? '' : '<button class="fbtn go" id="sign">Sign</button>'}`}</div>
            <div class="fscroll"><div class="paper">
                <div class="stamp ${h(s.status)}">${h(DONE_STAMP[s.status] || up(s.status))}</div>
                <div class="ftop">${BADGE}<div><u>${h(up(init.agency || 'San Andreas Police Department'))}</u><h3 id="ftitle"></h3></div></div>
                ${ro ? '<div class="fro">Read only: only the author or a supervisor can change this report.</div>' : ''}
                <div class="fr"><div style="grid-column:span 6"></div>${fbox('Form Number', s.id, 3, 'big')}${fbox('Report Type', up(s.kind), 3)}</div>
                ${fhead('', 'fdef')}
                ${frow(fbox("Driver's Licence Number", p.dl, 4), fbox('State', p.dl ? 'SA' : '', 1), fbox('Status', p.dl_valid === false ? 'INVALID' : p.dl_valid === true ? 'VALID' : '', 2),
                    fbox('Endorsements', '', 3), fbox('Restrictions', '', 2))}
                ${frow(fbox('Name: First', up(p.first), 5), fbox('Middle', '', 3), fbox('Last', up(p.last), 4))}
                ${frow(fbox('Residential Address', up(addr), 5), fbox('City', up(addrCity), 3), fbox('State', p.address ? 'SA' : '', 1), fbox('Postal', '', 1), fbox('Phone Number', '', 2))}
                ${frow(fbox('Gender', up(p.gender), 2), fbox('Eyes', '', 1), fbox('Hair', '', 1), fbox('Height', '', 1), fbox('Weight', '', 1), fbox('Date of Birth', p.dob, 2),
                    fbox('Flags', up(arr(p.flags).join(', ')), 4, 'flag'))}
                ${frow(fbox('Licence Plate', v.plate, 2), fbox('Year', v.year, 1), fbox('Color', up(v.color), 2), fbox('Make', up(v.make), 2), fbox('Model', up(v.model), 2),
                    fbox('State', v.plate ? 'SA' : '', 1), fbox('Registration', v.reg_valid === false ? 'INVALID' : v.reg_valid === true ? 'VALID' : '', 2))}
                ${frow(fbox('Registered Owner', up(v.owner), 6), fbox('Insurance', v.ins_valid === false ? 'UNINSURED' : v.ins_valid === true ? 'VALID' : '', 3),
                    fbox('Vehicle Flags', vehicleFlags(v).join(', '), 3, 'flag'))}
                ${fhead('The undersigned certifies that:')}
                ${frow(fbox('Date', started ? started.toLocaleDateString() : '', 2), fbox('Time', started ? hhmm(s.started) : '', 1),
                    fbox('Nature', up(s.title || s.kind), 4), fbox('Reporting Officer', s.officer, 3), fbox('Caller', r.caller, 2))}
                ${frow(fbox('Location', up(loc), 7), fbox('City / Zone', up(zone), 3), fbox('County', '', 2))}
                <div id="fcharges"></div>
                ${fhead('Parties and vehicles on this report (double-click to open)')}
                ${ptable(['Type', 'Identifier', 'Description', 'Flags'], parties, 'Nobody attached.')}
                ${fhead(`Narrative${auto ? ' (auto: follows the timeline until edited)' : ''}`)}
                <textarea class="fnarr" id="narr" aria-label="Narrative" spellcheck="true" ${ro ? 'readonly' : ''}></textarea>
                <div class="fcert" id="fcert"></div>
                <div class="fr fsig">${fbox('Officer Signature', r.signed_by || '', 6, 'sig')}${fbox('Date Signed', r.signed_at ? when(r.signed_at) : '', 3)}${fbox('Callsign', s.officer, 3)}</div>
                ${fhead('Incident log')}
                ${ptable(['Time', 'Event'], arr(r.events).map((e) => `<tr><td>${hhmm(e.t)}</td><td>${h(e.text)}</td></tr>`), 'Nothing logged.')}
                <div class="ffoot">${h(up(init.agency || 'San Andreas Police Department'))} &middot; FORM ${h(up(form))}-${h(s.id)} &middot; LWK DEVELOPMENT</div>
            </div></div>
        </section></div>
        <div class="dlg fchdlg" id="chdlg" role="dialog" aria-modal="true" aria-labelledby="chead" hidden>
            <div class="dlgtitle" id="chead">Charges</div>
            <div class="dlgbody">
                <input class="txt" id="csearch" placeholder="Search section, charge or description" aria-label="Search charges" autocomplete="off">
                <div class="listbox charges">${rows.map((x, n) => { const c = x.c, g = groupOf(x); return `${n === 0 || groupOf(rows[n - 1]) !== g ? `<div class="cgroup" data-g="${h(g)}">${h(groupName(g))}</div>` : ''}
                    <label data-g="${h(g)}" data-text="${h(`${chargeId(c)} ${c.label} ${c.desc || ''}`.toLowerCase())}" title="${h(c.desc || '')}">
                    <input type="checkbox" data-c="${x.i}" ${x.on ? 'checked' : ''} ${dis}>
                    <span class="sec">${h(chargeId(c))}</span><span class="cname">${h(c.label)}</span>
                    <span class="cls ${h(c.class)}">${CLASS[c.class] || ''}</span>
                    <span class="pts">${c.points ? `${c.points} pt` : ''}</span><span class="fine">${money(c.fine)}</span></label>`; }).join('')}</div>
                <div class="dlgbtns"><span class="total" id="total"></span><span class="grow"></span><button class="btn default" id="chdone">Done</button></div>
            </div></div>`;

    if ($('#wp')) $('#wp').onclick = async () => { const w = await req('waypoint', { id: s.id }); toast(w.error || 'Waypoint set.'); };
    if ($('#respond')) $('#respond').onclick = async () => {
        const w = await req('respond', { id: s.id });
        if (w.error) return toast(w.error);
        await req('waypoint', { id: s.id });
        toast(`Responding to 911 #${s.id}. Waypoint set.`);
        await refresh();
        rerender();
    };
    const narr = $('#narr');
    narr.value = draft ? draft.narrative : r.narrative || '';
    wire(view);

    const chosen = () => list.filter((_, i) => $(`[data-c="${i}"]`)?.checked).map(chargeId);
    const keep = () => { if (!ro) { dirty = true; unsaved[s.id] = { form, charges: chosen(), narrative: narr.value, auto }; tab(); } };
    const tab = () => ($('#ftab').textContent = `${formLabel(form)}${dirty ? '*' : ''} - ${s.id} (${(STATUS[s.status] || [s.status])[0]})`);
    narr.oninput = () => { auto = false; keep(); };
    const update = () => {
        const warn = form === 'warning', inc = form === 'incident';
        $('#ftitle').textContent = up(FORM_TITLE[form] || formLabel(form));
        $('#fdef').textContent = inc ? 'Subject' : form === 'arrest' ? 'Arrestee' : 'Defendant';
        $('#chead').textContent = warn ? 'Violations' : 'Charges';
        $('#fcert').textContent = warn ? 'This is a warning only. No fine is due and no court appearance is required. A further violation may be cited.'
            : form === 'citation' ? 'Without admitting guilt, the person named above promises to pay the fine shown or to appear in court on the date given.'
            : form === 'arrest' ? 'The person named above was placed under arrest for the charges listed, and advised of their rights.'
            : 'I declare that the information in this report is true and correct to the best of my knowledge.';
        const ids = chosen();
        const on = list.filter((c) => ids.includes(chargeId(c)));
        const total = on.reduce((n, c) => n + Number(c.fine || 0), 0), pts = on.reduce((n, c) => n + Number(c.points || 0), 0);
        $('#fcharges').innerHTML = fhead(inc ? 'Offenses noted:' : warn ? 'The driver was warned for the following:' : 'The defendant committed the following:')
            + (on.length ? on.map((c) => frow(fbox('Section', chargeId(c), 3), fbox('Violation', up(c.label), 9))
                + `<div class="fr"><div class="fb" style="grid-column:span 7"><span>Offense Classification</span><b class="cks">${tick(c.class === 'I', 'Infraction')}${tick(c.class === 'M', 'Misdemeanor')}${tick(c.class === 'F', 'Felony')}</b></div>
                    ${fbox('Fine Amount', warn ? 'NONE' : money(c.fine), 3)}${fbox('Points', c.points || 0, 2)}</div>`).join('')
                : frow(fbox('Section', '', 3), fbox('Violation', ro ? '' : 'NONE SELECTED: USE MANAGE CHARGES', 9, 'hint')))
            + frow(fbox('Counts', on.length, 3), fbox(warn ? 'Fine' : 'Total Fine', warn ? 'WRITTEN WARNING: NO FINE' : money(total), 6), fbox('Total Points', pts, 3));
        $('#total').textContent = `${ids.length} selected · ` + (warn ? 'Written warning: no fine' : `Total fine: ${money(total)}`);
        view.querySelectorAll('.fpick').forEach((b) => b.classList.toggle('on', b.dataset.form === form));
        tab();
    };
    view.querySelectorAll('.fpick').forEach((b) => (b.onclick = () => { form = b.dataset.form; update(); keep(); }));
    view.querySelectorAll('[data-c]').forEach((c) => (c.onchange = () => { update(); keep(); }));
    // every word must match; picked charges stay visible so you can see what's on the report
    $('#csearch').oninput = () => {
        const terms = $('#csearch').value.toLowerCase().split(/\s+/).filter(Boolean);
        const shown = new Set();
        view.querySelectorAll('.charges label').forEach((l) => {
            l.hidden = !(l.querySelector('input').checked || terms.every((t) => l.dataset.text.includes(t)));
            if (!l.hidden) shown.add(l.dataset.g);
        });
        view.querySelectorAll('.cgroup').forEach((g) => (g.hidden = !shown.has(g.dataset.g)));
    };
    update();
    if (ro) return;

    $('#mch').onclick = () => { $('#veil').hidden = false; $('#chdlg').hidden = false; setTimeout(() => $('#csearch').focus(), 50); };
    $('#chdone').onclick = closeCharges;
    const save = async (sign) => {
        const res = await req('save', { id: s.id, form, charges: chosen(), narrative: narr.value, auto, sign });
        if (res.error) return toast(res.error);
        delete unsaved[s.id];
        (sign ? sfx.signed : sfx.saved)();
        toast(sign ? `Incident #${s.id} signed.` : `Incident #${s.id} saved.`);
        await refresh();
        rerender();
    };
    $('#save').onclick = () => save(false);
    if ($('#sign')) $('#sign').onclick = () => save(true);
    $('#rebuild').onclick = () => { auto = true; save(false); };
    $('#del').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm Delete'; return; }
        const res = await req('delete', { id: s.id });
        if (res.error) return toast(res.error);
        delete unsaved[s.id];
        toast(`Incident #${s.id} deleted.`);
        await refresh();
        show(hist.length ? hist.pop() : homeScreen); // not goBack: Forward would lead to the deleted report
        fwd.length = 0;
        navButtons();
    };
}

function closeCharges() {
    const d = $('#chdlg');
    if (!d || d.hidden) return false;
    d.hidden = true;
    $('#veil').hidden = true;
    return true;
}

// ─── citizen portal ──────────────────────────────────────────────────────────

let civ = { characters: [], vehicles: [], record: [], flags: [], licences: [] };

async function civRefresh() {
    const r = await req('civInit');
    if (!r.error) civ = r;
    statusBar();
}

async function civStart() {
    const reopen = CIV && cur; // (still the Citizen Portal: back to the screen it was closed on)
    CIV = true;
    document.body.classList.add('civ');
    tools = CIV_TOOLS;
    buildToolbar();
    $('#mdt').classList.add('open');
    await civRefresh();
    if (reopen) return rerender();
    hist.length = 0;
    fwd.length = 0;
    cur = null;
    show(civCharsScreen);
}

// After a save or delete: back to the list, without a Forward into the form just left.
function leave(fallback) {
    show(hist.length ? hist.pop() : fallback);
    fwd.length = 0;
    navButtons();
}

const selected = (el) => el.querySelector('tr.sel')?.dataset.open?.replace(/^[a-z]+:/, '');

function civCharsScreen() {
    setTitle('My Characters');
    view.innerHTML = `<div class="formbar"><h2>My Characters</h2><span class="grow"></span>
            <button class="btn" id="cact" disabled>Set Active</button><button class="btn" id="cedit" disabled>Edit</button>
            <button class="btn" id="cdel" disabled>Delete</button><button class="btn default" id="cnew">New Character</button></div>
        <div class="pane" style="flex:1" id="clist">${grid([['Active', '54px'], ['Name', '22%'], ['DOB', '96px'], ['Sex', '70px'], ['Address', ''], ['Licence', '90px'], ['Flags', '24%']],
            arr(civ.characters).map((c) => ({ open: `char:${c.key}`, cells: [[c.key === civ.active ? 'ACTIVE' : '', 'gn'],
                [`${c.last}, ${c.first}`.toUpperCase(), 'cy'], [c.dob], [c.gender], [c.address], [c.dl, c.dl === 'Valid' ? '' : 'ye'],
                [arr(c.flags).join(', '), 'rd']] })), 'No characters yet. Press New Character.')}</div>
        <div class="hint">Your active character is the ID /showid shows and the owner /vehreg registers vehicles to. Police find your characters in their searches.</div>`;
    const list = $('#clist');
    wire(list);
    list.addEventListener('click', () => ['#cact', '#cedit', '#cdel'].forEach((b) => ($(b).disabled = !selected(list))));
    $('#cnew').onclick = () => go((t) => civCharForm(t, null));
    $('#cedit').onclick = () => go((t) => civCharForm(t, selected(list)));
    $('#cact').onclick = async () => {
        const r = await req('civActive', { key: selected(list) });
        if (r.error) return toast(r.error);
        await civRefresh();
        rerender();
    };
    $('#cdel').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm: delete with its vehicles'; return; }
        const r = await req('civDelete', { key: selected(list) });
        if (r.error) return toast(r.error);
        toast('Character deleted.');
        await civRefresh();
        rerender();
    };
}

function civCharForm(token, key) {
    const c = arr(civ.characters).find((x) => x.key === key) || {};
    const editing = !!c.key;
    setTitle(editing ? 'Edit Character' : 'New Character');
    const opt = (list, v) => list.map((o) => `<option ${o === v ? 'selected' : ''}>${h(o)}</option>`).join('');
    view.innerHTML = `<div class="formbar"><h2>${editing ? `Edit: ${h(c.first)} ${h(c.last)}` : 'New Character'}</h2></div>
        <fieldset><legend>Identity</legend><div class="form2">
            <label for="f-first">First name</label><input class="txt" id="f-first" maxlength="40" ${editing ? 'disabled' : ''}>
            <label for="f-last">Last name</label><input class="txt" id="f-last" maxlength="40" ${editing ? 'disabled' : ''}>
            <label for="f-dob">Date of birth</label><input class="txt" id="f-dob" placeholder="MM/DD/YYYY" maxlength="10" ${editing ? 'disabled' : ''}>
            <label for="f-gender">Sex</label><select class="txt" id="f-gender">${opt(['Male', 'Female', 'Other'], c.gender)}</select>
            <label for="f-address">Address</label><input class="txt" id="f-address" maxlength="60">
            <label for="f-dl">Licence</label><select class="txt" id="f-dl">${opt(arr(civ.licences), c.dl || 'Valid')}</select>
        </div>${editing ? '<div class="hint">Name and date of birth can\'t change once on file. Make a new character instead.</div>' : ''}</fieldset>
        <fieldset><legend>Flags (what police see when they run you)</legend><div class="flaggrid">${arr(civ.flags).map((f) =>
            `<label><input type="checkbox" value="${h(f)}" ${arr(c.flags).includes(f) ? 'checked' : ''}>${h(f)}</label>`).join('')}</div></fieldset>
        <div class="dlgbtns"><span class="grow"></span><button class="btn" id="fcancel">Cancel</button><button class="btn default" id="fsave">Save</button></div>`;
    $('#f-first').value = c.first || '';
    $('#f-last').value = c.last || '';
    $('#f-dob').value = c.dob || '';
    $('#f-address').value = c.address || '';
    $('#fcancel').onclick = () => leave(civCharsScreen);
    $('#fsave').onclick = async () => {
        const r = await req('civSave', {
            key: c.key, first: $('#f-first').value, last: $('#f-last').value, dob: $('#f-dob').value,
            gender: $('#f-gender').value, address: $('#f-address').value, dl: $('#f-dl').value,
            flags: [...view.querySelectorAll('.flaggrid input:checked')].map((i) => i.value),
        });
        if (r.error) return toast(r.error);
        toast('Character saved.');
        await civRefresh();
        leave(civCharsScreen);
    };
}

function civVehiclesScreen() {
    setTitle('My Vehicles');
    view.innerHTML = `<div class="formbar"><h2>My Vehicles</h2></div>
        <div class="pane" style="flex:1" id="vlist">${grid([['Plate', '96px'], ['Vehicle', ''], ['Owner', '20%'], ['Registration', '100px'], ['Insurance', '100px'], ['Stolen', '70px']],
            arr(civ.vehicles).map((v) => ({ open: `civveh:${v.plate}`, cells: [[v.plate, 'cy'], [[v.color, v.make, v.model].filter(Boolean).join(' ')], [v.owner],
                [v.reg_valid ? 'Valid' : 'Invalid', v.reg_valid ? '' : 'ye'], [v.ins_valid ? 'Insured' : 'Uninsured', v.ins_valid ? '' : 'ye'],
                [v.stolen ? 'STOLEN' : '', 'rd']] })), 'No vehicles. Sit in the driver seat and type /vehreg.')}</div>
        <fieldset><legend>Selected vehicle</legend><div class="dlgbtns">
            <label><input type="checkbox" id="v-reg" disabled> Registered</label>
            <label><input type="checkbox" id="v-ins" disabled> Insured</label>
            <label><input type="checkbox" id="v-stolen" disabled> Reported stolen</label>
            <span class="grow"></span><button class="btn" id="vunreg" disabled>Unregister</button><button class="btn default" id="vsave" disabled>Save</button>
        </div></fieldset>
        <div class="hint">Register a vehicle: sit in the driver seat and type /vehreg. It goes to your active character.</div>`;
    const list = $('#vlist');
    wire(list);
    const pick = () => arr(civ.vehicles).find((v) => v.plate === selected(list));
    list.addEventListener('click', () => {
        const v = pick();
        ['#v-reg', '#v-ins', '#v-stolen', '#vunreg', '#vsave'].forEach((b) => ($(b).disabled = !v));
        if (!v) return;
        $('#v-reg').checked = !!v.reg_valid;
        $('#v-ins').checked = !!v.ins_valid;
        $('#v-stolen').checked = !!v.stolen;
    });
    $('#vsave').onclick = async () => {
        const r = await req('civVehicle', { plate: pick().plate, reg_valid: $('#v-reg').checked, ins_valid: $('#v-ins').checked, stolen: $('#v-stolen').checked });
        if (r.error) return toast(r.error);
        toast('Vehicle saved.');
        await civRefresh();
        rerender();
    };
    $('#vunreg').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm Unregister'; return; }
        const r = await req('civUnreg', { plate: pick().plate });
        if (r.error) return toast(r.error);
        await civRefresh();
        rerender();
    };
}

function civRecordScreen() {
    setTitle('My Record');
    view.innerHTML = `<div class="formbar"><h2>My Record</h2><span class="grow"></span><span style="color:#666">Signed reports naming your characters or vehicles. Double-click to read one.</span></div>
        <div class="pane" style="flex:1" id="rlist">${grid([['Call#', '58px'], ['Date', '130px'], ['Type', '14%'], ['Form', '16%'], ['Charges', ''], ['Total', '80px'], ['Officer', '12%']],
            arr(civ.record).map((r) => ({ open: `civrec:${r.id}`, cells: [[r.id, 'cy'], [when(r.started)], [r.kind], [r.form],
                [arr(r.charges).map((c) => c.label).join(', '), 'ye'], [r.total ? money(r.total) : ''], [r.officer]] })), 'Clean record.')}</div>`;
    wire($('#rlist'));
}

function civReportScreen(token, id) {
    const r = arr(civ.record).find((x) => x.id === id);
    if (!r) return toast('Report not found.');
    setTitle(`Report #${id}`);
    const lines = [`${up(r.form)}  #${r.id}`, `${up(r.kind)}${r.location ? ' - ' + up(r.location) : ''}`, `OFFICER/${up(r.officer)}   DATE/${when(r.started)}`, '',
        ...(arr(r.charges).length ? arr(r.charges).map((c) => `${c.id.padEnd(16)}${c.label.padEnd(40)}${money(c.fine)}`) : ['NO CHARGES']),
        '', `TOTAL/${money(r.total)}`, '', 'NARRATIVE', r.narrative || ''];
    view.innerHTML = `<div class="formbar"><h2>Report #${h(r.id)}</h2></div><div class="pane"><pre class="return">${h(lines.join('\n'))}</pre></div>`;
}

function civ911Screen() {
    setTitle('Call 911');
    view.innerHTML = `<div class="formbar"><h2>Call 911</h2></div>
        <fieldset><legend>What's your emergency?</legend>
            <textarea class="txt" id="e-text" maxlength="300" style="height:120px" placeholder="Shots fired near the gas station, two males in a black SUV heading north..."></textarea>
            <div class="dlgbtns" style="margin-top:6px"><span class="hint">Your location goes with the call. Officers on duty are alerted.</span><span class="grow"></span>
            <button class="btn default" id="e-send">Send 911</button></div></fieldset>`;
    $('#e-text').focus();
    $('#e-send').onclick = async () => {
        const r = await req('civ911', { text: $('#e-text').value });
        if (r.error) return toast(r.error);
        $('#e-text').value = '';
        toast(`911 call #${r.id} placed. Officers have been alerted.`, 5000);
    };
}

// ─── game messages ───────────────────────────────────────────────────────────

// A record shown by a radio check: plate as typed, person as "first last" (what the search matches).
function rememberView(v) {
    const q = v?.type === 'vehicle' ? v.key : v?.type === 'person' ? String(v.key).split('|').slice(0, 2).join(' ') : null;
    if (!q) return;
    remember(q);
    lastQuery = q;
    store.set('lwk_mdt.last', q);
}

function screenFor(v) {
    if (v?.type === 'person') return (t) => personScreen(t, v.key);
    if (v?.type === 'vehicle') return (t) => vehicleScreen(t, v.key);
    if (v?.type === 'report') return (t) => reportScreen(t, v.id, v.form);
    return homeScreen;
}

// ─── pop-out ─────────────────────────────────────────────────────────────────

async function popOut() {
    const r = await req('popout');
    if (!r.url) return toast(r.error || 'The pop-out is not available.');
    try { window.invokeNative('openUrl', r.url); } catch { /* blocked or missing: the link in the dialog still works */ }
    $('#linkurl').value = r.url;
    $('#linkdlg').hidden = false;
    $('#linkurl').select();
}

$('#linkok').onclick = () => ($('#linkdlg').hidden = true);
$('#linkcopy').onclick = () => {
    $('#linkurl').select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch { /* fall through */ }
    toast(ok ? 'Link copied. Paste it into your browser.' : 'Select the link and press Ctrl+C.');
};

// ─── start ───────────────────────────────────────────────────────────────────

async function start(m) {
    if (m.civ) return civStart();
    const reopen = !CIV && cur; // (the MDT again: back to the screen it was closed on, its Back and Forward too)
    if (CIV) { CIV = false; document.body.classList.remove('civ'); tools = TOOLS; buildToolbar(); }
    $('#mdt').classList.add('open');
    myStatus = m.status;
    setQuick(m.quick);
    await refresh();
    if (init.prefs) applyStyle(init.prefs.style);
    if (init.signed === false) showSignOn(); // first open this session: who are you tonight?
    if (!reopen) {
        hist.length = 0;
        fwd.length = 0;
        cur = null;
        show(homeScreen);
    }
    if (m.view) { rememberView(m.view); go(screenFor(m.view)); } else if (reopen) rerender();
}

window.addEventListener('message', async (e) => {
    const m = e.data || {};
    if (m.type === 'open') {
        start(m);
    } else if (m.type === 'show') {
        rememberView(m.view);
        go(screenFor(m.view));
    } else if (m.type === 'status') {
        myStatus = m.status;
        statusBar();
    }
});

function close() {
    if (WEB) return; // a browser tab is closed with the browser
    $('#mdt').classList.remove('open');
    post('close');
}

$('#close').onclick = close;

window.addEventListener('keydown', (e) => {
    if (!$('#mdt').classList.contains('open')) return;
    if (!($('#chdlg')?.hidden ?? true)) { if (e.key === 'Escape') closeCharges(); return; } // the charges list has the keys
    if (e.key === 'Escape' && !$('#linkdlg').hidden) { $('#linkdlg').hidden = true; return; }
    if (e.key === 'Escape' && !$('#setdlg').hidden) { closeSettings(); return; }
    if (!$('#signon').hidden || !$('#setdlg').hidden) { if (e.key === 'Escape') close(); return; } // a dialog has the keys
    const k = (e.ctrlKey ? 'Ctrl+' : '') + (e.altKey ? 'Alt+' : '') + ({ ArrowLeft: 'Left', ArrowRight: 'Right', Escape: 'Esc' }[e.key] || e.key.toUpperCase());
    const t = tools.find((x) => x !== 'sep' && x.key.toUpperCase() === k.toUpperCase());
    if (t) { e.preventDefault(); t.run(); }
});

// The clock ticks every second; the home board refreshes every 5.
setInterval(() => { if ($('#mdt').classList.contains('open')) statusBar(); }, 1000);
setInterval(async () => {
    if (!$('#mdt').classList.contains('open') || cur !== homeScreen) return;
    const token = seq;
    await refresh();
    renderBoard(token);
}, 5000);

// Popped out: no game to send 'open', so start from the server's init, then poll for radio checks.
if (WEB) {
    document.body.classList.add('web');
    document.title = 'lwk MDT';
    (async () => {
        if (!TOKEN) return toast('Open this page with the Pop Out button in the in-game MDT.', 0);
        const r = await req('init');
        if (r.error) return toast(r.error, 0);
        start({ status: r.status, quick: r.quick });
    })();
    setInterval(async () => {
        if (!$('#mdt').classList.contains('open')) return;
        const r = await req('poll');
        if (!r || r.error) return;
        if (r.status !== myStatus) { myStatus = r.status; statusBar(); }
        if (r.show) { rememberView(r.show); go(screenFor(r.show)); }
    }, 3000);
}

// ─── sign on, settings, style ────────────────────────────────────────────────
// The callsign is asked for on the first open of a session (the server remembers it for next time, and puts it
// where lwk_control reads it). The style is the officer's own, modern unless they pick classic.

const STYLES = ['modern', 'command', 'enterprise', 'classic', 'cad'];
const FLAT = ['modern', 'command', 'enterprise']; // one layout, three palettes (body.flat + the style's own class)
function applyStyle(style) {
    const s = STYLES.includes(style) ? style : 'cad';
    for (const f of FLAT) document.body.classList.toggle(f, s === f);
    document.body.classList.toggle('flat', FLAT.includes(s));
    const wasCad = isCad();
    document.body.classList.toggle('cad', s === 'cad'); // the classic layout, dressed as a dispatch CAD
    if (wasCad !== (s === 'cad')) { buildToolbar(); navButtons(); if (cur) rerender(); else if (lastScreen) setTitle(lastScreen); }
    store.set('lwk_mdt.style', s); // so the Citizen Portal and the next open start in it too
    return s;
}
applyStyle(store.get('lwk_mdt.style', 'cad'));

function showSignOn() {
    $('#veil').hidden = false;
    $('#signon').hidden = false;
    $('#signcs').value = init.prefs?.callsign || '';
    $('#signerr').textContent = '';
    setTimeout(() => { $('#signcs').focus(); $('#signcs').select(); }, 50);
}

async function signOn() {
    const r = await req('signOn', { callsign: $('#signcs').value });
    if (!r || r.error) { $('#signerr').textContent = r?.error || 'No answer from the server.'; return; }
    $('#signon').hidden = true;
    $('#veil').hidden = true;
    await refresh();
    toast(`Signed on as ${init.officer}.`);
}
$('#signok').onclick = signOn;
$('#signcs').addEventListener('keydown', (e) => { if (e.key === 'Enter') signOn(); });

let styleBefore = null;
function openSettings() {
    if (CIV || !$('#signon').hidden) return;
    styleBefore = STYLES.find((x) => document.body.classList.contains(x)) || 'classic';
    $('#setcs').value = init.prefs?.callsign || '';
    $('#setpop').checked = init.prefs?.popups !== false;
    document.querySelectorAll('input[name=style]').forEach((r) => (r.checked = r.value === styleBefore));
    $('#seterr').textContent = '';
    $('#veil').hidden = false;
    $('#setdlg').hidden = false;
    setTimeout(() => $('#setcs').focus(), 50);
}
function closeSettings(keep) {
    if (!keep && styleBefore) applyStyle(styleBefore); // cancelled: undo the preview
    $('#setdlg').hidden = true;
    $('#veil').hidden = true;
}
// picking a style previews it straight away
document.querySelectorAll('input[name=style]').forEach((r) => (r.onchange = () => applyStyle(r.value)));
$('#gear').onclick = openSettings;
$('#setcancel').onclick = () => closeSettings();
$('#setsave').onclick = async () => {
    const style = document.querySelector('input[name=style]:checked')?.value || 'cad';
    const r = await req('settings', { callsign: $('#setcs').value, style, popups: $('#setpop').checked });
    if (!r || r.error) { $('#seterr').textContent = r?.error || 'No answer from the server.'; return; }
    applyStyle(r.prefs?.style || style);
    closeSettings(true);
    await refresh();
    toast('Settings saved.');
};
$('#setcs').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#setsave').click(); });
