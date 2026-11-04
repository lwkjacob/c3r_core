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
function show(render) { cur = render; seq++; render(seq); navButtons(); }
function goBack() { if (hist.length) { fwd.push(cur); show(hist.pop()); } }
function goFwd() { if (fwd.length) { hist.push(cur); show(fwd.pop()); } }
const rerender = () => cur && show(cur);
const stale = (token) => token !== seq; // a newer screen replaced this one while it loaded

let CIV = false; // true while the Citizen Portal is open (player not on duty)

function setTitle(screen) {
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

const TOOLS = [
    { id: 'back', label: 'Back', key: 'Alt+Left', run: goBack },
    { id: 'fwd', label: 'Forward', key: 'Alt+Right', run: goFwd },
    { id: 'home', label: 'Home', key: 'Alt+Home', run: () => go(homeScreen) },
    'sep',
    { id: 'query', label: 'Query', key: 'Ctrl+J', run: () => go(queryScreen) },
    { id: 'reports', label: 'Reports', key: 'Ctrl+R', run: () => go((t) => reportsScreen(t, 'all')) },
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
    { id: 'reports', label: 'Reports', key: 'Ctrl+R', run: () => go((t) => reportsScreen(t, 'all')) },
    { id: 'drafts', label: 'Drafts', key: 'Ctrl+D', run: () => go((t) => reportsScreen(t, 'drafts')) },
    { id: 'new', label: 'New PCR', key: 'Ctrl+N', run: () => newReport({}) },
    'sep',
    { id: 'popout', label: 'Pop Out', key: 'Ctrl+O', run: popOut },
    { id: 'close', label: 'Close', key: 'Esc', run: close },
];
let tools = TOOLS;

function buildToolbar() {
    $('#toolbar').innerHTML = tools.map((t) => (t === 'sep' ? '<span class="tsep"></span>'
        : `<button class="tile" id="t-${t.id}" title="${t.label} (${t.key})"><svg viewBox="0 0 24 24">${ICONS[t.id]}</svg>
           <span>${t.label}</span><small>${t.key}</small></button>`)).join('')
        + `<div class="brand"><b>lwk</b><small>${CIV ? 'CITIZEN PORTAL' : tools === EMS_TOOLS ? 'EMS DATA' : 'MOBILE DATA'}</small></div>`;
    tools.forEach((t) => t !== 'sep' && ($(`#t-${t.id}`).onclick = t.run));
}
buildToolbar();

function navButtons() {
    $('#t-back').disabled = !hist.length;
    $('#t-fwd').disabled = !fwd.length;
}

const ACTIONS = {
    close, home: () => go(homeScreen), query: () => go(queryScreen), settings: () => openSettings(),
    reports: () => go((t) => reportsScreen(t, 'all')), drafts: () => go((t) => reportsScreen(t, 'drafts')),
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

// cols: [label, width]; rows: { open: 'report:12', cells: [[text, class]] }
function grid(cols, rows, empty) {
    const head = `<colgroup><col style="width:24px">${cols.map(([, w]) => `<col${w ? ` style="width:${w}"` : ''}>`).join('')}</colgroup>
        <thead><tr><th class="rh">All</th>${cols.map(([l]) => `<th>${h(l)}</th>`).join('')}</tr></thead>`;
    const body = rows.length ? rows.map((r) => `<tr tabindex="0" ${r.open ? `data-open="${h(r.open)}"` : ''}><td class="rh"></td>${
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
        return { open: `report:${c.id}`, cells: [[c.id, 'cy'], [(c.title || c.kind || '').toUpperCase(), 'cy'], [loc], [zone], [c.priority ?? ''],
            [st, sc], [age(c.started), old || c.status !== 'open' ? 'rd' : ''], [c.officer]] };
    });
}

// c3r's calls: double-click one to attach to it, whoever's on it, popup or not.
function c3rRows(list) {
    return arr(list).filter((c) => !c.joined).map((c) => ({ open: `join:${c.id}`, cells: [['C' + c.id, 'cy'], [String(c.name || '').toUpperCase(), 'cy'],
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
    $('#calls').innerHTML = grid(CALL_COLS, [...c3rRows(init.c3r), ...callRows(init.calls)], 'No active calls.');
    $('#units').innerHTML = grid([['Unit', '13%'], ['Status', '62px'], ['Time', '58px'], ['Call#', '58px'], ['Zone', '12%'], ['Location', '22%'], ['Description', '']],
        arr(init.units).map((u) => {
            const [loc, zone] = splitLoc(u.location);
            const c = UNIT_COLOR[u.status] || '';
            return { open: u.call ? `report:${u.call}` : null, cells: [[u.unit, c], [u.status, c], [age(u.since), now() - u.since > 1800 ? 'rd' : ''],
                [u.call ?? ''], [zone], [loc], [u.call ? `${u.kind || ''}${u.title ? ' - ' + u.title : ''}` : '(MDT)', c]] };
        }), 'No units on duty.');
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
        ${init.admin ? '<span class="grow"></span><button class="btn" id="deldrafts">Delete All Drafts</button>' : ''}</div>
        <div class="pane" style="flex:1" id="rlist"></div>`;
    view.querySelectorAll('[data-f]').forEach((b) => (b.onclick = () => go((t) => reportsScreen(t, b.dataset.f))));
    if ($('#deldrafts')) $('#deldrafts').onclick = async (e) => {
        const b = e.currentTarget;
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm: delete every draft'; return; }
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

const vitalsRow = (label, v) => v && { cells: [[label], [v.t ? hhmm(v.t) : '', 'cy'], [v.hr ?? '-'], [v.sys ? `${v.sys}/${v.dia}` : '---'],
    [v.spo2 != null ? `${v.spo2}%` : '-'], [v.rr ?? '-'], [v.etco2 ?? '-'], [v.gcs ?? '-'], [v.rhythm || '']] };
const OUTCOME = (pc) => (pc.outcome === 'pronounced' ? 'Pronounced dead'
    : pc.outcome === 'transported' ? `Transported${pc.hospital ? ` to ${pc.hospital}` : ''}` : 'Not recorded');

// A patient care report: who, the vitals, what was found, the narrative (CHART, from the care log until edited), and
// every treatment with its time. No forms or charges.
function pcrScreen(r) {
    const s = r.summary, ro = !r.can_edit, pc = r.pcr || {};
    const draft = !ro && unsaved[s.id];
    let auto = draft ? draft.auto : r.auto;
    setTitle(`Patient Care Report #${s.id}`);
    view.innerHTML = `<div class="formbar"><h2>Patient Care Report #${h(s.id)} - ${h(up(s.title || ''))}</h2>
            <span class="badge ${h(s.status)}">${h((STATUS[s.status] || [s.status])[0])}</span><span class="grow"></span>
            ${ro ? '<span style="color:#666">Read only: only the author or a supervisor can change this report.</span>' : ''}</div>
        <fieldset><legend>Call</legend><div class="info">
            <div><b>Complaint:</b> ${h(s.title || '-')}</div><div><b>Location:</b> ${h(s.location || '-')}</div>
            <div><b>Medic:</b> ${h(s.officer)}</div><div><b>Patient contact:</b> ${when(pc.contact || s.started)}</div>
            <div><b>Outcome:</b> ${h(OUTCOME(pc))}</div>
            <div><b>Signed:</b> ${r.signed_by ? `${h(r.signed_by)}, ${when(r.signed_at)}` : '-'}</div></div></fieldset>
        <fieldset><legend>Patient</legend><div class="pane" id="inv" style="min-height:0">${grid([['Name', '34%'], ['DOB', '120px'], ['Sex', '']],
            arr(r.people).map((p) => ({ open: `person:${p.key}`, cells: [[`${p.last || ''}, ${p.first || ''}`.toUpperCase(), 'cy'], [p.dob], [p.gender]] })),
            'Unidentified patient.')}</div></fieldset>
        <div class="cols">
            <fieldset class="grow"><legend>Vitals</legend><div class="pane" style="min-height:0">${grid([['Set', '70px'], ['Time', '54px'], ['HR', ''], ['BP', ''],
                ['SpO2', ''], ['RR', ''], ['EtCO2', ''], ['GCS', ''], ['Rhythm', '24%']],
                [vitalsRow('Initial', pc.first), vitalsRow('Final', pc.last)].filter(Boolean), 'No monitor readings.')}</div></fieldset>
            <fieldset class="grow"><legend>Findings</legend><div class="pane" style="min-height:0">${grid([['Area', '90px'], ['Finding', ''], ['', '70px']],
                arr(pc.findings).map((f) => ({ cells: [[up(f.part || '')], [f.text], [f.treated ? 'TREATED' : 'OPEN', f.treated ? 'gy' : 'rd']] })),
                'Nothing found.')}</div></fieldset>
        </div>
        <fieldset><legend>Narrative${auto ? ' (auto, written from the care log until edited)' : ''}</legend>
            <textarea class="txt" id="narr" aria-label="Narrative" ${ro ? 'readonly' : ''}></textarea></fieldset>
        ${ro ? '' : `<div class="dlgbtns"><button class="btn" id="rebuild" title="Replace the text with a fresh draft from the care log">Rebuild</button>
            <span class="grow"></span><button class="btn" id="del">Delete</button>
            <button class="btn" id="save">${s.status === 'signed' ? 'Save Changes' : 'Save Draft'}</button>
            ${s.status === 'signed' ? '' : '<button class="btn default" id="sign">Sign</button>'}</div>`}
        <fieldset><legend>Care Given</legend><div class="pane" id="tl" style="min-height:0">${grid([['Time', '64px'], ['Treatment', '']],
            arr(pc.care).map((e) => ({ cells: [[hhmm(e.t), 'cy'], [e.text]] })), 'Nothing logged.')}</div></fieldset>`;
    const narr = $('#narr');
    narr.value = draft ? draft.narrative : r.narrative || '';
    wire($('#inv'));
    if (ro) return;
    const keep = () => { unsaved[s.id] = { form: 'pcr', charges: [], narrative: narr.value, auto }; };
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

async function reportScreen(token, id, presetForm) {
    const r = await req('report', { id: Number(id) });
    if (stale(token)) return;
    if (r && r.pcr) return pcrScreen(r);
    if (!r || !r.summary) return toast('Report not found.');
    const list = await chargeList();
    if (stale(token)) return;
    if (!r.summary) return toast('Report not found.');
    const s = r.summary, ro = !r.can_edit;
    const draft = !ro && unsaved[s.id];
    let form = presetForm || (draft ? draft.form : r.form), auto = draft ? draft.auto : r.auto;
    const picked = new Set(draft ? draft.charges : arr(r.charges).map((c) => c.id));
    const dis = ro ? 'disabled' : '';
    // signed: what's on it goes to the top, where it's seen at a glance (the sort is stable: code order within)
    const signed = s.status === 'signed';
    const rows = list.map((c, i) => ({ c, i, on: picked.has(chargeId(c)) }));
    if (signed) rows.sort((a, b) => b.on - a.on);
    const groupOf = (x) => (signed && x.on ? 'ON' : x.c.code);
    const groupName = (g) => (g === 'ON' ? 'On this report' : GROUPS[g] || g);
    setTitle(`Incident #${s.id}`);

    view.innerHTML = `<div class="formbar"><h2>Incident #${h(s.id)} - ${h(s.title || s.kind)}</h2>
            <span class="badge ${h(s.status)}">${h((STATUS[s.status] || [s.status])[0])}</span><span class="grow"></span>
            ${r.coords ? '<button class="btn" id="wp">Set Waypoint</button>' : ''}
            ${s.status === 'pending' ? '<button class="btn default" id="respond">Respond</button>' : ''}
            ${ro && s.status !== 'pending' ? '<span style="color:#666">Read only: only the author or a supervisor can change this report.</span>' : ''}</div>
        <fieldset><legend>Incident</legend><div class="info">
            <div><b>Type:</b> ${h(s.kind)}</div><div><b>Nature:</b> ${h(s.title || '-')}</div>
            <div><b>Location:</b> ${h(s.location || '-')}</div><div><b>Officer:</b> ${h(s.officer)}</div>
            <div><b>Started:</b> ${when(s.started)}</div>${r.caller ? `<div><b>Caller:</b> ${h(r.caller)}</div>` : ''}
            <div><b>Signed:</b> ${r.signed_by ? `${h(r.signed_by)}, ${when(r.signed_at)}` : '-'}</div></div></fieldset>
        <fieldset><legend>Involved</legend><div class="pane" id="inv" style="min-height:0">${grid([['Type', '80px'], ['Identifier', '24%'], ['Description', ''], ['Flags', '30%']], [
            ...arr(r.vehicles).map((v) => ({ open: `vehicle:${v.plate}`, cells: [['VEHICLE'], [v.plate, 'cy'],
                [[v.year, v.color, v.make, v.model].filter(Boolean).join(' ')], [vehicleFlags(v).join(', '), 'rd']] })),
            ...arr(r.people).map((p) => ({ open: `person:${p.key}`, cells: [['PERSON'], [`${p.last || ''}, ${p.first || ''}`.toUpperCase(), 'cy'],
                [p.dob ? `DOB ${p.dob}` : ''], [[...arr(p.flags), p.dl_valid === false ? 'LICENCE ' + up(p.dl || 'INVALID') : ''].filter(Boolean).join(', '), 'rd']] })),
        ], 'Nobody attached.')}</div></fieldset>
        <div class="cols">
            <fieldset><legend>Form</legend><div class="radios">${arr(init.forms).map(({ id: k, label: l }) =>
                `<label><input type="radio" name="form" value="${h(k)}" ${k === form ? 'checked' : ''} ${dis}>${h(l)}</label>`).join('')}</div></fieldset>
            <fieldset class="grow"><legend id="chead">Charges</legend>
                <input class="txt" id="csearch" placeholder="Search section, charge or description" aria-label="Search charges" autocomplete="off">
                <div class="listbox charges">${rows.map((x, n) => { const c = x.c, g = groupOf(x); return `${n === 0 || groupOf(rows[n - 1]) !== g ? `<div class="cgroup" data-g="${h(g)}">${h(groupName(g))}</div>` : ''}
                    <label data-g="${h(g)}" data-text="${h(`${chargeId(c)} ${c.label} ${c.desc || ''}`.toLowerCase())}" title="${h(c.desc || '')}">
                    <input type="checkbox" data-c="${x.i}" ${x.on ? 'checked' : ''} ${dis}>
                    <span class="sec">${h(chargeId(c))}</span><span class="cname">${h(c.label)}</span>
                    <span class="cls ${h(c.class)}">${CLASS[c.class] || ''}</span>
                    <span class="pts">${c.points ? `${c.points} pt` : ''}</span><span class="fine">${money(c.fine)}</span></label>`; }).join('')}</div>
                <div class="total" id="total"></div></fieldset>
        </div>
        <fieldset><legend>Narrative${auto ? ' (auto, follows the timeline until edited)' : ''}</legend>
            <textarea class="txt" id="narr" aria-label="Narrative" ${ro ? 'readonly' : ''}></textarea></fieldset>
        ${ro ? '' : `<div class="dlgbtns"><button class="btn" id="rebuild" title="Replace the text with a fresh draft from the timeline">Rebuild</button>
            <span class="grow"></span><button class="btn" id="del">Delete</button>
            <button class="btn" id="save">${s.status === 'signed' ? 'Save Changes' : 'Save Draft'}</button>
            ${s.status === 'signed' ? '' : '<button class="btn default" id="sign">Sign</button>'}</div>`}
        <fieldset><legend>Timeline</legend><div class="pane" id="tl" style="min-height:0">${grid([['Time', '64px'], ['Event', '']],
            arr(r.events).map((e) => ({ cells: [[hhmm(e.t), 'cy'], [e.text]] })), 'Nothing logged.')}</div></fieldset>`;

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
    wire($('#inv'));
    wire($('#tl'));

    const chosen = () => list.filter((_, i) => $(`[data-c="${i}"]`)?.checked).map(chargeId);
    const keep = () => { if (!ro) unsaved[s.id] = { form, charges: chosen(), narrative: narr.value, auto }; };
    narr.oninput = () => { auto = false; keep(); };
    const update = () => {
        $('#chead').textContent = form === 'warning' ? 'Violations' : 'Charges';
        const ids = chosen();
        const total = list.filter((c) => ids.includes(chargeId(c))).reduce((n, c) => n + Number(c.fine || 0), 0);
        $('#total').textContent = `${ids.length} selected · ` + (form === 'warning' ? 'Written warning: no fine' : `Total fine: ${money(total)}`);
    };
    view.querySelectorAll('[name=form]').forEach((b) => (b.onchange = () => { form = b.value; update(); keep(); }));
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

const STYLES = ['modern', 'command', 'enterprise', 'classic'];
const FLAT = ['modern', 'command', 'enterprise']; // one layout, three palettes (body.flat + the style's own class)
function applyStyle(style) {
    const s = STYLES.includes(style) ? style : 'modern';
    for (const f of FLAT) document.body.classList.toggle(f, s === f);
    document.body.classList.toggle('flat', FLAT.includes(s));
    store.set('lwk_mdt.style', s); // so the Citizen Portal and the next open start in it too
    return s;
}
applyStyle(store.get('lwk_mdt.style', 'modern'));

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
    const style = document.querySelector('input[name=style]:checked')?.value || 'modern';
    const r = await req('settings', { callsign: $('#setcs').value, style, popups: $('#setpop').checked });
    if (!r || r.error) { $('#seterr').textContent = r?.error || 'No answer from the server.'; return; }
    applyStyle(r.prefs?.style || style);
    closeSettings(true);
    await refresh();
    toast('Settings saved.');
};
$('#setcs').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#setsave').click(); });
