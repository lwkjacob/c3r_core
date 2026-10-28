/*
 * ears.js — mic capture + speech recognition for lwk_control.
 *
 * Engine: sherpa-onnx streaming Zipformer (nui/sherpa/, model bundled in the .data package),
 * running in this page. index.html sets up `Module` and `window.sherpaReady` before loading it.
 * Without WebAssembly the same model runs on the server (server/asr.js): audio goes up as PCM.
 *
 * Lua -> NUI : { type: 'pttDown' }, { type: 'talkDown' }, { type: 'pttUp' }, { type: 'serverTranscript' }
 *              talkDown = speech to the subject: no clicks, transcript carries target: 'subject'
 * NUI -> Lua : ready (returns config), status, modelLoaded, transcript, error, asrWarm, asrChunk
 */
(function () {
    'use strict';

    var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    var RATE = 16000;
    var CHUNK_MS = 25; // must match ears-worklet.js (400 samples @ 16 kHz)

    var cfg = null;
    var recognizer = null;

    var ctx = null, outCtx = null, workletLoaded = false;
    var stream = null, srcNode = null, capNode = null, opening = null;
    var lingerTimer = null;
    var ring = [];          // pre-roll chunks while not recording
    var recording = null;   // sherpa stream currently receiving audio
    var pressed = false;
    var pressId = 0;
    // stream id -> { test: mic check, target: 'subject' } for server transcripts still on their way, so a
    // late answer can't land on the wrong key
    var serverPending = {};
    var clicks = {};

    // ── helpers ─────────────────────────────────────────────────────────────

    // Resource paths ('nui/...') as absolute URLs: clips and the model are in lwk_control_assets.
    function resUrl(path) {
        path = String(path).replace(/^\/+/, '');
        if (/^nui\/(voice|clicks|sherpa)\//.test(path)) return window.ASSETS + path;
        return new URL('/' + path, location.href).href;
    }

    function post(endpoint, data) {
        if (!RES) {
            console.log('[lwk_control] -> ' + endpoint, data);
            return Promise.resolve({});
        }
        return fetch('https://' + RES + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(function (r) { return r.json(); }).catch(function () { return {}; });
    }

    function dbg(msg) { if (cfg && cfg.debug) console.log('[lwk_control] ' + msg); }

    function status(state) {
        var hud = document.getElementById('hud');
        if (hud) hud.className = 'state-' + state;
        post('status', { state: state });
    }

    function fail(where, err) {
        var msg = where + ': ' + (err && err.message ? err.message : String(err));
        console.error('[lwk_control] ' + msg);
        post('error', { message: msg });
    }

    // ── clicks ──────────────────────────────────────────────────────────────

    function playClick(which) {
        var path = cfg.clicks && cfg.clicks.enabled !== false && cfg.clicks[which];
        if (!path) return;
        outCtx = outCtx || new AudioContext();
        var p = clicks[path] || (clicks[path] = fetch(resUrl(path))
            .then(function (r) { return r.arrayBuffer(); })
            .then(function (ab) { return outCtx.decodeAudioData(ab); }));
        p.then(function (buf) {
            var gain = outCtx.createGain();
            gain.gain.value = Math.max(0, Math.min(1, (cfg.clicks.volume || 0) / 100));
            gain.connect(outCtx.destination);
            var src = outCtx.createBufferSource();
            src.buffer = buf;
            src.connect(gain);
            return outCtx.resume().then(function () { src.start(); });
        }).catch(function (e) { fail('click', e); });
    }

    // ── model ───────────────────────────────────────────────────────────────

    // Beam search so nui/hotwords.txt (every command phrase, tools/hotword_phrases.lua) can bias it.
    // No endpointing: push-to-talk decides when an utterance ends.
    var SHERPA_CONFIG = {
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
    // Hotwords are plain words; sherpa splits them into word pieces with the model's bpe.vocab.
    function useHotwords(config, Module, hotwords, vocab) {
        try { Module.FS_createDataFile('/', 'bpe.vocab', new Uint8Array(vocab), true, false, false); } catch (e) {} // already there on a reload
        config.modelConfig.modelingUnit = 'bpe';
        config.modelConfig.bpeVocab = '/bpe.vocab';
        config.hotwordsBuf = hotwords;
        config.hotwordsBufSize = Module.lengthBytesUTF8(hotwords);
    }
    var TAIL = new Float32Array(RATE * 0.6); // silence after release so the model flushes its look-ahead

    // Chromium drops WebAssembly entirely when its JIT is blocked (Windows Exploit Protection's
    // Arbitrary Code Guard, anti-exploit / antivirus hardening). Recognition then runs server-side.
    var NO_WASM = typeof WebAssembly === 'undefined';

    // Server-side stream: same feed()/free() shape as a sherpa stream, but ships 16-bit PCM to Lua
    // in ~250 ms chunks (seq-numbered, the server reorders them).
    function ServerStream(id) { this.id = id; this.seq = 0; this.parts = []; this.n = 0; }
    ServerStream.prototype.free = function () { this.parts = []; this.n = 0; };
    ServerStream.prototype.send = function (final) {
        var pcm = new Int16Array(this.n), at = 0;
        this.parts.forEach(function (p) {
            for (var i = 0; i < p.length; i++) pcm[at++] = Math.max(-1, Math.min(1, p[i])) * 32767;
        });
        this.free();
        var bytes = new Uint8Array(pcm.buffer), bin = '';
        for (var j = 0; j < bytes.length; j += 4096) bin += String.fromCharCode.apply(null, bytes.subarray(j, j + 4096));
        post('asrChunk', { id: this.id, seq: this.seq++, pcm: btoa(bin), final: final });
    };

    function loadModel() {
        var t0 = performance.now();
        if (NO_WASM) {
            dbg('no WebAssembly: using server-side recognition');
            post('asrWarm');
            status('idle');
            return Promise.resolve();
        }
        status('loading');
        function get(f, as) { return fetch(f).then(function (r) { return r.ok ? r[as]() : null; }).catch(function () { return null; }); }
        return Promise.all([window.sherpaReady, get('hotwords.txt', 'text'), get('bpe.vocab', 'arrayBuffer')]).then(function (res) {
            if (res[1] && res[2]) useHotwords(SHERPA_CONFIG, Module, res[1], res[2]);
            recognizer = new OnlineRecognizer(SHERPA_CONFIG, Module);
            post('modelLoaded', { ms: Math.round(performance.now() - t0), url: 'sherpa-onnx streaming zipformer' });
            status('idle');
        }).catch(function (e) {
            fail('model load', e);
            status('error');
        });
    }

    function feed(s, samples) {
        if (s instanceof ServerStream) {
            s.parts.push(samples);
            s.n += samples.length;
            if (s.n >= RATE / 4) s.send(false);
            return;
        }
        s.acceptWaveform(RATE, samples);
        while (recognizer.isReady(s)) recognizer.decode(s); // decode as we go so release is fast
    }

    // ── mic ─────────────────────────────────────────────────────────────────

    // Mic check in /control: loudness of each chunk for its meter.
    function level(data) {
        var peak = 0, sum = 0;
        for (var i = 0; i < data.length; i++) {
            var v = Math.abs(data[i]);
            if (v > peak) peak = v;
            sum += v * v;
        }
        window.dispatchEvent(new CustomEvent('lwkMicLevel', { detail: { rms: Math.sqrt(sum / data.length), peak: peak } }));
    }

    function onChunk(data) {
        if (recording) {
            if (recording.test) level(data);
            feed(recording, data);
            return;
        }
        ring.push(data);
        var max = Math.ceil((cfg.preRollMs || 0) / CHUNK_MS);
        while (ring.length > max) ring.shift();
    }

    function openMic() {
        if (stream) return Promise.resolve();
        if (opening) return opening;
        opening = (async function () {
            ctx = ctx || new AudioContext({ sampleRate: RATE });
            if (!workletLoaded) {
                await ctx.audioWorklet.addModule(resUrl('nui/ears-worklet.js'));
                workletLoaded = true;
            }
            // Browser voice processing helps in noisy rooms but its artifacts can hurt recognition;
            // players toggle it in /control.
            var fx = cfg.micProcessing !== false;
            var audio = { echoCancellation: fx, noiseSuppression: fx, autoGainControl: fx, channelCount: 1 };
            if (cfg.micDeviceId) audio.deviceId = { exact: cfg.micDeviceId };
            stream = await navigator.mediaDevices.getUserMedia({ audio: audio, video: false });
            srcNode = ctx.createMediaStreamSource(stream);
            capNode = new AudioWorkletNode(ctx, 'ears-capture');
            capNode.port.onmessage = function (e) { onChunk(e.data); };
            srcNode.connect(capNode);
            capNode.connect(ctx.destination); // outputs silence; keeps the node pulled by the graph
            await ctx.resume();
            dbg('mic live');
        })();
        return opening.finally(function () { opening = null; });
    }

    function closeMic() {
        if (!stream) return;
        stream.getTracks().forEach(function (t) { t.stop(); });
        if (srcNode) srcNode.disconnect();
        if (capNode) { capNode.port.onmessage = null; capNode.disconnect(); }
        stream = srcNode = capNode = null;
        ring = [];
        dbg('mic closed');
    }

    function scheduleLinger() {
        clearTimeout(lingerTimer);
        if (cfg.micMode === 'warm') return;
        lingerTimer = setTimeout(function () {
            if (!pressed && !recording) closeMic();
        }, cfg.lingerMs || 0);
    }

    // ── push to talk ────────────────────────────────────────────────────────

    // test = the /control mic check: the transcript is shown there instead of being run.
    function pttDown(test, target) {
        if (pressed) return;
        pressed = true;
        var id = ++pressId;
        clearTimeout(lingerTimer);
        if (!recognizer && !NO_WASM) {
            post('error', { message: 'model_loading' });
            return;
        }

        var s = NO_WASM ? new ServerStream(id) : recognizer.createStream();
        s.test = test === true;
        s.target = target || null;
        if (!stream) status('opening');

        openMic().then(function () {
            if (id !== pressId || !pressed) { s.free(); return; }
            // Talk-permit: the click means "the mic hears you now".
            if (!s.target) playClick('on');
            ring.forEach(function (c) { feed(s, c); });
            ring = [];
            recording = s;
            status('listening');
        }).catch(function (e) {
            s.free();
            pressed = false;
            fail('mic', e);
            status('idle');
        });
    }

    function pttUp() {
        if (!pressed) return;
        pressed = false;
        var s = recording;
        recording = null;
        if (!s) { status('idle'); scheduleLinger(); return; } // released before the mic went live

        if (!s.target) playClick('off');
        status('processing');
        if (s instanceof ServerStream) { serverPending[s.id] = { test: s.test, target: s.target }; s.send(true); scheduleLinger(); return; } // answer: serverTranscript
        var t0 = performance.now();
        feed(s, TAIL);
        s.inputFinished();
        while (recognizer.isReady(s)) recognizer.decode(s);
        var text = recognizer.getResult(s).text.trim().toLowerCase();
        s.free();
        post('transcript', { text: text, words: [], ms: Math.round(performance.now() - t0), test: s.test, target: s.target });
        status('idle');
        scheduleLinger();
    }

    // ── wiring ──────────────────────────────────────────────────────────────

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d || !cfg) return;
        if (d.type === 'pttDown') pttDown(false);
        else if (d.type === 'talkDown') pttDown(false, 'subject');
        else if (d.type === 'paDown') pttDown(false, 'pa');
        else if (d.type === 'pttUp') pttUp();
        else if (d.type === 'micTestStart') {
            // test with the mic picked in the panel, saved or not (Lua re-applies the saved one on close)
            if (pressed) return;
            if (d.micDeviceId !== cfg.micDeviceId || d.micProcessing !== cfg.micProcessing) {
                if (!recording) closeMic();
                cfg.micDeviceId = d.micDeviceId;
                cfg.micProcessing = d.micProcessing;
            }
            pttDown(true);
        }
        else if (d.type === 'micTestStop') pttUp();
        else if (d.type === 'serverTranscript') {
            var p = serverPending[d.id] || {};
            delete serverPending[d.id];
            if (d.error) post('error', { message: d.error });
            else post('transcript', { text: d.text || '', words: [], ms: d.ms, test: p.test === true, target: p.target || null });
            if (!pressed) status('idle');
        }
        else if (d.type === 'shutdown') {
            pressed = false;
            if (recording) { recording.free(); recording = null; }
            closeMic();
        }
        else if (d.type === 'applySettings') {
            var reopen = d.micDeviceId !== cfg.micDeviceId || d.micProcessing !== cfg.micProcessing;
            if (reopen && !recording) closeMic(); // next press opens with the new device / processing
            cfg.micDeviceId = d.micDeviceId;
            cfg.micProcessing = d.micProcessing;
            cfg.clicks = d.clicks;
            if (cfg.micMode === 'warm') openMic().catch(function (e) { fail('mic', e); });
        }
    });

    function start(config) {
        cfg = config;
        loadModel().then(function () {
            if (cfg.micMode === 'warm') openMic().catch(function (e) { fail('mic', e); });
        });
    }

    // Lua answers the ready callback with the config, so there is no startup timing guess.
    window.lwkControlStart = start; // lets a plain browser test inject config without Lua
    if (RES) post('ready').then(start);
})();
