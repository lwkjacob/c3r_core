// lwk_control — server-side speech recognition for players whose game browser has no WebAssembly
// (nui/ears.js NO_WASM). Same sherpa-onnx streaming Zipformer as the NUI, loaded from lwk_control_assets/nui/sherpa/
// on first use. Clients send 16-bit PCM in sequenced chunks; the text goes back to their NUI.
'use strict';

const fs = require('fs');
const path = require('path');

const RATE = 16000;
const MAX_SAMPLES = RATE * 15;     // utterance cap; audio past it is dropped
const MAX_CHUNK_B64 = 64 * 1024;   // one chunk is ~250 ms (~11 KB base64)
const MAX_PENDING = 100;           // out-of-order / not-yet-fed chunks per player
const IDLE_MS = 20000;             // no chunk for this long = client went away mid-utterance
const STARTS_PER_MIN = 30;

// Must match SHERPA_CONFIG in nui/ears.js.
const CONFIG = {
    featConfig: { sampleRate: RATE, featureDim: 80 },
    modelConfig: {
        transducer: { encoder: './encoder.onnx', decoder: './decoder.onnx', joiner: './joiner.onnx' },
        paraformer: { encoder: '', decoder: '' }, zipformer2Ctc: { model: '' }, nemoCtc: { model: '' },
        toneCtc: { model: '' }, tokens: './tokens.txt', numThreads: 1, provider: 'cpu', debug: 0,
        modelType: '', modelingUnit: '', bpeVocab: '',
    },
    decodingMethod: 'modified_beam_search', maxActivePaths: 4, enableEndpoint: 0,
    rule1MinTrailingSilence: 2.4, rule2MinTrailingSilence: 1.2, rule3MinUtteranceLength: 20,
    hotwordsFile: '', hotwordsScore: 2.0, hotwordsBuf: '', hotwordsBufSize: 0, ctcFstDecoderConfig: { graph: '', maxActive: 3000 },
    ruleFsts: '', ruleFars: '',
};
const TAIL = new Float32Array(RATE * 0.6);

let recognizer = null;
let loading = null;

// The Emscripten build reads a global `Module`, so it is evaluated with one passed in rather than
// require()d; locateFile makes the .wasm / .data paths absolute (the server's cwd is elsewhere).
function load(dir) {
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
        const Module = {
            locateFile: (f) => path.join(dir, f),
            onRuntimeInitialized: () => resolve(Module),
            onAbort: (what) => reject(new Error('sherpa aborted: ' + what)),
            print: () => {}, printErr: () => {},
        };
        const src = fs.readFileSync(path.join(dir, 'sherpa-onnx-wasm-main-asr.js'), 'utf8');
        // FXServer's Node 16 has no global `performance`, which Emscripten's clock uses.
        new Function('Module', 'require', '__dirname', 'performance', src)(Module, require, dir, require('perf_hooks').performance);
    }).then((Module) => {
        // Hotwords as in nui/ears.js: plain words, split into word pieces with the model's bpe.vocab.
        try {
            const nui = path.join(GetResourcePath(GetCurrentResourceName()), 'nui');
            CONFIG.hotwordsBuf = fs.readFileSync(path.join(nui, 'hotwords.txt'), 'utf8');
            Module.FS_createDataFile('/', 'bpe.vocab', fs.readFileSync(path.join(nui, 'bpe.vocab')), true, false, false);
            CONFIG.hotwordsBufSize = Module.lengthBytesUTF8(CONFIG.hotwordsBuf);
            CONFIG.modelConfig.modelingUnit = 'bpe';
            CONFIG.modelConfig.bpeVocab = '/bpe.vocab';
        } catch (e) { CONFIG.hotwordsBuf = ''; } // no hotwords: plain beam search
        recognizer = require(path.join(dir, 'sherpa-onnx-asr.js')).createOnlineRecognizer(Module, CONFIG);
    });
    return loading;
}

function pcmToFloat(b64) {
    const buf = Buffer.from(b64, 'base64');
    const n = buf.length >> 1;
    const out = new Float32Array(n);
    for (let i = 0; i < n; i++) out[i] = buf.readInt16LE(i * 2) / 32768;
    return out;
}

// ─── per-player utterances ────────────────────────────────────────────────────

const users = new Map(); // src -> { id, send, stream, next, pending: Map(seq -> { pcm, final }), samples, final, timer, t0 }
const starts = new Map(); // src -> recent start timestamps

function drop(src) {
    const u = users.get(src);
    if (!u) return;
    clearTimeout(u.timer);
    if (u.stream) u.stream.free();
    users.delete(src);
}

function rateLimited(src) {
    const now = Date.now();
    const list = (starts.get(src) || []).filter((t) => now - t < 60000);
    starts.set(src, list);
    if (list.length >= STARTS_PER_MIN) return true;
    list.push(now);
    return false;
}

// Feeds whatever is contiguous from u.next; the final chunk adds the silence tail and closes input.
function drain(src) {
    const u = users.get(src);
    if (!u || !recognizer || u.final) return;
    if (!u.stream) u.stream = recognizer.createStream();
    while (u.pending.has(u.next)) {
        const c = u.pending.get(u.next);
        u.pending.delete(u.next++);
        if (c.pcm && u.samples < MAX_SAMPLES) {
            const f = pcmToFloat(c.pcm);
            const room = MAX_SAMPLES - u.samples;
            u.stream.acceptWaveform(RATE, f.length > room ? f.subarray(0, room) : f);
            u.samples += Math.min(f.length, room);
        }
        if (c.final) {
            u.stream.acceptWaveform(RATE, TAIL);
            u.stream.inputFinished();
            u.final = true;
            break;
        }
    }
    schedule();
}

// One decode() per server tick, round-robin across talkers: each call is ~50 ms (~360 ms of audio), so
// a long utterance never holds the server thread longer than that.
// ponytail: still on the server thread (FXServer's Node crashes on worker_threads); an external
// process is the upgrade if many players need this at once.
// setTick, not setImmediate: FXServer drains immediates within one server frame.
let scheduled = false;
function schedule() {
    if (scheduled) return;
    scheduled = true;
    if (typeof setTick !== 'function') return setImmediate(pump); // plain Node (tests)
    const t = setTick(() => { clearTick(t); pump(); });
}

function pump() {
    scheduled = false;
    for (const [src, u] of users) {
        if (!u.stream) continue;
        try {
            if (recognizer.isReady(u.stream)) {
                recognizer.decode(u.stream);
                users.delete(src); users.set(src, u); // to the back of the queue
                return schedule();
            }
            if (!u.final) continue;
            const text = recognizer.getResult(u.stream).text.trim().toLowerCase();
            drop(src);
            u.send(src, u.id, text, null, Date.now() - u.t0);
        } catch (e) {
            console.log('[lwk_control] server speech recognition error: ' + e.message);
            drop(src);
            return schedule();
        }
    }
}

// id: the client's press counter, seq: chunk index within it, pcm: base64 16-bit LE mono 16 kHz.
function onChunk(src, id, seq, pcm, final, dir, send) {
    if (!Number.isInteger(id) || !Number.isInteger(seq) || seq < 0 || seq > 10000) return;
    if (typeof pcm !== 'string' || pcm.length > MAX_CHUNK_B64) return;
    let u = users.get(src);
    if (!u || u.id !== id) {
        if (u && id < u.id) return; // late chunk of a superseded press
        drop(src);
        if (rateLimited(src)) { if (final === true) send(src, id, '', null, 0); return; }
        u = { id, send, stream: null, next: 0, pending: new Map(), samples: 0, final: false, timer: null, t0: Date.now() };
        users.set(src, u);
    }
    if (u.final) return;
    if (u.pending.size >= MAX_PENDING) return drop(src);
    u.pending.set(seq, { pcm: pcm || null, final: final === true });
    clearTimeout(u.timer);
    u.timer = setTimeout(() => { drop(src); send(src, id, '', null, 0); }, IDLE_MS);
    if (recognizer) return drain(src);
    load(dir).then(() => drain(src), (e) => {
        console.log('[lwk_control] server speech recognition failed to load: ' + e.message);
        drop(src);
        if (final === true) send(src, id, null, 'server_asr_failed', 0);
    });
}

// ─── FXServer wiring ──────────────────────────────────────────────────────────

if (typeof onNet === 'function') {
    const dir = path.join(GetResourcePath('lwk_control_assets'), 'nui', 'sherpa'); // model lives in the assets resource
    const send = (src, id, text, err, ms) => emitNet('lwk_control:asrResult', src, id, text, err, ms);

    // A WebAssembly-less client reports in when its NUI loads, so the model is ready by its first press.
    onNet('lwk_control:asrWarm', () => {
        load(dir).catch((e) => console.log('[lwk_control] server speech recognition failed to load: ' + e.message));
    });
    onNet('lwk_control:asr', (id, seq, pcm, final) => {
        const src = Number(global.source);
        try { onChunk(src, id, seq, pcm, final, dir, send); } catch (e) {
            console.log('[lwk_control] server speech recognition error: ' + e.message);
            drop(src);
        }
    });
    on('playerDropped', () => { drop(Number(global.source)); starts.delete(Number(global.source)); });
}
if (typeof module !== 'undefined') module.exports = { load, onChunk, users }; // test/asr_test.js
