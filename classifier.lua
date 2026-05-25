-- GearTree classifier
-- Semantic inference layer: converts a tree node's path, assignment, and
-- resolver conditions into human-readable category, trigger, conditions,
-- purpose, and confidence. Works on arbitrary GearSwap Lua files.
-- Design rule: no job encyclopedias — everything derived from path structure,
-- naming conventions, set_combine/ref analysis, and resolver logic.

local classifier = {}

----------------------------------------------------------------------
-- Modifier dictionary: suffix key → plain-English description
----------------------------------------------------------------------

local MODIFIERS = {
    -- Combat buffs
    SA         = 'Sneak Attack active',
    TA         = 'Trick Attack active',
    SATA       = 'Sneak Attack + Trick Attack active',
    -- Accuracy modes
    Acc        = 'Accuracy-focused variant',
    SomeAcc    = 'Light accuracy variant',
    FullAcc    = 'Full accuracy variant',
    -- Damage reduction
    PDT        = 'Physical damage reduction active',
    MDT        = 'Magic damage reduction active',
    DT         = 'General damage reduction active',
    -- Utility overlays
    TH         = 'Treasure Hunter tagging',
    -- Enemy difficulty variants
    Resistant  = 'Resistant targets (magic accuracy focus)',
    Fodder     = 'Easy targets (damage focus)',
    -- Misc combat modes
    Proc       = 'Proc / low-damage utility mode',
    SIRD       = 'Spell interruption rate down',
    MB         = 'Magic Burst',
    FullMacc   = 'Maximum magic accuracy',
    -- Aftermath states
    AM         = 'Aftermath active',
    AM1        = 'Aftermath level 1',
    AM2        = 'Aftermath level 2',
    AM3        = 'Aftermath level 3',
    -- AoE
    AoE        = 'Area-of-effect mode',
    -- TP states
    MaxTP      = 'Maximum / near-max TP',
    LowTP      = 'Low TP opener',
    -- Movement / dual wield
    DW         = 'Dual Wield focused',
    DW2        = 'Dual Wield Tier 2',
    DW3        = 'Dual Wield Tier 3',
    -- Elemental enspells
    Enfire     = 'Enfire active',
    Enthunder  = 'Enthunder active',
    Enblizzard = 'Enblizzard active',
    Enaero     = 'Enaero active',
    Enstone    = 'Enstone active',
    Enwater    = 'Enwater active',
    Enlight    = 'Enlight active',
    Endark     = 'Endark active',
    -- Misc
    Knockback  = 'Knockback resistance',
    Subtle     = 'Subtle Blow / TP denial',
    Stun       = 'Stun / interrupt focus',
    Weak       = 'Weakened / recovering state',
    Normal     = 'Standard (no extra mode)',
    Hybrid     = 'Hybrid offense/defense',
    Learning   = 'Learning mode',
    Town       = 'Town / non-combat area',
    Resting    = 'Resting / healing variant',
    Magic      = 'Magic-based variant',
    Melee      = 'Melee-based variant',
    Ranged     = 'Ranged-based variant',
    Low        = 'Low-tier / easy targets',
    High       = 'High-tier / hard targets',
    Haste      = 'Haste focused',
    Refresh    = 'Refresh focused',
    Cure       = 'Cure spell variant',
    Regen      = 'Regen spell variant',
    Physical   = 'Physical damage variant',
    Magical    = 'Magical damage variant',
    Breath     = 'Breath attack variant',
    Hybrid2    = 'Hybrid damage variant',
}

----------------------------------------------------------------------
-- Helper: case-insensitive modifier lookup
----------------------------------------------------------------------

local function mod_lookup(key)
    if MODIFIERS[key] then return MODIFIERS[key] end
    for k, v in pairs(MODIFIERS) do
        if k:lower() == key:lower() then return v end
    end
    return nil
end

local function last_key_is_modifier(keys)
    local k = keys[#keys]
    if not k then return false end
    return mod_lookup(k) ~= nil
end

----------------------------------------------------------------------
-- Category detection — 8-tier taxonomy
-- Returns: display_label (string), cat_key (internal id string)
----------------------------------------------------------------------

local function detect_category(keys)
    local depth = #keys          -- keys[1] == 'sets'
    local k2    = (keys[2] or ''):lower()
    local k3    = (keys[3] or ''):lower()
    local last  = last_key_is_modifier(keys)

    -- ── Overlay / utility ──────────────────────────────────────────
    if k2 == 'treasurehunter' or k2 == 'th' then
        return 'Utility Overlay', 'overlay.TH'
    end
    if k2 == 'utility' then
        return 'Utility Overlay', 'overlay.utility'
    end

    -- ── Reactive overrides ─────────────────────────────────────────
    if k2 == 'buff' then
        return 'Reactive Override', 'reactive.buff'
    end
    if k2 == 'defense' then
        if depth == 2 then return 'Defense Set', 'defense.base' end
        return 'Defense Variant', 'defense.variant'
    end

    -- ── Weapon Skill ───────────────────────────────────────────────
    if k2 == 'precast' and (k3 == 'ws' or k3 == 'weaponskill') then
        if depth >= 5 and last then
            return 'Weapon Skill Modifier', 'ws.modifier'
        elseif depth >= 4 then
            return 'Weapon Skill Set', 'ws.set'
        else
            return 'Action Set', 'ws.base'
        end
    end

    -- ── Job Ability ────────────────────────────────────────────────
    if k2 == 'precast' and (k3 == 'ja' or k3 == 'jobability' or k3 == 'job_ability') then
        if depth >= 5 and last then
            return 'Job Ability Modifier', 'ja.modifier'
        elseif depth >= 4 then
            return 'Job Ability Set', 'ja.set'
        else
            return 'Action Set', 'ja.base'
        end
    end

    -- ── Ranged ─────────────────────────────────────────────────────
    if k2 == 'precast' and (k3 == 'ra' or k3 == 'ranged') then
        return 'Ranged Set', 'ranged'
    end
    if k2 == 'rangedattack' or k2 == 'ranged' then
        return 'Ranged Set', 'ranged'
    end

    -- ── Item use ───────────────────────────────────────────────────
    if k2 == 'precast' and k3 == 'item' then
        return 'Item Use Set', 'item_use'
    end

    -- ── Fast cast / precast spells ─────────────────────────────────
    if k2 == 'precast' and (k3 == 'fc' or k3 == 'fastcast') then
        if depth >= 5 and last then return 'Spell Modifier', 'spell.modifier' end
        if depth >= 4 then return 'Spell Set', 'precast.spell' end
        return 'Spell Set', 'precast.FC'
    end
    if k2 == 'precast' and depth >= 3 then
        if last and depth >= 4 then return 'Spell Modifier', 'spell.modifier' end
        return 'Spell Set', 'precast.generic'
    end
    if k2 == 'precast' then
        return 'Spell Set', 'precast.FC'
    end

    -- ── Midcast ────────────────────────────────────────────────────
    if k2 == 'midcast' then
        if depth == 2 then return 'Spell Set', 'midcast.base' end
        if last and depth >= 4 then return 'Spell Modifier', 'spell.modifier' end
        return 'Spell Set', 'midcast.spell'
    end

    -- ── Aftercast ─────────────────────────────────────────────────
    if k2 == 'aftercast' then
        return 'Aftercast Return', 'aftercast'
    end

    -- ── Engaged (melee) ───────────────────────────────────────────
    if k2 == 'engaged' then
        if depth == 2 then return 'Base Engaged State', 'engaged.base' end
        if last then return 'Modifier Set', 'engaged.modifier' end
        return 'Engaged Variant', 'engaged.variant'
    end

    -- ── Idle ──────────────────────────────────────────────────────
    if k2 == 'idle' then
        if depth == 2 then return 'Base Idle State', 'idle.base' end
        return 'Idle Variant', 'idle.variant'
    end

    -- ── Resting ───────────────────────────────────────────────────
    if k2 == 'resting' then
        return 'Resting State', 'resting'
    end

    -- ── Weapons ───────────────────────────────────────────────────
    if k2 == 'weapons' then
        return 'Weapon Set', 'weapons'
    end

    -- ── Fuzzy fallback on common root names ───────────────────────
    if k2:find('idle') then
        return depth == 2 and 'Base Idle State' or 'Idle Variant',
               depth == 2 and 'idle.base' or 'idle.variant'
    end
    if k2:find('engaged') or k2:find('melee') or k2:find('^tp$') then
        return depth == 2 and 'Base Engaged State' or 'Engaged Variant',
               depth == 2 and 'engaged.base' or 'engaged.variant'
    end
    if k2:find('defense') or k2:find('pdt') then
        return 'Defense Set', 'defense.base'
    end
    if k2:find('buff') then
        return 'Reactive Override', 'reactive.buff'
    end

    -- ── Generic depth-based fallback ─────────────────────────────
    if depth == 2 then return 'Base State', 'base.custom' end
    if last then return 'Modifier Set', 'modifier.custom' end
    if depth == 3 then return 'Variant State', 'variant.custom' end
    return 'Variant State', 'deep.custom'
end

----------------------------------------------------------------------
-- Readable display name: drop 'sets', join rest with ' > '
----------------------------------------------------------------------

local function readable_name(keys)
    local parts = {}
    for i = 2, #keys do parts[#parts + 1] = keys[i] end
    return table.concat(parts, ' > ')
end

----------------------------------------------------------------------
-- Detect modifiers from keys[3..n]
----------------------------------------------------------------------

local function detect_modifiers(keys)
    local mods, seen = {}, {}
    for i = 3, #keys do
        local k = keys[i]
        local desc = mod_lookup(k)
        if desc and not seen[k] then
            seen[k] = true
            mods[#mods + 1] = { key = k, desc = desc }
        end
    end
    return mods
end

----------------------------------------------------------------------
-- Inheritance analysis from RHS
----------------------------------------------------------------------

local function has_th_base(rhs)
    if not rhs or rhs.kind ~= 'combine' then return false end
    for _, ref in ipairs(rhs.refs or {}) do
        local r = ref:lower()
        if r:find('treasurehunter') or r:find('%.th') or r:find('%[.th.%]') then
            return true
        end
    end
    return false
end

local function build_inheritance(rhs)
    if not rhs then return nil end
    if rhs.kind == 'combine' then
        local bases, overrides = {}, {}
        for _, ref in ipairs(rhs.refs or {}) do bases[#bases + 1] = ref end
        for slot in pairs(rhs.slots or {}) do overrides[#overrides + 1] = slot end
        table.sort(overrides)
        return { kind = 'combine', bases = bases, overrides = overrides }
    elseif rhs.kind == 'ref' then
        return { kind = 'ref', target = rhs.target or '' }
    end
    return nil
end

----------------------------------------------------------------------
-- Assignment type label
----------------------------------------------------------------------

local function assign_type_label(rhs)
    if not rhs then return 'unknown' end
    if rhs.kind == 'combine' then return 'set_combine' end
    if rhs.kind == 'ref'     then return 'alias / reference' end
    if rhs.kind == 'other'   then return 'function call / expression' end
    if rhs.kind == 'table' then
        local count = 0
        for _ in pairs(rhs.slots or {}) do count = count + 1 end
        if count == 0 then return 'empty set {}' end
        return 'direct table (' .. count .. ' slots)'
    end
    return rhs.kind or 'unknown'
end

----------------------------------------------------------------------
-- Trigger string
----------------------------------------------------------------------

local function build_trigger(keys, cat_key)
    local k3 = keys[3] or ''
    local k4 = keys[4] or ''
    local k5 = keys[5] or ''

    if cat_key == 'ws.set' or cat_key == 'ws.modifier' then
        local ws = k4 ~= '' and k4 or k3
        if cat_key == 'ws.modifier' and k5 ~= '' then
            return 'Weapon Skill: ' .. ws .. '  [' .. k5 .. ']'
        end
        return 'Weapon Skill: ' .. ws

    elseif cat_key == 'ws.base' then
        return 'Any weapon skill'

    elseif cat_key == 'ja.set' or cat_key == 'ja.modifier' then
        local ja = k4 ~= '' and k4 or k3
        if ja:lower() ~= 'ja' then return 'Job Ability: ' .. ja end
        return 'Any job ability'

    elseif cat_key == 'ja.base' then
        return 'Any job ability'

    elseif cat_key == 'precast.FC' or cat_key == 'precast.generic' or cat_key == 'spell.modifier' then
        local spell = ''
        -- Walk path for spell name (first key after 'fc' / 'precast')
        for i = 3, #keys do
            local lk = keys[i]:lower()
            if lk ~= 'fc' and lk ~= 'fastcast' and lk ~= 'precast' and
               not mod_lookup(keys[i]) then
                spell = keys[i]; break
            end
        end
        if spell ~= '' then return 'Magic precast: ' .. spell end
        return 'Any magic precast (fast cast phase)'

    elseif cat_key == 'precast.spell' then
        local spell = k4 ~= '' and k4 or k3
        if spell ~= '' then return 'Magic precast: ' .. spell end
        return 'Any magic precast'

    elseif cat_key == 'midcast.base' then
        return 'Any magic midcast'

    elseif cat_key == 'midcast.spell' then
        local spell = k3 ~= '' and k3 or ''
        if spell:lower() ~= 'midcast' and spell ~= '' then
            return 'Magic midcast: ' .. spell
        end
        return 'Any magic midcast'

    elseif cat_key == 'engaged.base' then
        return 'Actively engaged in melee combat'

    elseif cat_key == 'engaged.variant' or cat_key == 'engaged.modifier' then
        local variant = keys[3] or ''
        return 'Engaged — ' .. variant .. ' mode'

    elseif cat_key == 'idle.base' then
        return 'Idle (not in combat)'

    elseif cat_key == 'idle.variant' then
        local sub = keys[3] or ''
        return 'Idle — ' .. sub .. ' context'

    elseif cat_key == 'resting' then
        return '/heal resting'

    elseif cat_key == 'defense.base' or cat_key == 'defense.variant' then
        local sub = keys[3] or ''
        if sub ~= '' and sub:lower() ~= 'defense' then
            return 'Defense mode — ' .. sub
        end
        return 'Defense mode active'

    elseif cat_key == 'reactive.buff' then
        local buff = keys[3] or ''
        if buff ~= '' then return 'Status active: ' .. buff end
        return 'Status condition active'

    elseif cat_key == 'aftercast' then
        return 'Post-cast / aftercast return'

    elseif cat_key == 'overlay.TH' or cat_key == 'overlay.utility' then
        return 'Applied as overlay over current set'

    elseif cat_key == 'weapons' then
        local sub = keys[3] or ''
        if sub ~= '' then return 'Weapon set: ' .. sub end
        return 'Weapon set selection'

    elseif cat_key == 'ranged' then
        return 'Ranged attack'

    elseif cat_key == 'item_use' then
        local item = keys[4] or keys[3] or ''
        if item ~= '' and item:lower() ~= 'item' then
            return 'Item use: ' .. item
        end
        return 'Any item use'

    else
        local top = keys[2] or ''
        return top ~= '' and top or '(unknown)'
    end
end

----------------------------------------------------------------------
-- Conditions list — returns plain strings.
----------------------------------------------------------------------

local function build_conditions(mods, rhs)
    local conds, seen = {}, {}

    for _, m in ipairs(mods) do
        if not seen[m.desc] then
            seen[m.desc] = true
            conds[#conds + 1] = m.desc
        end
    end

    if has_th_base(rhs) then
        local c = 'Treasure Hunter via set_combine'
        if not seen[c] then
            seen[c] = true
            conds[#conds + 1] = c
        end
    end

    return conds
end

----------------------------------------------------------------------
-- Purpose string — specific semantic sentences, not generic ones
----------------------------------------------------------------------

local function build_purpose(keys, cat_key, mods, rhs)
    local k3 = keys[3] or ''
    local k4 = keys[4] or ''
    local k5 = keys[5] or ''

    -- Build modifier phrase (used in several branches)
    local mod_descs = {}
    for _, m in ipairs(mods) do mod_descs[#mod_descs + 1] = m.desc end
    local mod_ph = #mod_descs > 0 and (' (' .. table.concat(mod_descs, ', ') .. ')') or ''

    if cat_key == 'ws.set' then
        local ws = k4 ~= '' and k4 or k3
        return 'Maximizes ' .. ws .. ' weapon skill damage' .. mod_ph .. '.'

    elseif cat_key == 'ws.modifier' then
        local ws = k4 ~= '' and k4 or k3
        local modifier_key = k5 ~= '' and k5 or mods[1] and mods[1].key or ''
        if modifier_key ~= '' then
            local mdesc = mod_lookup(modifier_key) or modifier_key
            return ws .. ' with ' .. mdesc .. ' — specialized modifier set.'
        end
        return ws .. ' weapon skill — modifier variant.'

    elseif cat_key == 'ws.base' then
        return 'Fallback gear worn for any weapon skill that has no specific set.'

    elseif cat_key == 'ja.set' then
        local ja = k4 ~= '' and k4 or k3
        if ja:lower() ~= 'ja' and ja:lower() ~= 'jobability' then
            return 'Equips gear that enhances the ' .. ja .. ' job ability.'
        end
        return 'Equips optimal gear for a job ability.'

    elseif cat_key == 'ja.modifier' then
        local ja = k4 ~= '' and k4 or k3
        return ja .. ' job ability — modifier variant' .. mod_ph .. '.'

    elseif cat_key == 'ja.base' then
        return 'Fallback gear for any job ability without a specific set.'

    elseif cat_key == 'precast.FC' or cat_key == 'precast.generic' then
        return 'Maximizes fast cast to reduce spell cast time.'

    elseif cat_key == 'precast.spell' then
        local spell = k4 ~= '' and k4 or k3
        return 'Precast gear for ' .. spell .. mod_ph .. '.'

    elseif cat_key == 'spell.modifier' then
        local spell = ''
        for i = 3, #keys do
            local lk = keys[i]:lower()
            if lk ~= 'fc' and lk ~= 'fastcast' and not mod_lookup(keys[i]) then
                spell = keys[i]; break
            end
        end
        if spell ~= '' then
            return spell .. ' precast — modifier variant' .. mod_ph .. '.'
        end
        return 'Spell precast modifier variant' .. mod_ph .. '.'

    elseif cat_key == 'midcast.base' then
        return has_th_base(rhs)
            and 'Midcast gear with Treasure Hunter to tag targets.'
            or  'Optimizes stat gear during the active casting window.'

    elseif cat_key == 'midcast.spell' then
        local spell = k3:lower() ~= 'midcast' and k3 ~= '' and k3 or ''
        if has_th_base(rhs) then
            return 'Midcast gear for ' .. (spell ~= '' and spell or 'spells') ..
                   ' with Treasure Hunter tagging.'
        end
        if spell ~= '' then
            return 'Maximizes potency/accuracy for ' .. spell .. mod_ph .. '.'
        end
        return 'Midcast gear optimized for the current spell' .. mod_ph .. '.'

    elseif cat_key == 'engaged.base' then
        return 'Standard melee set worn while actively engaged in combat.'

    elseif cat_key == 'engaged.variant' then
        local variant = k3 ~= '' and k3 or '?'
        local vdesc = mod_lookup(variant)
        if vdesc then
            return vdesc .. ' — melee gear variant for this mode.'
        end
        return variant .. ' melee variant — purpose from naming convention.'

    elseif cat_key == 'engaged.modifier' then
        return 'Melee gear modifier applied on top of the current engaged set' .. mod_ph .. '.'

    elseif cat_key == 'idle.base' then
        return 'Worn while idle for survivability, refresh, or regen.'

    elseif cat_key == 'idle.variant' then
        local sub = k3 ~= '' and k3 or '?'
        local vdesc = mod_lookup(sub)
        if vdesc then return vdesc .. ' — idle gear variant.' end
        return sub .. ' idle variant.'

    elseif cat_key == 'resting' then
        return 'Worn while /heal resting to accelerate HP/MP recovery.'

    elseif cat_key == 'defense.base' then
        return 'Reduces damage taken while defense mode is active.'

    elseif cat_key == 'defense.variant' then
        local sub = k3 ~= '' and k3 or ''
        if sub ~= '' then
            return 'Defense variant focused on ' .. sub .. '.'
        end
        return 'Defense mode variant.'

    elseif cat_key == 'reactive.buff' then
        local buff = k3 ~= '' and k3 or ''
        if buff ~= '' then
            return 'Reactive gear swap while ' .. buff .. ' is active.'
        end
        return 'Reactive gear swap triggered by an active buff or debuff.'

    elseif cat_key == 'aftercast' then
        return 'Return gear worn immediately after a spell cast completes.'

    elseif cat_key == 'overlay.TH' then
        return 'Ensures Treasure Hunter gear is applied over the current set.'

    elseif cat_key == 'overlay.utility' then
        return 'Utility overlay set applied in specific situations.'

    elseif cat_key == 'weapons' then
        local sub = k3 ~= '' and k3 or ''
        if sub ~= '' then return 'Weapon set used in ' .. sub .. ' mode.' end
        return 'Defines which weapons are equipped for a combat mode.'

    elseif cat_key == 'ranged' then
        return 'Gear worn during ranged attacks.'

    elseif cat_key == 'item_use' then
        local item = keys[4] or k3
        if item ~= '' and item:lower() ~= 'item' then
            return 'Gear set used when using ' .. item .. '.'
        end
        return 'Gear set used during item use.'

    else
        return 'Purpose unknown — custom or unrecognized set name.'
    end
end

----------------------------------------------------------------------
-- Confidence
----------------------------------------------------------------------

local STANDARD_CATS = {
    ['ws.set'] = true, ['ws.modifier'] = true, ['ws.base'] = true,
    ['ja.set'] = true, ['ja.modifier'] = true, ['ja.base'] = true,
    ['precast.FC'] = true, ['precast.spell'] = true, ['precast.generic'] = true,
    ['spell.modifier'] = true,
    ['midcast.base'] = true, ['midcast.spell'] = true,
    ['engaged.base'] = true, ['engaged.variant'] = true, ['engaged.modifier'] = true,
    ['idle.base'] = true, ['idle.variant'] = true,
    ['resting'] = true,
    ['defense.base'] = true, ['defense.variant'] = true,
    ['reactive.buff'] = true,
    ['aftercast'] = true,
    ['overlay.TH'] = true, ['overlay.utility'] = true,
    ['weapons'] = true,
    ['ranged'] = true,
    ['item_use'] = true,
}

local function rate_confidence(cat_key)
    if STANDARD_CATS[cat_key] then return 'Likely' end
    return 'Low'
end

----------------------------------------------------------------------
-- Simple word-wrap
----------------------------------------------------------------------

function classifier.wrap(text, max_chars)
    if #text <= max_chars then return { text } end
    local lines = {}
    local remaining = text
    while #remaining > max_chars do
        local cut = max_chars
        while cut > 1 and remaining:sub(cut, cut) ~= ' ' do cut = cut - 1 end
        if cut <= 1 then cut = max_chars end
        lines[#lines + 1] = remaining:sub(1, cut):gsub('%s+$', '')
        remaining = remaining:sub(cut + 1):gsub('^%s+', '')
    end
    if remaining ~= '' then lines[#lines + 1] = remaining end
    return lines
end

----------------------------------------------------------------------
-- Main entry point
----------------------------------------------------------------------

function classifier.classify(node)
    if not node then return nil end
    local keys = node.path or {}
    if #keys < 2 then return nil end

    local a   = node.assignment
    local rhs = a and a.rhs

    local category, cat_key = detect_category(keys)
    local mods        = detect_modifiers(keys)
    local trigger     = build_trigger(keys, cat_key)
    local conditions  = build_conditions(mods, rhs)
    local purpose     = build_purpose(keys, cat_key, mods, rhs)
    local confidence  = rate_confidence(cat_key)
    local inheritance = build_inheritance(rhs)

    local slot_count = 0
    if rhs and rhs.slots then
        for _ in pairs(rhs.slots) do slot_count = slot_count + 1 end
    end

    return {
        readable_name = readable_name(keys),
        category      = category,
        cat_key       = cat_key,
        trigger       = trigger,
        conditions    = conditions,   -- list of plain strings
        purpose       = purpose,
        confidence    = confidence,   -- 'Likely' | 'Low'
        mods          = mods,
        inheritance   = inheritance,
        assign_type   = assign_type_label(rhs),
        slot_count    = slot_count,
        has_th        = has_th_base(rhs),
    }
end

return classifier
