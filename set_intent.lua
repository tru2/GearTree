-- GearTree set_intent
-- Gear/stat evidence fallback classifier for sets that reach Other > Uncategorized.
-- Called from semantics.lua after all path/reference/content rules have failed.
-- Read-only: no equip, save, parse, or mutation.

local set_intent = {}

-- Stat keyword signals scored against augment/item text in rhs.slots.
local STAT_SIGNALS = {
    {
        intent    = 'precast',
        route     = { 'Magic', 'Precast' },
        category  = 'Pre-Action Timing',
        trigger   = 'Fast Cast / Precast',
        keywords  = { 'fast cast', 'quick magic', 'sird', 'spell interruption', 'snapshot' },
        threshold = 1,
    },
    {
        intent    = 'healing',
        route     = { 'Magic', 'Cure / Healing' },
        category  = 'Healing / Cure Sets',
        trigger   = 'Healing Magic',
        keywords  = { 'cure potency', 'healing magic', 'cursna', 'cure received' },
        threshold = 1,
    },
    {
        intent    = 'enhancing',
        route     = { 'Magic', 'Enhancing' },
        category  = 'Buff Duration / Enhancing Sets',
        trigger   = 'Enhancing Magic',
        keywords  = { 'enhancing magic', 'stoneskin', 'phalanx', 'aquaveil', 'haste duration' },
        threshold = 1,
    },
    {
        intent    = 'elemental',
        route     = { 'Magic', 'Elemental / Nuking' },
        category  = 'Nuking / Elemental Sets',
        trigger   = 'Elemental Magic',
        keywords  = { 'magic atk', 'mag. atk.', 'mab', 'elemental magic skill', 'magic dmg' },
        threshold = 1,
    },
    {
        intent    = 'enfeebling',
        route     = { 'Magic', 'Enfeebling' },
        category  = 'Debuff / Magic Accuracy Sets',
        trigger   = 'Enfeebling Magic',
        keywords  = { 'enfeebling magic', 'enfeebling skill' },
        threshold = 1,
    },
    {
        intent    = 'engaged',
        route     = { 'Current State', 'Engaged' },
        category  = 'Melee / TP Sets',
        trigger   = 'Engaged melee state',
        -- Requires 2+ signals: any one of these alone is too ambiguous
        keywords  = { 'store tp', 'dual wield', 'multi attack', 'double attack', 'triple attack' },
        threshold = 2,
    },
    {
        intent    = 'weaponskill',
        route     = { 'Actions', 'Weapon Skills' },
        category  = 'Weapon Skill Set',
        trigger   = 'Weapon Skill',
        keywords  = { 'weapon skill damage', 'wsd', 'tp bonus', 'fstr' },
        threshold = 1,
    },
    {
        intent    = 'defensive',
        route     = { 'Current State', 'Defense' },
        category  = 'Defensive Modes',
        trigger   = 'Defense mode',
        keywords  = { 'damage taken', 'pdt', 'mdt', 'magic damage taken', 'meva', 'magic evasion' },
        threshold = 1,
    },
    {
        intent    = 'idle',
        route     = { 'Current State', 'Idle' },
        category  = 'Idle / Recovery Sets',
        trigger   = 'Idle state',
        -- Requires 2+: refresh alone appears in too many sets
        keywords  = { 'refresh', 'regen', 'hp recovered', 'mp recovered' },
        threshold = 2,
    },
    {
        intent    = 'treasurehunter',
        route     = { 'Overlays / Modifiers', 'Treasure Hunter' },
        category  = 'Loot / Tagging Overlay',
        trigger   = 'Treasure Hunter tagging',
        keywords  = { 'treasure hunter' },
        threshold = 1,
    },
    {
        intent    = 'pet',
        route     = { 'Pet' },
        category  = 'Pet / Companion Sets',
        trigger   = 'Pet / Avatar',
        keywords  = { 'pet:', 'blood pact', 'maneuver' },
        threshold = 1,
    },
}

-- WS-context path key patterns (normalized: lowercase, no punctuation/spaces).
-- 'ws' alone matches key == 'ws' exactly; the rest are substring matches.
-- Covers: WSEars, TPWSEars, MaxTPWSEars, AccWSEars, AccDayMaxTPWSEars, DayMaxTPWSEars, etc.
local WS_KEY_SUBSTRINGS = { 'wsear', 'tpws', 'maxtp', 'accws', 'wssupport' }

-- Known WS/TP/accuracy swap earrings (lowercase). Both path and item evidence required.
-- Moonshade Earring:  TP Bonus+25 variant — common WS earring.
-- Brutal Earring:     Attk+4, TP Bonus+150 — classic WS earring.
-- Zennaroi Earring:   Accuracy/Attack — used in accuracy WS sets.
-- Telos Earring:      Accuracy+10, Attack+15 — accuracy/TP earring.
-- Ishvara Earring:    Weapon Skill Damage+2% — direct WS earring.
-- Thrud Earring:      Physical WS damage/Attack — WS damage earring.
-- Sherida Earring:    Store TP+5, multi-attack — TP/WS earring.
local WS_EARRINGS = {
    'moonshade earring',
    'brutal earring',
    'zennaroi earring',
    'telos earring',
    'ishvara earring',
    'thrud earring',
    'sherida earring',
}

local function lower(v)
    return tostring(v or ''):lower()
end

local function normalize_key(v)
    return lower(v):gsub('[%s%p_]+', '')
end

local function get_keys(node_or_assignment)
    if not node_or_assignment then return {} end
    if node_or_assignment.keys then return node_or_assignment.keys end
    if node_or_assignment.path then return node_or_assignment.path end
    if node_or_assignment.assignment and node_or_assignment.assignment.keys then
        return node_or_assignment.assignment.keys
    end
    return {}
end

local function collect_slot_text(node_or_assignment)
    -- Mirrors gear_values() in semantics.lua; flattens all slot values to one string.
    local rhs
    if node_or_assignment then
        if node_or_assignment.assignment and node_or_assignment.assignment.rhs then
            rhs = node_or_assignment.assignment.rhs
        elseif node_or_assignment.rhs then
            rhs = node_or_assignment.rhs
        end
    end
    if not rhs or not rhs.slots then return '' end
    local parts = {}
    for _, value in pairs(rhs.slots) do
        parts[#parts + 1] = lower(tostring(value))
    end
    return table.concat(parts, ' ')
end

local function path_has_ws_context(keys)
    for i = 2, #keys do
        local k = normalize_key(tostring(keys[i] or ''))
        if k == 'ws' then return true end
        for _, sub in ipairs(WS_KEY_SUBSTRINGS) do
            if k:find(sub, 1, true) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Broad name/path family rules
-- Checked before stat-signal scoring; return Likely when a key segment matches.
-- No gear/item evidence required — the path name is the signal.
-- ---------------------------------------------------------------------------

local ELEMENTS = {
    wind=true, ice=true, earth=true, fire=true, water=true,
    thunder=true, lightning=true, light=true, dark=true,
}

local function check_name_families(keys)
    -- Family 3: sets.element.<element>
    -- Requires exactly k2 == 'element' plus a recognised element name at k3.
    -- Does NOT catch top-level WindNuke / Nuke sets (those are already handled
    -- by semantics.lua content_route_for_keys before set_intent is reached).
    if normalize_key(tostring(keys[2] or '')) == 'element' then
        local el_key = normalize_key(tostring(keys[3] or ''))
        if ELEMENTS[el_key] then
            return {
                route          = { 'Overlays / Modifiers', 'Elemental Affinity' },
                category       = 'Layered Set Modifiers',
                trigger        = 'Element affinity helper',
                intent         = 'element_affinity',
                confidence     = 'Likely',
                evidence_lines = {
                    'Element affinity path detected: sets.element.' .. tostring(keys[3] or ''),
                },
            }
        end
    end

    -- Scan each key segment (k2 onward) for the remaining four families.
    for i = 2, #keys do
        local raw = tostring(keys[i] or '')
        local k   = normalize_key(raw)

        -- Family 1: Reraise / survival / Twilight
        if k:find('reraise',      1, true)
        or k:find('twilight',     1, true)
        or k:find('deathrecovery',1, true)
        or k:find('survival',     1, true) then
            return {
                route          = { 'Reactive', 'Reraise' },
                category       = 'Status / Condition Responses',
                trigger        = 'Reraise / survival helper',
                intent         = 'reraise_survival',
                confidence     = 'Likely',
                evidence_lines = { 'Reactive survival keyword detected: ' .. raw },
            }
        end

        -- Family 2: Self / received / recovery modifiers
        if k:find('selfhealing',  1, true)
        or k:find('curereceived', 1, true)
        or k:find('selfrefresh',  1, true)
        or k:find('latentrefresh',1, true)
        or k:find('recovermp',    1, true)
        or k:find('conservemp',   1, true) then
            return {
                route          = { 'Overlays / Modifiers', 'Self / Received Effects' },
                category       = 'Layered Set Modifiers',
                trigger        = 'Self/received recovery modifier',
                intent         = 'self_received',
                confidence     = 'Likely',
                evidence_lines = { 'Self/received recovery keyword detected: ' .. raw },
            }
        end

        -- Family 4: HP manipulation / HP cure
        if k:find('hpdown', 1, true)
        or k:find('hpcure', 1, true) then
            return {
                route          = { 'Overlays / Modifiers', 'Self / Received Effects' },
                category       = 'Layered Set Modifiers',
                trigger        = 'HP/cure support modifier',
                intent         = 'hp_support',
                confidence     = 'Likely',
                evidence_lines = { 'HP support keyword detected: ' .. raw },
            }
        end

        -- Family 5: Waltz helper
        if k:find('selfwaltz',    1, true)
        or k:find('waltzreceived',1, true) then
            return {
                route          = { 'Actions', 'Waltz / Steps / Flourishes' },
                category       = 'Action-Triggered Sets',
                trigger        = 'Waltz support helper',
                intent         = 'waltz_helper',
                confidence     = 'Likely',
                evidence_lines = { 'Waltz helper keyword detected: ' .. raw },
            }
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Earring helper rule: requires both a WS-context key in the path AND a known
-- WS earring in the gear. Does NOT fire on Moonshade alone in an unrelated set.
local function check_ws_earring_helper(keys, slot_text)
    if not path_has_ws_context(keys) then return nil end
    local found
    for _, earring in ipairs(WS_EARRINGS) do
        if slot_text:find(earring, 1, true) then
            found = earring
            break
        end
    end
    if not found then return nil end
    return {
        route         = { 'Overlays / Modifiers', 'Weapon Skill' },
        category      = 'Layered Set Modifiers',
        trigger       = 'Weapon Skill earring helper',
        intent        = 'ws_earring_helper',
        confidence    = 'Likely',
        evidence_lines = {
            'WS-context path key detected',
            'WS earring detected: ' .. found,
        },
    }
end

local function score_stat_signals(slot_text)
    if slot_text == '' then return nil end

    local candidates = {}
    for _, sig in ipairs(STAT_SIGNALS) do
        local score = 0
        local matched = {}
        for _, kw in ipairs(sig.keywords) do
            if slot_text:find(kw, 1, true) then
                score = score + 1
                matched[#matched + 1] = kw
            end
        end
        if score >= sig.threshold then
            candidates[#candidates + 1] = {
                score    = score,
                sig      = sig,
                matched  = matched,
            }
        end
    end

    if #candidates == 0 then return nil end

    local max_score = 0
    for _, c in ipairs(candidates) do
        if c.score > max_score then max_score = c.score end
    end

    local winners = {}
    for _, c in ipairs(candidates) do
        if c.score == max_score then winners[#winners + 1] = c end
    end

    -- Tie between two signals at the same score: don't override, let fallback win.
    if #winners > 1 then return nil end

    local w = winners[1]
    local evidence_lines = {}
    for _, kw in ipairs(w.matched) do
        evidence_lines[#evidence_lines + 1] = 'Stat keyword: ' .. kw
    end

    return {
        route          = w.sig.route,
        category       = w.sig.category,
        trigger        = w.sig.trigger,
        intent         = w.sig.intent,
        confidence     = w.score >= 2 and 'Likely' or 'Low',
        evidence_lines = evidence_lines,
    }
end

function set_intent.classify(node_or_assignment)
    local keys      = get_keys(node_or_assignment)
    local slot_text = collect_slot_text(node_or_assignment)

    -- Earring helper rule checked first (path + item evidence required).
    local ws_result = check_ws_earring_helper(keys, slot_text)
    if ws_result then return ws_result end

    -- Broad name/path family rules (path evidence only, no item scan needed).
    local family_result = check_name_families(keys)
    if family_result then return family_result end

    return score_stat_signals(slot_text)
end

return set_intent
