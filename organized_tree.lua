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
        'Elemental Affinity',
        'Max TP',
        'Job Buffs',
        'Self / Received Effects',
        'Extra Melee',
    }),
    ['Reactive'] = order_map({
        'Doom',
        'Sleep',
        'Weakness',
        'Reraise',
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

local function normalize_display_key(value)
    local text = tostring(value or ''):lower()
    text = text:gsub('&', 'and')
    text = text:gsub('[%s_%-%p]+', '')
    return text
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
    -- If the label collides with an existing non-gear folder, redirect this set
    -- inside that folder rather than appending a "(line N)" suffix at parent level.
    -- Handles the common pattern where a named set shares its label with a category
    -- folder (e.g. sets.Reraise placed alongside a Reraise subfolder).
    local folder_collision = parent.child_map[label]
    if folder_collision and not folder_collision.has_gear and #folder_collision.children > 0 then
        local keys = assignment.keys
        local inner_label = tostring(keys[#keys] or label)
        return add_leaf(folder_collision, inner_label, assignment)
    end

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

local function trim_redundant_terminal_folder(route_parts, label)
    if #route_parts == 0 then return route_parts end
    -- Exact string match only: 'Max TP' and 'MaxTP' are distinct, so sets.MaxTP
    -- correctly nests inside the Max TP folder rather than appearing as a sibling.
    if route_parts[#route_parts] == label then
        table.remove(route_parts, #route_parts)
    end
    return route_parts
end

local function prune_empty_folders(node)
    if not node or not node.children then return end

    -- Returns true when this node is, or contains, at least one real gear set.
    -- Children with no real gear descendants are removed in-place so that
    -- category descriptions, labels, or metadata nodes never count as content.
    local function has_real_set(n)
        -- A node with has_gear or an assignment is a real set — keep it immediately.
        if n.has_gear == true or n.assignment ~= nil then
            return true
        end
        -- Folder: recurse and drop children with no real gear anywhere under them.
        for i = #n.children, 1, -1 do
            local child = n.children[i]
            if not has_real_set(child) then
                table.remove(n.children, i)
                if n.child_map then n.child_map[child.key] = nil end
            end
        end
        -- Keep this folder only when at least one child survived.
        return #n.children > 0
    end

    -- Apply to root's children only; the root itself is never removed.
    for i = #node.children, 1, -1 do
        local child = node.children[i]
        if not has_real_set(child) then
            table.remove(node.children, i)
            if node.child_map then node.child_map[child.key] = nil end
        end
    end
end

-- Inject a 'Base' child node carrying the given gear assignment into
-- parent_node.  Called when a WS parent that holds direct gear gains
-- its first child variant so the base set stays separately selectable.
local function inject_base_child(parent_node, gear_assignment)
    if parent_node.child_map['Base'] then return end
    local base = new_node('Base', copy_path(gear_assignment.keys))
    base.assignment   = gear_assignment
    base.has_gear     = true
    base.organized_leaf = true
    table.insert(parent_node.children, 1, base)
    parent_node.child_map['Base'] = base
end

-- Special-case placement for sets.precast.WS paths.
--
-- Global helper variants (depth 4: sets.precast.WS[k4]) land flat under
-- Weapon Skills when they have no child variants.
--
-- Named-WS sets that have both direct gear AND child variants get a 'Base'
-- child injected so the base set remains separately selectable.  The parent
-- k4 node becomes a folder-only node (has_gear=false) and never pretends to
-- be an equipable set.
--
-- Processing-order safe:
--   • Depth-4 first, depth-5 later: depth-4 creates gear leaf; when the
--     first depth-5 arrives, Base is injected and parent is demoted.
--   • Depth-5 first, depth-4 later: placeholder folder is created for k4;
--     when depth-4 arrives and the folder already has children, Base is
--     injected for the depth-4 set instead of upgrading the folder directly.
local function place_ws_leaf(ws_folder, assignment)
    local keys = assignment.keys
    local k4   = keys[4]

    if #keys == 3 then
        -- sets.precast.WS → Base WS, flat under Weapon Skills.
        add_leaf(ws_folder, 'Base WS', assignment)

    elseif #keys == 4 then
        -- sets.precast.WS[k4]: named WS base set.
        local existing = ws_folder.child_map[k4]
        if existing and not existing.has_gear then
            if #existing.children > 0 then
                -- Placeholder folder already has variant children (depth-5 arrived
                -- first).  Inject a Base child for this set instead of upgrading
                -- the folder, so the base set is separately selectable.
                inject_base_child(existing, assignment)
            else
                -- Empty placeholder; upgrade it in-place (no variants yet).
                existing.has_gear     = true
                existing.assignment   = assignment
                existing.path         = assignment.keys
                existing.organized_leaf = true
            end
        else
            add_leaf(ws_folder, k4, assignment)
        end

    else
        -- sets.precast.WS[k4].<variant...>: nest under the k4 parent.
        local ws_parent = ws_folder.child_map[k4]
        if not ws_parent then
            ws_parent = ensure_folder(ws_folder, k4)
        end
        -- If the parent already carries direct gear, demote it to a folder
        -- and inject a 'Base' child so the base gear remains selectable.
        if ws_parent.has_gear then
            if not ws_parent.child_map['Base'] then
                inject_base_child(ws_parent, ws_parent.assignment)
                ws_parent.has_gear      = false
                ws_parent.assignment    = nil
                ws_parent.organized_leaf = false
            end
        end
        add_leaf(ws_parent, join_from(keys, 5), assignment)
    end
end

function organized_tree.build_organized_tree(assignments)
    reset_order()
    local root = new_node('Gear Sets', { 'sets' })
    for _, assignment in ipairs(assignments or {}) do
        if has_direct_gear_slots(assignment) then
            local keys = assignment.keys
            if keys[2] == 'precast' and keys[3] == 'WS' then
                -- WS paths use dedicated nesting so named-WS nodes can hold
                -- both an assignment and variant children.
                local ws_folder = ensure_folder(ensure_folder(root, 'Actions'), 'Weapon Skills')
                place_ws_leaf(ws_folder, assignment)
            else
                local parent = root
                local label = organized_tree.leaf_label(assignment)
                local route_parts = trim_redundant_terminal_folder(organized_tree.get_organized_route(assignment), label)
                for _, folder in ipairs(route_parts) do
                    parent = ensure_folder(parent, folder)
                end
                add_leaf(parent, label, assignment)
            end
        end
    end
    prune_empty_folders(root)
    apply_folder_order(root)
    return root
end

organized_tree.build = organized_tree.build_organized_tree

return organized_tree
