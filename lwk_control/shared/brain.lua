--[[
    lwk_control — Brain: grammar builder + transcript parser. Pure Lua, no FiveM calls,
    so test/brain_test.lua can run it with a plain interpreter.

    Vosk grammar entries concatenate freely, so fillers ("dispatch", "can i get", "a")
    are single entries and every intent phrase is one entry. The parser then reads the
    word sequence: a verb group (request / cancel) plus the longest intent phrase found.
]]

Brain = {}

-- Every word here must exist in the model vocabulary (test/vocab_check.py).
Brain.fillers = {
    'dispatch', 'control', 'copy', 'please', 'a', 'an', 'the', 'my', 'me', 'to', 'on', 'that',
    'this', 'for', 'at', 'i', 'can you', 'go ahead', 'show me', 'roger', 'unit', 'location',
    'and', 'also',
}

Brain.verbs = {
    request = { 'requesting', 'request', 'i need', 'need', 'send', 'send me', 'roll', 'roll me',
                'can i get', 'get me', 'i want' },
    cancel  = { 'cancel', 'disregard', 'scratch', 'call off', 'no longer need' },
}

-- Phonetic alphabet: LAPD and NATO both map to the letter. "x ray" is two words in the vocabulary.
Brain.letters = {
    adam = 'A', boy = 'B', charles = 'C', david = 'D', edward = 'E', frank = 'F', george = 'G',
    henry = 'H', ida = 'I', john = 'J', king = 'K', lincoln = 'L', mary = 'M', nora = 'N',
    ocean = 'O', paul = 'P', queen = 'Q', robert = 'R', sam = 'S', tom = 'T', union = 'U',
    victor = 'V', william = 'W', ['x ray'] = 'X', young = 'Y', zebra = 'Z',
    alpha = 'A', bravo = 'B', charlie = 'C', delta = 'D', echo = 'E', foxtrot = 'F', golf = 'G',
    hotel = 'H', india = 'I', juliet = 'J', kilo = 'K', lima = 'L', mike = 'M', november = 'N',
    oscar = 'O', papa = 'P', quebec = 'Q', romeo = 'R', sierra = 'S', tango = 'T',
    uniform = 'U', whiskey = 'W', yankee = 'Y', zulu = 'Z',
}
Brain.digits = {
    zero = '0', one = '1', two = '2', three = '3', four = '4',
    five = '5', six = '6', seven = '7', eight = '8', nine = '9',
}

Brain.yes = { 'affirmative', 'yes', 'correct', 'that is correct', 'confirm', 'go ahead' }
Brain.no  = { 'negative', 'no', 'disregard', 'cancel', 'cancel that' }

local function words(s)
    local t = {}
    for w in s:gmatch('%S+') do t[#t + 1] = w end
    return t
end

-- Position of phrase (word list) in tokens as a whole-word run, searching from `from`.
local function find_run(tokens, phrase, from)
    for i = from or 1, #tokens - #phrase + 1 do
        local ok = true
        for j = 1, #phrase do
            if tokens[i + j - 1] ~= phrase[j] then ok = false break end
        end
        if ok then return i end
    end
end

local function add_all(set, list, list_is_keys)
    if list_is_keys then
        for k in pairs(list) do set[k] = true end
    else
        for _, p in ipairs(list) do set[p] = true end
    end
end

local function to_list(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

--- Grammar for normal mode: fillers, verbs, every intent phrase, plate vocabulary, plus
--- any extra words (the player's callsign).
function Brain.grammar(intents, extra)
    local set = {}
    add_all(set, extra or {})
    add_all(set, Brain.fillers)
    for _, list in pairs(Brain.verbs) do add_all(set, list) end
    for _, it in ipairs(intents) do add_all(set, it.say) end
    add_all(set, Brain.letters, true)
    add_all(set, Brain.digits, true)
    set['code'] = true
    return to_list(set)
end

function Brain.confirm_grammar()
    local set = {}
    add_all(set, Brain.yes)
    add_all(set, Brain.no)
    add_all(set, { 'dispatch', 'copy', 'say again' })
    return to_list(set)
end

function Brain.plate_grammar()
    local set = { dispatch = true, plate = true, disregard = true }
    add_all(set, Brain.letters, true)
    add_all(set, Brain.digits, true)
    return to_list(set)
end

--- Reads phonetic letters / digits from tokens[from..to]. Returns the plate string or nil.
function Brain.read_plate(tokens, from, to)
    local out = {}
    local i = from or 1
    to = to or #tokens
    while i <= to do
        local two = tokens[i + 1] and (tokens[i] .. ' ' .. tokens[i + 1])
        if two and Brain.letters[two] then
            out[#out + 1] = Brain.letters[two]
            i = i + 2
        else
            local ch = Brain.letters[tokens[i]] or Brain.digits[tokens[i]]
            if ch then out[#out + 1] = ch end
            i = i + 1
        end
    end
    return #out > 0 and table.concat(out) or nil
end

-- General fixes for free-form transcripts (sherpa-onnx): mishearings this kind of model makes on
-- radio phrasing. Rules that hold for any speaker, not fixes for individual clips. Words that are
-- too common in normal speech ("corner", "right") are deliberately left alone.
local WORD_FIX = {
    callouts = 'call outs', callout = 'call out', colleges = 'call outs', college = 'call out',
    despatch = 'dispatch', dispatcher = 'dispatch', dispatched = 'dispatch',
    -- commands never use ordinals: "ten eighth" -> "ten eight"
    fourth = 'four', fifth = 'five', sixth = 'six', seventh = 'seven', eighth = 'eight', ninth = 'nine', tenth = 'ten',
    play = 'plate', played = 'plate', plait = 'plate', plated = 'plate', plates = 'plate',
    tote = 'tow', toe = 'tow', towing = 'tow', towed = 'tow',
    seen = 'scene', seeing = 'scene', scenes = 'scene',
    corona = 'coroner', coronary = 'coroner', coroners = 'coroner',
}
-- After "code" / "ten" a number is expected: "code for" -> "code four", "ten ate" -> "ten eight".
local NUMBER_FIX = { ['for'] = 'four', fore = 'four', to = 'two', too = 'two', won = 'one', tree = 'three',
    free = 'three', ate = 'eight', secs = 'six', sex = 'six', sicks = 'six', sax = 'six' }
-- "corner" is coroner only right after a request ("need a corner"), never "around the corner"
local REQUEST_WORDS = { need = true, send = true, get = true, requesting = true, request = true, roll = true,
    want = true, call = true }
local ROUTE_LIKE = { route = true, rout = true, root = true, routes = true }
local CODE_LIKE = { coat = true, coke = true, cold = true, coach = true } -- "coat four" -> "code four"
local AIR_LIKE = { their = true, there = true, your = true, hair = true, ["they're"] = true } -- "their support"
local NUMBERS = { zero = true, one = true, two = true, three = true, four = true, five = true, six = true,
    seven = true, eight = true, nine = true, ten = true }

function Brain.normalize(text)
    local t = {}
    for w in (text or ''):lower():gsub("[^%w%s'%[%]]", ' '):gmatch('%S+') do -- keep ' (what's) and [unk]
        t[#t + 1] = WORD_FIX[w] or w
    end
    for i, w in ipairs(t) do
        local prev, nxt = t[i - 1], t[i + 1]
        if (prev == 'code' or prev == 'ten') and NUMBER_FIX[w] then t[i] = NUMBER_FIX[w] end
        if CODE_LIKE[w] and (NUMBERS[nxt or ''] or NUMBER_FIX[nxt or '']) then t[i] = 'code' end
        if AIR_LIKE[w] and (nxt == 'support' or nxt == 'unit') then t[i] = 'air' end
        if (w == 'two' or w == 'to' or w == 'too') and nxt == 'truck' then t[i] = 'tow' end
        if w == 'corner' and (prev == 'a' or prev == 'the') and REQUEST_WORDS[t[i - 2] or ''] then t[i] = 'coroner' end
        if (w == 'in' or w == 'on') and ROUTE_LIKE[nxt or ''] then t[i], t[i + 1] = 'en', 'route' end
    end
    -- a second look for "coat for": the number fix above runs on the word after "code"
    for i = 2, #t do
        if t[i - 1] == 'code' and NUMBER_FIX[t[i]] then t[i] = NUMBER_FIX[t[i]] end
    end
    return table.concat(t, ' ')
end

-- ─── tolerant phrase matching ─────────────────────────────────────────────────
-- Free-form speech doesn't follow our phrase list word for word, so a phrase matches when:
--   * up to MAX_GAP extra words sit between its words      ("hold ALL my call outs")
--   * small words in the phrase are missing                 ("scene clear" ~ "scene is clear")
--   * a word differs by an ending                           ("plates", "resumed", "requested")
--   * a long word is one letter off or clipped              ("ambulence", "ambul")
-- Exact words score higher than loose ones, so a loose match never beats a clear one.

local MAX_GAP = 2
local OPTIONAL = { a = true, an = true, the = true, that = true, this = true, my = true, me = true, to = true,
    is = true, of = true, ['for'] = true, at = true, i = true, can = true, please = true, will = true }
local INFLECT = { s = true, es = true, d = true, ed = true, ing = true, er = true, ers = true }
-- Everyday words one letter away from a command word; never fuzzy-match them ("corner" isn't "coroner").
local NO_FUZZY = { corner = true, corners = true, cancer = true, plane = true, place = true, places = true,
    sound = true }

local function within_one_edit(a, b)
    if math.abs(#a - #b) > 1 then return false end
    local i, j, edits = 1, 1, 0
    while i <= #a and j <= #b do
        if a:sub(i, i) == b:sub(j, j) then
            i, j = i + 1, j + 1
        else
            edits = edits + 1
            if edits > 1 then return false end
            if #a > #b then i = i + 1 elseif #b > #a then j = j + 1 else i, j = i + 1, j + 1 end
        end
    end
    return edits + (#a - i + 1) + (#b - j + 1) <= 1
end

-- How well token t stands for phrase word p: 1 exact, less for looser matches, 0 no match.
local function word_score(t, p)
    if t == p then return 1 end
    if #t > #p and t:sub(1, #p) == p and INFLECT[t:sub(#p + 1)] then return 0.9 end
    if #p > #t and p:sub(1, #t) == t and INFLECT[p:sub(#t + 1)] then return 0.9 end
    if #t >= 5 and #p >= 5 and not NO_FUZZY[t] and within_one_edit(t, p) then return 0.7 end
    if #t >= 4 and #p >= 6 and p:sub(1, #t) == t then return 0.6 end -- clipped long word
    return 0
end

-- Best alignment of phrase words pw[i..] onto tokens from k on. Returns score, first, last token.
local function align(tokens, pw, i, k, gaps, first, last, score)
    if i > #pw then
        if not first then return nil end
        return score - 0.3 * gaps, first, last
    end
    local w = pw[i]
    local best_s, bf, bl
    for g = 0, first and MAX_GAP or 0 do -- the phrase itself has to start where we start
        local t = tokens[k + g]
        if not t then break end
        local q = word_score(t, w)
        if q > 0 then
            local s, f, l = align(tokens, pw, i + 1, k + g + 1, gaps + g, first or (k + g), k + g,
                score + q * (OPTIONAL[w] and 0.5 or 1))
            if s and (not best_s or s > best_s) then best_s, bf, bl = s, f, l end
        end
    end
    if OPTIONAL[w] then -- the small word may be missing
        local s, f, l = align(tokens, pw, i + 1, k, gaps, first, last, score)
        if s and (not best_s or s > best_s) then best_s, bf, bl = s, f, l end
    end
    return best_s, bf, bl
end

-- Every place phrase p matches: { { score, first, last }, ... }
local function phrase_hits(tokens, p)
    local pw, hits = words(p), {}
    for k = 1, #tokens do
        local s, f, l = align(tokens, pw, 1, k, 0, nil, nil, 0)
        if s then hits[#hits + 1] = { s, f, l } end
    end
    return hits
end

--- 'yes' | 'no' | nil for a confirm-mode transcript.
function Brain.parse_confirm(text)
    local tokens = words(text)
    local best, best_score = nil, 0
    for answer, list in pairs({ yes = Brain.yes, no = Brain.no }) do
        for _, p in ipairs(list) do
            for _, h in ipairs(phrase_hits(tokens, p)) do
                if h[1] > best_score then best, best_score = answer, h[1] end
            end
        end
    end
    return best
end

-- Verb phrases by start position: [pos] = verb group (best-scoring phrase wins at a position).
local function verb_marks(tokens)
    local marks, scores = {}, {}
    for verb, list in pairs(Brain.verbs) do
        for _, p in ipairs(list) do
            for _, h in ipairs(phrase_hits(tokens, p)) do
                local s, pos = h[1], h[2]
                if not scores[pos] or s > scores[pos] then marks[pos], scores[pos] = verb, s end
            end
        end
    end
    return marks
end

-- The verb that governs a command at `pos`: the nearest one said before it.
local function verb_before(marks, pos)
    for i = pos - 1, 1, -1 do
        if marks[i] then return marks[i] end
    end
end

--[[ Every command in the token list, by position, best-scoring phrases first, so "back in service"
     claims its words before "in service" can. Each command uses the nearest verb before it,
     which is what lets "cancel the tow truck and the ambulance" cancel both, and it doesn't
     depend on hearing "and". Phrases match tolerantly (see align).
     Returns a list of { it, pos, len, verb } in spoken order, or nil, 'ambiguous' when two
     different intents claim the same words with equal scores. ]]
local function match_all(tokens, intents)
    local marks = verb_marks(tokens)
    local hits = {} -- computed once: { it, score, first, last }
    for _, it in ipairs(intents) do
        for _, p in ipairs(it.say) do
            for _, h in ipairs(phrase_hits(tokens, p)) do
                hits[#hits + 1] = { it = it, score = h[1], first = h[2], last = h[3] }
            end
        end
    end
    local used, found = {}, {}
    while true do
        local best, tie
        for _, h in ipairs(hits) do
            local free = true
            for i = h.first, h.last do
                if used[i] then free = false break end
            end
            local verb = verb_before(marks, h.first)
            local it = h.it
            if free and (it.verb == nil or it.verb == verb or (verb == nil and it.verb == 'request')) then
                if not best or h.score > best.score + 1e-6 then
                    best, tie = { it = it, pos = h.first, len = h.last - h.first + 1, verb = verb, score = h.score }, false
                elseif math.abs(h.score - best.score) <= 1e-6 and it ~= best.it
                    and h.first < best.pos + best.len and best.pos <= h.last then
                    tie = true
                end
            end
        end
        if not best then break end
        if tie then return nil, 'ambiguous' end
        for i = best.pos, best.pos + best.len - 1 do used[i] = true end
        found[#found + 1] = best
    end
    table.sort(found, function(a, b) return a.pos < b.pos end)
    return found
end

local function tokenize(text)
    local tokens = {}
    for _, w in ipairs(words(text or '')) do
        if w ~= '[unk]' then tokens[#tokens + 1] = w end
    end
    return tokens
end

-- Slots read from the words after the command, up to where the next command starts.
local function context(m, tokens, to)
    local ctx = { verb = m.verb, text = table.concat(tokens, ' ') }
    if m.it.slot == 'plate' then
        ctx.plate = Brain.read_plate(tokens, m.pos + m.len, to)
    elseif m.it.slot == 'code' then
        local c = find_run(tokens, { 'code' }, m.pos)
        if c and c < to then ctx.code = tonumber(Brain.digits[tokens[c + 1] or ''] or '') end
    end
    return ctx
end

--[[ Every command in a transcript, in spoken order, repeats collapsed:
     "send me a tow truck and an ambulance" -> request_tow, request_ambulance
     Returns { { intent, ctx }, ... }  or  nil, reason  ('empty' | 'unknown' | 'ambiguous').
     An intent with `verb` only matches when that verb group governs it; 'request' is also the
     default when no verb is said ("dispatch, tow truck"). Intents without `verb` ignore it. ]]
function Brain.parse_all(text, intents)
    local tokens = tokenize(text)
    if #tokens == 0 then return nil, (text or ''):find('%[unk%]') and 'unknown' or 'empty' end
    local found, reason = match_all(tokens, intents)
    if not found then return nil, reason end
    if #found == 0 then return nil, 'unknown' end
    local out, seen = {}, {}
    for i, m in ipairs(found) do
        if not seen[m.it] then
            seen[m.it] = true
            local to = found[i + 1] and found[i + 1].pos - 1 or #tokens
            out[#out + 1] = { intent = m.it, ctx = context(m, tokens, to) }
        end
    end
    return out
end

--- Single-command parse: intent, ctx  or  nil, reason (two different commands -> 'ambiguous').
function Brain.parse(text, intents)
    local cmds, reason = Brain.parse_all(text, intents)
    if not cmds then return nil, reason end
    if #cmds > 1 then return nil, 'ambiguous' end
    return cmds[1].intent, cmds[1].ctx
end

-- ─── sound-alike snapping ─────────────────────────────────────────────────────
-- Last resort when nothing matched: compare how the words SOUND with every command phrase and take
-- the closest, if it's close enough. "play check" ~ "plate check", "corner" ~ "coroner".

-- Rough pronunciation code: consonant skeleton, a leading vowel kept as 'a', doubles collapsed.
local function sound(w)
    w = w:lower():gsub('[^a-z]', '')
    if w == '' then return '' end
    w = w:gsub('tch', 'C'):gsub('ch', 'C'):gsub('sh', 'S'):gsub('th', 'T'):gsub('ph', 'f'):gsub('ck', 'k')
        :gsub('wh', 'w'):gsub('kn', 'n'):gsub('wr', 'r'):gsub('gh', 'g'):gsub('dge', 'j'):gsub('qu', 'kw')
        :gsub('c([eiy])', 's%1'):gsub('c', 'k'):gsub('q', 'k'):gsub('x', 'ks'):gsub('z', 's')
    local first, rest = w:sub(1, 1), w:sub(2):gsub('[aeiouyh]', '')
    if first:match('[aeiouy]') then first = 'a' end
    return ((first .. rest):gsub('(.)%1+', '%1'))
end

local function edit_distance(a, b)
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a:byte(i) == b:byte(j) and 0 or 1))
        end
        prev = cur
    end
    return prev[#b]
end

local SNAP_MAX = 0.25    -- at most 1 sound in 4 different
local SNAP_ASK = 0.34     -- closer than this but not sure: ask "did you mean ...?" instead
local SNAP_MIN_LEN = 3   -- phrases with fewer consonant sounds are never snapped to: "tow" is too easy to hit
local SNAP_MARGIN = 0.08 -- a different command this close behind = too unsure to run without asking
local SNAP_LIKELY = 0.06 -- head start for commands that fit the situation (plate check on a traffic stop)

--[[ The closest-sounding command. Respects verbs the same way as parse_all.
     likely = { [intent id] = true } for commands that fit the current situation (optional).
     Returns intent, ctx, sure, fix  or nil. sure = close and clearly ahead of any other command;
     otherwise worth asking about. fix = { from = heard words, to = the phrase they sounded like }. ]]
function Brain.snap(text, intents, likely)
    local tokens = tokenize(text)
    if #tokens == 0 then return nil end
    local codes = {}
    for i, t in ipairs(tokens) do codes[i] = sound(t) end
    local marks = verb_marks(tokens)
    local best, second
    for _, it in ipairs(intents) do
        if not it.chat then
            local bonus = likely and likely[it.id] and SNAP_LIKELY or 0
            for _, p in ipairs(it.say) do
                local pw = words(p)
                local target = ''
                for _, w in ipairs(pw) do target = target .. sound(w) end
                -- consonant sounds only: vowel-led words collapse to 'a' ("are you" ~ "air one")
                if #target:gsub('a', '') >= SNAP_MIN_LEN then
                    -- one or two-word commands need as many heard words ("me check" isn't "mechanic",
                    -- "under" isn't "on duty"); longer ones may lose a word ("holmecoll cuts")
                    for len = #pw <= 2 and #pw or #pw - 1, #pw == 1 and 1 or #pw + 1 do
                        for i = 1, #tokens - len + 1 do
                            local verb = verb_before(marks, i)
                            if it.verb == nil or it.verb == verb or (verb == nil and it.verb == 'request') then
                                local heard = table.concat(codes, '', i, i + len - 1)
                                local d = edit_distance(heard, target) / #target - bonus
                                -- the opening sound must agree (robust in speech); vowel-led phrases and a
                                -- leading h (often dropped or misheard: "told" for "hold") are exempt
                                local onset_ok = target:sub(1, 1) == 'a' or target:sub(1, 1) == 'h'
                                    or heard:sub(1, 1) == target:sub(1, 1)
                                -- one sound off in a one-word command ("place" / "plate") is too weak to ask about
                                if d <= (#pw == 1 and SNAP_MAX or SNAP_ASK) and onset_ok then
                                    local c = { it = it, pos = i, len = len, verb = verb, d = d, phrase = p }
                                    if not best or d < best.d then
                                        if best and best.it ~= it then second = best end
                                        best = c
                                    elseif it ~= best.it and (not second or d < second.d) then
                                        second = c
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not best then return nil end
    local sure = best.d <= SNAP_MAX and not (second and second.d - best.d < SNAP_MARGIN)
    local fix = { from = table.concat(tokens, ' ', best.pos, best.pos + best.len - 1), to = best.phrase }
    return best.it, context(best, tokens, #tokens), sure, fix
end

-- ─── learned corrections ──────────────────────────────────────────────────────
-- After a "say again", the retry that worked shows what the recognizer got wrong the first time:
-- "tote truck" then "tow truck" teaches tote -> tow for this player.

local LEARN_MAX = 0.5 -- the misheard and corrected words must sound at least half alike

local function vocabulary(intents)
    local set = {}
    for _, p in ipairs(Brain.grammar(intents)) do
        for w in p:gmatch('%S+') do set[w] = true end
    end
    return set
end

local function sounds(list, i, j)
    local out = ''
    for k = i, j do out = out .. sound(list[k]) end
    return out
end

--[[ Corrections from a failed transcript and the retry that parsed: the word runs that differ
     between them (aligned on the words they share), kept only when the misheard words are all
     outside the command vocabulary and sound like their replacement.
     Returns { { from, to }, ... } (possibly empty). ]]
function Brain.learn(failed, ok, intents)
    local a, b = tokenize(failed), tokenize(ok)
    -- longest common subsequence table, then walk it to pair up the runs between shared words
    local L = {}
    for i = #a + 1, 1, -1 do
        L[i] = {}
        for j = #b + 1, 1, -1 do
            if i > #a or j > #b then L[i][j] = 0
            elseif a[i] == b[j] then L[i][j] = L[i + 1][j + 1] + 1
            else L[i][j] = math.max(L[i + 1][j], L[i][j + 1]) end
        end
    end
    local vocab, out = vocabulary(intents), {}
    local function pair(i1, i2, j1, j2)
        if i2 < i1 or j2 < j1 or i2 - i1 > 2 or j2 - j1 > 3 then return end
        for k = i1, i2 do if vocab[a[k]] or #a[k] < 3 then return end end
        local sa, sb = sounds(a, i1, i2), sounds(b, j1, j2)
        if #sb < 2 or edit_distance(sa, sb) / math.max(#sa, #sb) > LEARN_MAX then return end
        out[#out + 1] = { from = table.concat(a, ' ', i1, i2), to = table.concat(b, ' ', j1, j2) }
    end
    local i, j, ri, rj = 1, 1, 1, 1
    while i <= #a and j <= #b do
        if a[i] == b[j] then
            pair(ri, i - 1, rj, j - 1)
            i, j = i + 1, j + 1
            ri, rj = i, j
        elseif L[i + 1][j] >= L[i][j + 1] then i = i + 1
        else j = j + 1 end
    end
    pair(ri, #a, rj, #b)
    return out
end

--- Applies learned { from, to } corrections as whole-word replacements.
function Brain.apply_fixes(text, fixes)
    if not fixes or #fixes == 0 or text == '' then return text end
    local padded = ' ' .. text .. ' '
    for _, f in ipairs(fixes) do
        if f.from:match("^[%w' ]+$") then
            padded = padded:gsub(' ' .. f.from .. ' ', ' ' .. f.to .. ' ')
        end
    end
    return padded:sub(2, -2)
end

-- ─── plate readout ────────────────────────────────────────────────────────────

-- Colour strings vary ("Metallic Black", "Hot Pink", "Dark Blue"): first keyword hit wins,
-- so the more specific words come first.
local COLOR_WORDS = {
    { 'maroon', 'maroon' }, { 'burgundy', 'maroon' }, { 'wine', 'maroon' }, { 'pink', 'pink' },
    { 'purple', 'purple' }, { 'violet', 'purple' }, { 'orange', 'orange' }, { 'gold', 'gold' },
    { 'bronze', 'bronze' }, { 'beige', 'beige' }, { 'tan', 'beige' }, { 'cream', 'beige' },
    { 'champagne', 'beige' }, { 'silver', 'silver' }, { 'chrome', 'silver' }, { 'aluminum', 'silver' },
    { 'graphite', 'grey' }, { 'grey', 'grey' }, { 'gray', 'grey' }, { 'brown', 'brown' },
    { 'chocolate', 'brown' }, { 'olive', 'green' }, { 'lime', 'green' }, { 'green', 'green' },
    { 'yellow', 'yellow' }, { 'teal', 'blue' }, { 'blue', 'blue' }, { 'red', 'red' },
    { 'white', 'white' }, { 'black', 'black' },
}

-- Makes that start with a vowel sound but not a vowel letter, and vice versa.
local AN_MAKES = { mtl = true, lcc = true }

--- 'Übermacht' -> 'ubermacht', 'Mercedes-Benz' -> 'mercedes_benz'
function Brain.clip_key(s)
    s = tostring(s or ''):gsub('\195[\156\188]', 'u'):gsub('\195[\137\169]', 'e'):lower() -- Üü, Éé (lower() skips UTF-8)
    s = s:gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return s
end

function Brain.color_key(color)
    local c = ' ' .. tostring(color or ''):lower():gsub('[^%a]+', ' ') .. ' '
    for _, e in ipairs(COLOR_WORDS) do
        if c:find(' ' .. e[1] .. ' ', 1, true) then return e[2] end
    end
end

--[[ Vehicle words for "returns to a <year> <color> <make> <model>".
     exists(key) says whether nui/voice/vehicle/<key>.ogg is present; words without a clip are
     skipped. Returns the keys plus 'a' / 'an' for the connective, or nil when nothing can be said. ]]
function Brain.vehicle_words(v, exists)
    local keys, first = {}, nil
    local function add(key, word)
        if key and exists(key) then
            keys[#keys + 1] = key
            first = first or word
        end
    end
    local year = tonumber(v.year)
    add(year and ('year_' .. math.floor(year)), 'year')
    local color = Brain.color_key(v.color)
    add(color and ('color_' .. color), color)
    local make = Brain.clip_key(v.make)
    if make ~= '' and not exists('make_' .. make) then make = make:match('^[^_]+') end -- "Bravado Motors"
    add(make ~= '' and ('make_' .. make), make)
    local model = Brain.clip_key(v.model)
    add(model ~= '' and ('model_' .. model), model) -- no model clips ship; owners can add them
    if #keys == 0 then return nil end
    local article = (first ~= 'year' and (first:find('^[aeiou]') or AN_MAKES[first])) and 'an' or 'a'
    return keys, article
end

-- ─── callsigns ────────────────────────────────────────────────────────────────

local LAPD = {}
for i, w in ipairs({ 'adam', 'boy', 'charles', 'david', 'edward', 'frank', 'george', 'henry', 'ida', 'john',
    'king', 'lincoln', 'mary', 'nora', 'ocean', 'paul', 'queen', 'robert', 'sam', 'tom', 'union', 'victor',
    'william', 'x ray', 'young', 'zebra' }) do
    LAPD[string.char(96 + i)] = w
end
local ONES = { [0] = 'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
    'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen' }
local TENS = { [2] = 'twenty', [3] = 'thirty', [4] = 'forty', [5] = 'fifty', [6] = 'sixty', [7] = 'seventy',
    [8] = 'eighty', [9] = 'ninety' }

--[[ '1-Adam-12', '1A12', '3 charles 11' -> {
       clips = { 'nui/voice/letters/1.ogg', 'nui/voice/letters/a.ogg', 'nui/voice/numbers/12.ogg' },
       words = { 'one', 'adam', 'twelve' },   -- what the player says (added to the grammar)
     }
     Numbers are said the way people say callsigns: "twelve", "four thirty eight", "one oh four",
     "twelve thirty four". A leading zero or 5+ digits go digit by digit ("zero four"). Letters are spoken with the LAPD alphabet; a NATO word maps to its letter.
     Returns nil for anything else. ]]
function Brain.callsign(s)
    s = tostring(s or ''):lower():gsub('(%d)(%a)', '%1 %2'):gsub('(%a)(%d)', '%1 %2')
    local clips, said = {}, {}
    local function digit(d)
        clips[#clips + 1] = ('nui/voice/letters/%s.ogg'):format(d)
        said[#said + 1] = ONES[tonumber(d)]
    end
    local function pair(n) -- 10..99 as one number: "thirty eight"
        clips[#clips + 1] = ('nui/voice/numbers/%d.ogg'):format(n)
        if n < 20 then said[#said + 1] = ONES[n]
        else
            said[#said + 1] = TENS[n // 10]
            if n % 10 > 0 then said[#said + 1] = ONES[n % 10] end
        end
    end
    -- the last two digits of a 3-4 digit number: "38" -> thirty eight, "04" -> oh four, "00" -> zero zero
    local function tail(two)
        if two:sub(1, 1) ~= '0' then return pair(tonumber(two)) end
        if two == '00' then digit('0') digit('0') return end
        clips[#clips + 1] = 'nui/voice/time_oh_1.ogg'
        said[#said + 1] = 'oh'
        digit(two:sub(2))
    end
    for g in s:gmatch('%w+') do
        if g:match('^%d+$') then
            local n = tonumber(g)
            if #g == 1 then
                digit(g)
            elseif #g == 2 and g:sub(1, 1) ~= '0' then
                pair(n)
            elseif #g == 3 and g:sub(1, 1) ~= '0' then -- 438 -> four thirty eight, 104 -> one oh four
                digit(g:sub(1, 1))
                tail(g:sub(2))
            elseif #g == 4 and g:sub(1, 1) ~= '0' then -- 1234 -> twelve thirty four
                pair(tonumber(g:sub(1, 2)))
                tail(g:sub(3))
            else
                for d in g:gmatch('%d') do digit(d) end
            end
        else
            local letter = #g == 1 and g or (Brain.letters[g] or ''):lower()
            if letter == '' then return nil end
            clips[#clips + 1] = ('nui/voice/letters/%s.ogg'):format(letter)
            said[#said + 1] = #g == 1 and LAPD[letter] or g
        end
    end
    if #clips == 0 or #clips > 8 then return nil end
    return { clips = clips, words = said }
end

-- ─── locations ────────────────────────────────────────────────────────────────

--[[ Spoken location from GetStreetNameAtCoord / GetNameOfZone output:
       loc = { street = 'Strawberry Ave', cross = 'Davis Ave', zone = 'DAVIS', zone_name = 'Davis' }
     -> items for Speak ('loc_and' / 'loc_in' are voice keys, places are clip paths) and feed text:
       "Strawberry Ave & Davis Ave", or "Strawberry Ave in Davis" with no cross street,
       or just the area off-road. exists(key) says whether nui/voice/places/<key>.ogg ships;
       anything without a clip is left out. Returns nil when nothing can be said. ]]
function Brain.location_words(loc, exists)
    local function key(prefix, s) return s and s ~= '' and (prefix .. Brain.clip_key(s)) or nil end
    local function path(k) return ('nui/voice/places/%s.ogg'):format(k) end
    local street, cross, zone = key('street_', loc.street), key('street_', loc.cross), key('zone_', loc.zone)
    local items, text = {}, {}
    if street and exists(street) then
        items[#items + 1], text[#text + 1] = path(street), loc.street
        if cross and cross ~= street and exists(cross) then
            items[#items + 1], items[#items + 2] = 'loc_and', path(cross)
            text[#text + 1] = '& ' .. loc.cross
        elseif zone and exists(zone) then
            items[#items + 1], items[#items + 2] = 'loc_in', path(zone)
            text[#text + 1] = 'in ' .. (loc.zone_name or loc.zone)
        end
    elseif zone and exists(zone) then
        items[#items + 1], text[#text + 1] = path(zone), loc.zone_name or loc.zone
    end
    if #items == 0 then return nil end
    return items, table.concat(text, ' ')
end

-- ─── distance / direction / time ──────────────────────────────────────────────

local function number_clip(n)
    return n < 10 and ('nui/voice/letters/%d.ogg'):format(n) or ('nui/voice/numbers/%d.ogg'):format(n)
end

--- Metres -> spoken distance: "right near you", "a quarter mile", "half a mile", ..., "3 miles".
--- Returns Speak items, feed text.
function Brain.distance_words(metres)
    local mi = metres / 1609.34
    if mi < 0.12 then return { 'dist_close' }, 'right near you' end
    if mi < 0.375 then return { 'dist_quarter' }, 'a quarter mile' end
    if mi < 0.625 then return { 'dist_half' }, 'half a mile' end
    if mi < 0.875 then return { 'dist_threequarter' }, 'three quarters of a mile' end
    if mi < 1.5 then return { 'dist_mile' }, 'a mile' end
    local n = math.min(99, math.floor(mi + 0.5))
    return { number_clip(n), 'dist_miles' }, n .. ' miles'
end

local DIRS = { 'n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw' }
local DIR_TEXT = { n = 'north', ne = 'northeast', e = 'east', se = 'southeast', s = 'south', sw = 'southwest',
    w = 'west', nw = 'northwest' }

--- Compass direction of a vector (GTA: +y north, +x east) -> 'dir_ne', 'northeast'.
function Brain.direction(dx, dy)
    local deg = math.deg(math.atan(dx, dy)) % 360
    local d = DIRS[math.floor((deg + 22.5) / 45) % 8 + 1]
    return 'dir_' .. d, DIR_TEXT[d]
end

--- 24-hour clock -> "fourteen thirty hours", "zero nine hundred hours", "twenty one oh five hours".
function Brain.time_words(h, m)
    local items = {}
    if h < 10 then
        items[1], items[2] = number_clip(0), number_clip(h)
    else
        items[1] = number_clip(h)
    end
    if m == 0 then
        items[#items + 1] = 'time_hundred'
    else
        if m < 10 then items[#items + 1] = 'time_oh' end
        items[#items + 1] = number_clip(m)
        items[#items + 1] = 'time_hours'
    end
    return items, ('%02d%02d hours'):format(h, m)
end

--- Which unit's callsign was said: units = { { id, callsign, words = { 'two', 'boy', 'four' } } }.
--- The longest callsign said as a run of words wins. Returns the unit or nil.
function Brain.find_unit(text, units)
    local tokens = {}
    for w in (text or ''):gmatch('%S+') do tokens[#tokens + 1] = w end
    local best, best_len = nil, 0
    for _, u in ipairs(units) do
        local words = {}
        for _, w in ipairs(u.words or {}) do
            for part in w:gmatch('%S+') do words[#words + 1] = part end -- 'x ray' -> 'x', 'ray'
        end
        if #words > best_len and find_run(tokens, words) then best, best_len = u, #words end
    end
    return best
end
