/*
 * settings.js — player settings panel (mic, dispatcher volume, radio clicks).
 * Lua -> NUI : { type: 'openSettings', micDeviceId, voiceVolume, clicksEnabled, clicksVolume, learned }
 *              { type: 'micTestResult', heard, command }
 * NUI -> Lua : saveSettings {...}, closeSettings
 * Mic check: micTestStart / micTestStop to ears.js (same page), which meters the audio (lwkMicLevel).
 */
(function () {
    'use strict';

    var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    var $ = function (id) { return document.getElementById(id); };

    function post(endpoint, data) {
        if (!RES) { console.log('[lwk_control] -> ' + endpoint, data); return Promise.resolve(); }
        return fetch('https://' + RES + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    // Device labels are only exposed after mic permission, so open and immediately close a stream first.
    function listMics(selected) {
        var sel = $('set-mic');
        navigator.mediaDevices.getUserMedia({ audio: true })
            .then(function (s) { s.getTracks().forEach(function (t) { t.stop(); }); })
            .catch(function () {})
            .then(function () { return navigator.mediaDevices.enumerateDevices(); })
            .then(function (devices) {
                sel.innerHTML = '<option value="">Default system microphone</option>';
                devices.filter(function (d) { return d.kind === 'audioinput'; }).forEach(function (d, i) {
                    var o = document.createElement('option');
                    o.value = d.deviceId;
                    o.textContent = d.label || ('Microphone ' + (i + 1));
                    sel.appendChild(o);
                });
                sel.value = selected || '';
                if (sel.value !== (selected || '')) sel.value = ''; // saved device unplugged
            });
    }

    function bindSlider(id) {
        var s = $(id), b = $(id + '-val');
        s.addEventListener('input', function () { b.textContent = s.value + '%'; });
        return function (v) { s.value = v; b.textContent = v + '%'; };
    }

    // ── mic check ──
    var testPeak = -1;
    var micTest = $('mic-test');

    function testStart() {
        if (micTest.classList.contains('held')) return;
        micTest.classList.add('held');
        testPeak = -1;
        $('mic-hint').textContent = '';
        $('mic-heard').textContent = 'Listening...';
        window.postMessage({ type: 'micTestStart', micDeviceId: $('set-mic').value, micProcessing: $('set-micfx').checked }, '*');
    }

    function testStop() {
        if (!micTest.classList.contains('held')) return;
        micTest.classList.remove('held');
        $('mic-level').style.width = '0';
        $('mic-heard').textContent = 'Working...';
        window.postMessage({ type: 'micTestStop' }, '*');
        // peak level over the whole test: too quiet hurts recognition, clipping distorts it
        if (testPeak < 0) $('mic-hint').textContent = 'no audio from this mic';
        else if (testPeak < 0.05) $('mic-hint').textContent = 'very quiet: turn the mic up';
        else if (testPeak >= 0.99) $('mic-hint').textContent = 'clipping: turn the mic down';
        else $('mic-hint').textContent = 'level good';
    }

    micTest.addEventListener('mousedown', testStart);
    micTest.addEventListener('mouseup', testStop);
    micTest.addEventListener('mouseleave', testStop);

    window.addEventListener('lwkMicLevel', function (e) {
        if (!micTest.classList.contains('held')) return;
        var d = e.detail;
        testPeak = Math.max(testPeak, d.peak);
        var db = 20 * Math.log10(Math.max(d.rms, 1e-6)); // speech sits around -30..-15 dB
        var bar = $('mic-level');
        bar.style.width = Math.max(0, Math.min(100, (db + 60) / 60 * 100)) + '%';
        bar.classList.toggle('clip', d.peak >= 0.99);
    });

    function showTest(d) {
        var heard = d.heard ? 'Heard "' + d.heard + '"' : 'Heard nothing';
        $('mic-heard').textContent = heard + (d.heard ? ' \u2192 ' + (d.command || 'no command (dispatch would say "say again")') : '');
    }

    // ── learned corrections ──
    var learned = [];

    function renderLearned() {
        var box = $('learned');
        box.innerHTML = '';
        if (!learned.length) {
            box.innerHTML = '<div class="muted">None yet. When dispatch says "say again" and your retry works, the misheard words are remembered here.</div>';
            return;
        }
        learned.forEach(function (f, i) {
            var row = document.createElement('div');
            row.className = 'fix';
            var label = document.createElement('span');
            label.textContent = '"' + f.from + '" \u2192 "' + f.to + '"';
            var x = document.createElement('button');
            x.textContent = '\u00d7';
            x.title = 'Forget this correction';
            x.addEventListener('click', function () { learned.splice(i, 1); renderLearned(); });
            row.appendChild(label);
            row.appendChild(x);
            box.appendChild(row);
        });
    }

    var setVoice = bindSlider('set-voice');
    var setClicks = bindSlider('set-clicks');

    function open(d) {
        listMics(d.micDeviceId);
        setVoice(d.voiceVolume);
        setClicks(d.clicksVolume);
        $('set-clicks-on').checked = d.clicksEnabled !== false;
        $('set-micfx').checked = d.micProcessing !== false;
        $('set-callsign').value = d.callsign || '';
        $('set-callsign').disabled = !!d.callsignFromCad; // signed on in the CAD: changed there, in its settings
        $('set-callsign-hint').textContent = d.callsignFromCad ? '(from the CAD: change it in the CAD settings)' : '';
        $('set-callsign-on').checked = d.callsignSpoken !== false;
        var anim = $('set-anim');
        anim.innerHTML = '';
        (d.radioAnims || []).forEach(function (name) {
            var o = document.createElement('option');
            o.value = o.textContent = name;
            anim.appendChild(o);
        });
        anim.value = d.radioAnim;
        if (anim.selectedIndex < 0) anim.selectedIndex = 0; // saved pick no longer offered (e.g. rpemotes gone)
        learned = Array.isArray(d.learned) ? d.learned.slice() : [];
        renderLearned();
        $('mic-hint').textContent = '';
        $('mic-heard').textContent = 'Shows what dispatch hears and which command it matches.';

        $('settings').classList.add('open');
    }

    function close(save) {
        testStop();
        $('settings').classList.remove('open');
        if (!save) return post('closeSettings');
        post('saveSettings', {
            micDeviceId: $('set-mic').value,
            voiceVolume: Number($('set-voice').value),
            clicksEnabled: $('set-clicks-on').checked,
            clicksVolume: Number($('set-clicks').value),
            callsign: $('set-callsign').value.trim(),
            callsignSpoken: $('set-callsign-on').checked,
            radioAnim: $('set-anim').value,
            micProcessing: $('set-micfx').checked,
            learned: learned,
        });
    }

    $('set-save').addEventListener('click', function () { close(true); });
    $('set-cancel').addEventListener('click', function () { close(false); });
    $('set-test').addEventListener('click', function () {
        window.postMessage({ type: 'speak', clips: ['nui/voice/copy_1.ogg'], volume: Number($('set-voice').value) }, '*');
    });
    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && $('settings').classList.contains('open')) close(false);
    });

    window.addEventListener('message', function (e) {
        if (e.data && e.data.type === 'openSettings') open(e.data);
        else if (e.data && e.data.type === 'micTestResult') showTest(e.data);
        else if (e.data && e.data.type === 'closeSettingsUi') $('settings').classList.remove('open');
    });
})();
