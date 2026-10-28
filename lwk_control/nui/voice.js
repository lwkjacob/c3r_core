/*
 * voice.js — dispatcher audio queue for lwk_control.
 *
 * Lua -> NUI : { type: 'speak', id, clips: [path...], volume }   queued, played in order
 *              { type: 'stopVoice' }                             clears the queue
 * NUI -> Lua : spoke { id }   when that item's last clip ends (or failed)
 *
 * Clips inside one item are decoded up front and scheduled back to back on one Web Audio
 * timeline, so spelled-out plates have no uneven gaps between letters.
 */
(function () {
    'use strict';

    var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    var GAP_S = 0.25; // pause between queued items

    var ctx = null;
    var queue = [];
    var busy = false;
    var generation = 0;
    var sources = [];
    var cache = {};

    function post(endpoint, data) {
        if (!RES) { console.log('[lwk_control] -> ' + endpoint, data); return; }
        fetch('https://' + RES + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    // Clips live in lwk_control_assets (index.html sets window.ASSETS).
    function url(path) {
        if (/^https:\/\/cfx-nui-[\w-]+\//.test(path)) return path; // another resource's clip (lwk_mdt's 911 line)
        path = String(path).replace(/^\/+/, '');
        if (/^nui\/(voice|clicks|sherpa)\//.test(path)) return window.ASSETS + path;
        return new URL('/' + path, location.href).href;
    }

    function decode(path) {
        if (!cache[path]) {
            cache[path] = fetch(url(path))
                .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + path); return r.arrayBuffer(); })
                .then(function (ab) { return ctx.decodeAudioData(ab); })
                .catch(function (e) { delete cache[path]; throw e; });
        }
        return cache[path];
    }

    function next() {
        if (busy || queue.length === 0) return;
        busy = true;
        var item = queue.shift();
        var gen = generation;
        ctx = ctx || new AudioContext();

        function done() {
            if (gen !== generation) return;
            sources = [];
            busy = false;
            post('spoke', { id: item.id });
            next();
        }

        ctx.resume()
            .then(function () { return Promise.all(item.clips.map(decode)); })
            .then(function (buffers) {
                if (gen !== generation) return;
                var gain = ctx.createGain();
                gain.gain.value = Math.max(0, Math.min(1, (item.volume == null ? 100 : item.volume) / 100));
                gain.connect(ctx.destination);
                var t = ctx.currentTime + 0.03;
                buffers.forEach(function (buf) {
                    var src = ctx.createBufferSource();
                    src.buffer = buf;
                    src.connect(gain);
                    src.start(t);
                    sources.push(src);
                    t += buf.duration;
                });
                setTimeout(done, Math.max(0, (t - ctx.currentTime + GAP_S) * 1000));
            })
            .catch(function (e) {
                console.error('[lwk_control] voice: ' + (e && e.message ? e.message : e));
                done();
            });
    }

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d) return;
        if (d.type === 'speak' && Array.isArray(d.clips) && d.clips.length) {
            queue.push({ id: d.id, clips: d.clips, volume: d.volume });
            next();
        } else if (d.type === 'stopVoice' || d.type === 'shutdown') {
            generation++;
            queue = [];
            sources.forEach(function (s) { try { s.stop(); } catch (x) {} });
            sources = [];
            busy = false;
        }
    });
})();
