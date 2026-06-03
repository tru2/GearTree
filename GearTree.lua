-- GearTree
-- A Windower addon that parses your currently-loaded Gearswap user file,
-- builds a clickable tree of gear sets, and equips them via `gs equip`.

_addon.name    = 'GearTree'
_addon.author  = 'Tru + Codex'
_addon.version = '0.4.0'
_addon.commands = { 'geartree', 'gt' }

require('logger')
config = require('config')

local parser = require('parser')
local tree   = require('tree')
local organized_tree = require('organized_tree')
local layout = require('layout')
local ui     = require('ui_adapter')
local snapshot = require('snapshot')
local writer   = require('writer')
local gear_slots = require('gear_slots')
local res     = require('resources')
local extdata = require('extdata')
local category_debug = require('category_debug')

----------------------------------------------------------------------
-- Settings (persisted to /addons/GearTree/data/settings.xml)
----------------------------------------------------------------------

local defaults = {
    pos_x = 100,
    pos_y = 100,
    width = 260,
    visible_rows = 22,
    ui_scale = 1.0,
    auto_load = true,
    -- Organized is the normal/user-friendly view. Raw remains available
    -- with //gt mode raw for debugging exact Lua structure.
    tree_mode = 'organized',
    edit_mode = true,
    -- When true, plain arrow keys pass through to FFXI and Shift+Arrow controls GearTree.
    shift_arrow_nav = false,
    last_set_path = '',
    last_undo_backup = '',
    last_undo_file = '',
    last_undo_set_path = '',
    -- If set, always parse this file. If empty, try to auto-detect
    -- the loaded Gearswap user file.
    gear_file_override = '',
    -- Optional command used by //gt open to jump to a source line.
    -- Tokens: {file}, {line}. Leave empty to auto-detect common editors,
    -- then fall back to the Windows default .lua file association.
    -- Examples:
    --   code -g "{file}:{line}"
    --   notepad++ -n{line} "{file}"
    --   subl "{file}:{line}"
    source_editor_command = '',
    -- Mouse activation: 'on' (default) = left click activates rows/tabs.
    -- 'off' = hover only; keyboard navigation is the interaction method.
    mouse_mode = 'on',
    -- Visual-only ornate cursor overlay drawn at the mouse while GearTree is
    -- visible.  Uses cursor.png from the active theme when present, otherwise
    -- falls back to a primitive crosshair.  Does not affect click behavior.
    cursor_overlay = true,
    -- Active visual theme.  Names map to subfolders under themes/.
    theme = 'jeuno',
    -- Global window opacity: 35-100 (100 = fully opaque).  Scales all background
    -- and frame elements while leaving text fully readable.
    opacity = 100,
    -- When false (default during UI cleanup), saved layout values in settings.xml
    -- are ignored on load and //gt calib save is a no-op.  Set true to re-enable
    -- persistence once the layout is stable.
    layout_calibration_enabled = false,
    -- Layout calibration metrics (edited via //gt calib).  Defaults match the
    -- renderer's built-in values, so an empty/missing table changes nothing.
    -- Old saved tables missing the newer keys simply fall back to these defaults.
    layout = {
        chrome_inset    = 6,
        content_top_pad = 10,
        header_x_offset = 0,
        header_y_offset = 0,
        header_w_adjust = 0,
        header_h_adjust = 0,
        header_text_x_offset = 0,
        header_text_y_offset = 0,
        tab_x_offset    = 0,
        tab_y_offset    = 0,
        tab_w_adjust    = 0,
        tab_h_adjust    = 0,
        tab_right_trim  = 0,
        preview_tab_text_x_offset = 0,
        preview_tab_text_y_offset = 0,
        tree_header_text_x_offset = 0,
        tree_header_text_y_offset = 0,
        content_x_offset = 0,
        content_w_adjust = 0,
        footer_x_offset = 0,
        footer_y_offset = 2,
        footer_w_adjust = 0,
        footer_h_adjust = 0,
        footer_text_x_offset = 0,
        footer_text_y_offset = 0,
    },
}

local settings = config.load(defaults)

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

local current_root = nil
local current_file = nil
local current_assignments = {}
local current_gear_references = {}
local baselines = {}
local edit_mode = settings.edit_mode ~= false
local shift_arrow_nav = settings.shift_arrow_nav == true
local active_edit_path = nil
local active_edit_node = nil
local last_auto_equip_path = nil
local live_changes = {}
local live_change_path = nil
local live_change_count = 0
local live_change_signature = nil
local next_live_check_at = 0
local inventory_locations = { items = {}, items_by_id = {}, bags = {} }
local next_inventory_scan_at = 0
local load_file
local ensure_ui

-- Keyboard controls are only bound while GearTree is visible.
-- Enter is intentionally not used because it conflicts with normal FFXI chat/input.
local NAV_KEYS = {
    up     = 'up',
    down   = 'down',
    expand = 'right',
    back   = 'left',
    equip  = 'end',
    close  = 'escape',
}

local nav_keys_bound = false

local NAV_REPEAT_KEYS = {
    [200] = 'up',
    [208] = 'down',
    [203] = 'left',
    [205] = 'right',
}

local SHIFT_KEYS = {
    [42] = true,
    [54] = true,
}

local NAV_REPEAT_INITIAL_DELAY = 0.32
local NAV_REPEAT_INTERVAL = 0.075
local LIVE_CHECK_INTERVAL = 0.5
local INVENTORY_SCAN_INTERVAL = 5
local nav_repeat_action = nil
local nav_repeat_next_at = 0
local shift_toggle_down = false

local CHAT = {
    info = 207,
    success = 158,
    warn = 57,
    error = 167,
    detail = 160,
}

local function gt_chat(color, message)
    if windower and windower.add_to_chat then
        windower.add_to_chat(color, '[GearTree] ' .. message)
    else
        log(message)
    end
end

local function clear_nav_repeat()
    nav_repeat_action = nil
    nav_repeat_next_at = 0
end

local function clear_shift_toggle()
    shift_toggle_down = false
end

local function begin_nav_repeat(action)
    if nav_repeat_action == action then return end
    nav_repeat_action = action
    nav_repeat_next_at = os.clock() + NAV_REPEAT_INITIAL_DELAY
end

local function end_nav_repeat(action)
    if nav_repeat_action == action then
        clear_nav_repeat()
    end
end

local function run_nav_repeat_action(action)
    if action == 'up' then
        ui.cursor_up()
    elseif action == 'down' then
        ui.cursor_down()
    elseif action == 'left' then
        if ui.cursor_left then ui.cursor_left(true) end
    elseif action == 'right' then
        if ui.cursor_right then ui.cursor_right(true) end
    end
end


local function bind_nav_keys()
    if nav_keys_bound then return end
    -- shift_arrow_nav on: bind ~arrow (Windower Shift modifier) so plain arrows pass through.
    -- shift_arrow_nav off: bind plain arrows as normal.
    local p = shift_arrow_nav and '~' or ''
    windower.send_command('bind ' .. p .. NAV_KEYS.up     .. ' gt up')
    windower.send_command('bind ' .. p .. NAV_KEYS.down   .. ' gt down')
    windower.send_command('bind ' .. p .. NAV_KEYS.expand .. ' gt expand')
    windower.send_command('bind ' .. p .. NAV_KEYS.back   .. ' gt back')
    windower.send_command('bind ' .. NAV_KEYS.equip .. ' gt equip')
    windower.send_command('bind ' .. NAV_KEYS.close .. ' gt hide')
    nav_keys_bound = true
end

local function unbind_nav_keys()
    if not nav_keys_bound then return end
    -- Defensively unbind both plain and Shift-modified arrow variants so a
    -- mode toggle or reload never leaves stale binds in Windower.
    windower.send_command('unbind up')
    windower.send_command('unbind down')
    windower.send_command('unbind right')
    windower.send_command('unbind left')
    windower.send_command('unbind ~up')
    windower.send_command('unbind ~down')
    windower.send_command('unbind ~right')
    windower.send_command('unbind ~left')
    windower.send_command('unbind ' .. NAV_KEYS.equip)
    windower.send_command('unbind ' .. NAV_KEYS.close)
    clear_nav_repeat()
    clear_shift_toggle()
    nav_keys_bound = false
end

local function normalized_tree_mode()
    local mode = tostring(settings.tree_mode or 'organized'):lower()
    if mode == 'raw' then return 'raw' end
    if mode == 'organized' or mode == 'organised' then return 'organized' end
    return 'organized'
end

local function tree_mode_label()
    return normalized_tree_mode() == 'organized' and 'Organized Tree' or 'Raw Lua Tree'
end

local function build_tree_for_mode(assignments)
    local root
    if normalized_tree_mode() == 'organized' then
        root = organized_tree.build(assignments)
    else
        root = tree.build(assignments)
    end
    return layout.apply(root)
end

local function parse_gear_references_from_source(refs, src)
    local function skip_ws(text, pos)
        while pos <= #text do
            local ch = text:sub(pos, pos)
            if ch ~= ' ' and ch ~= '\t' and ch ~= '\r' and ch ~= '\n' then
                return pos
            end
            pos = pos + 1
        end
        return pos
    end

    local function decode_lua_escape(ch, next_ch)
        if next_ch == 'n' then return '\n' end
        if next_ch == 'r' then return '\r' end
        if next_ch == 't' then return '\t' end
        if next_ch == '\\' then return '\\' end
        if next_ch == '"' then return '"' end
        if next_ch == "'" then return "'" end
        return next_ch
    end

    local function parse_quoted(text, pos)
        local quote = text:sub(pos, pos)
        local i = pos + 1
        local out = {}
        while i <= #text do
            local ch = text:sub(i, i)
            if ch == '\\' then
                local next_ch = text:sub(i + 1, i + 1)
                if next_ch == '' then
                    break
                end
                out[#out + 1] = decode_lua_escape(ch, next_ch)
                i = i + 2
            elseif ch == quote then
                return table.concat(out), i + 1
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return nil, pos
    end

    local function parse_balanced(text, pos, open_char, close_char)
        local depth = 0
        local i = pos
        local start = pos
        local quote = nil

        while i <= #text do
            local ch = text:sub(i, i)
            if quote then
                if ch == '\\' then
                    i = i + 2
                elseif ch == quote then
                    quote = nil
                    i = i + 1
                else
                    i = i + 1
                end
            elseif ch == '"' or ch == "'" then
                quote = ch
                i = i + 1
            elseif ch == open_char then
                depth = depth + 1
                i = i + 1
            elseif ch == close_char then
                depth = depth - 1
                i = i + 1
                if depth == 0 then
                    return text:sub(start, i - 1), i
                end
            else
                i = i + 1
            end
        end
        return nil, pos
    end

    local function parse_augment_list(text)
        local list = {}
        local pos = 1
        while pos <= #text do
            local ch = text:sub(pos, pos)
            if ch == '"' or ch == "'" then
                local value, next_pos = parse_quoted(text, pos)
                if value then
                    list[#list + 1] = value
                    pos = next_pos
                else
                    pos = pos + 1
                end
            else
                pos = pos + 1
            end
        end
        return list
    end

    local function parse_alias_body(body)
        local name = body:match('name%s*=%s*"([^"]+)"') or body:match("name%s*=%s*'([^']+)'")
        local augments = nil
        local aug_key = body:find('augments%s*=%s*{')
        if aug_key then
            local start = body:find('{', aug_key)
            if start then
                local block, _ = parse_balanced(body, start, '{', '}')
                if block then
                    local inner = block:sub(2, -2)
                    local list = parse_augment_list(inner)
                    if #list > 0 then
                        augments = list
                    end
                end
            end
        end
        return name, augments
    end

    local function remember(name, item, augments)
        if name and item and item ~= '' then
            refs['gear.' .. name] = {
                name = item,
                augments = augments,
                augmented = type(augments) == 'table' and #augments > 0 or (augments ~= nil and augments ~= ''),
            }
        end
    end

    local pos = 1
    while true do
        local start_pos, end_pos, name = src:find('gear%.([%a_][%w_]*)%s*=%s*', pos)
        if not start_pos then break end

        local value_pos = skip_ws(src, end_pos + 1)
        local first = src:sub(value_pos, value_pos)
        if first == '"' or first == "'" then
            local item, next_pos = parse_quoted(src, value_pos)
            remember(name, item, nil)
            pos = next_pos > value_pos and next_pos or (end_pos + 1)
        elseif first == '{' then
            local body, next_pos = parse_balanced(src, value_pos, '{', '}')
            if body then
                remember(name, parse_alias_body(body))
                pos = next_pos
            else
                pos = end_pos + 1
            end
        else
            pos = end_pos + 1
        end
    end

    for name, item in src:gmatch('gear%.([%a_][%w_]*)%s*=%s*"([^"\r\n]+)"') do
        remember(name, item)
    end
    for name, item in src:gmatch("gear%.([%a_][%w_]*)%s*=%s*'([^'\r\n]+)'") do
        remember(name, item)
    end
end

local function read_gear_references(refs, path)
    local f = io.open(path, 'r')
    if not f then return end
    local src = f:read('*a') or ''
    f:close()
    parse_gear_references_from_source(refs, src)
end

local function gear_reference_paths(path)
    local paths = {path}
    local dir = path:match('^(.*[/\\])') or ''
    local file = path:match('[^/\\]+$') or ''
    local character = file:match('^([^_%-]+)[_%-]')

    if character and dir ~= '' then
        paths[#paths + 1] = dir .. character .. '-Items.lua'
        paths[#paths + 1] = dir .. character .. '-Globals.lua'
        paths[#paths + 1] = dir .. character .. '_Items.lua'
        paths[#paths + 1] = dir .. character .. '_Globals.lua'
    end

    return paths
end

local function parse_gear_references(path)
    local refs = {}
    local seen = {}

    for _, reference_path in ipairs(gear_reference_paths(path)) do
        if reference_path and not seen[reference_path] then
            seen[reference_path] = true
            read_gear_references(refs, reference_path)
        end
    end

    return refs
end

local STORAGE_BAGS = {
    { id = 0,  label = 'Inventory',  equip_ready = true },
    { id = 1,  label = 'Mog Safe',   equip_ready = false },
    { id = 2,  label = 'Storage',    equip_ready = false },
    { id = 3,  label = 'Temporary',  equip_ready = false },
    { id = 4,  label = 'Mog Locker', equip_ready = false },
    { id = 5,  label = 'Satchel',    equip_ready = false },
    { id = 6,  label = 'Sack',       equip_ready = false },
    { id = 7,  label = 'Case',       equip_ready = false },
    { id = 8,  label = 'Wardrobe 1', equip_ready = true },
    { id = 9,  label = 'Mog Safe 2', equip_ready = false },
    { id = 10, label = 'Wardrobe 2', equip_ready = true },
    { id = 11, label = 'Wardrobe 3', equip_ready = true },
    { id = 12, label = 'Wardrobe 4', equip_ready = true },
    { id = 13, label = 'Wardrobe 5', equip_ready = true },
    { id = 14, label = 'Wardrobe 6', equip_ready = true },
    { id = 15, label = 'Wardrobe 7', equip_ready = true },
    { id = 16, label = 'Wardrobe 8', equip_ready = true },
}

local function normalize_item_name(name)
    local text = tostring(name or '')
    text = text:gsub("%c", " ")
    text = text:gsub("’", "'"):gsub("‘", "'")
    text = text:gsub("\194\160", " ")
    text = text:lower()
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

local function inventory_item_name(item)
    if not item or not item.id or item.id == 0 then return nil end
    local r = res.items[item.id]
    return r and (r.english or r.en or r.name) or nil
end

local function normalize_augment_text(augment)
    if augment == nil then return nil end
    augment = tostring(augment)
    augment = augment:gsub('^%s+', ''):gsub('%s+$', '')
    if augment == '' or augment == 'none' then return nil end
    return augment
end

local function inventory_item_augments(item)
    local ok, decoded = pcall(extdata.decode, item)
    if not ok or not decoded or type(decoded.augments) ~= 'table' then
        return {}, false, nil, nil, nil
    end

    local out = {}
    for _, augment in ipairs(decoded.augments) do
        augment = normalize_augment_text(augment)
        if augment then
            out[#out + 1] = augment
        end
    end
    return out, true, decoded.path, decoded.rank, decoded.augment_system
end

local function max_bag_index(bag)
    local max_index = tonumber(bag and bag.max) or tonumber(bag and bag.size) or 0
    for key in pairs(bag or {}) do
        if type(key) == 'number' and key > max_index then
            max_index = key
        end
    end
    return max_index
end

local function read_bag_info(id)
    if not windower or not windower.ffxi or not windower.ffxi.get_bag_info then
        return nil
    end

    local ok, info = pcall(windower.ffxi.get_bag_info, id)
    if ok and type(info) == 'table' then
        return info
    end

    return nil
end

local function bag_is_available(info, fallback_max)
    if type(info) == 'table' then
        if info.enabled == false then return false end
        return (tonumber(info.max) or 0) > 0
    end

    return (tonumber(fallback_max) or 0) > 0
end

local function scan_inventory_locations(force)
    if not windower or not windower.ffxi or not windower.ffxi.get_items then
        return inventory_locations
    end

    local now = os.clock()
    if not force and now < next_inventory_scan_at then
        return inventory_locations
    end
    next_inventory_scan_at = now + INVENTORY_SCAN_INTERVAL

    local locations = { items = {}, items_by_id = {}, bags = {} }

    for _, def in ipairs(STORAGE_BAGS) do
        local info = read_bag_info(def.id)
        local ok, bag = pcall(windower.ffxi.get_items, def.id)
        local got_bag = ok and type(bag) == 'table'
        local fallback_max = got_bag and max_bag_index(bag) or 0
        local available = bag_is_available(info, fallback_max)
        local max_index = tonumber(info and info.max) or fallback_max
        local scan_max = got_bag and math.max(max_index, fallback_max) or 0
        local count = tonumber(info and info.count) or (got_bag and tonumber(bag.count)) or nil

        locations.bags[#locations.bags + 1] = {
            id = def.id,
            label = def.label,
            equip_ready = def.equip_ready,
            available = available,
            count = count,
            max = max_index,
        }

        if got_bag then
            for index = 1, scan_max do
                local item = bag[index]
                if type(item) ~= 'table' then
                    local ok_item, slot_item = pcall(windower.ffxi.get_items, def.id, index)
                    if ok_item and type(slot_item) == 'table' then
                        item = slot_item
                    end
                end
                if type(item) == 'table' and item.id and item.id ~= 0 then
                    local name = inventory_item_name(item)
                    if name then
                        local key = normalize_item_name(name)
                        locations.items[key] = locations.items[key] or {}
                        local augments, augments_available, aug_path, aug_rank, augment_system = inventory_item_augments(item)
                        local entry = {
                            id = item.id,
                            name = name,
                            extdata = item.extdata,
                            augments = augments,
                            augments_available = augments_available,
                            aug_path = aug_path,
                            aug_rank = aug_rank,
                            augment_system = augment_system,
                            bag = def.id,
                            index = index,
                            label = def.label,
                            equip_ready = def.equip_ready,
                            available = available,
                        }
                        locations.items[key][#locations.items[key] + 1] = entry
                        locations.items_by_id[item.id] = locations.items_by_id[item.id] or {}
                        locations.items_by_id[item.id][#locations.items_by_id[item.id] + 1] = entry
                    end
                end
            end
        end
    end

    inventory_locations = locations
    return inventory_locations
end

local function node_path_id(node)
    if not node or not node.path then return nil end
    local parts = {}
    for i = 1, #node.path do
        parts[#parts + 1] = tostring(node.path[i])
    end
    return table.concat(parts, '\31')
end

local function capture_expanded_paths(root)
    local expanded = {}
    local function walk(node)
        if not node then return end
        local id = node_path_id(node)
        if id and node.expanded then expanded[id] = true end
        for _, child in ipairs(node.children or {}) do walk(child) end
    end
    walk(root)
    return expanded
end

local function restore_expanded_paths(root, expanded)
    if not root or not expanded then return end
    local function walk(node)
        local id = node_path_id(node)
        if id and expanded[id] then node.expanded = true end
        for _, child in ipairs(node.children or {}) do walk(child) end
    end
    walk(root)
end

local function rebuild_current_tree()
    local expanded = capture_expanded_paths(current_root)
    current_root = build_tree_for_mode(current_assignments or {})
    restore_expanded_paths(current_root, expanded)
    if current_root then ui.rebuild(current_root) end
end

local function display_parent_of(target)
    if not current_root or not target then return nil end

    local function walk(parent)
        for _, child in ipairs(parent.children or {}) do
            if child == target then return parent end
            local found = walk(child)
            if found then return found end
        end
        return nil
    end

    return walk(current_root)
end

local function is_root_node(node)
    return node == current_root or (node and node.path and #node.path == 1 and node.path[1] == 'sets')
end

local function node_display_name(node)
    if not node then return '' end
    if node.virtual then return tostring(node.key or '') end
    return tree.path_string(node)
end

local function walk_display_nodes(fn)
    local function walk(node)
        if not node then return nil end
        local result = fn(node)
        if result then return result end
        for _, child in ipairs(node.children or {}) do
            result = walk(child)
            if result then return result end
        end
        return nil
    end
    return walk(current_root)
end

local function find_display_node(query, predicate)
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if query == '' then return nil, 'Name is empty.' end

    local q = query:lower()
    local matches = {}

    walk_display_nodes(function(node)
        if node ~= current_root and (not predicate or predicate(node)) then
            local key = tostring(node.key or '')
            local path = node_display_name(node)
            if key:lower() == q or path:lower() == q then
                matches[#matches + 1] = node
            end
        end
    end)

    if #matches == 0 then
        walk_display_nodes(function(node)
            if node ~= current_root and (not predicate or predicate(node)) then
                local key = tostring(node.key or '')
                local path = node_display_name(node)
                if key:lower():find(q, 1, true) or path:lower():find(q, 1, true) then
                    matches[#matches + 1] = node
                end
            end
        end)
    end

    if #matches == 0 then return nil, 'No match: ' .. query end
    if #matches > 1 then return nil, 'Multiple matches for ' .. query .. '. Use more of the Lua path.' end
    return matches[1]
end

local function find_layout_path_node(query)
    return find_display_node(query, function(node)
        return not node.virtual and node.path and not is_root_node(node)
    end)
end

local function selected_layout_path_node()
    local node = ui.get_selected_node and ui.get_selected_node() or nil
    if node and not node.virtual and node.path and not is_root_node(node) then
        return node
    end
    return nil, 'Highlight a Lua set or folder first.'
end

local function selected_or_parent_container_ref()
    local node = ui.get_selected_node and ui.get_selected_node() or nil

    if node and node.virtual then
        return layout.ref_for_node(node, current_root)
    end

    if node and node.children and #node.children > 0 and not is_root_node(node) then
        return layout.ref_for_node(node, current_root)
    end

    local parent = display_parent_of(node)
    if parent then return layout.ref_for_node(parent, current_root) end
    return 'root'
end

local function select_after_layout(path, folder_id)
    if not current_root then return end
    if path and ui.select_path and ui.select_path(path) then return end
    if folder_id and ui.select_virtual_folder and ui.select_virtual_folder(folder_id) then return end
end

local function save_layout_and_rebuild(select_path, select_folder_id)
    local ok, err = layout.save()
    if not ok then
        gt_chat(CHAT.error, 'Layout save failed: ' .. tostring(err))
        return false
    end

    rebuild_current_tree()
    select_after_layout(select_path, select_folder_id)
    if ui.refresh then ui.refresh() end
    return true
end

local function remember_last_saved_set(path)
    settings.last_set_path = path or ''
    settings:save()

    if ui.set_last_saved then
        ui.set_last_saved(settings.last_set_path)
    end
    if ui.set_status then
        ui.set_status(settings.last_set_path ~= '' and ('Last saved: ' .. settings.last_set_path) or '')
    end
end

local function select_last_saved_set()
    local path = tostring(settings.last_set_path or '')
    if path == '' then
        gt_chat(CHAT.warn, 'No last saved set yet.')
        return false
    end
    if not ensure_ui() then return false end
    if ui.set_last_saved then ui.set_last_saved(path) end
    if ui.select_path and ui.select_path(path) then
        gt_chat(CHAT.info, 'Highlighted last saved set: ' .. path)
        return true
    end
    gt_chat(CHAT.warn, 'Last saved set is not in the current tree: ' .. path)
    return false
end

----------------------------------------------------------------------
-- Helpers: find the Gearswap user file
----------------------------------------------------------------------

-- Try the standard Gearswap data folder. Falls back through common locations.
-- Mote-style files are typically named <CharName>_<JOB>_Gear.lua and live in
-- one of these directories (per gearswap.lua):
--   ../Windower4/addons/GearSwap/data/<character>/
--   ../Windower4/addons/GearSwap/data/common/
--   ../Windower4/addons/GearSwap/data/
local function candidate_dirs()
    local wp = windower.windower_path or ''
    local pp = windower.addon_path:gsub('GearTree[/\\]?$', '') -- /addons/
    local char = (windower.ffxi and windower.ffxi.get_player and
                  windower.ffxi.get_player() and windower.ffxi.get_player().name) or ''
    return {
        wp .. 'addons/GearSwap/data/' .. char .. '/',
        wp .. 'addons/GearSwap/data/common/',
        wp .. 'addons/GearSwap/data/',
        pp .. 'GearSwap/data/' .. char .. '/',
        pp .. 'GearSwap/data/common/',
        pp .. 'GearSwap/data/',
    }
end

local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function read_file(path)
    local f, err = io.open(path, 'r')
    if not f then return nil, err end
    local src = f:read('*a')
    f:close()
    return src
end

local function write_file(path, src)
    local f, err = io.open(path, 'w+')
    if not f then return nil, err end
    f:write(src)
    f:close()
    return true
end

-- Build candidate filenames using the player's current job and name.
local function candidate_filenames()
    local p = windower.ffxi and windower.ffxi.get_player and windower.ffxi.get_player()
    if not p then return {} end
    local name = p.name or ''
    local job = (p.main_job or ''):upper()
    local job_lc = (p.main_job or ''):lower()
    local job_cap = job_lc:sub(1, 1):upper() .. job_lc:sub(2)
    return {
        name .. '_' .. job_cap .. '_Gear.lua',
        name .. '_' .. job .. '_Gear.lua',
        name .. '_' .. job_cap .. '.lua',
        name .. '_' .. job .. '.lua',
        job .. '.lua',
        job_cap .. '.lua',
    }
end

local function locate_gear_file()
    if settings.gear_file_override ~= '' then
        if file_exists(settings.gear_file_override) then
            return settings.gear_file_override
        end
        log('Override path not found: ' .. settings.gear_file_override)
    end
    for _, dir in ipairs(candidate_dirs()) do
        for _, name in ipairs(candidate_filenames()) do
            local p = dir .. name
            if file_exists(p) then return p end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Load / reload
----------------------------------------------------------------------

local function save_pos(x, y)
    settings.pos_x = x
    settings.pos_y = y
    settings:save()
end

local function is_equippable_leaf(node)
    return node and node.has_gear and not (node.children and #node.children > 0)
end

local function change_rows(path, baseline, changes)
    local rows = {}
    for _, slot in ipairs(gear_slots.ordered_changes(changes or {})) do
        rows[#rows + 1] = {
            slot = slot,
            before = snapshot.describe_item(baseline and baseline[slot]),
            after = snapshot.describe_item(changes[slot]),
        }
    end
    return rows
end

local function change_signature(changes, count)
    local parts = { tostring(count or 0) }
    for _, slot in ipairs(gear_slots.ordered_changes(changes or {})) do
        parts[#parts + 1] = slot .. '=' .. snapshot.describe_item(changes[slot])
    end
    return table.concat(parts, '|')
end

local function copy_changes(changes)
    local out = {}
    for slot, item in pairs(changes or {}) do
        out[slot] = item
    end
    return out
end

local function changed_slot_names(changes)
    local slots = {}
    for _, slot in ipairs(gear_slots.ordered_changes(changes or {})) do
        slots[#slots + 1] = slot
    end
    return slots
end

local function gear_reference_key(value)
    local raw = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return raw:match('^(gear%.[%a_][%w_]*)$')
end

local function unresolved_alias_replacements(node, changes)
    local notes = {}
    local slots = node and node.assignment and node.assignment.rhs and node.assignment.rhs.slots or {}

    for _, slot in ipairs(gear_slots.ordered_changes(changes or {})) do
        local raw_value = slots[slot]
        local ref = gear_reference_key(raw_value)
        if ref and not current_gear_references[ref] then
            local item = changes and changes[slot] or nil
            local item_name = (item and item.name) or snapshot.describe_item(item)
            notes[#notes + 1] = string.format(
                '%s: unresolved alias %s replaced inline with %s',
                slot,
                ref,
                tostring(item_name or 'unknown')
            )
        end
    end

    return notes
end

local function publish_changes(path, baseline, changes, count)
    live_changes = copy_changes(changes)
    live_change_path = path
    live_change_count = count or 0
    live_change_signature = change_signature(changes, count)
    if ui.set_changes then
        ui.set_changes(path, change_rows(path, baseline, changes), live_change_count)
    end
end

local function clear_live_changes()
    live_changes = {}
    live_change_path = nil
    live_change_count = 0
    live_change_signature = nil
    if ui.clear_changes then ui.clear_changes() end
end

local function publish_current_equipment(path, equipment)
    if ui.set_current_equipment then
        ui.set_current_equipment(path, equipment)
    end
end

local function publish_inventory_locations(locations)
    if ui.set_inventory_locations then
        ui.set_inventory_locations(locations)
    end
end

local function refresh_inventory_locations(force)
    publish_inventory_locations(scan_inventory_locations(force))
end

local function clear_current_equipment()
    if ui.clear_current_equipment then
        ui.clear_current_equipment()
    end
end

local function clear_inventory_locations()
    inventory_locations = { items = {}, items_by_id = {}, bags = {} }
    next_inventory_scan_at = 0
    if ui.clear_inventory_locations then
        ui.clear_inventory_locations()
    end
end

-- Re-capture current equipment and refresh the Gear tab display.
-- Called automatically after equipping a set (at 1s, 3s, 6s) and on
-- demand via //gt snap.  Does not update the save baseline.
local function refresh_equipment_display(path)
    if active_edit_path ~= path then return end
    local later = snapshot.capture()
    if later then
        publish_current_equipment(path, later)
        refresh_inventory_locations(false)
    end
end

local function capture_baseline_for(node)
    local path = tree.path_string(node)
    active_edit_path = path
    active_edit_node = node
    next_live_check_at = 0
    -- First capture at 1s: stores the save baseline and seeds the display.
    coroutine.schedule(function()
        if active_edit_path ~= path then return end
        local shot, err = snapshot.capture()
        if shot then
            baselines[path] = shot
            publish_current_equipment(path, shot)
            refresh_inventory_locations(true)
            if active_edit_path == path then
                publish_changes(path, shot, {}, 0)
            end
            gt_chat(CHAT.info, 'Ready to edit: ' .. path)
        else
            gt_chat(CHAT.error, 'Could not capture edit baseline: ' .. (err or 'unknown error'))
        end
    end, 1)
    -- Two follow-up display refreshes at 3s and 6s so the Gear tab
    -- reflects post-equip state even when GearSwap or the server is slow.
    coroutine.schedule(function() refresh_equipment_display(path) end, 3)
    coroutine.schedule(function() refresh_equipment_display(path) end, 6)
end

-- ── Paired-slot equip retry ──────────────────────────────────────────────────
-- FFXI/GearSwap cannot swap paired ear or ring items in one equip pass when the
-- item needs to cross from one side to the other.
--
-- Example: current left_ear=Moonshade, right_ear=Thrud; target left_ear=Thrud,
-- right_ear=Brutal.  GearSwap equips Brutal to right_ear but cannot move Thrud
-- from right_ear to left_ear in the same pass.  The fix: detect the pattern and
-- re-send the identical gs equip command ~0.65s later.

local PAIRED_SLOT_PAIRS = {
    { 'left_ear',  'right_ear'  },
    { 'left_ring', 'right_ring' },
}

-- Extract a plain item name from a raw Lua value string captured by the parser.
-- Handles: "Item Name", 'Item Name', or { name="Item Name", augments={...} }.
local function slot_name_from_lua_value(val)
    if not val then return nil end
    val = val:gsub('^%s+', ''):gsub('%s+$', '')
    local plain = val:match('^["\'](.+)["\']$')
    if plain then return plain end
    local from_table = val:match('[Nn]ame%s*=%s*["\']([^"\']+)["\']')
    if from_table then return from_table end
    return nil
end

local function names_equal(a, b)
    if not a or not b then return false end
    a = tostring(a):lower():match('^%s*(.-)%s*$')
    b = tostring(b):lower():match('^%s*(.-)%s*$')
    return a == b
end

-- Inspect equipped paired slots vs target set slots.  If an item would need to
-- cross from one side of a pair to the other (e.g. right_ear → left_ear),
-- schedule one delayed re-send of the equip command so FFXI can complete the
-- move on the second pass.  Logs per-pair state at CHAT.detail level always.
local function maybe_schedule_paired_retry(node, cmd, path)
    local assignment = node and node.assignment
    local rhs        = assignment and assignment.rhs
    if not rhs then return end
    local target_slots = rhs.slots or {}

    local current, cur_err = snapshot.capture()
    if not current then
        gt_chat(CHAT.detail, 'Paired-slot check: could not read current equipment: ' .. tostring(cur_err or '?'))
        return
    end

    local risk = false

    for _, pair in ipairs(PAIRED_SLOT_PAIRS) do
        local sl, sr = pair[1], pair[2]
        local cur_l = current[sl] and not current[sl].empty and current[sl].name or nil
        local cur_r = current[sr] and not current[sr].empty and current[sr].name or nil
        local tgt_l = slot_name_from_lua_value(target_slots[sl])
        local tgt_r = slot_name_from_lua_value(target_slots[sr])

        gt_chat(CHAT.detail,
            'Paired-slot [' .. sl .. '/' .. sr .. '] '
            .. 'cur=' .. (cur_l or 'empty') .. '/' .. (cur_r or 'empty') .. ' '
            .. 'tgt=' .. (tgt_l or '?') .. '/' .. (tgt_r or '?'))

        -- Cross-move: target wants an item currently in the opposite slot of the pair.
        local l_needs_cross = tgt_l and cur_r and names_equal(tgt_l, cur_r)
        local r_needs_cross = tgt_r and cur_l and names_equal(tgt_r, cur_l)

        if l_needs_cross or r_needs_cross then
            local why = {}
            if l_needs_cross then why[#why+1] = tgt_l .. ' (' .. sr .. ' → ' .. sl .. ')' end
            if r_needs_cross then why[#why+1] = tgt_r .. ' (' .. sl .. ' → ' .. sr .. ')' end
            gt_chat(CHAT.detail, 'Paired-slot retry scheduled: ' .. table.concat(why, ', '))
            risk = true
        end
    end

    if not risk then return end

    coroutine.schedule(function()
        if active_edit_path ~= path then
            gt_chat(CHAT.detail, 'Paired-slot retry skipped: path changed to ' .. tostring(active_edit_path))
            return
        end
        gt_chat(CHAT.detail, 'Paired-slot retry: ' .. cmd)
        windower.send_command(cmd)
    end, 0.65)
end

local function equip_node(node, cmd)
    local path = tree.path_string(node)
    if not cmd then
        gt_chat(CHAT.warn, 'Skipping auto-equip for ' .. path .. ': command could not be serialized safely.')
        return
    end
    last_auto_equip_path = path
    gt_chat(CHAT.detail, 'Equip command: ' .. cmd)
    -- Capture current state BEFORE sending so the pre-equip snapshot is accurate.
    maybe_schedule_paired_retry(node, cmd, path)
    windower.send_command(cmd)
    capture_baseline_for(node)
end

local function re_equip_after_gearswap_reload(node, cmd)
    if not node or not cmd then return end
    coroutine.schedule(function()
        if not ui.is_visible or not ui.is_visible() then return end
        last_auto_equip_path = nil
        equip_node(node, cmd)
    end, 2)
end

local function handle_selection_changed(node)
    if not edit_mode or not ui.is_visible or not ui.is_visible() then return end

    if not is_equippable_leaf(node) then
        active_edit_path = nil
        active_edit_node = nil
        last_auto_equip_path = nil
        clear_live_changes()
        clear_current_equipment()
        clear_inventory_locations()
        return
    end

    local path = tree.path_string(node)
    if path == last_auto_equip_path then return end

    local cmd, cmd_err = tree.equip_command(node)
    if not cmd then
        gt_chat(CHAT.warn, 'Skipping auto-equip for ' .. path .. ': ' .. tostring(cmd_err or 'command could not be serialized safely.'))
        return
    end

    last_auto_equip_path = path
    equip_node(node, cmd)
end

local function update_live_changes(force)
    if not edit_mode or not ui.is_visible or not ui.is_visible() then return end
    if not active_edit_path then return end

    local now = os.clock()
    if not force and now < next_live_check_at then return end
    next_live_check_at = now + LIVE_CHECK_INTERVAL

    local node = ui.get_selected_node and ui.get_selected_node() or active_edit_node
    if not is_equippable_leaf(node) then return end

    local path = tree.path_string(node)
    if path ~= active_edit_path then
        handle_selection_changed(node)
        return
    end

    local baseline = baselines[path]
    if not baseline then return end

    local current = snapshot.capture()
    if not current then return end
    publish_current_equipment(path, current)
    refresh_inventory_locations(false)

    local changes, count = snapshot.diff(baseline, current)
    local sig = change_signature(changes, count)
    if sig == live_change_signature then return end

    publish_changes(path, baseline, changes, count)
end

local function warn_unsaved_on_hide()
    update_live_changes(true)
    if live_change_count > 0 and active_edit_path then
        gt_chat(CHAT.warn, string.format('Hidden with %d unsaved changes to %s', live_change_count, active_edit_path))
    end
end

local function stop_edit_tracking()
    active_edit_path = nil
    active_edit_node = nil
    last_auto_equip_path = nil
    next_live_check_at = 0
    clear_live_changes()
    clear_current_equipment()
    clear_inventory_locations()
end

local function show_save_feedback(path, changes, baseline, result, alias_notes, extra_lines)
    gt_chat(CHAT.success, 'Saved ' .. path)
    for _, slot in ipairs(gear_slots.ordered_changes(changes)) do
        local before = snapshot.describe_item(baseline and baseline[slot])
        local after = snapshot.describe_item(changes[slot])
        gt_chat(CHAT.detail, '  ' .. slot .. ': ' .. before .. ' -> ' .. after)
    end
    for _, note in ipairs(alias_notes or {}) do
        gt_chat(CHAT.detail, '  ' .. note)
    end
    for _, line in ipairs(extra_lines or {}) do
        gt_chat(CHAT.detail, '  ' .. line)
    end
    if result and result.backup then
        gt_chat(CHAT.detail, 'Backup created: ' .. result.backup)
    end
    gt_chat(CHAT.info, 'GearSwap reload queued.')
end

local function remember_undo_backup(file_path, set_path, result)
    if not result or not result.backup then return end
    settings.last_undo_backup = result.backup
    settings.last_undo_file = file_path or ''
    settings.last_undo_set_path = set_path or ''
    settings:save()
end

local function finish_save(node, path, baseline, current, changes, result, alias_notes, extra_lines)
    local saved_slots = changed_slot_names(changes)
    remember_last_saved_set(path)
    if ui.set_recent_saved_slots then
        ui.set_recent_saved_slots(path, saved_slots)
    end
    load_file(current_file, true)
    baselines[path] = current
    publish_current_equipment(path, current)
    publish_changes(path, current, {}, 0)
    if ui.set_recent_saved_slots then
        ui.set_recent_saved_slots(path, saved_slots)
    end
    remember_undo_backup(current_file, path, result)
    show_save_feedback(path, changes, baseline, result, alias_notes, extra_lines)
    windower.send_command('gs reload')
    local cmd, cmd_err = tree.equip_command(node)
    if not cmd then
        gt_chat(CHAT.warn, 'Skipping re-equip after save for ' .. path .. ': ' .. tostring(cmd_err or 'command could not be serialized safely.'))
        return
    end
    gt_chat(CHAT.detail, 'Re-equip command: ' .. cmd)
    re_equip_after_gearswap_reload(node, cmd)
end

load_file = function(path, keep_baselines)
    if not path then
        log('No gear file specified or detected. Use `//gt load <path>` to set one.')
        return false
    end
    if not file_exists(path) then
        log('File not found: ' .. path)
        return false
    end
    local assignments, err = parser.parse_file(path)
    if not assignments then
        log('Parse failed: ' .. (err or 'unknown error'))
        return false
    end
    local expanded = capture_expanded_paths(current_root)
    current_assignments = assignments
    layout.load_for(path)
    current_root = build_tree_for_mode(assignments)
    restore_expanded_paths(current_root, expanded)
    current_file = path
    current_gear_references = parse_gear_references(path)
    if ui.set_gear_reference_items then
        ui.set_gear_reference_items(current_gear_references)
    end
    if not keep_baselines then
        baselines = {}
        stop_edit_tracking()
    end
    log(string.format('Loaded %d sets from %s (%s)', #assignments, path, tree_mode_label()))
    if current_root then
        local last_path = tostring(settings.last_set_path or '')
        if ui.set_last_saved then ui.set_last_saved(last_path) end
        ui.rebuild(current_root)
        if ui.set_status then
            ui.set_status(last_path ~= '' and ('Last saved: ' .. last_path) or '')
        end
    end
    return true
end

local function set_tree_mode(mode)
    mode = tostring(mode or ''):lower()
    if mode == '' then
        log('Tree mode: ' .. tree_mode_label() .. '. Use //gt mode raw, //gt mode organized, or //gt mode toggle.')
        return
    elseif mode == 'toggle' then
        mode = normalized_tree_mode() == 'organized' and 'raw' or 'organized'
    elseif mode == 'organised' then
        mode = 'organized'
    end

    if mode ~= 'raw' and mode ~= 'organized' then
        log('Usage: //gt mode raw | organized | toggle')
        return
    end

    if normalized_tree_mode() == mode then
        log('Tree mode already set to ' .. tree_mode_label())
        return
    end

    settings.tree_mode = mode
    settings:save()
    rebuild_current_tree()
    log('Tree mode set to ' .. tree_mode_label())
end

local function set_edit_mode(value)
    edit_mode = value and true or false
    settings.edit_mode = edit_mode
    settings:save()

    if edit_mode then
        gt_chat(CHAT.info, 'Edit mode on.')
        if ui.is_visible and ui.is_visible() then
            handle_selection_changed(ui.get_selected_node and ui.get_selected_node() or nil)
        end
    else
        stop_edit_tracking()
        gt_chat(CHAT.info, 'Edit mode off.')
    end
end

local function handle_edit_command(arg)
    arg = tostring(arg or 'toggle'):lower()
    if arg == '' or arg == 'toggle' then
        set_edit_mode(not edit_mode)
    elseif arg == 'on' or arg == 'true' or arg == '1' then
        set_edit_mode(true)
    elseif arg == 'off' or arg == 'false' or arg == '0' then
        set_edit_mode(false)
    else
        gt_chat(CHAT.warn, 'Usage: //gt edit [on|off|toggle]')
    end
end

local function set_shift_arrow_nav(value)
    -- Unbind with the old prefix, update state, rebind with the new prefix.
    local was_bound = nav_keys_bound
    if was_bound then unbind_nav_keys() end
    shift_arrow_nav = value and true or false
    settings.shift_arrow_nav = shift_arrow_nav
    settings:save()
    if was_bound then bind_nav_keys() end
    if shift_arrow_nav then
        gt_chat(CHAT.info, 'Shift-arrow navigation enabled. Plain arrows pass through to FFXI.')
    else
        gt_chat(CHAT.info, 'Shift-arrow navigation disabled. Plain arrows control GearTree.')
    end
end

local function handle_shift_command(arg)
    arg = tostring(arg or 'status'):lower()
    if arg == 'on' or arg == 'true' or arg == '1' then
        set_shift_arrow_nav(true)
    elseif arg == 'off' or arg == 'false' or arg == '0' then
        set_shift_arrow_nav(false)
    elseif arg == 'status' or arg == '' then
        gt_chat(CHAT.info, 'Shift-arrow navigation: ' .. (shift_arrow_nav and 'on' or 'off') .. '.')
    else
        gt_chat(CHAT.warn, 'Usage: //gt shift [on|off|status]')
    end
end

local function handle_mouse_mode_command(arg)
    arg = tostring(arg or 'status'):lower()
    -- Backward compat: map old mode names to current 'on'/'off'.
    if arg == 'normal' or arg == 'left' then arg = 'on' end
    if arg == 'shift' or arg == 'right' then arg = 'off' end
    if arg == 'on' then
        settings.mouse_mode = 'on'
        settings:save()
        ui.set_mouse_mode('on')
        gt_chat(CHAT.info, 'Mouse activation: on. Left click controls GearTree.')
    elseif arg == 'off' then
        settings.mouse_mode = 'off'
        settings:save()
        ui.set_mouse_mode('off')
        gt_chat(CHAT.info, 'Mouse activation: off. Hover only; use keyboard controls to interact.')
    elseif arg == 'status' or arg == '' then
        -- ui.get_mouse_mode() reads the live cfg value, not just the saved setting.
        local live = ui.get_mouse_mode and ui.get_mouse_mode() or tostring(settings.mouse_mode or 'on')
        if live == 'off' then
            gt_chat(CHAT.info, 'Mouse activation: off. Hover only; use keyboard controls to interact.')
        else
            gt_chat(CHAT.info, 'Mouse activation: on. Left click controls GearTree.')
        end
    else
        gt_chat(CHAT.warn, 'Usage: //gt mouse [on|off|status]')
    end
end

local function handle_cursor_command(arg)
    arg = tostring(arg or 'status'):lower()
    if arg == 'on' then
        settings.cursor_overlay = true
        settings:save()
        if ui.set_cursor_overlay then ui.set_cursor_overlay(true) end
        gt_chat(CHAT.info, 'Cursor overlay: on. A crosshair follows the mouse inside GearTree.')
    elseif arg == 'off' then
        settings.cursor_overlay = false
        settings:save()
        if ui.set_cursor_overlay then ui.set_cursor_overlay(false) end
        gt_chat(CHAT.info, 'Cursor overlay: off.')
    elseif arg == 'status' or arg == '' then
        local live = ui.get_cursor_overlay and ui.get_cursor_overlay() or (settings.cursor_overlay == true)
        gt_chat(CHAT.info, 'Cursor overlay: ' .. (live and 'on' or 'off') .. '.')
    else
        gt_chat(CHAT.warn, 'Usage: //gt cursor [on|off|status]')
    end
end

-- Print the actual computed frame/background/zone bounds (read-only diagnostic).
local function handle_bginfo_command()
    local lines = ui.bounds_lines and ui.bounds_lines() or {}
    gt_chat(CHAT.info, 'Background / layout bounds:')
    for _, line in ipairs(lines) do
        if windower and windower.add_to_chat then
            windower.add_to_chat(CHAT.detail, line)
        else
            log(line)
        end
    end
end

local function handle_scale_command(arg)
    arg = tostring(arg or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if arg == '' then
        local s = ui.get_scale and ui.get_scale() or (settings.ui_scale or 1.0)
        gt_chat(CHAT.info, string.format('UI scale: %.2f  (range 0.75-2.0, default 1.0)', s))
        return
    elseif arg == 'reset' then
        settings.ui_scale = 1.0
        settings:save()
        if ui.set_scale then ui.set_scale(1.0) end
        gt_chat(CHAT.info, 'UI scale reset to 1.0.')
        return
    end
    local s = tonumber(arg)
    if not s then
        gt_chat(CHAT.warn, 'Usage: //gt scale [0.75-2.0 | reset]  e.g. //gt scale 1.25')
        return
    end
    s = math.max(0.75, math.min(s, 2.0))
    settings.ui_scale = s
    settings:save()
    if ui.set_scale then ui.set_scale(s) end
    gt_chat(CHAT.info, string.format('UI scale set to %.2f', s))
end

local function handle_opacity_command(arg)
    arg = tostring(arg or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if arg == '' then
        local cur = ui.get_opacity and ui.get_opacity() or (settings.opacity or 100)
        gt_chat(CHAT.info, string.format('UI opacity: %d%%  (range 35-100, default 100)', cur))
        return
    elseif arg == 'reset' then
        settings.opacity = 100
        settings:save()
        if ui.set_opacity then ui.set_opacity(100) end
        gt_chat(CHAT.info, 'UI opacity reset to 100%.')
        return
    end
    local pct = tonumber(arg)
    if not pct then
        gt_chat(CHAT.warn, 'Usage: //gt opacity | //gt opacity <35-100> | //gt opacity reset')
        return
    end
    pct = math.max(35, math.min(100, math.floor(pct)))
    settings.opacity = pct
    settings:save()
    if ui.set_opacity then ui.set_opacity(pct) end
    gt_chat(CHAT.info, string.format('UI opacity set to %d%%.', pct))
end

-- Layout calibration tool (distinct from the folder //gt layout command).
local function handle_calib_command(arg)
    arg = tostring(arg or ''):lower()
    if arg == 'on' then
        if ui.set_layout_mode then ui.set_layout_mode(true) end
        gt_chat(CHAT.info, 'Layout calibration: on. Drag the guide boxes to align sections; drag a box bottom edge to resize. //gt calib save to persist.')
    elseif arg == 'off' then
        if ui.set_layout_mode then ui.set_layout_mode(false) end
        gt_chat(CHAT.info, 'Layout calibration: off.')
    elseif arg == 'save' then
        if settings.layout_calibration_enabled ~= true then
            gt_chat(CHAT.warn, 'Layout calibration persistence is disabled during UI cleanup. Use //gt calib print to inspect values.')
        else
            if ui.get_layout then settings.layout = ui.get_layout() end
            settings:save()
            gt_chat(CHAT.info, 'Layout calibration saved to settings.')
        end
    elseif arg == 'reset' then
        local def = ui.reset_layout and ui.reset_layout() or nil
        if settings.layout_calibration_enabled ~= true then
            gt_chat(CHAT.info, 'Layout calibration reset to live defaults. (Persistence disabled — settings.xml not written.)')
        else
            if def then settings.layout = def end
            settings:save()
            gt_chat(CHAT.info, 'Layout calibration reset to defaults (saved).')
        end
    elseif arg == 'print' then
        local lines = ui.layout_lines and ui.layout_lines() or {}
        gt_chat(CHAT.info, 'Current layout metrics (copyable):')
        -- Use a colored addon line (no prefix) so the table stays copyable and
        -- does not look like white /say chat.
        for _, line in ipairs(lines) do
            if windower and windower.add_to_chat then
                windower.add_to_chat(CHAT.detail, line)
            else
                log(line)
            end
        end
    elseif arg == 'bounds' or arg == 'bginfo' then
        handle_bginfo_command()
    else
        gt_chat(CHAT.warn, 'Usage: //gt calib on|off|save|reset|print|bounds')
    end
end

-- ── Theme switching ──────────────────────────────────────────────────────────

local function apply_theme_by_name(name, recreate)
    if not ui.set_theme_name then return false end
    if not ui.set_theme_name(name) then
        gt_chat(CHAT.warn, 'Theme "' .. name .. '" not found. Check themes/' .. name .. '/panel_fill.png exists.')
        return false
    end
    if recreate then
        local was_visible = ui.is_visible and ui.is_visible()
        ui.destroy()
        ui.create(current_root, save_pos)
        if settings.layout_calibration_enabled == true and ui.set_layout then
            ui.set_layout(settings.layout)
        end
        ui.set_equip_callback(equip_node)
        if ui.set_selection_callback then ui.set_selection_callback(handle_selection_changed) end
        if was_visible then ui.show() end
    end
    return true
end

local function handle_theme_command(sub, name)
    sub  = tostring(sub  or ''):lower()
    name = tostring(name or ''):lower()

    if sub == '' then
        local cur = ui.get_theme_name and ui.get_theme_name() or settings.theme
        gt_chat(CHAT.info, 'Current theme: ' .. cur .. '.  //gt theme list | //gt theme <name> | //gt theme next')

    elseif sub == 'list' then
        local themes = ui.list_themes and ui.list_themes() or {}
        if #themes == 0 then
            gt_chat(CHAT.warn, 'No theme folders found under themes/.')
        else
            local cur = ui.get_theme_name and ui.get_theme_name() or settings.theme
            gt_chat(CHAT.info, 'Available themes:')
            for _, t in ipairs(themes) do
                local marker = (t == cur) and ' *' or ''
                windower.add_to_chat(CHAT.detail, '  ' .. t .. marker)
            end
        end

    elseif sub == 'next' then
        local themes = ui.list_themes and ui.list_themes() or {}
        if #themes == 0 then gt_chat(CHAT.warn, 'No themes found.'); return end
        local cur = settings.theme
        local idx = 1
        for i, t in ipairs(themes) do if t == cur then idx = i; break end end
        local next_theme = themes[(idx % #themes) + 1]
        if apply_theme_by_name(next_theme, true) then
            settings.theme = next_theme
            settings:save()
            gt_chat(CHAT.info, 'Theme: ' .. next_theme)
        end

    elseif sub == 'reload' then
        local cur = settings.theme
        if apply_theme_by_name(cur, true) then
            gt_chat(CHAT.info, 'Theme "' .. cur .. '" reloaded.')
        end

    elseif sub ~= '' then
        -- Treat sub as the theme name (//gt theme <name>).
        if apply_theme_by_name(sub, true) then
            settings.theme = sub
            settings:save()
            gt_chat(CHAT.info, 'Theme set to "' .. sub .. '".')
        end

    else
        gt_chat(CHAT.warn, 'Usage: //gt theme [list | <name> | next | reload]')
    end
end

local function save_selected_set()
    if not current_file then
        gt_chat(CHAT.warn, 'No gear file is loaded. Use //gt auto or //gt load <path> first.')
        return
    end

    local node = ui.get_selected_node()
    if not node or not node.has_gear then
        gt_chat(CHAT.warn, 'Highlight a gear set first, then run //gt save.')
        return
    end

    local path = tree.path_string(node)
    local baseline = baselines[path]
    if not baseline then
        gt_chat(CHAT.warn, 'Equip this set from GearTree first, then change gear and run //gt save.')
        return
    end

    update_live_changes(true)

    local current, capture_err = snapshot.capture()
    if not current then
        gt_chat(CHAT.error, 'Could not read current equipment: ' .. (capture_err or 'unknown error'))
        return
    end

    publish_current_equipment(path, current)

    local changes = live_change_path == path and live_changes or {}
    local count = live_change_path == path and live_change_count or 0
    if count == 0 then
        gt_chat(CHAT.warn, 'No changed gear slots to save for ' .. path)
        return
    end

    local alias_notes = unresolved_alias_replacements(node, changes)

    local result, save_err = writer.save(current_file, node.assignment, changes)
    if not result then
        gt_chat(CHAT.error, 'Save failed: ' .. (save_err or 'unknown error'))
        return
    end

    if not result.changed then
        gt_chat(CHAT.warn, 'No file update needed for ' .. path)
        baselines[path] = current
        publish_current_equipment(path, current)
        publish_changes(path, current, {}, 0)
        return
    end

    finish_save(node, path, baseline, current, changes, result, alias_notes, nil)
end

local function handle_saveslot_command(args)
    if not ensure_ui() then return end

    if not current_file then
        gt_chat(CHAT.warn, 'No gear file is loaded. Use //gt auto or //gt load <path> first.')
        return
    end

    local slot = tostring(args and args[1] or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if slot == '' then
        gt_chat(CHAT.warn, 'Usage: //gt saveslot <slot>')
        return
    end

    local node = ui.get_selected_node()
    if not node or not node.has_gear then
        gt_chat(CHAT.warn, 'Highlight a gear set first, then run //gt saveslot.')
        return
    end

    local canonical = gear_slots.canonical(slot)
    if not canonical then
        gt_chat(CHAT.warn, 'Unknown gear slot: ' .. slot)
        return
    end

    local current, capture_err = snapshot.capture()
    if not current then
        gt_chat(CHAT.error, 'Could not read current equipment: ' .. (capture_err or 'unknown error'))
        return
    end

    local path = tree.path_string(node)
    publish_current_equipment(path, current)

    local item = current[canonical]
    if not item then
        gt_chat(CHAT.warn, 'No equipped item found in ' .. canonical .. '.')
        return
    end

    local changes = {}
    changes[canonical] = item

    local result, save_err = writer.save(current_file, node.assignment, changes)
    if not result then
        gt_chat(CHAT.error, 'Save failed: ' .. (save_err or 'unknown error'))
        return
    end

    local alias_notes = unresolved_alias_replacements(node, changes)
    local forced_note = string.format('%s forced saved -> %s', canonical, tostring(item.name or snapshot.describe_item(item)))
    finish_save(node, path, baselines[path], current, changes, result, alias_notes, { forced_note })
end

local function undo_last_save()
    local backup = tostring(settings.last_undo_backup or '')
    local file = tostring(settings.last_undo_file or '')
    local set_path = tostring(settings.last_undo_set_path or '')

    if backup == '' or file == '' then
        gt_chat(CHAT.warn, 'No GearTree save to undo.')
        return
    end
    if not file_exists(backup) then
        gt_chat(CHAT.error, 'Undo backup not found: ' .. backup)
        return
    end

    local src, read_err = read_file(backup)
    if not src then
        gt_chat(CHAT.error, 'Undo failed reading backup: ' .. tostring(read_err))
        return
    end

    local ok, write_err = write_file(file, src)
    if not ok then
        gt_chat(CHAT.error, 'Undo failed writing gear file: ' .. tostring(write_err))
        return
    end

    settings.last_undo_backup = ''
    settings.last_undo_file = ''
    settings.last_undo_set_path = ''
    settings:save()

    current_file = file
    load_file(file)
    gt_chat(CHAT.success, 'Undid last save' .. (set_path ~= '' and (' for ' .. set_path) or '') .. '.')
    windower.send_command('gs reload')
end

function ensure_ui()
    if current_root then return true end
    local f = locate_gear_file()
    if not f then
        log('Could not auto-detect gear file. Use `//gt load <path>`.')
        return false
    end
    if not load_file(f) then return false end
    return true
end

local function unresolved_gear_references()
    local seen = {}
    local refs = {}

    for _, assignment in ipairs(current_assignments or {}) do
        local slots = assignment.rhs and assignment.rhs.slots or {}
        for _, value in pairs(slots) do
            local ref = gear_reference_key(value)
            if ref and not current_gear_references[ref] and not seen[ref] then
                seen[ref] = true
                refs[#refs + 1] = ref
            end
        end
    end

    table.sort(refs)
    return refs
end


local function windows_quote(value)
    return '"' .. tostring(value or ''):gsub('"', '') .. '"'
end

local function command_exists(command)
    command = tostring(command or ''):gsub('"', '')
    if command == '' then return false end
    local ok = os.execute('cmd /c where ' .. command .. ' >nul 2>nul')
    return ok == true or ok == 0
end

local function expand_source_editor_command(template, file, line)
    local expanded = tostring(template or '')
    expanded = expanded:gsub('{file}', function() return file end)
    expanded = expanded:gsub('{line}', function() return tostring(line or 1) end)
    return expanded
end

local function run_source_open_command(command)
    if not command or command == '' then return false end
    local ok = os.execute(command)
    return ok == true or ok == 0
end

local function open_with_default_windows_app(file)
    -- start opens the file with the user's Windows file association for .lua.
    -- The empty quoted title is required when the path is quoted.
    return run_source_open_command('cmd /c start "" ' .. windows_quote(file))
end

local function first_existing_notepadpp()
    local candidates = {
        (os.getenv('ProgramFiles') or 'C:\\Program Files') .. '\\Notepad++\\notepad++.exe',
        (os.getenv('ProgramFiles(x86)') or 'C:\\Program Files (x86)') .. '\\Notepad++\\notepad++.exe',
    }

    for _, path in ipairs(candidates) do
        if file_exists(path) then return path end
    end

    return nil
end

local function open_source_at_line(file, line)
    line = tonumber(line) or 1

    local configured = tostring(settings.source_editor_command or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if configured ~= '' then
        local command = expand_source_editor_command(configured, file, line)
        if run_source_open_command(command) then
            return true, 'configured editor'
        end
        gt_chat(CHAT.warn, 'Configured editor command failed; falling back to auto/default open.')
    end

    -- VS Code, if its command-line launcher is available.
    if command_exists('code') then
        if run_source_open_command('cmd /c code -g ' .. windows_quote(file .. ':' .. tostring(line))) then
            return true, 'VS Code'
        end
    end

    -- Notepad++, if available in PATH or common install folders.
    if command_exists('notepad++') then
        if run_source_open_command('cmd /c notepad++ -n' .. tostring(line) .. ' ' .. windows_quote(file)) then
            return true, 'Notepad++'
        end
    else
        local notepadpp = first_existing_notepadpp()
        if notepadpp then
            if run_source_open_command(windows_quote(notepadpp) .. ' -n' .. tostring(line) .. ' ' .. windows_quote(file)) then
                return true, 'Notepad++'
            end
        end
    end

    -- Sublime Text, if available.
    if command_exists('subl') then
        if run_source_open_command('cmd /c subl ' .. windows_quote(file .. ':' .. tostring(line))) then
            return true, 'Sublime Text'
        end
    end

    if open_with_default_windows_app(file) then
        return true, 'default app'
    end

    return false, nil
end

local function open_selected_source()
    if not ensure_ui() then return end

    local node = ui.get_selected_node and ui.get_selected_node() or nil
    if not node then
        gt_chat(CHAT.warn, 'Highlight a Lua set first, then use //gt open.')
        return
    end

    local assignment = node.assignment
    if not assignment then
        gt_chat(CHAT.warn, 'The highlighted item has no direct source assignment to open.')
        return
    end

    if not current_file or current_file == '' then
        gt_chat(CHAT.warn, 'No gear file is loaded. Use //gt auto or //gt load <path> first.')
        return
    end

    local line = tonumber(assignment.line) or 1
    local ok, method = open_source_at_line(current_file, line)
    local short_file = current_file:match('[^/\\]+$') or current_file

    if ok then
        if method == 'default app' then
            gt_chat(CHAT.info, string.format('Opened %s with default app. Set starts near line %d.', short_file, line))
        else
            gt_chat(CHAT.info, string.format('Opened %s near line %d using %s.', short_file, line, method))
        end
    else
        gt_chat(CHAT.error, string.format('Could not open source file. File: %s line %d', current_file, line))
    end
end

local function show_status()
    update_live_changes(true)

    local selected = ui.get_selected_node and ui.get_selected_node() or nil
    local selected_path = selected and tree.path_string(selected) or 'none'
    local unresolved = unresolved_gear_references()
    local file = current_file or 'none'
    local visible = ui.is_visible and ui.is_visible() and 'shown' or 'hidden'

    gt_chat(CHAT.info, 'Status')
    gt_chat(CHAT.detail, 'File: ' .. file)
    gt_chat(CHAT.detail, 'Sets parsed: ' .. tostring(#(current_assignments or {})))
    gt_chat(CHAT.detail, 'Mode: ' .. normalized_tree_mode() .. ' | UI: ' .. visible .. ' | Edit: ' .. (edit_mode and 'on' or 'off'))
    gt_chat(CHAT.detail, 'Selected: ' .. selected_path)
    gt_chat(CHAT.detail, 'Unsaved changes: ' .. tostring(live_change_count or 0) .. (live_change_path and (' in ' .. live_change_path) or ''))
    gt_chat(CHAT.detail, 'Unresolved gear refs: ' .. tostring(#unresolved))

    for i = 1, math.min(5, #unresolved) do
        gt_chat(CHAT.detail, '  ' .. unresolved[i])
    end
    if #unresolved > 5 then
        gt_chat(CHAT.detail, '  ...and ' .. tostring(#unresolved - 5) .. ' more')
    end
end

local function handle_augdebug_command()
    if not ensure_ui() then return end

    local lines, err
    if ui.debug_selected_gear then
        lines, err = ui.debug_selected_gear()
    end
    if not lines then
        gt_chat(CHAT.warn, err or 'Select a gear row first.')
        return
    end

    gt_chat(CHAT.info, 'Augment debug')
    for _, line in ipairs(lines) do
        gt_chat(CHAT.detail, line)
    end
end
local function handle_why_command()
    if not ensure_ui() then return end

    local node = ui.get_selected_node and ui.get_selected_node() or nil
    local lines, err = category_debug.explain_node(node)

    if not lines then
        gt_chat(CHAT.warn, err or 'No category explanation is available for the highlighted item.')
        return
    end

    gt_chat(CHAT.info, 'Category explanation')
    for _, line in ipairs(lines) do
        gt_chat(CHAT.detail, line)
    end
end
local function handle_debugslot_command(args)
    local slot = table.concat(args or {}, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if slot == '' then
        gt_chat(CHAT.warn, 'Usage: //gt debugslot <slot>')
        return
    end

    if not ensure_ui() then return end

    local lines, err
    if ui.debug_selected_slot then
        lines, err = ui.debug_selected_slot(slot)
    end
    if not lines then
        gt_chat(CHAT.warn, err or 'Select a gear set first.')
        return
    end

    gt_chat(CHAT.info, 'Slot debug: ' .. slot)
    for _, line in ipairs(lines) do
        gt_chat(CHAT.detail, line)
    end
end

local function arg_text(args, first)
    local out = {}
    for i = first or 1, #(args or {}) do
        out[#out + 1] = tostring(args[i] or '')
    end
    return table.concat(out, ' '):gsub('^%s+', ''):gsub('%s+$', '')
end

local function folder_id_from_selected()
    local node = ui.get_selected_node and ui.get_selected_node() or nil
    if node and node.virtual then return node.virtual_id, nil end
    return nil, 'Highlight a virtual folder first.'
end

local function handle_find_command(args)
    local query = arg_text(args)
    if query == '' then
        gt_chat(CHAT.warn, 'Usage: //gt find <text>')
        return
    end
    if not ensure_ui() then return end
    if ui.find and ui.find(query) then
        local node = ui.get_selected_node and ui.get_selected_node() or nil
        gt_chat(CHAT.info, 'Found: ' .. (node and node_display_name(node) or query))
    else
        gt_chat(CHAT.warn, 'No set or folder matched: ' .. query)
    end
end

local function handle_make_command(args)
    if not ensure_ui() then return end

    local name = arg_text(args)
    local parent_ref = selected_or_parent_container_ref()
    if name:lower():match('%s+root$') then
        name = name:gsub('%s+[Rr][Oo][Oo][Tt]$', ''):gsub('%s+$', '')
        parent_ref = 'root'
    end

    if name == '' then
        gt_chat(CHAT.warn, 'Usage: //gt make <folder> [root]')
        return
    end

    local folder, err = layout.make_folder(name, parent_ref)
    if not folder then
        gt_chat(CHAT.error, err or 'Could not make folder.')
        return
    end

    if save_layout_and_rebuild(nil, folder.id) then
        gt_chat(CHAT.success, 'Made virtual folder: ' .. folder.name)
    end
end

local function move_path_to_folder(node, folder_name)
    if not node or node.virtual or not node.path or is_root_node(node) then
        gt_chat(CHAT.warn, 'Choose a Lua set or folder to move.')
        return
    end

    local folder, folder_err = layout.find_folder(folder_name)
    if not folder then
        gt_chat(CHAT.warn, folder_err or 'Virtual folder not found.')
        return
    end

    local path = layout.path_for_node(node)
    local ok, err = layout.move_path_to_folder(path, folder.id)
    if not ok then
        gt_chat(CHAT.error, err or 'Move failed.')
        return
    end

    if save_layout_and_rebuild(path) then
        gt_chat(CHAT.success, 'Moved ' .. path .. ' to ' .. folder.name)
    end
end

local function handle_move_here()
    local folder_id, folder_err = folder_id_from_selected()
    if not folder_id then
        gt_chat(CHAT.warn, folder_err .. ' Then use //gt move here to move the last saved set into it.')
        return
    end

    local path = tostring(settings.last_set_path or '')
    if path == '' then
        gt_chat(CHAT.warn, 'No last saved set to move here yet.')
        return
    end

    local ok, err = layout.move_path_to_folder(path, folder_id)
    if not ok then
        gt_chat(CHAT.error, err or 'Move failed.')
        return
    end

    if save_layout_and_rebuild(path) then
        gt_chat(CHAT.success, 'Moved last saved set here: ' .. path)
    end
end

local MOVE_DIRECTIONS = {
    up = true,
    down = true,
    top = true,
    bottom = true,
}

local function reorder_node(node, direction)
    if not node or is_root_node(node) then
        gt_chat(CHAT.warn, 'Choose a set or virtual folder to reorder.')
        return
    end

    local parent = display_parent_of(node)
    if not parent then
        gt_chat(CHAT.warn, 'Could not find this item in the display tree.')
        return
    end

    local refs = layout.item_refs(parent.children, current_root)
    local target_ref = layout.ref_for_node(node, current_root)
    local index = nil
    for i, ref in ipairs(refs) do
        if ref == target_ref then
            index = i
            break
        end
    end
    if not index then
        gt_chat(CHAT.warn, 'Could not reorder this item.')
        return
    end

    local new_index = index
    if direction == 'up' then
        new_index = math.max(1, index - 1)
    elseif direction == 'down' then
        new_index = math.min(#refs, index + 1)
    elseif direction == 'top' then
        new_index = 1
    elseif direction == 'bottom' then
        new_index = #refs
    end

    if new_index == index then
        gt_chat(CHAT.detail, 'Already at ' .. direction .. '.')
        return
    end

    table.remove(refs, index)
    table.insert(refs, new_index, target_ref)
    layout.set_order(layout.ref_for_node(parent, current_root), refs)

    local select_path = (not node.virtual) and layout.path_for_node(node) or nil
    local select_folder = node.virtual and node.virtual_id or nil
    if save_layout_and_rebuild(select_path, select_folder) then
        gt_chat(CHAT.success, 'Moved ' .. node_display_name(node) .. ' ' .. direction)
    end
end

local function handle_move_command(args)
    if not ensure_ui() then return end

    local text = arg_text(args)
    if text == '' then
        gt_chat(CHAT.warn, 'Usage: //gt move <set> to <folder> | //gt move [set] up/down/top/bottom | //gt move here')
        return
    end

    if text:lower() == 'here' then
        handle_move_here()
        return
    end

    local source_name, folder_name = text:match('^(.-)%s+[Tt][Oo]%s+(.+)$')
    if source_name and folder_name then
        local node, err = find_layout_path_node(source_name)
        if not node then
            gt_chat(CHAT.warn, err or 'Set not found.')
            return
        end
        move_path_to_folder(node, folder_name)
        return
    end

    local last_word = text:match('(%S+)$')
    local direction = last_word and last_word:lower() or ''
    if MOVE_DIRECTIONS[direction] then
        local source_text = text:sub(1, #text - #last_word):gsub('%s+$', '')
        local node, err
        if source_text == '' then
            node, err = ui.get_selected_node and ui.get_selected_node() or nil, nil
        else
            node, err = find_display_node(source_text, function(candidate)
                return not is_root_node(candidate)
            end)
        end
        if not node then
            gt_chat(CHAT.warn, err or 'Nothing selected to reorder.')
            return
        end
        reorder_node(node, direction)
        return
    end

    gt_chat(CHAT.warn, 'Usage: //gt move <set> to <folder> | //gt move [set] up/down/top/bottom | //gt move here')
end

local function handle_rename_command(args)
    if not ensure_ui() then return end

    local text = arg_text(args)
    if text == '' then
        gt_chat(CHAT.warn, 'Usage: //gt rename <new name> | //gt rename <folder> to <new name>')
        return
    end

    local old_name, new_name = text:match('^(.-)%s+[Tt][Oo]%s+(.+)$')
    local folder_id
    if old_name and new_name then
        local folder, err = layout.find_folder(old_name)
        if not folder then
            gt_chat(CHAT.warn, err or 'Virtual folder not found.')
            return
        end
        folder_id = folder.id
    else
        folder_id = folder_id_from_selected()
        new_name = text
    end

    if not folder_id then
        gt_chat(CHAT.warn, 'Highlight a virtual folder first, or use //gt rename <folder> to <new name>.')
        return
    end

    local ok, err = layout.rename_folder(folder_id, new_name)
    if not ok then
        gt_chat(CHAT.error, err or 'Rename failed.')
        return
    end

    if save_layout_and_rebuild(nil, folder_id) then
        gt_chat(CHAT.success, 'Renamed virtual folder to ' .. new_name)
    end
end

local function handle_remove_command(args)
    if not ensure_ui() then return end

    local text = arg_text(args)
    local folder_id
    if text == '' then
        folder_id = folder_id_from_selected()
    else
        local folder, err = layout.find_folder(text)
        if not folder then
            gt_chat(CHAT.warn, err or 'Virtual folder not found.')
            return
        end
        folder_id = folder.id
    end

    if not folder_id then
        gt_chat(CHAT.warn, 'Highlight a virtual folder first, or use //gt remove <folder>.')
        return
    end

    local ok, err = layout.remove_folder(folder_id)
    if not ok then
        gt_chat(CHAT.error, err or 'Remove failed.')
        return
    end

    if save_layout_and_rebuild() then
        gt_chat(CHAT.success, 'Removed virtual folder. Lua sets returned to their original display locations.')
    end
end

local function handle_unmove_command(args)
    if not ensure_ui() then return end

    local text = arg_text(args)
    local node, err
    if text == '' then
        node, err = selected_layout_path_node()
    else
        node, err = find_layout_path_node(text)
    end
    if not node then
        gt_chat(CHAT.warn, err or 'Set not found.')
        return
    end

    local path = layout.path_for_node(node)
    layout.unmove_path(path)
    if save_layout_and_rebuild(path) then
        gt_chat(CHAT.success, 'Returned to Lua order/location: ' .. path)
    end
end

local function handle_layout_command(args)
    if not ensure_ui() then return end

    local sub = tostring(args[1] or ''):lower()
    if sub == 'reset' then
        layout.reset()
        if save_layout_and_rebuild() then
            gt_chat(CHAT.success, 'Layout reset to Lua order.')
        end
    else
        gt_chat(CHAT.warn, 'Usage: //gt layout reset')
    end
end

----------------------------------------------------------------------
-- Mouse event handler
----------------------------------------------------------------------
-- Windower's mouse event delivers: type, x, y, delta, blocked
-- type: 0=move, 1=lmb-down, 2=lmb-up, 3/4=rmb, 7/10=wheel
-- We return true to block further propagation (e.g. for our own clicks).

windower.register_event('mouse', function(type, x, y, delta, blocked)
    if blocked then return false end
    if type == 0 then
        return ui.on_mouse_move(x, y)
    elseif type == 1 then
        -- Left-click: select/expand/equip row, or begin title drag.
        return ui.on_left_click(x, y)
    elseif type == 2 then
        return ui.on_left_up(x, y)
    elseif type == 3 then
        -- Right button down: activate in right mode, preview-cursor in left mode.
        return ui.on_right_click(x, y)
    elseif type == 4 then
        -- Right button up: no action. Right click never starts a drag, so there
        -- is no up-event cleanup needed (unlike LMB which uses on_left_up).
        return false
    elseif type == 5 or type == 6 then
        -- Middle mouse button: do not handle. Pass through to FFXI/Windower.
        return false
    elseif type == 7 or type == 10 then
        -- Scroll wheel: move cursor
        return ui.on_scroll(x, y, delta)
    end
    return false
end)

----------------------------------------------------------------------
-- Keyboard repeat
----------------------------------------------------------------------

windower.register_event('keyboard', function(dik, down)
    if SHIFT_KEYS[dik] then
        if down then
            shift_toggle_down = true
        else
            clear_shift_toggle()
            if shift_arrow_nav then clear_nav_repeat() end
        end
        return false
    end

    local action = NAV_REPEAT_KEYS[dik]
    if not action then return false end

    -- Both modes: binds handle the initial press; keyboard event drives repeat.
    if not nav_keys_bound then
        clear_nav_repeat()
        return false
    end

    if down then
        begin_nav_repeat(action)
    else
        end_nav_repeat(action)
    end

    return false
end)

windower.register_event('lose focus', function()
    clear_nav_repeat()
    clear_shift_toggle()
end)

windower.register_event('prerender', function()
    update_live_changes()

    if not nav_repeat_action then return end

    if not nav_keys_bound or not ui.is_visible() then
        clear_nav_repeat()
        return
    end

    local now = os.clock()
    if now < nav_repeat_next_at then return end

    run_nav_repeat_action(nav_repeat_action)
    nav_repeat_next_at = now + NAV_REPEAT_INTERVAL
end)

----------------------------------------------------------------------
-- Addon commands
----------------------------------------------------------------------

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or 'show'):lower()
    local args = { ... }

    if cmd == 'show' or cmd == 'on' then
        if not ensure_ui() then return end
        ui.show()
        bind_nav_keys()
        handle_selection_changed(ui.get_selected_node and ui.get_selected_node() or nil)
    elseif cmd == 'hide' or cmd == 'off' or cmd == 'close' then
        warn_unsaved_on_hide()
        ui.hide()
        unbind_nav_keys()
        stop_edit_tracking()
    elseif cmd == 'toggle' then
        if not ensure_ui() then return end
        if ui.is_visible() then
            warn_unsaved_on_hide()
            ui.hide()
            unbind_nav_keys()
            stop_edit_tracking()
        else
            ui.show()
            bind_nav_keys()
            handle_selection_changed(ui.get_selected_node and ui.get_selected_node() or nil)
        end
    elseif cmd == 'reload' or cmd == 'r' then
        if current_file then
            load_file(current_file)
        else
            ensure_ui()
        end
    elseif cmd == 'save' then
        if not ensure_ui() then return end
        save_selected_set()
    elseif cmd == 'saveslot' then
        handle_saveslot_command(args)
    elseif cmd == 'undo' then
        undo_last_save()
    elseif cmd == 'last' then
        select_last_saved_set()
    elseif cmd == 'open' or cmd == 'source' then
        open_selected_source()
    elseif cmd == 'find' then
        handle_find_command(args)
    elseif cmd == 'load' then
        local path = table.concat(args, ' ')
        if path == '' then
            log('Usage: //gt load <full path to gear file>')
            return
        end
        load_file(path)
    elseif cmd == 'auto' then
        local f = locate_gear_file()
        if f then
            log('Detected: ' .. f)
            load_file(f)
        else
            gt_chat(CHAT.warn, 'Could not detect a gear file for your current job.')
        end
    elseif cmd == 'mode' or cmd == 'tree' or cmd == 'view' then
        set_tree_mode(args[1])
    elseif cmd == 'edit' then
        handle_edit_command(args[1])
    elseif cmd == 'shift' then
        handle_shift_command(args[1])
    elseif cmd == 'mouse' then
        handle_mouse_mode_command(args[1])
    elseif cmd == 'cursor' then
        handle_cursor_command(args[1])
    elseif cmd == 'scale' then
        handle_scale_command(args[1])
    elseif cmd == 'opacity' then
        handle_opacity_command(args[1])
    elseif cmd == 'theme' or cmd == 'themes' then
        handle_theme_command(args[1], args[2])
    elseif cmd == 'calib' then
        handle_calib_command(args[1])
    elseif cmd == 'bginfo' or cmd == 'bounds' then
        handle_bginfo_command()
    elseif cmd == 'raw' then
        set_tree_mode('raw')
    elseif cmd == 'organized' or cmd == 'organised' then
        set_tree_mode('organized')
    elseif cmd == 'expandall' then
        if current_root then
            tree.expand_all(current_root)
            ui.refresh()
        end
    elseif cmd == 'collapseall' then
        if current_root then
            tree.collapse_all(current_root)
            ui.refresh()
        end
    elseif cmd == 'pos' then
        local x = tonumber(args[1])
        local y = tonumber(args[2])
        if x and y then
            ui.set_position(x, y)
            save_pos(x, y)
        else
            local cx, cy = ui.get_position()
            log(string.format('Position: %d, %d', cx, cy))
        end
    elseif cmd == 'up' then
        if not ensure_ui() then return end
        ui.cursor_up()
    elseif cmd == 'down' then
        if not ensure_ui() then return end
        ui.cursor_down()
    elseif cmd == 'equip' then
        if not ensure_ui() then return end
        if ui.cursor_equip then ui.cursor_equip() else ui.cursor_select() end
    elseif cmd == 'select' then
        if not ensure_ui() then return end
        ui.cursor_select()
    elseif cmd == 'expand' then
        if not ensure_ui() then return end
        if ui.cursor_right then ui.cursor_right() else ui.cursor_select() end
    elseif cmd == 'back' then
        if not ensure_ui() then return end
        if ui.cursor_left then ui.cursor_left() else ui.cursor_back() end
    elseif cmd == 'status' then
        show_status()
    elseif cmd == 'snap' then
        -- Force an immediate live snapshot refresh of the Gear tab display.
        local shot, err = snapshot.capture()
        if shot and active_edit_path then
            publish_current_equipment(active_edit_path, shot)
            refresh_inventory_locations(false)
            gt_chat(CHAT.info, 'Gear tab refreshed.')
        elseif shot then
            gt_chat(CHAT.warn, 'No active edit set — select a set first.')
        else
            gt_chat(CHAT.error, 'Snapshot failed: ' .. (err or 'unknown'))
        end
    elseif cmd == 'augdebug' or cmd == 'debugaug' then
        handle_augdebug_command()
    elseif cmd == 'why' or cmd == 'debugcat' then
        handle_why_command()
    elseif cmd == 'debugslot' then
        handle_debugslot_command(args)
    elseif cmd == 'debugstatus' then
        if not ensure_ui() then return end
        local lines, err
        if ui.debug_status_trace then
            lines, err = ui.debug_status_trace()
        end
        if not lines then
            gt_chat(CHAT.warn, err or 'Select a gear set first.')
        else
            for _, line in ipairs(lines) do gt_chat(CHAT.detail, line) end
        end
    elseif cmd == 'make' then
        handle_make_command(args)
    elseif cmd == 'move' then
        handle_move_command(args)
    elseif cmd == 'rename' then
        handle_rename_command(args)
    elseif cmd == 'remove' then
        handle_remove_command(args)
    elseif cmd == 'unmove' then
        handle_unmove_command(args)
    elseif cmd == 'layout' then
        handle_layout_command(args)
    elseif cmd == 'help' or cmd == '?' then
        log('GearTree  (//gt devhelp for dev/debug commands)')
        log('-- Basic --')
        log('  //gt show | hide | toggle')
        log('  //gt reload               - re-parse the current gear file')
        log('  //gt help')
        log('-- Navigation --')
        log('  Keyboard: Up/Down move, Right expand, Left back, End equip, Esc close')
        log('  Left-click a row to expand/equip. Drag the title bar to move the window.')
        log('  (//gt shift on to use Shift+Arrow instead of plain Arrow keys.)')
        log('  //gt find <text>          - jump to a matching set or folder')
        log('  //gt expandall | collapseall')
        log('  //gt last                 - jump back to the last saved set')
        log('-- Saving --')
        log('  //gt save                 - save changed equipped slots into highlighted set')
        log('  //gt saveslot <slot>      - force-save the equipped item in one slot')
        log('  //gt undo                 - restore the backup from the last GearTree save')
        log('-- Notes --')
        log('  //gt note <text>          - save a note on the highlighted set or folder')
        log('  //gt note                 - show the saved note for the highlighted set or folder')
        log('  //gt note clear           - clear the note for the highlighted set or folder')
        log('-- Views --')
        log('  //gt mode [raw|organized|toggle]  - switch tree display mode')
        log('-- Layout --')
        log('  //gt make <folder> [root] - add a virtual display folder')
        log('  //gt move <set> to <folder>')
        log('  //gt move [set] up|down|top|bottom')
        log('  //gt move here            - move the last saved set into the highlighted folder')
        log('  //gt rename <new>  |  //gt rename <folder> to <new>')
        log('  //gt remove [folder]  |  //gt unmove [set]  |  //gt layout reset')
        log('-- Settings --')
        log('  //gt shift [on|off|status]  - Shift+Arrow navigation (frees plain arrows for FFXI)')
        log('  //gt mouse [on|off|status]  - left-click activation (on by default)')
        log('  //gt cursor [on|off|status] - show mouse pointer inside GearTree (on by default)')
        log('  //gt scale [0.75-2.0|reset] - zoom level (default 1.0)')
        log('  //gt opacity [35-100|reset] - window transparency (100 = fully opaque)')
        log('  //gt pos [x y]              - show or set window position')
        log('Developer/debug commands: //gt devhelp')
    elseif cmd == 'devhelp' then
        log('GearTree dev/debug commands:')
        log('  //gt snap                  - force-refresh Gear tab from live equipment')
        log('  //gt augdebug | debugaug   - print augments and raw extdata for the selected gear row')
        log('  //gt debugslot <slot>      - print expected/equipped/storage details for one slot')
        log('  //gt debugstatus           - print slot/item/equipped/status trace for the selected set')
        log('  //gt why | debugcat        - explain why the selected set/folder is categorized as it is')
        log('  //gt calib [on|off|save|reset|print|bounds]  - drag-align UI sections')
        log('  //gt bginfo | bounds       - print frame/background/zone bounds')
        log('  //gt theme [list|<name>|next|reload]  - switch visual skin')
        log('  //gt status                - show loaded file, mode, selection, and live changes')
        log('  //gt edit [on|off|toggle]  - auto-equip highlighted sets and track live changes')
        log('  //gt open                  - open the highlighted set source near its Lua line')
        log('  //gt load <path>           - parse a specific gear file')
        log('  //gt auto                  - auto-detect gear file for the current job')
        log('Player commands: //gt help')
    else
        log('Unknown command: ' .. cmd .. '. Try //gt help')
    end
end)

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

windower.register_event('load', function()
    -- Build a placeholder root so UI can be created even before file is loaded
    current_assignments = {}
    current_root = build_tree_for_mode(current_assignments)

    ui.configure({
        pos_x = settings.pos_x,
        pos_y = settings.pos_y,
        width = settings.width,
        visible_rows = settings.visible_rows,
        ui_scale = settings.ui_scale,
        mouse_mode = settings.mouse_mode,
        cursor_overlay = settings.cursor_overlay,
        ui_opacity = settings.opacity or 100,
    })
    -- Load the persisted theme before creating UI objects.
    apply_theme_by_name(settings.theme or 'jeuno', false)
    ui.create(current_root, save_pos)
    -- Apply persisted layout calibration only when explicitly enabled.
    if settings.layout_calibration_enabled == true and ui.set_layout then
        ui.set_layout(settings.layout)
    end
    ui.set_equip_callback(equip_node)
    if ui.set_selection_callback then
        ui.set_selection_callback(handle_selection_changed)
    end

    if settings.auto_load then
        -- Defer until we're logged in (player info available)
        coroutine.schedule(function()
            local f = locate_gear_file()
            if f then load_file(f) end
        end, 2)
    end
end)

windower.register_event('unload', function()
    unbind_nav_keys()
    stop_edit_tracking()
    ui.destroy()
end)

-- Re-detect on job change
windower.register_event('job change', function()
    if settings.auto_load then
        coroutine.schedule(function()
            local f = locate_gear_file()
            if f then load_file(f) end
        end, 1)
    end
end)
