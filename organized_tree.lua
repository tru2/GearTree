-- GearTree organized tree builder
-- Builds a player-friendly display tree without changing parsed assignments.
--
-- Important design rule:
-- This module creates a VIRTUAL display tree. Leaves keep the original
-- assignment.keys path so equip/save/preview behavior still points back to the
-- real Lua set path.

local organized_tree = {}
local semantics = require('semantics')
local next_order = 0

local function reset_order()
    next_order = 0
end

local function new_node(key, path)
    next_order = next_order + 1
    return {
        key = key,
        path = path,
        children = {},
        child_map = {},
        assignment = nil,
        has_gear = false,
        -- Folders start collapsed by default so the organized view opens clean.
        -- Users can expand only the sections they need.
        expanded = false,
        organized = true,
        order_index = next_order,
    }
end

local function order_map(list)
    local out = {}
    for i, key in ipairs(list) do out[key] = i end
    return out
end

local FOLDER_ORDER = {
    ['Gear Sets'] = order_map({
        'Current State',
        'Actions',
        'Magic',
        'Overlays / Modifiers',
        'Reactive',
        'Weapons',
        'Other',
    }),
    ['Current State'] = order_map({
        'Engaged',
        'Idle',
        'Resting',
        'Defense',
        'Movement',
    }),
    ['Actions'] = order_map({
        'Job Abilities',
        'Weapon Skills',
        'Ranged',
        'Waltz / Steps / Flourishes',
        'Items / Utility',
    }),
    ['Magic'] = order_map({
        'Precast',
        'Midcast',
        'Cure / Healing',
        'Enhancing',
        'Enfeebling',
        'Elemental / Nuking',
        'Dark',
        'Songs',
        'Blue Magic',
    }),
    ['Overlays / Modifiers'] = order_map({
        'Accuracy',
        'Defensive',
        'Treasure Hunter',
        'Magic Burst',
        'Max TP',
        'Job Buffs',
        'Self / Received Effects',
        'Extra Melee',
    }),
    ['Reactive'] = order_map({
        'Doom',
        'Sleep',
        'Weakness',
        'Status / Emergency',
    }),
    ['Weapons'] = order_map({
        'Melee',
        'Magic',
        'Accuracy',
        'Ranged',
        'Utility',
    }),
    ['Other'] = order_map({
        'Uncategorized',
        'Unknown',
    }),
}

local function apply_folder_order(node)
    local map = FOLDER_ORDER[node.key]
    if map then
        table.sort(node.children, function(a, b)
            local oa = map[a.key] or 9999
            local ob = map[b.key] or 9999
            if oa ~= ob then return oa < ob end
            return (a.order_index or 0) < (b.order_index or 0)
        end)
    end
    for _, child in ipairs(node.children) do
        if #child.children > 0 then apply_folder_order(child) end
    end
end

local function copy_path(path)
    local out = {}
    for i = 1, #path do out[i] = path[i] end
    return out
end

local function join_from(keys, first)
    local out = {}
    for i = first, #keys do out[#out + 1] = tostring(keys[i]) end
    return table.concat(out, ' > ')
end

local function keys_equal(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function starts_with(value, prefix)
    value = tostring(value or '')
    return value:sub(1, #prefix) == prefix
end

local function contains_text(value, text)
    return tostring(value or ''):lower():find(tostring(text or ''):lower(), 1, true) ~= nil
end

local function refs_contain(assignment, text)
    local rhs = assignment and assignment.rhs
    if not rhs then return false end
    if rhs.kind == 'ref' and contains_text(rhs.target, text) then return true end
    if rhs.kind == 'combine' then
        for _, ref in ipairs(rhs.refs or {}) do
            if contains_text(ref, text) then return true end
        end
    end
    return false
end

local function route(folder1, folder2, folder3)
    local out = {}
    if folder1 then out[#out + 1] = folder1 end
    if folder2 then out[#out + 1] = folder2 end
    if folder3 then out[#out + 1] = folder3 end
    return out
end

local function is_healing_spell(spell)
    if not spell then return false end
    return spell == 'Cure'
        or spell == 'Curaga'
        or spell == 'Cursna'
        or spell == 'LightWeatherCure'
        or spell == 'LightDayCure'
        or contains_text(spell, 'Healing')
end

local function is_enhancing_spell(spell)
    if not spell then return false end
    return spell == 'Enhancing Magic'
        or spell == 'Refresh'
        or spell == 'Aquaveil'
        or spell == 'Stoneskin'
        or spell == 'BarElement'
        or spell == 'Protect'
        or spell == 'Protectra'
        or spell == 'Shell'
        or spell == 'Shellra'
        or spell == 'Phalanx'
end

local function is_enfeebling_spell(spell)
    if not spell then return false end
    return spell == 'Enfeebling Magic'
        or spell == 'IntEnfeebles'
        or spell == 'MndEnfeebles'
        or starts_with(spell, 'Dia')
        or starts_with(spell, 'Bio')
end

local function is_elemental_spell(spell)
    if not spell then return false end
    return spell == 'Elemental Magic'
        or spell == 'Helix'
        or spell == 'Impact'
        or contains_text(spell, 'Nuke')
end

local function is_dark_spell(spell)
    if not spell then return false end
    return spell == 'Dark Magic'
        or spell == 'Drain'
        or spell == 'Aspir'
        or spell == 'Death'
        or spell == 'Stun'
end

local function is_song_spell(spell)
    if not spell then return false end
    return spell == 'BardSong'
        or spell == 'SongEffect'
        or spell == 'SongDebuff'
        or spell == 'Lullaby'
        or spell == 'Horde Lullaby'
        or spell == 'DaurdablaDummy'
        or spell == 'SongRecast'
        or contains_text(spell, 'Song')
        or contains_text(spell, 'Lullaby')
end

local function is_movement_name(name)
    if not name then return false end
    return name == 'Kiting'
        or name == 'Movement'
        or name == 'MoveSpeed'
        or name == 'Move_Speed'
        or name == 'Run'
        or name == 'Running'
        or contains_text(name, 'Kiting')
        or contains_text(name, 'MoveSpeed')
        or contains_text(name, 'Movement')
end

local function is_utility_name(name)
    if not name then return false end
    return contains_text(name, 'Utility')
        or contains_text(name, 'Util')
        or contains_text(name, 'Tool')
end

local function weapon_subfolder(keys)
    local name = join_from(keys, 3):lower()
    if name:find('nuke', 1, true) or name:find('magic', 1, true) then
        return 'Magic'
    elseif name:find('macc', 1, true) or name:find('acc', 1, true) then
        return 'Accuracy'
    elseif name:find('pull', 1, true) or name:find('ranged', 1, true)
        or name:find('bow', 1, true) or name:find('gun', 1, true) then
        return 'Ranged'
    elseif name:find('utility', 1, true) or name:find('util', 1, true)
        or name:find('th', 1, true) then
        return 'Utility'
    end
    return 'Melee'
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

function organized_tree.get_organized_route(node_or_assignment)
    local info = semantics.classify_organized(node_or_assignment)
    if info and info.route then
        return info.route
    end
    return route('Other', 'Uncategorized')
end

function organized_tree.leaf_label(node_or_assignment)
    local keys = get_keys(node_or_assignment)
    local k2, k3, k4 = keys[2], keys[3], keys[4]

    if k2 == 'engaged' then
        return #keys == 2 and 'Base' or join_from(keys, 3)
    elseif k2 == 'idle' then
        return #keys == 2 and 'Base' or join_from(keys, 3)
    elseif k2 == 'resting' then
        return 'Resting'
    elseif k2 == 'defense' then
        return k3 and join_from(keys, 3) or 'Defense'
    elseif is_movement_name(k2) then
        return k2
    elseif k2 == 'TreasureHunter' then
        return 'Treasure Hunter'
    elseif k2 == 'buff' then
        return k3 and join_from(keys, 3) or 'Buff'
    elseif k2 == 'precast' and k3 == 'JA' then
        return k4 and join_from(keys, 4) or 'Job Abilities'
    elseif k2 == 'precast' and k3 == 'WS' then
        if not k4 then return 'Base WS' end
        return #keys == 4 and k4 or join_from(keys, 5)
    elseif k2 == 'precast' and k3 == 'FC' then
        return #keys == 3 and 'Fast Cast' or join_from(keys, 4)
    elseif k2 == 'precast' and (k3 == 'RA' or k3 == 'Waltz' or k3 == 'Step' or k3 == 'Flourish1') then
        return #keys == 3 and k3 or join_from(keys, 3)
    elseif k2 == 'midcast' then
        return k3 and join_from(keys, 3) or 'Midcast'
    elseif k2 == 'weapons' then
        return k3 and join_from(keys, 3) or 'Weapons'
    elseif k2 then
        return join_from(keys, 2)
    end
    return 'Unknown'
end

local function ensure_folder(parent, key)
    local child = parent.child_map[key]
    if child then return child end
    local path = copy_path(parent.path)
    path[#path + 1] = key
    child = new_node(key, path)
    parent.children[#parent.children + 1] = child
    parent.child_map[key] = child
    return child
end

local function unique_leaf_key(parent, label, assignment)
    local existing = parent.child_map[label]
    if not existing then return label end
    if existing.has_gear and existing.assignment and keys_equal(existing.path, assignment.keys) then
        return label
    end
    local line = assignment.line and (' line ' .. assignment.line) or ' duplicate'
    local candidate = label .. ' (' .. line .. ')'
    local n = 2
    while parent.child_map[candidate] do
        candidate = label .. ' (' .. line .. ' #' .. n .. ')'
        n = n + 1
    end
    return candidate
end

local function add_leaf(parent, label, assignment)
    local key = unique_leaf_key(parent, label, assignment)
    local existing = parent.child_map[key]
    if existing and existing.has_gear and keys_equal(existing.path, assignment.keys) then
        existing.assignment = assignment
        return existing
    end
    local leaf = new_node(key, assignment.keys)
    leaf.assignment = assignment
    leaf.has_gear = true
    leaf.organized_leaf = true
    parent.children[#parent.children + 1] = leaf
    parent.child_map[key] = leaf
    return leaf
end

local function has_direct_gear_slots(assignment)
    local rhs = assignment and assignment.rhs
    if not rhs then return false end

    for _ in pairs(rhs.slots or {}) do
        return true
    end

    return false
end

local function prune_empty_folders(node)
    if not node or not node.children then return false end

    for i = #node.children, 1, -1 do
        local child = node.children[i]
        if prune_empty_folders(child) then
            table.remove(node.children, i)
            if node.child_map then
                node.child_map[child.key] = nil
            end
        end
    end

    return node.organized == true and not node.has_gear and #node.children == 0
end

function organized_tree.build_organized_tree(assignments)
    reset_order()
    local root = new_node('Gear Sets', { 'sets' })
    for _, assignment in ipairs(assignments or {}) do
        if has_direct_gear_slots(assignment) then
            local parent = root
            local route_parts = organized_tree.get_organized_route(assignment)
            for _, folder in ipairs(route_parts) do
                parent = ensure_folder(parent, folder)
            end
            add_leaf(parent, organized_tree.leaf_label(assignment), assignment)
        end
    end
    prune_empty_folders(root)
    apply_folder_order(root)
    return root
end

organized_tree.build = organized_tree.build_organized_tree

return organized_tree
