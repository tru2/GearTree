-- GearTree semantics
-- Thin preview-only interpretation layer for parsed GearTree nodes.
-- This module should never equip, save, parse, or mutate anything.

local semantics = {}

local TOKEN_INFO = {
    SA = {
        condition = 'Sneak Attack active',
        purpose = 'Sneak Attack',
        plain = 'Sneak Attack modifier.',
        state = 'Sneak Attack',
        confidence = 'Likely',
    },
    TA = {
        condition = 'Trick Attack active',
        purpose = 'Trick Attack',
        plain = 'Trick Attack modifier.',
        state = 'Trick Attack',
        confidence = 'Likely',
    },
    SATA = {
        condition = 'Sneak Attack and Trick Attack active',
        purpose = 'Sneak Attack and Trick Attack',
        plain = 'Sneak Attack and Trick Attack modifier.',
        state = 'Sneak Attack and Trick Attack',
        confidence = 'Likely',
    },
    Kiting = {
        category_hint = 'Movement / Utility Overlay',
        condition = 'Kiting mode active or manually equipped',
        purpose = 'Equips movement-speed gear for safer repositioning.',
        plain = 'Used when movement speed is needed while running, repositioning, or kiting enemies.',
        state = 'movement speed',
        confidence = 'Likely',
    },
    Movement = {
        category_hint = 'Movement / Utility Overlay',
        condition = 'Movement mode active or manually equipped',
        purpose = 'Equips movement-speed gear for travel or repositioning.',
        plain = 'Used when movement speed is needed.',
        state = 'movement speed',
        confidence = 'Likely',
    },
    MoveSpeed = {
        category_hint = 'Movement / Utility Overlay',
        condition = 'Movement-speed mode active or manually equipped',
        purpose = 'Equips movement-speed gear for travel or repositioning.',
        plain = 'Used when movement speed is needed.',
        state = 'movement speed',
        confidence = 'Likely',
    },
    TreasureHunter = {
        category_hint = 'Utility Overlay',
        condition = 'Treasure Hunter tagging mode, TH action, or manual equip',
        purpose = 'Adds Treasure Hunter gear to tag enemies for improved loot/drop tagging.',
        plain = 'Used to apply Treasure Hunter gear while tagging or engaging enemies.',
        state = 'Treasure Hunter tagging',
        confidence = 'Likely',
    },
    Doom = {
        category_hint = 'Reactive / Buff Override',
        condition = 'Doom status active',
        purpose = 'Equips anti-Doom/curse removal gear while Doom is active.',
        plain = 'Used while Doom status is active.',
        state = 'Doom status',
        confidence = 'Likely',
    },
    Sleep = {
        category_hint = 'Reactive / Buff Override',
        condition = 'Sleep status active',
        purpose = 'Equips sleep-handling gear while slept.',
        plain = 'Used while Sleep status is active.',
        state = 'Sleep status',
        confidence = 'Likely',
    },
    Weak = {
        category_hint = 'Reactive / Status Override',
        condition = 'Weakness active',
        purpose = 'Uses safer idle gear while weakened.',
        plain = 'Used while weakened.',
        state = 'weakness',
        confidence = 'Likely',
    },
    Weakness = {
        category_hint = 'Reactive / Status Override',
        condition = 'Weakness active',
        purpose = 'Uses safer idle gear while weakened.',
        plain = 'Used while weakened.',
        state = 'weakness',
        confidence = 'Likely',
    },
    Knockback = {
        category_hint = 'Utility Overlay',
        condition = 'Knockback mode active or manually equipped',
        purpose = 'Helps manage knockback or positioning-heavy fights.',
        plain = 'Used for fights where knockback or positioning matters.',
        state = 'knockback mode',
        confidence = 'Likely',
    },
    Acc = {
        condition = 'Accuracy mode active',
        purpose = 'accuracy',
        plain = 'Accuracy-focused variant.',
        state = 'accuracy mode',
        confidence = 'Likely',
    },
    SomeAcc = {
        condition = 'Light accuracy mode active',
        purpose = 'light accuracy',
        plain = 'Light accuracy-focused variant.',
        state = 'light accuracy mode',
        confidence = 'Likely',
    },
    FullAcc = {
        condition = 'Full accuracy mode active',
        purpose = 'full accuracy',
        plain = 'Full accuracy-focused variant.',
        state = 'full accuracy mode',
        confidence = 'Likely',
    },
    PDT = {
        condition = 'Physical damage reduction mode active',
        purpose = 'physical damage reduction',
        plain = 'Physical damage reduction variant.',
        state = 'physical damage reduction',
        confidence = 'Likely',
    },
    MDT = {
        condition = 'Magic damage reduction mode active',
        purpose = 'magic damage reduction',
        plain = 'Magic damage reduction variant.',
        state = 'magic damage reduction',
        confidence = 'Likely',
    },
    DT = {
        condition = 'Damage taken mode active',
        purpose = 'damage taken reduction',
        plain = 'Defensive damage taken variant.',
        state = 'damage taken reduction',
        confidence = 'Likely',
    },
    MEVA = {
        condition = 'Magic evasion / resist mode active',
        purpose = 'magic evasion / resist',
        plain = 'Magic evasion / resist-focused variant.',
        state = 'magic evasion / resist mode',
        confidence = 'Likely',
    },
    Resistant = {
        condition = 'Resistant target or magic accuracy mode active',
        purpose = 'landing rate / magic accuracy',
        plain = 'Used when the target is resistant or accuracy matters.',
        state = 'magic accuracy or landing rate',
        confidence = 'Likely',
    },
    Fodder = {
        condition = 'Easy target / low-threat situation',
        purpose = 'aggressive damage gear',
        plain = 'Used for weaker or easier targets.',
        state = 'fodder mode',
        confidence = 'Likely',
    },
    Proc = {
        condition = 'Proc mode active',
        purpose = 'proc / utility support',
        plain = 'Used for proc or utility actions.',
        state = 'proc mode',
        confidence = 'Likely',
    },
    SIRD = {
        condition = 'Spell interruption risk',
        purpose = 'spell interruption reduction',
        plain = 'Spell interruption reduction variant.',
        state = 'spell interruption risk',
        confidence = 'Likely',
    },
    FullMacc = {
        condition = 'Maximum magic accuracy mode',
        purpose = 'maximum magic accuracy',
        plain = 'Maximum magic accuracy variant.',
        state = 'maximum magic accuracy',
        confidence = 'Likely',
    },
    MagicBurst = {
        condition = 'Magic Burst mode active',
        purpose = 'magic burst damage or accuracy',
        plain = 'Used for magic burst situations.',
        state = 'Magic Burst mode',
        confidence = 'Likely',
    },
    MaxTP = {
        condition = 'TP capped or near 3000 TP',
        purpose = 'high/max TP optimization',
        plain = 'Used when TP is capped or near maximum.',
        state = 'high/max TP',
        confidence = 'Likely',
    },
    AccMaxTP = {
        condition = 'Accuracy mode plus TP capped or near 3000 TP',
        purpose = 'accuracy-focused high/max TP optimization',
        plain = 'Accuracy-focused high/max TP modifier.',
        state = 'accuracy-focused high/max TP',
        confidence = 'Likely',
    },
    AM = {
        condition = 'Aftermath active',
        purpose = 'aftermath-active adjustment',
        plain = 'Used while Aftermath is active.',
        state = 'Aftermath',
        confidence = 'Likely',
    },
    FC = {
        condition = 'Spell precast',
        purpose = 'Fast Cast',
        plain = 'Fast Cast set.',
        state = 'spell precast',
        confidence = 'Likely',
    },
    FastRecast = {
        condition = 'Spell midcast or recast-focused casting',
        purpose = 'fast recast',
        plain = 'Fast recast casting set.',
        state = 'fast recast',
        confidence = 'Likely',
    },
    Utsusemi = {
        condition = 'Casting Utsusemi',
        purpose = 'Ninja shadow spell casting',
        plain = 'Used when casting Utsusemi.',
        state = 'Utsusemi casting',
        confidence = 'Likely',
    },
    RA = {
        condition = 'Ranged attack',
        purpose = 'ranged attack timing or accuracy',
        plain = 'Ranged attack set.',
        state = 'ranged attack',
        confidence = 'Likely',
    },
    Cure = {
        condition = 'Casting Cure or cure-related spell',
        purpose = 'healing output or reliability',
        plain = 'Healing magic set.',
        state = 'healing magic',
        confidence = 'Likely',
    },
    Refresh = {
        condition = 'Refresh or idle recovery mode',
        purpose = 'MP recovery / Refresh effects',
        plain = 'MP recovery / Refresh-focused set.',
        state = 'Refresh or MP recovery',
        confidence = 'Likely',
    },
    Self_Healing = {
        condition = 'Player is healing self',
        purpose = 'self-targeted healing',
        plain = 'Used when healing yourself.',
        state = 'self healing',
        confidence = 'Likely',
    },
    Cure_Received = {
        condition = 'Player receives cure',
        purpose = 'healing received',
        plain = 'Used when receiving cures.',
        state = 'cure received',
        confidence = 'Likely',
    },
    Self_Refresh = {
        condition = 'Player casts Refresh on self or self-refresh mode active',
        purpose = 'self Refresh effect/duration',
        plain = 'Used for self Refresh.',
        state = 'self Refresh',
        confidence = 'Likely',
    },
    DayIdle = {
        condition = 'Idle during daytime, if Lua logic supports it',
        purpose = 'daytime idle adjustment',
        plain = 'Daytime idle variant.',
        state = 'daytime idle',
        confidence = 'Likely',
    },
    NightIdle = {
        condition = 'Idle during nighttime, if Lua logic supports it',
        purpose = 'nighttime idle adjustment',
        plain = 'Nighttime idle variant.',
        state = 'nighttime idle',
        confidence = 'Likely',
    },
}

local ALIASES = {
    TH = 'TreasureHunter',
    Treasure_Hunter = 'TreasureHunter',
    MB = 'MagicBurst',
    Magic_Burst = 'MagicBurst',
    Move_Speed = 'MoveSpeed',
    MovementSpeed = 'MoveSpeed',
}

local SLOT_ORDER = {
    main = 1, sub = 2, range = 3, ammo = 4,
    head = 5, neck = 6, ear1 = 7, ear2 = 8, left_ear = 7, right_ear = 8, lear = 7, rear = 8,
    body = 9, hands = 10, ring1 = 11, ring2 = 12, left_ring = 11, right_ring = 12, lring = 11, rring = 12,
    back = 13, waist = 14, legs = 15, feet = 16,
}

local MOVEMENT_ITEMS = {
    'Jute Boots +1', 'Jute Boots', 'Herald\'s Gaiters', 'Carmine Cuisses +1',
    'Carmine Cuisses', 'Hippo. Socks +1', 'Hippo. Socks', 'Skadi\'s Jambeaux',
    'Fajin Boots', 'Danzo Sune-Ate', 'Geomancy Sandals', 'Pillager\'s Poulaines',
}

local TREASURE_HUNTER_ITEMS = {
    'Chaac Belt', 'Volte Bracers', 'Plunderer\'s Armlets', 'Plun. Armlets',
    'Skulker\'s Poulaines', 'Skulk. Poulaines', 'Sandung',
}

local DOOM_ITEMS = {
    'Gishdubar Sash', 'Saida Ring', 'Purity Ring',
}

local function add(list, value)
    if value and value ~= '' then list[#list + 1] = value end
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function add_unique(list, value)
    if value and value ~= '' and not contains(list, value) then
        list[#list + 1] = value
    end
end

local function lower(value)
    return tostring(value or ''):lower()
end

local function contains_text(value, text)
    return lower(value):find(lower(text), 1, true) ~= nil
end

local function join_from(keys, first)
    local out = {}
    for i = first, #keys do out[#out + 1] = tostring(keys[i]) end
    return table.concat(out, ' > ')
end

local function join_english(list)
    if #list == 0 then return '' end
    if #list == 1 then return list[1] end
    if #list == 2 then return list[1] .. ' and ' .. list[2] end
    local out = {}
    for i = 1, #list - 1 do out[#out + 1] = list[i] end
    return table.concat(out, ', ') .. ', and ' .. list[#list]
end

local function path_string(node)
    if not node or not node.path or not node.path[1] then return 'unknown' end
    local s = tostring(node.path[1])
    for i = 2, #node.path do
        local k = tostring(node.path[i])
        if k:match('^[%a_][%w_]*$') then
            s = s .. '.' .. k
        else
            s = s .. '["' .. k:gsub('"', '\\"') .. '"]'
        end
    end
    return s
end

local function canonical_token(token)
    return ALIASES[token] or token
end

local function token_info(token)
    return TOKEN_INFO[canonical_token(token)]
end

local function is_movement_key(key)
    key = tostring(key or '')
    return key == 'Kiting'
        or key == 'Movement'
        or key == 'MoveSpeed'
        or key == 'Move_Speed'
        or key == 'Running'
        or key == 'Run'
        or contains_text(key, 'Kiting')
        or contains_text(key, 'MoveSpeed')
        or contains_text(key, 'Movement')
end

local function match_tokens(keys)
    local matches = {}
    local seen = {}
    for i = 2, #keys do
        local token = tostring(keys[i])
        local canonical = canonical_token(token)
        local info = TOKEN_INFO[canonical]
        if info and not seen[canonical] then
            matches[#matches + 1] = {
                token = token,
                canonical = canonical,
                info = info,
                index = i,
            }
            seen[canonical] = true
        end
    end
    return matches
end

local function has_token(keys, token)
    local canonical = canonical_token(token)
    for _, match in ipairs(match_tokens(keys)) do
        if match.canonical == canonical then return true end
    end
    return false
end

local function matched_from(keys, first_index)
    local out = {}
    local seen = {}
    for i = first_index, #keys do
        local token = tostring(keys[i])
        local canonical = canonical_token(token)
        local info = TOKEN_INFO[canonical]
        if info and not seen[canonical] then
            out[#out + 1] = { token = token, canonical = canonical, info = info, index = i }
            seen[canonical] = true
        end
    end
    return out
end

local function states_from(matches)
    local out = {}
    for _, match in ipairs(matches or {}) do add(out, match.info.state or match.info.plain) end
    return out
end

local function purposes_from(matches)
    local out = {}
    for _, match in ipairs(matches or {}) do add(out, match.info.purpose) end
    return out
end

local function conditions_from(matches)
    local out = {}
    for _, match in ipairs(matches or {}) do add_unique(out, match.info.condition) end
    return out
end

local function active_phrase(matches)
    local states = states_from(matches)
    local phrase = join_english(states)
    if phrase == '' then return '' end
    if #states == 1 then return phrase .. ' is active' end
    return phrase .. ' are active'
end

local function sorted_slots(slots)
    local out = {}
    for slot in pairs(slots or {}) do out[#out + 1] = slot end
    table.sort(out, function(a, b)
        local oa = SLOT_ORDER[a] or 99
        local ob = SLOT_ORDER[b] or 99
        if oa == ob then return a < b end
        return oa < ob
    end)
    return out
end

local function inheritance_for(node)
    local info = { bases = {}, override_slots = {}, references = {}, kind = 'direct' }
    local rhs = node and node.assignment and node.assignment.rhs
    if not rhs then return info end
    if rhs.kind == 'combine' then
        info.kind = 'combine'
        for _, ref in ipairs(rhs.refs or {}) do info.bases[#info.bases + 1] = ref end
        info.override_slots = sorted_slots(rhs.slots or {})
    elseif rhs.kind == 'ref' and rhs.target then
        info.kind = 'reference'
        info.references[#info.references + 1] = rhs.target
    end
    return info
end

local function source_for(assignment)
    if not assignment then return 'Unknown source' end
    local file = assignment.source_file or 'Lua file'
    if assignment.line and assignment.end_line and assignment.end_line > assignment.line then
        return string.format('%s lines %d-%d', file, assignment.line, assignment.end_line)
    elseif assignment.line then
        return string.format('%s line %d', file, assignment.line)
    end
    return file
end

local function title_for(keys)
    if keys[2] == 'precast' and keys[3] == 'WS' and keys[4] then
        return join_from(keys, 4)
    elseif keys[2] == 'precast' and keys[3] == 'JA' and keys[4] then
        return join_from(keys, 4)
    elseif keys[2] == 'midcast' and keys[3] then
        return join_from(keys, 3)
    elseif keys[2] == 'TreasureHunter' then
        return 'Treasure Hunter'
    end
    return join_from(keys, 2)
end

local function category_for(keys)
    if keys[2] == 'engaged' then
        if #keys == 2 then return 'Base Engaged State' end
        if has_token(keys, 'PDT') or has_token(keys, 'DT') or has_token(keys, 'MDT') or has_token(keys, 'MEVA') then
            return 'Defensive Engaged Variant'
        end
        return 'Engaged Variant'
    elseif keys[2] == 'idle' then
        return #keys == 2 and 'Idle State' or 'Idle Variant'
    elseif keys[2] == 'resting' then
        return 'Resting State'
    elseif keys[2] == 'defense' then
        return 'Defense Set'
    elseif keys[2] == 'precast' and keys[3] == 'WS' then
        return #keys > 4 and 'Weapon Skill Modifier' or 'Weapon Skill Set'
    elseif keys[2] == 'precast' and keys[3] == 'JA' then
        return 'Job Ability Set'
    elseif keys[2] == 'precast' and keys[3] == 'FC' then
        return #keys > 3 and 'Magic Precast Variant' or 'Magic Precast'
    elseif keys[2] == 'precast' and keys[3] == 'RA' then
        return 'Ranged Precast'
    elseif keys[2] == 'midcast' and keys[3] == 'RA' then
        return 'Ranged Midcast'
    elseif keys[2] == 'midcast' then
        return 'Magic Midcast'
    elseif keys[2] == 'TreasureHunter' then
        return 'Utility Overlay'
    elseif keys[2] == 'buff' then
        return 'Reactive / Buff Override'
    elseif keys[2] == 'weapons' then
        return 'Weapon Loadout'
    elseif is_movement_key(keys[2]) then
        return 'Movement / Utility Overlay'
    elseif keys[2] == 'Knockback' then
        return 'Utility Overlay'
    end
    return 'Unknown / Custom Set'
end

local function trigger_for(keys, category)
    if keys[2] == 'precast' and keys[3] == 'WS' and keys[4] then
        return 'Weapon Skill -> ' .. keys[4]
    elseif keys[2] == 'precast' and keys[3] == 'WS' then
        return 'Weapon Skill'
    elseif keys[2] == 'precast' and keys[3] == 'JA' and keys[4] then
        return 'Job Ability -> ' .. keys[4]
    elseif keys[2] == 'precast' and keys[3] == 'JA' then
        return 'Job Ability'
    elseif keys[2] == 'precast' and keys[3] == 'FC' then
        return keys[4] and ('Magic -> Precast -> ' .. keys[4]) or 'Magic -> Precast'
    elseif category == 'Ranged Precast' then
        return 'Ranged Attack -> Precast'
    elseif category == 'Ranged Midcast' then
        return 'Ranged Attack -> Midcast'
    elseif keys[2] == 'midcast' and keys[3] then
        return 'Magic -> Midcast -> ' .. keys[3]
    elseif keys[2] == 'engaged' then
        return 'Engaged melee state'
    elseif keys[2] == 'idle' then
        return 'Idle state'
    elseif keys[2] == 'resting' then
        return 'Resting state'
    elseif keys[2] == 'defense' then
        return 'Defense mode'
    elseif keys[2] == 'TreasureHunter' then
        return 'Treasure Hunter tagging'
    elseif keys[2] == 'buff' then
        return 'Buff/reactive override'
    elseif keys[2] == 'weapons' then
        return 'Weapon loadout'
    elseif is_movement_key(keys[2]) then
        return 'Movement / Kiting mode'
    elseif keys[2] == 'Knockback' then
        return 'Knockback/positioning mode'
    end
    return 'Unknown'
end

local function references_treasure_hunter(inheritance)
    for _, ref in ipairs(inheritance.bases or {}) do
        if tostring(ref):find('TreasureHunter', 1, true) then return true end
    end
    for _, ref in ipairs(inheritance.references or {}) do
        if tostring(ref):find('TreasureHunter', 1, true) then return true end
    end
    return false
end

local function gear_values(node)
    local out = {}
    local rhs = node and node.assignment and node.assignment.rhs
    for slot, value in pairs((rhs and rhs.slots) or {}) do
        out[#out + 1] = { slot = slot, value = tostring(value) }
    end
    return out
end

local function detect_known_item(values, items)
    for _, item in ipairs(items) do
        local item_l = item:lower()
        for _, entry in ipairs(values) do
            if entry.value:lower():find(item_l, 1, true) then
                return item
            end
        end
    end
    return nil
end

local function build_evidence(keys, category, matches, inheritance, node)
    local evidence = {}
    local lua_path = path_string(node)
    if category ~= 'Unknown / Custom Set' then
        add(evidence, 'Path rule: ' .. lua_path)
    end
    for _, match in ipairs(matches) do
        add(evidence, 'Semantic keyword: ' .. match.token)
    end
    if inheritance.kind == 'combine' then
        for _, ref in ipairs(inheritance.bases or {}) do
            add(evidence, 'set_combine base: ' .. ref)
        end
    elseif inheritance.kind == 'reference' then
        for _, ref in ipairs(inheritance.references or {}) do
            add(evidence, 'Alias/reference: ' .. ref)
        end
    end

    local values = gear_values(node)
    if is_movement_key(keys[2]) or category == 'Movement / Utility Overlay' then
        local item = detect_known_item(values, MOVEMENT_ITEMS)
        if item then add(evidence, 'Movement-speed gear detected: ' .. item) end
    end
    if keys[2] == 'TreasureHunter' or has_token(keys, 'TreasureHunter') or references_treasure_hunter(inheritance) then
        local item = detect_known_item(values, TREASURE_HUNTER_ITEMS)
        if item then add(evidence, 'Treasure Hunter gear detected: ' .. item) end
        for _, entry in ipairs(values) do
            if entry.value:find('Treasure Hunter', 1, true) then
                add(evidence, 'Treasure Hunter augment detected')
                break
            end
        end
    end
    if has_token(keys, 'Doom') then
        local item = detect_known_item(values, DOOM_ITEMS)
        if item then add(evidence, 'Doom/curse gear detected: ' .. item) end
    end
    return evidence
end

local function build_conditions(keys, category, inheritance)
    local conditions = {}
    if keys[2] == 'engaged' then
        for _, condition in ipairs(conditions_from(matched_from(keys, 3))) do add_unique(conditions, condition) end
    elseif keys[2] == 'precast' and keys[3] == 'WS' then
        for _, condition in ipairs(conditions_from(matched_from(keys, 5))) do add_unique(conditions, condition) end
    elseif keys[2] == 'precast' and keys[3] == 'FC' then
        add_unique(conditions, TOKEN_INFO.FC.condition)
        for _, condition in ipairs(conditions_from(matched_from(keys, 4))) do add_unique(conditions, condition) end
    elseif keys[2] == 'midcast' then
        if keys[3] and keys[3] ~= 'RA' then add_unique(conditions, 'Casting ' .. keys[3]) end
        for _, condition in ipairs(conditions_from(matched_from(keys, 3))) do add_unique(conditions, condition) end
    elseif keys[2] == 'idle' then
        for _, condition in ipairs(conditions_from(matched_from(keys, 3))) do add_unique(conditions, condition) end
    elseif keys[2] == 'resting' then
        add_unique(conditions, 'Resting')
    elseif keys[2] == 'defense' then
        if keys[3] then add_unique(conditions, 'Defense mode = ' .. keys[3]) end
        for _, condition in ipairs(conditions_from(matched_from(keys, 4))) do add_unique(conditions, condition) end
    elseif keys[2] == 'buff' then
        if keys[3] then
            local info = token_info(keys[3])
            add_unique(conditions, info and info.condition or (keys[3] .. ' active'))
        end
    elseif keys[2] == 'TreasureHunter' then
        add_unique(conditions, TOKEN_INFO.TreasureHunter.condition)
    elseif is_movement_key(keys[2]) then
        add_unique(conditions, TOKEN_INFO.Kiting.condition)
    elseif keys[2] == 'Knockback' then
        add_unique(conditions, TOKEN_INFO.Knockback.condition)
    elseif category == 'Weapon Loadout' and keys[3] then
        add_unique(conditions, 'Weapon set = ' .. keys[3])
    end
    if references_treasure_hunter(inheritance) then
        add_unique(conditions, TOKEN_INFO.TreasureHunter.condition)
    end
    return conditions
end

local function ws_text(keys)
    local ws = keys[4]
    local matches = matched_from(keys, 5)
    if #matches > 0 then
        local active = active_phrase(matches)
        local purpose = join_english(purposes_from(matches))
        return 'Used when performing ' .. ws .. ' while ' .. active .. '.',
               'Optimizes the ' .. purpose .. ' version of ' .. ws .. '.'
    end
    return 'Used when performing ' .. ws .. '.',
           'Provides the main gear set for ' .. ws .. '.'
end

local function engaged_text(keys)
    if #keys == 2 then
        return 'Used as the base melee set while engaged.',
               'Provides the default engaged gear before variants are applied.'
    end
    local matches = matched_from(keys, 3)
    if #matches > 0 then
        return 'Used while engaged when ' .. active_phrase(matches) .. '.',
               'Keeps melee gear active while adding ' .. join_english(purposes_from(matches)) .. '.'
    end
    return 'Used while engaged for the ' .. join_from(keys, 3) .. ' variant.',
           'Keeps melee gear organized for this custom engaged state.'
end

local function midcast_text(keys, inheritance)
    local spell = keys[3]
    if spell and has_token(keys, 'Resistant') then
        return 'Used during ' .. spell .. ' midcast when magic accuracy or landing rate matters.',
               'Prioritizes landing rate over pure damage.'
    elseif spell and references_treasure_hunter(inheritance) then
        return 'Used during ' .. spell .. ' midcast, likely to apply Treasure Hunter gear while tagging the target.',
               'Combines the spell set with Treasure Hunter gear for tagging.'
    elseif spell then
        local info = token_info(spell)
        if info then return info.plain, info.purpose end
        return 'Used during ' .. spell .. ' midcast.',
               'Applies the midcast gear for ' .. spell .. '.'
    end
    return 'Used during spell midcast.',
           'Applies midcast gear for magic actions.'
end

local function plain_text_for(keys, category, inheritance)
    if keys[2] == 'precast' and keys[3] == 'WS' and keys[4] then
        return ws_text(keys)
    elseif keys[2] == 'precast' and keys[3] == 'WS' then
        return 'Used as the base weapon skill set.',
               'Provides the default weapon skill gear before weapon-specific sets or modifiers are applied.'
    elseif keys[2] == 'engaged' then
        return engaged_text(keys)
    elseif keys[2] == 'TreasureHunter' then
        return TOKEN_INFO.TreasureHunter.plain, TOKEN_INFO.TreasureHunter.purpose
    elseif is_movement_key(keys[2]) then
        return TOKEN_INFO.Kiting.plain, TOKEN_INFO.Kiting.purpose
    elseif keys[2] == 'Knockback' then
        return TOKEN_INFO.Knockback.plain, TOKEN_INFO.Knockback.purpose
    elseif keys[2] == 'buff' and keys[3] and token_info(keys[3]) then
        local info = token_info(keys[3])
        return info.plain, info.purpose
    elseif keys[2] == 'precast' and keys[3] == 'JA' and keys[4] then
        return 'Used when using ' .. keys[4] .. '.',
               'Provides the gear for the ' .. keys[4] .. ' job ability.'
    elseif keys[2] == 'precast' and keys[3] == 'FC' then
        if keys[4] then
            return 'Used before casting when the ' .. keys[4] .. ' fast-cast variant applies.',
                   'Adjusts Fast Cast gear for ' .. keys[4] .. '.'
        end
        return TOKEN_INFO.FC.plain, TOKEN_INFO.FC.purpose
    elseif category == 'Ranged Precast' then
        return 'Used before a ranged attack fires.',
               'Prepares ranged attack gear before the shot.'
    elseif category == 'Ranged Midcast' then
        return 'Used while a ranged attack is resolving.',
               'Applies ranged attack gear for the shot.'
    elseif keys[2] == 'midcast' then
        return midcast_text(keys, inheritance)
    elseif keys[2] == 'idle' then
        if #keys == 2 then
            return 'Used while idle and not engaged.',
                   'Provides the default idle gear set.'
        end
        local info = token_info(keys[3])
        if info then return info.plain, info.purpose end
        return 'Used while idle for the ' .. join_from(keys, 3) .. ' variant.',
               'Adjusts idle gear for this mode or condition.'
    elseif keys[2] == 'resting' then
        return 'Used while resting.',
               'Supports HP or MP recovery while resting.'
    elseif keys[2] == 'defense' then
        return 'Used when defense mode is active.',
               'Prioritizes defensive gear for the selected defense mode.'
    elseif keys[2] == 'weapons' then
        return 'Used to equip a saved weapon loadout.',
               'Groups saved weapon combinations.'
    elseif category == 'Unknown / Custom Set' and #match_tokens(keys) > 0 then
        return 'Used for a custom set with recognizable GearSwap mode tokens.',
               'Applies the custom mode or status implied by its name.'
    end
    return 'Purpose unknown - custom or unrecognized set name.',
           'Unknown. This may be a custom user-defined set.'
end

local function confidence_for(category, matches, evidence)
    if category == 'Unknown / Custom Set' then
        return #matches > 0 and 'Low' or 'Unknown'
    end

    local score = 0
    if category ~= 'Unknown / Custom Set' then score = score + 1 end
    if #matches > 0 then score = score + 1 end
    for _, item in ipairs(evidence or {}) do
        if contains_text(item, 'gear detected') or contains_text(item, 'augment detected') then
            score = score + 1
            break
        end
    end
    for _, item in ipairs(evidence or {}) do
        if contains_text(item, 'set_combine base') or contains_text(item, 'Alias/reference') then
            score = score + 1
            break
        end
    end

    if score >= 3 then return 'High' end
    if score >= 1 then return 'Likely' end
    return 'Low'
end


local CATEGORY_INFO = {
    currentstate = {
        title = 'Current State',
        category = 'Live / State Context',
        purpose = 'Shows sets or state-related groupings tied to what the character is currently doing.',
        explanation = 'In GearSwap, the final gear choice usually depends on status such as idle, engaged, casting, resting, buffs, weapons, and active modes. This section helps group state-driven logic rather than one-off action swaps.',
        typical_use = 'Idle state, engaged state, movement state, weapon mode, defense mode, or currently resolved context.',
    },
    actions = {
        title = 'Actions',
        category = 'Action-Triggered Sets',
        purpose = 'Groups gear logic used when the character actively does something.',
        explanation = 'GearSwap separates many actions by timing. A weapon skill, spell, job ability, ranged attack, or item use can briefly equip specialized gear, then return to idle or engaged gear afterward.',
        typical_use = 'Weapon skills, job abilities, spell precast, spell midcast, ranged attacks, and item-use swaps.',
    },
    magic = {
        title = 'Magic',
        category = 'Spellcasting Sets',
        purpose = 'Groups sets used for spellcasting.',
        explanation = 'Magic sets are often split because the best gear before a spell starts is not the same as the best gear while the spell resolves. Fast Cast helps start the spell quickly, while midcast gear focuses on potency, duration, skill, magic accuracy, cure potency, or damage.',
        typical_use = 'Fast Cast, midcast, healing, enhancing, enfeebling, elemental, dark magic, blue magic, and spell-specific variants.',
    },
    precast = {
        title = 'Precast',
        category = 'Pre-Action Timing',
        purpose = 'Gear equipped before an action begins.',
        explanation = 'In GearSwap, precast runs at the start of an action. For spells this usually means Fast Cast or interruption reduction. For ranged attacks it often means Snapshot. For weapon skills and job abilities it may equip the actual ability or WS gear before the action fires.',
        typical_use = 'Fast Cast, Snapshot, weapon skill sets, job ability enhancement gear.',
    },
    midcast = {
        title = 'Midcast',
        category = 'Action Resolution Timing',
        purpose = 'Gear equipped while a spell or ranged action resolves.',
        explanation = 'Midcast is where the result is usually determined. Spell sets often prioritize potency, accuracy, duration, skill, cure potency, or magic burst stats. Ranged midcast or midshot sets usually prioritize ranged accuracy, ranged attack, Store TP, or damage.',
        typical_use = 'Cure potency, enhancing duration, enfeebling accuracy, elemental damage, magic burst, ranged accuracy/damage.',
    },
    aftercast = {
        title = 'Aftercast',
        category = 'Return Logic',
        purpose = 'Logic that returns the player to the correct normal set after an action completes.',
        explanation = 'Aftercast usually decides whether the character should return to idle, engaged, movement, defensive, or another state-based set after a temporary action swap ends.',
        typical_use = 'Returning to idle/engaged gear after casting, weapon skills, job abilities, or ranged attacks.',
    },
    engaged = {
        title = 'Engaged',
        category = 'Melee / TP Sets',
        purpose = 'Gear used while actively engaged with a target.',
        explanation = 'Engaged sets are usually the default melee or TP sets. They often balance haste, accuracy, Store TP, multi-attack, Dual Wield, Subtle Blow, and damage taken depending on the job, buffs, weapon, and enemy difficulty.',
        typical_use = 'Base TP sets, accuracy variants, hybrid DT sets, weapon-specific engaged sets, high/low buff variants.',
    },
    idle = {
        title = 'Idle',
        category = 'Idle / Recovery Sets',
        purpose = 'Gear used while not actively fighting or performing an action.',
        explanation = 'Idle gear is usually focused on survival and recovery because the character is not actively swinging. Common priorities are damage taken reduction, Refresh, Regen, movement speed, town gear, or safe idle variants.',
        typical_use = 'Refresh idle, DT idle, movement idle, town idle, resting/safe idle.',
    },
    movement = {
        title = 'Movement',
        category = 'Movement / Travel Sets',
        purpose = 'Groups gear used when movement speed or repositioning matters.',
        explanation = 'Movement sets are usually used outside normal action timing. GearSwap files often equip these while running, kiting, traveling, or using a movement mode, then combine or swap back into idle or engaged gear when the movement condition no longer applies.',
        typical_use = 'Movement speed boots, kiting sets, town movement, travel mode, and repositioning/safety variants.',
    },
    resting = {
        title = 'Resting',
        category = 'Resting / Recovery Sets',
        purpose = 'Groups gear used while the character is resting to recover HP or MP.',
        explanation = 'Resting sets are older-style recovery sets that can still appear in GearSwap files. They usually focus on hMP, hHP, Refresh-style recovery, or safer recovery gear while the character is not fighting.',
        typical_use = 'Resting recovery gear, MP recovery, HP recovery, safe recovery, or legacy resting sets.',
    },
    weapons = {
        title = 'Weapons',
        category = 'Weapon Loadouts',
        purpose = 'Groups weapon combinations or weapon modes.',
        explanation = 'Many GearSwap files separate weapons because the selected weapon can change the correct TP set, weapon skill set, aftermath logic, accuracy needs, or ranged/ammo setup.',
        typical_use = 'Main/sub weapon pairs, ranged weapon setups, weapon modes, aftermath-related setups.',
    },
    weaponskills = {
        title = 'Weapon Skills',
        category = 'Weapon Skill Sets',
        purpose = 'Groups gear used when performing weapon skills.',
        explanation = 'Weapon skill gear is usually different from engaged gear because the game evaluates specific stats at the moment the WS fires. Different WS may prioritize WSD, STR, DEX, AGI, MND, CHR, attack, accuracy, multi-hit stats, or magic attack depending on the WS formula.',
        typical_use = 'Base WS sets, WS-specific sets, Sneak Attack/Trick Attack variants, accuracy variants, max TP variants.',
    },
    jobabilities = {
        title = 'Job Abilities',
        category = 'Job Ability Sets',
        purpose = 'Groups gear used for job abilities.',
        explanation = 'Many job abilities have specific enhancement gear that only needs to be worn briefly when the ability is used. GearSwap can equip that gear for the ability, then return to the normal state afterward.',
        typical_use = 'Ability duration gear, potency gear, recast gear, job-specific ability bonuses.',
    },
    ranged = {
        title = 'Ranged',
        category = 'Ranged Attack Sets',
        purpose = 'Groups gear used for ranged attacks.',
        explanation = 'Ranged attacks are commonly split into pre-shot and mid-shot timing. Snapshot reduces the time before the shot, while midshot gear affects accuracy, damage, Store TP, and ranged attack performance.',
        typical_use = 'Snapshot sets, ranged accuracy sets, ranged damage sets, midshot variants.',
    },
    overlaysmodifiers = {
        title = 'Overlays / Modifiers',
        category = 'Layered Set Modifiers',
        purpose = 'Groups partial sets that modify another base set.',
        explanation = 'These sets are often combined with idle, engaged, WS, or casting sets instead of replacing them completely. In Lua this is commonly done with set_combine() or conditional logic.',
        typical_use = 'Treasure Hunter layers, damage taken layers, movement speed, Capacity Points, Doom gear, special fight conditions, accuracy or defensive modifiers.',
    },
    reactive = {
        title = 'Reactive',
        category = 'Status / Condition Responses',
        purpose = 'Groups sets that respond to buffs, debuffs, or changing conditions.',
        explanation = 'Reactive sets are used when gear should change because something happened to the character or the fight state changed. These are often tied to buffactive checks, status changes, mode changes, or defensive conditions.',
        typical_use = 'Doom, Sleep, Weakness, Sneak Attack, Trick Attack, aftermath, low HP, defensive reactions, buff/debuff overrides.',
    },
    buff = {
        title = 'Buff',
        category = 'Buff / Debuff Overrides',
        purpose = 'Groups sets tied to active buffs or debuffs.',
        explanation = 'GearSwap files often use buffactive or buff_change logic to equip special gear while a status is active. These sets may override or layer onto normal idle, engaged, or action sets.',
        typical_use = 'Doom gear, sleep gear, Sneak Attack, Trick Attack, weakness, aftermath, special status gear.',
    },
    defense = {
        title = 'Defense',
        category = 'Defensive Modes',
        purpose = 'Groups gear modes focused on reducing incoming damage or resisting effects.',
        explanation = 'Defense sets usually trade some offense for survival. Depending on the Lua, these may be full defensive sets or hybrid overlays combined with engaged/idle sets.',
        typical_use = 'PDT, MDT, DT, magic evasion, hybrid engaged sets, emergency defense modes.',
    },
    utility = {
        title = 'Utility',
        category = 'Utility Sets',
        purpose = 'Groups practical helper sets that do not fit one combat timing.',
        explanation = 'Utility sets are commonly used for travel, special objectives, quality-of-life swaps, or situational gear that supports gameplay but is not a normal idle/engaged/cast set.',
        typical_use = 'Movement speed, Treasure Hunter, Capacity Points, Warp, town gear, sneak/invisible helpers.',
    },
    other = {
        title = 'Other',
        category = 'Miscellaneous / Custom Sets',
        purpose = 'Groups custom or uncommon sets that do not fit the main categories.',
        explanation = 'Many GearSwap files contain personal helper sets, experimental sets, old sets, or job-specific logic that does not map cleanly to standard categories.',
        typical_use = 'User-defined helpers, custom modes, special-case logic, experimental sets.',
    },
    treasurehunter = {
        title = 'Treasure Hunter',
        category = 'Loot / Tagging Overlay',
        purpose = 'Groups gear used to apply or maintain Treasure Hunter on enemies.',
        explanation = 'Treasure Hunter sets are usually layered briefly onto an action, ranged attack, spell, or melee hit so the enemy gets tagged without replacing the whole normal set for long.',
        typical_use = 'TH tagging actions, pull/tag sets, Treasure Hunter layers, and opener swaps.',
    },
    healingmagic = {
        title = 'Healing Magic',
        category = 'Healing / Cure Sets',
        purpose = 'Groups gear used for healing spells or cure-related variants.',
        explanation = 'Healing sets usually focus on cure potency, received cure bonuses, healing magic skill, enmity control, casting speed, or self-healing variants depending on the job and spell.',
        typical_use = 'Cure, Curaga, self-cure, cure received, healing skill, and low-enmity cure variants.',
    },
    elementalmagic = {
        title = 'Elemental Magic',
        category = 'Nuking / Elemental Sets',
        purpose = 'Groups gear used for elemental damage spells.',
        explanation = 'Elemental magic sets usually prioritize magic attack, magic accuracy, INT, elemental skill, magic burst bonuses, and resist handling. Many Lua files split these into normal, resistant, and Magic Burst variants.',
        typical_use = 'Nuking, Magic Burst, resistant targets, elemental accuracy, and spell-family variants.',
    },
    enhancingmagic = {
        title = 'Enhancing Magic',
        category = 'Buff Duration / Enhancing Sets',
        purpose = 'Groups gear used for enhancing magic spells.',
        explanation = 'Enhancing sets often care about duration, enhancing magic skill, potency, or spell-specific bonuses. These are commonly split because buffs like Stoneskin, Phalanx, Haste, and Refresh care about different stats.',
        typical_use = 'Haste, Refresh, Phalanx, Stoneskin, Aquaveil, Barspells, and duration variants.',
    },
    enfeeblingmagic = {
        title = 'Enfeebling Magic',
        category = 'Debuff / Magic Accuracy Sets',
        purpose = 'Groups gear used to land enfeebling spells.',
        explanation = 'Enfeebling sets usually prioritize magic accuracy, enfeebling skill, MND or INT, duration, and resist handling. Some files split them by white/black magic style or by accuracy level.',
        typical_use = 'Slow, Paralyze, Silence, Sleep, Gravity, Dia/Bio-style debuffs, and resistant variants.',
    },
    darkmagic = {
        title = 'Dark Magic',
        category = 'Dark Magic Sets',
        purpose = 'Groups gear used for dark magic spells.',
        explanation = 'Dark magic sets commonly focus on magic accuracy, dark magic skill, drain/aspir potency, absorb effects, or spell-specific bonuses.',
        typical_use = 'Drain, Aspir, Absorb spells, Stun, dark magic accuracy, and dark skill variants.',
    },
    bluemagic = {
        title = 'Blue Magic',
        category = 'Blue Magic Sets',
        purpose = 'Groups gear used for Blue Mage spells.',
        explanation = 'Blue magic sets can vary heavily because physical blue magic, magical blue magic, healing blue magic, and utility spells all want different stats. Lua files often split these by spell family or effect.',
        typical_use = 'Physical blue magic, magical blue magic, healing blue magic, stun/utility spells, and spell-family variants.',
    },
    ninjutsu = {
        title = 'Ninjutsu',
        category = 'Ninjutsu Sets',
        purpose = 'Groups gear used for Ninja magic.',
        explanation = 'Ninjutsu sets often split Utsusemi from offensive or enfeebling ninjutsu. Utsusemi commonly values Fast Cast, recast, and interruption reduction, while offensive ninjutsu may value magic accuracy or damage.',
        typical_use = 'Utsusemi, elemental wheel, ninjutsu enfeebles, recast, and interruption-reduction variants.',
    },
    songs = {
        title = 'Songs',
        category = 'Bard Song Sets',
        purpose = 'Groups gear used for Bard songs.',
        explanation = 'Song sets often care about song duration, song effect, singing skill, instrument skill, magic accuracy, or song count. Many files split dummy songs, debuff songs, and buff songs separately.',
        typical_use = 'March, Minuet, Madrigal, Ballad, Lullaby, Elegy, Finale, dummy songs, and duration variants.',
    },
    pet = {
        title = 'Pet',
        category = 'Pet / Companion Sets',
        purpose = 'Groups gear used for pets, avatars, automatons, wyverns, or pet commands.',
        explanation = 'Pet sets usually separate master gear from pet-focused gear. Depending on the job, these may affect pet accuracy, attack, magic, damage taken, ready moves, blood pacts, maneuvers, or survivability.',
        typical_use = 'Avatar sets, automaton sets, wyvern sets, Ready moves, Blood Pacts, pet DT, and pet accuracy/damage variants.',
    },
    corsairrolls = {
        title = 'Corsair Rolls',
        category = 'Corsair Roll Sets',
        purpose = 'Groups gear used for Corsair rolls and Phantom Roll logic.',
        explanation = 'Roll sets usually equip roll-enhancing gear only while the roll is performed, then return to the normal idle or engaged set afterward.',
        typical_use = 'Phantom Roll, Double-Up, roll duration, roll bonus gear, and job-specific roll helpers.',
    },
    quickdraw = {
        title = 'Quick Draw',
        category = 'Quick Draw Sets',
        purpose = 'Groups gear used for Corsair Quick Draw shots.',
        explanation = 'Quick Draw sets usually focus on magic accuracy, magic attack, AGI, elemental bonuses, or special utility depending on whether the shot is for damage, accuracy, or effect support.',
        typical_use = 'Elemental shots, magic accuracy shots, damage shots, and utility shots.',
    },
    snapshot = {
        title = 'Snapshot',
        category = 'Ranged Pre-Shot Sets',
        purpose = 'Groups gear used before a ranged attack fires.',
        explanation = 'Snapshot gear is usually worn at the start of a ranged attack to shorten the pre-shot delay. It is commonly separate from midshot gear, which affects the actual shot result.',
        typical_use = 'Snapshot, Rapid Shot, pre-shot ranged sets, and ranged precast variants.',
    },
    midshot = {
        title = 'Midshot',
        category = 'Ranged Resolution Sets',
        purpose = 'Groups gear used while a ranged attack resolves.',
        explanation = 'Midshot sets are the ranged equivalent of midcast-style timing. They usually focus on ranged accuracy, ranged attack, Store TP, Double Shot, crit, or damage depending on the weapon and target.',
        typical_use = 'Ranged accuracy, ranged damage, Store TP, Double Shot, and high/low accuracy variants.',
    },
    enmity = {
        title = 'Enmity',
        category = 'Threat Control Sets',
        purpose = 'Groups gear used to raise or lower enemy attention.',
        explanation = 'Enmity sets are commonly used by tanks, supports, and healers. Some actions want high enmity to hold hate, while cures or support actions may want lower enmity to avoid pulling hate.',
        typical_use = 'High-enmity tank actions, low-enmity cure/support sets, and job ability threat variants.',
    },
    capacitypoints = {
        title = 'Capacity Points',
        category = 'Experience / CP Utility Sets',
        purpose = 'Groups gear used for Capacity Point or experience gain bonuses.',
        explanation = 'Capacity Point sets are usually utility overlays. They may be combined with idle or engaged gear when safe, but are often skipped for harder fights where survival or accuracy matters more.',
        typical_use = 'CP cape, experience bonus gear, farming sets, and safe utility overlays.',
    },
    town = {
        title = 'Town',
        category = 'Town / Non-Combat Sets',
        purpose = 'Groups gear used in towns or safe non-combat situations.',
        explanation = 'Town sets usually prioritize movement, appearance, convenience, or quality of life instead of combat stats. They are often separate from normal idle gear.',
        typical_use = 'Town gear, movement gear, cosmetic sets, and non-combat idle variants.',
    },
    accuracyvariants = {
        title = 'Accuracy Variants',
        category = 'Accuracy Mode Sets',
        purpose = 'Groups variants used when landing hits or spells matters more than raw damage.',
        explanation = 'Accuracy folders usually contain alternate versions of engaged, weapon skill, ranged, or magic sets. These trade some damage stats for better hit rate, magic accuracy, or reliability.',
        typical_use = 'Low/medium/high accuracy sets, resistant targets, evasive enemies, and progression variants.',
    },
    hybriddefense = {
        title = 'Hybrid / Defensive Variants',
        category = 'Hybrid Safety Sets',
        purpose = 'Groups variants that trade some offense for survivability.',
        explanation = 'Hybrid sets are often combined with engaged, idle, or action sets when the fight is dangerous. They usually add DT, PDT, MDT, magic evasion, or defensive stats while keeping some offensive value.',
        typical_use = 'Hybrid TP, DT engaged, magic evasion variants, emergency defense, and dangerous-fight modes.',
    },
    modes = {
        title = 'Modes',
        category = 'State / Mode Controls',
        purpose = 'Groups gear logic tied to user-selected modes or state toggles.',
        explanation = 'Many GearSwap files use modes to choose between accuracy levels, weapon choices, idle styles, defense levels, casting variants, or utility overlays. These folders usually organize those mode-dependent choices.',
        typical_use = 'Accuracy mode, weapon mode, idle mode, defense mode, casting mode, and user toggle variants.',
    },
    items = {
        title = 'Items',
        category = 'Item-Use Sets',
        purpose = 'Groups gear used when activating items or utility tools.',
        explanation = 'Item-use sets are usually temporary swaps for convenience or special effects. GearSwap can equip them for the item action, then return to the normal idle or engaged set.',
        typical_use = 'Warp items, teleport items, tools, consumables, and item-triggered utility swaps.',
    },
}


local CATEGORY_ALIASES = {
    current = 'currentstate',
    currentstate = 'currentstate',
    currentgear = 'currentstate',
    actions = 'actions',
    action = 'actions',
    magic = 'magic',
    spells = 'magic',
    spellcasting = 'magic',
    precast = 'precast',
    midcast = 'midcast',
    aftercast = 'aftercast',
    engaged = 'engaged',
    idle = 'idle',
    movement = 'movement',
    movements = 'movement',
    movespeed = 'movement',
    movementspeed = 'movement',
    kiting = 'movement',
    run = 'movement',
    running = 'movement',
    resting = 'resting',
    rest = 'resting',
    weapons = 'weapons',
    weapon = 'weapons',
    weaponskill = 'weaponskills',
    weaponskills = 'weaponskills',
    ws = 'weaponskills',
    abilities = 'jobabilities',
    ability = 'jobabilities',
    jobability = 'jobabilities',
    jobabilities = 'jobabilities',
    ja = 'jobabilities',
    ranged = 'ranged',
    rangedattack = 'ranged',
    rangedattacks = 'ranged',
    ra = 'ranged',
    overlaysmodifiers = 'overlaysmodifiers',
    overlays = 'overlaysmodifiers',
    overlay = 'overlaysmodifiers',
    modifiers = 'overlaysmodifiers',
    modifier = 'overlaysmodifiers',
    reactive = 'reactive',
    reaction = 'reactive',
    reactions = 'reactive',
    buff = 'buff',
    buffs = 'buff',
    defense = 'defense',
    defensive = 'defense',
    utility = 'utility',
    utilities = 'utility',
    other = 'other',
    miscellaneous = 'other',
    misc = 'other',
    th = 'treasurehunter',
    treasurehunter = 'treasurehunter',
    treasure = 'treasurehunter',
    healing = 'healingmagic',
    healingmagic = 'healingmagic',
    cure = 'healingmagic',
    cures = 'healingmagic',
    curaga = 'healingmagic',
    elemental = 'elementalmagic',
    elementalmagic = 'elementalmagic',
    nuking = 'elementalmagic',
    nuke = 'elementalmagic',
    nukes = 'elementalmagic',
    magicburst = 'elementalmagic',
    mb = 'elementalmagic',
    enhancing = 'enhancingmagic',
    enhancingmagic = 'enhancingmagic',
    enfeebling = 'enfeeblingmagic',
    enfeeblingmagic = 'enfeeblingmagic',
    darkmagic = 'darkmagic',
    dark = 'darkmagic',
    bluemagic = 'bluemagic',
    blue = 'bluemagic',
    ninjutsu = 'ninjutsu',
    ninja = 'ninjutsu',
    songs = 'songs',
    song = 'songs',
    singing = 'songs',
    bard = 'songs',
    brd = 'songs',
    pet = 'pet',
    pets = 'pet',
    avatar = 'pet',
    avatars = 'pet',
    automaton = 'pet',
    automatons = 'pet',
    wyvern = 'pet',
    bloodpact = 'pet',
    bloodpacts = 'pet',
    ready = 'pet',
    roll = 'corsairrolls',
    rolls = 'corsairrolls',
    corsairrolls = 'corsairrolls',
    phantomroll = 'corsairrolls',
    quickdraw = 'quickdraw',
    qd = 'quickdraw',
    snapshot = 'snapshot',
    preshot = 'snapshot',
    midshot = 'midshot',
    midshoot = 'midshot',
    enmity = 'enmity',
    hate = 'enmity',
    capacitypoints = 'capacitypoints',
    capacitypoint = 'capacitypoints',
    cp = 'capacitypoints',
    exp = 'capacitypoints',
    experience = 'capacitypoints',
    town = 'town',
    towns = 'town',
    acc = 'accuracyvariants',
    accuracy = 'accuracyvariants',
    fullacc = 'accuracyvariants',
    someacc = 'accuracyvariants',
    hybrid = 'hybriddefense',
    pdt = 'hybriddefense',
    mdt = 'hybriddefense',
    dt = 'hybriddefense',
    meva = 'hybriddefense',
    magicdefense = 'hybriddefense',
    modes = 'modes',
    mode = 'modes',
    states = 'modes',
    state = 'modes',
    item = 'items',
    items = 'items',
    itemuse = 'items',
}


local CATEGORY_KEY_PATTERNS = {
    -- Specific spell/job families first, before broad words like "magic" or "weapon".
    { pattern = 'treasurehunter', category = 'treasurehunter' },
    { pattern = 'magicburst', category = 'elementalmagic' },
    { pattern = 'elemental', category = 'elementalmagic' },
    { pattern = 'nuk', category = 'elementalmagic' },
    { pattern = 'healingmagic', category = 'healingmagic' },
    { pattern = 'curaga', category = 'healingmagic' },
    { pattern = 'cure', category = 'healingmagic' },
    { pattern = 'enhancing', category = 'enhancingmagic' },
    { pattern = 'enfeebling', category = 'enfeeblingmagic' },
    { pattern = 'darkmagic', category = 'darkmagic' },
    { pattern = 'bluemagic', category = 'bluemagic' },
    { pattern = 'blue', category = 'bluemagic' },
    { pattern = 'ninjutsu', category = 'ninjutsu' },
    { pattern = 'utsusemi', category = 'ninjutsu' },
    { pattern = 'song', category = 'songs' },
    { pattern = 'singing', category = 'songs' },
    { pattern = 'lullaby', category = 'songs' },
    { pattern = 'avatar', category = 'pet' },
    { pattern = 'automaton', category = 'pet' },
    { pattern = 'wyvern', category = 'pet' },
    { pattern = 'bloodpact', category = 'pet' },
    { pattern = 'pet', category = 'pet' },
    { pattern = 'phantomroll', category = 'corsairrolls' },
    { pattern = 'roll', category = 'corsairrolls' },
    { pattern = 'quickdraw', category = 'quickdraw' },
    { pattern = 'snapshot', category = 'snapshot' },
    { pattern = 'preshot', category = 'snapshot' },
    { pattern = 'midshot', category = 'midshot' },
    { pattern = 'ranged', category = 'ranged' },
    { pattern = 'rangedattack', category = 'ranged' },
    { pattern = 'weaponskill', category = 'weaponskills' },
    { pattern = 'weapon', category = 'weapons' },
    { pattern = 'jobability', category = 'jobabilities' },
    { pattern = 'abilities', category = 'jobabilities' },
    { pattern = 'ability', category = 'jobabilities' },
    { pattern = 'enmity', category = 'enmity' },
    { pattern = 'capacitypoint', category = 'capacitypoints' },
    { pattern = 'exp', category = 'capacitypoints' },
    { pattern = 'town', category = 'town' },
    { pattern = 'accuracy', category = 'accuracyvariants' },
    { pattern = 'fullacc', category = 'accuracyvariants' },
    { pattern = 'someacc', category = 'accuracyvariants' },
    { pattern = 'hybrid', category = 'hybriddefense' },
    { pattern = 'magicdefense', category = 'hybriddefense' },
    { pattern = 'defense', category = 'defense' },
    { pattern = 'defensive', category = 'defense' },
    { pattern = 'pdt', category = 'hybriddefense' },
    { pattern = 'mdt', category = 'hybriddefense' },
    { pattern = 'meva', category = 'hybriddefense' },
    { pattern = 'doom', category = 'reactive' },
    { pattern = 'sleep', category = 'reactive' },
    { pattern = 'weakness', category = 'reactive' },
    { pattern = 'sneakattack', category = 'reactive' },
    { pattern = 'trickattack', category = 'reactive' },
    { pattern = 'buff', category = 'buff' },
    { pattern = 'mode', category = 'modes' },
    { pattern = 'state', category = 'modes' },
    { pattern = 'item', category = 'items' },
    { pattern = 'utility', category = 'utility' },
}

local function normalize_category_key(value)
    local key = tostring(value or ''):lower()
    key = key:gsub('&', 'and')
    key = key:gsub('[%s%p_]+', '')

    local alias = CATEGORY_ALIASES[key]
    if alias then return alias end

    for _, rule in ipairs(CATEGORY_KEY_PATTERNS) do
        if key:find(rule.pattern, 1, true) then
            return rule.category
        end
    end

    return key
end

local function copy_category_info(info, node)
    local title = info.title
    if not title or title == '' then
        title = node and node.key or 'Category'
    end

    return {
        title = title,
        category = info.category,
        plain_english = info.explanation,
        purpose = info.purpose,
        typical_use = info.typical_use,
        conditions = {},
        confidence = nil,
        evidence = {},
        lua_path = path_string(node),
        source = 'Organized tree category',
        inheritance = { bases = {}, override_slots = {}, references = {}, kind = 'category' },
        node_kind = 'category',
        summary_only = true,
    }
end

local function category_node_info(node)
    if not node or node.has_gear then return nil end

    local candidates = {}
    candidates[#candidates + 1] = node.key
    candidates[#candidates + 1] = node.virtual_id

    if node.path then
        for i = #node.path, 1, -1 do
            candidates[#candidates + 1] = node.path[i]
        end
    end

    for _, candidate in ipairs(candidates) do
        local normalized = normalize_category_key(candidate)
        local info = CATEGORY_INFO[normalized]
        if info then return copy_category_info(info, node) end
    end

    if node.virtual or (node.children and #node.children > 0) then
        return copy_category_info({
            title = node.key or 'Custom Category',
            category = 'Custom Category',
            purpose = 'Groups related GearSwap sets under a custom section.',
            explanation = 'This appears to be a user-defined organization point. Open one of its child entries to inspect the actual gear or Lua source.',
            typical_use = 'Custom grouping, job-specific organization, or personal layout.',
        }, node)
    end

    return nil
end

function semantics.is_category_node(node)
    return category_node_info(node) ~= nil
end


function semantics.build_set_info(node)
    local category_info = category_node_info(node)
    if category_info then return category_info end

    local keys = (node and node.path) or {}
    local assignment = node and node.assignment
    local inheritance = inheritance_for(node)
    local category = category_for(keys)
    local matches = match_tokens(keys)
    local plain, purpose = plain_text_for(keys, category, inheritance)
    local evidence = build_evidence(keys, category, matches, inheritance, node)

    return {
        title = title_for(keys),
        category = category,
        plain_english = plain,
        trigger = trigger_for(keys, category),
        conditions = build_conditions(keys, category, inheritance),
        purpose = purpose,
        confidence = confidence_for(category, matches, evidence),
        evidence = evidence,
        lua_path = path_string(node),
        source = source_for(assignment),
        inheritance = inheritance,
    }
end

return semantics
