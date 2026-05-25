-- GearTree facelift UI
-- Windower text-overlay backend with a wider, multi-pane layout.

local tree      = require('tree')
local semantics = require('semantics')
local texts     = require('texts')
local images    = require('images')
local gear_slots = require('gear_slots')

local ui = {}

local cfg = {
    pos_x = 100,
    pos_y = 100,
    width = 205, -- legacy setting now means tree pane width
    visible_rows = 24,
    row_height = 16,
    font = 'Consolas',
    font_size = 10,

    gap = 6,
    header_height = 20,
    footer_height = 18,
    show_list_pane = false,
    list_width = 300,
    preview_width = 390,
    show_icons = false,
    icon_size = 10,

    bg_color = { 225, 6, 12, 18 },
    panel_bg = { 218, 7, 18, 28 },
    title_bg = { 235, 20, 34, 56 },
    title_fg = { 225, 210, 170 },
    active_title_bg = { 245, 46, 74, 110 },
    active_title_fg = { 255, 232, 150 },
    row_fg_set = { 220, 220, 215 },
    row_fg_cat = { 155, 198, 230 },
    row_fg_dim = { 132, 138, 145 },
    row_fg_gold = { 245, 210, 120 },
    row_fg_green = { 160, 230, 115 },
    row_fg_blue = { 120, 190, 255 },
    row_fg_violet = { 199, 146, 234 },
    row_fg_red = { 255, 105, 105 },
    row_fg_cursor = { 255, 244, 184 },
    row_bg_cursor = { 185, 42, 72, 120 },
    row_bg_changed = { 90, 199, 146, 234 },
}

function ui.configure(overrides)
    for k, v in pairs(overrides or {}) do
        if k == 'width' then
            cfg.width = math.max(190, math.min(tonumber(v) or cfg.width, 205))
        elseif cfg[k] ~= nil then
            cfg[k] = v
        end
    end
end

local state = {
    root = nil,
    flat = {},
    scroll = 0,
    cursor = 0,
    visible = false,
    drag = nil,
    save_pos_callback = nil,
    equip_callback = nil,
    preview_lines = {},
    preview_cards = { summary = {}, gear = {}, changes = {}, evidence = {} },
    preview_card = 'gear',
    preview_scroll = 0,
    source_cursor = 0,
    source_pan = 0,
    source_left_edge_until = 0,
    focus = 'tree',
    selection_callback = nil,
    last_selection_node = nil,
    live_changes = { path = nil, rows = {}, count = 0 },
    recent_saved = { path = nil, slots = {} },
    current_equipment = { path = nil, slots = {} },
    gear_reference_items = {},
    inventory_locations = { items = {}, bags = {} },
    status_text = '',
    last_saved_path = '',
    objects = {},
    image_objects = {},
    tree_rows = {},
    tree_icons = {},
    list_rows = {},
    list_icons = {},
    preview_rows = {},
    preview_aug_tags = {},
    preview_tab_bg = nil,
    preview_gear_title = nil,
    preview_changes_title = nil,
    preview_data_title = nil,
}

local auto_preview

local function clear_source_left_guard()
    state.source_left_edge_until = 0
end

local function dims()
    local tree_w = cfg.width
    local list_w = cfg.show_list_pane and cfg.list_width or 0
    local preview_w = cfg.preview_width
    local preview_x = cfg.pos_x + tree_w + cfg.gap
    if cfg.show_list_pane then
        preview_x = preview_x + list_w + cfg.gap
    end
    local total_w = preview_x - cfg.pos_x + preview_w
    local body_y = cfg.pos_y + cfg.header_height + 2
    local body_h = (cfg.visible_rows + 1) * cfg.row_height
    local footer_y = body_y + body_h + 8

    return {
        x = cfg.pos_x,
        y = cfg.pos_y,
        tree_x = cfg.pos_x,
        list_x = cfg.pos_x + tree_w + cfg.gap,
        preview_x = preview_x,
        body_y = body_y,
        footer_y = footer_y,
        tree_w = tree_w,
        list_w = list_w,
        preview_w = preview_w,
        total_w = total_w,
        body_h = body_h,
    }
end

local function cols(width)
    return math.max(12, math.floor(width / 7))
end

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function add_object(obj)
    state.objects[#state.objects + 1] = obj
    return obj
end

local function add_image(obj)
    state.image_objects[#state.image_objects + 1] = obj
    return obj
end

local function image_obj()
    local obj = images.new({
        draggable = false,
        visible = false,
        color = { alpha = 190, red = 255, green = 255, blue = 255 },
        size = { width = cfg.icon_size, height = cfg.icon_size },
        texture = { fit = true, path = '' },
    })
    return add_image(obj)
end

local function text_obj()
    local obj = texts.new({ flags = { draggable = false } })
    obj:font(cfg.font)
    obj:size(cfg.font_size)
    obj:stroke_transparency(255)
    obj:bg_visible(false)
    obj:bg_alpha(0)
    obj:visible(false)
    return add_object(obj)
end

local function panel_obj(width, rows)
    local obj = text_obj()
    obj:bg_visible(true)
    obj:bg_color(cfg.panel_bg[2], cfg.panel_bg[3], cfg.panel_bg[4])
    obj:bg_alpha(cfg.panel_bg[1])
    obj:color(cfg.row_fg_dim[1], cfg.row_fg_dim[2], cfg.row_fg_dim[3])

    local line = string.rep(' ', cols(width))
    local lines = {}
    for _ = 1, rows do
        lines[#lines + 1] = line
    end
    obj:text(table.concat(lines, '\n'))
    return obj
end

local function fill_panel(obj, width, rows)
    local line = string.rep(' ', cols(width))
    local lines = {}
    for _ = 1, rows do
        lines[#lines + 1] = line
    end
    obj:text(table.concat(lines, '\n'))
end

local function rendered_width(obj, fallback)
    if obj and obj.extents then
        local width = obj:extents()
        if type(width) == 'number' and width > 0 then
            return width
        end
    end
    return fallback
end

local function title_obj()
    local obj = text_obj()
    obj:bg_visible(true)
    obj:bg_color(cfg.title_bg[2], cfg.title_bg[3], cfg.title_bg[4])
    obj:bg_alpha(cfg.title_bg[1])
    obj:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    return obj
end

local function set_color(obj, color)
    obj:color(color[1], color[2], color[3])
end

local function set_title_active(obj, active)
    local bg = active and cfg.active_title_bg or cfg.title_bg
    local fg = active and cfg.active_title_fg or cfg.title_fg
    obj:bg_color(bg[2], bg[3], bg[4])
    obj:bg_alpha(bg[1])
    obj:color(fg[1], fg[2], fg[3])
end

local function truncate(text, max_cols)
    text = tostring(text or '')
    if #text <= max_cols then return text end
    if max_cols <= 3 then return text:sub(1, max_cols) end
    return text:sub(1, max_cols - 3) .. '...'
end

local function pad(text, max_cols)
    text = truncate(text, max_cols)
    return text .. string.rep(' ', math.max(0, max_cols - #text))
end

local function center_pad(text, max_cols)
    text = truncate(text, max_cols)
    local extra = math.max(0, max_cols - #text)
    local left = math.floor(extra / 2)
    local right = extra - left
    return string.rep(' ', left) .. text .. string.rep(' ', right)
end

local function node_kind(node)
    if not node then return ' ' end
    if node.children and #node.children > 0 then
        return node.expanded and '-' or '+'
    end
    return node.has_gear and '*' or ' '
end

local function asset_path(relative)
    local base = windower and windower.windower_path or ''
    if base ~= '' then
        if base:sub(-1) ~= '/' and base:sub(-1) ~= '\\' then
            base = base .. '/'
        end
        return base .. relative
    end
    return 'C:/Program Files (x86)/Windower/' .. relative
end

local ICONS = {
    current = asset_path('addons/trust/assets/icons/cursor_slot.png'),
    action = asset_path('addons/trust/assets/icons/icon_job_ability_light.png'),
    magic = asset_path('addons/trust/assets/icons/icon_light.png'),
    song = asset_path('addons/trust/assets/icons/icon_singing_light.png'),
    movement = asset_path('addons/trust/assets/icons/icon_wind.png'),
    defense = asset_path('addons/trust/assets/icons/icon_earth.png'),
    dark = asset_path('addons/trust/assets/icons/icon_dark.png'),
    fire = asset_path('addons/trust/assets/icons/icon_fire.png'),
    water = asset_path('addons/trust/assets/icons/icon_water.png'),
    weapon = asset_path('addons/trust/assets/icons/icon_bullet.png'),
    timer = asset_path('addons/trust/assets/icons/icon_timer.png'),
    cursor = asset_path('addons/trust/assets/icons/cursor.png'),
}

local function node_icon(node)
    local key = tostring(node and node.key or ''):lower()
    local path = {}
    if node and node.path then
        for _, part in ipairs(node.path) do
            path[#path + 1] = tostring(part):lower()
        end
    end
    local joined = table.concat(path, ' ')

    if key:find('song', 1, true) or key:find('lullaby', 1, true) or joined:find('song', 1, true) then
        return ICONS.song
    elseif key:find('magic', 1, true) or key == 'precast' or key == 'midcast' or joined:find('magic', 1, true) then
        return ICONS.magic
    elseif key:find('movement', 1, true) or key:find('kiting', 1, true) or key:find('move', 1, true) then
        return ICONS.movement
    elseif key:find('defense', 1, true) or key:find('defensive', 1, true) or key:find('pdt', 1, true) or key:find('mdt', 1, true) then
        return ICONS.defense
    elseif key:find('weapon', 1, true) or key:find('ranged', 1, true) or joined:find('weapon', 1, true) then
        return ICONS.weapon
    elseif key:find('dark', 1, true) then
        return ICONS.dark
    elseif key:find('elemental', 1, true) or key:find('nuk', 1, true) then
        return ICONS.fire
    elseif key:find('cure', 1, true) or key:find('healing', 1, true) then
        return ICONS.water
    elseif key:find('current', 1, true) or key == 'idle' or key == 'engaged' or key == 'resting' then
        return ICONS.current
    elseif key:find('action', 1, true) or key:find('abilit', 1, true) or key:find('waltz', 1, true) then
        return ICONS.action
    elseif node and node.has_gear then
        return ICONS.cursor
    end

    return ICONS.timer
end

local function path_string(node)
    if not node or not node.path then return '' end
    return tree.path_string(node)
end

local function walk_display(node, fn)
    if not node then return nil end
    local result = fn(node)
    if result then return result end
    for _, child in ipairs(node.children or {}) do
        result = walk_display(child, fn)
        if result then return result end
    end
    return nil
end

local function find_node_by_path(path)
    path = tostring(path or '')
    if path == '' then return nil end

    return walk_display(state.root, function(node)
        if node ~= state.root and not node.virtual and path_string(node) == path then
            return node
        end
    end)
end

local function find_virtual_folder(id)
    id = tostring(id or '')
    if id == '' then return nil end

    return walk_display(state.root, function(node)
        if node and node.virtual and tostring(node.virtual_id or '') == id then
            return node
        end
    end)
end

local function selected_entry()
    if state.cursor < 1 or state.cursor > #state.flat then return nil end
    return state.flat[state.cursor]
end

local function selected_node()
    local entry = selected_entry()
    return entry and entry.node or nil
end

local function is_equippable_leaf(node)
    return node and node.has_gear and not (node.children and #node.children > 0)
end

local function notify_selection_changed()
    local node = selected_node()
    if node == state.last_selection_node then return end
    state.last_selection_node = node
    if state.selection_callback then
        state.selection_callback(node)
    end
end

local function flat_index_for_node(node)
    for i, entry in ipairs(state.flat) do
        if entry.node == node then return i end
    end
    return nil
end

local function find_display_parent(target)
    if not state.root or not target then return nil end

    local function walk(parent)
        for _, child in ipairs(parent.children or {}) do
            if child == target then return parent end
            local found = walk(child)
            if found then return found end
        end
        return nil
    end

    return walk(state.root)
end

local function find_parent(node)
    local display_parent = find_display_parent(node)
    if display_parent then return display_parent end

    if not state.root or not node or not node.path or #node.path <= 2 then return nil end
    local parent_path = {}
    for i = 1, #node.path - 1 do
        parent_path[i] = node.path[i]
    end
    return tree.find(state.root, parent_path)
end

local function expand_ancestors(node)
    if not state.root or not node then return end

    local display_path = {}

    local function walk(parent)
        for _, child in ipairs(parent.children or {}) do
            display_path[#display_path + 1] = child
            if child == node then return true end
            if walk(child) then return true end
            display_path[#display_path] = nil
        end
        return false
    end

    if walk(state.root) then
        for i = 1, #display_path - 1 do
            display_path[i].expanded = true
        end
        return
    end

    if not node.path then return end

    local path = { node.path[1] }
    for i = 2, #node.path - 1 do
        path[i] = node.path[i]
        local ancestor = tree.find(state.root, path)
        if ancestor then ancestor.expanded = true end
    end
end

local function ensure_cursor_visible()
    local max_scroll = math.max(0, #state.flat - cfg.visible_rows)
    state.scroll = clamp(state.scroll, 0, max_scroll)

    if state.cursor <= state.scroll then
        state.scroll = math.max(0, state.cursor - 1)
    elseif state.cursor > state.scroll + cfg.visible_rows then
        state.scroll = state.cursor - cfg.visible_rows
    end
end

local function select_node(node)
    if not node then return end
    expand_ancestors(node)
    state.flat = tree.flatten(state.root)
    local idx = flat_index_for_node(node)
    if idx then
        state.cursor = idx
        ensure_cursor_visible()
    end
end

local function active_list_node()
    local node = selected_node()
    if not node then return state.root end
    if node.children and #node.children > 0 then return node end
    return find_parent(node) or node
end

local function active_list_items()
    local node = active_list_node()
    return node and node.children or {}
end

local function wrap_into(out, text, color, width)
    local max_cols = math.max(16, cols(width) - 2)
    local line = tostring(text or '')
    local prefix = line:match('^(%s*)') or ''

    repeat
        if #line <= max_cols then
            out[#out + 1] = { text = line, color = color }
            return
        end

        local cut
        for i = max_cols, #prefix + 2, -1 do
            local ch = line:sub(i, i)
            if ch == ' ' or ch == ',' or ch == '/' then
                cut = i
                break
            end
        end
        cut = cut or max_cols
        out[#out + 1] = { text = line:sub(1, cut):gsub('%s+$', ''), color = color }
        line = prefix .. line:sub(cut + 1):gsub('^%s+', '')
    until line == ''
end

local function add_line(out, text, color)
    out[#out + 1] = { text = tostring(text or ''), color = color or cfg.row_fg_set }
end

local function add_section(out, title)
    add_line(out, '', cfg.row_fg_set)
    add_line(out, '== ' .. title .. ' ==', cfg.row_fg_gold)
end

local function safe(value, fallback)
    if value == nil or tostring(value) == '' then return fallback or 'Unknown' end
    return tostring(value)
end

local function list_count(t)
    return type(t) == 'table' and #t or 0
end

local function source_line(node, info)
    local assignment = node and node.assignment or nil
    local file = info.source_file or info.file or assignment and assignment.source_file or assignment and assignment.file
    local line = info.line or info.start_line or assignment and assignment.line or assignment and assignment.start_line
    local end_line = info.end_line or assignment and assignment.end_line

    if file and line and end_line and tostring(line) ~= tostring(end_line) then
        return string.format('%s:%s-%s', tostring(file), tostring(line), tostring(end_line))
    elseif file and line then
        return string.format('%s:%s', tostring(file), tostring(line))
    elseif line then
        return 'line ' .. tostring(line)
    end
    return safe(info.source, 'Unknown source')
end

local function add_lua_source(out, node, width)
    local assignment = node and node.assignment or nil
    local source = assignment and assignment.source_text or ''
    local start_line = tonumber(assignment and assignment.line) or 1

    add_section(out, 'Lua Source')
    if source == '' then
        wrap_into(out, 'No source text captured for this node.', cfg.row_fg_dim, width)
        return
    end

    local line_no = start_line
    source = source:gsub('\r\n', '\n'):gsub('\r', '\n')
    if source:sub(-1) ~= '\n' then source = source .. '\n' end

    for line in source:gmatch('(.-)\n') do
        out[#out + 1] = {
            text = string.format('%4d | %s', line_no, line),
            color = cfg.row_fg_set,
            source_line = true,
        }
        line_no = line_no + 1
    end
end

local SLOT_LABELS = {
    main = 'Main',
    sub = 'Sub',
    range = 'Range',
    ammo = 'Ammo',
    head = 'Head',
    body = 'Body',
    hands = 'Hands',
    legs = 'Legs',
    feet = 'Feet',
    neck = 'Neck',
    waist = 'Waist',
    back = 'Back',
    ear1 = 'Ear 1',
    ear2 = 'Ear 2',
    left_ear = 'Ear 1',
    right_ear = 'Ear 2',
    lear = 'Ear 1',
    rear = 'Ear 2',
    ring1 = 'Ring 1',
    ring2 = 'Ring 2',
    left_ring = 'Ring 1',
    right_ring = 'Ring 2',
    lring = 'Ring 1',
    rring = 'Ring 2',
}

local function slot_label(slot)
    local key = tostring(slot or ''):lower()
    return SLOT_LABELS[key] or tostring(slot or 'Slot')
end

local function trim(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function strip_outer_quotes(text)
    local value = trim(text)
    return value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
end

local function extract_augments(raw)
    local block = tostring(raw or ''):match('augments%s*=%s*{(.-)}')
    if not block then return nil end

    local augments = {}
    for augment in block:gmatch('"([^"]+)"') do
        augments[#augments + 1] = augment
    end
    for augment in block:gmatch("'([^']+)'") do
        augments[#augments + 1] = augment
    end

    if #augments == 0 then return nil end
    return table.concat(augments, '; ')
end

local function gear_reference_key(value)
    local raw = trim(value)
    return raw:match('^(gear%.[%a_][%w_]*)$')
end

local function gear_display(value)
    local raw = tostring(value or '')
    local reference = gear_reference_key(raw)
    if reference and state.gear_reference_items[reference] then
        local resolved = state.gear_reference_items[reference]
        if type(resolved) == 'table' then
            return resolved.name or raw, resolved.augments, resolved.augmented == true, false
        end
        return resolved, nil, false, false
    end

    local name = raw:match('name%s*=%s*"([^"]+)"') or raw:match("name%s*=%s*'([^']+)'")
    if name then
        local augments = extract_augments(raw)
        return name, augments, augments ~= nil and augments ~= '', false
    end

    return strip_outer_quotes(raw), nil, false, reference ~= nil
end

local function comparable_gear_value(value)
    local raw = trim(value)
    if raw == '' then return false end
    if raw == 'empty' then return true end
    if gear_reference_key(raw) then
        return true
    end
    return raw:sub(1, 1) == '"' or raw:sub(1, 1) == "'" or raw:find('name%s*=', 1) ~= nil
end

local function equipped_item_for_slot(slot)
    local canonical = gear_slots.canonical(slot)
    if not canonical then return nil end
    return state.current_equipment.slots and state.current_equipment.slots[canonical] or nil
end

local function same_name(left, right)
    return tostring(left or ''):lower() == tostring(right or ''):lower()
end

local function bag_label(id)
    for _, bag in ipairs(state.inventory_locations.bags or {}) do
        if bag.id == id then return bag.label end
    end
    if id == 0 then return 'Inventory' end
    return id and ('Bag ' .. tostring(id)) or 'Unknown'
end

local function item_locations(name)
    return (state.inventory_locations.items or {})[tostring(name or ''):lower()] or {}
end

local function bag_access(id)
    for _, bag in ipairs(state.inventory_locations.bags or {}) do
        if bag.id == id then
            return bag.available == true
        end
    end
    return nil
end

local function best_location(name)
    local locations = item_locations(name)
    for _, location in ipairs(locations) do
        if location.equip_ready and (location.available == true or bag_access(location.bag)) then
            return location, false
        end
    end
    if locations[1] then
        return locations[1], locations[1].available == false or not bag_access(locations[1].bag)
    end
    return nil, false
end

local function gear_line_status(item, set_path)
    if not item or state.current_equipment.path ~= set_path then
        return 'Unknown', 'Unknown', cfg.row_fg_dim
    end
    if not comparable_gear_value(item.value) then
        return 'Unknown', 'Unknown', cfg.row_fg_dim
    end

    local equipped = equipped_item_for_slot(item.slot)
    local expected = trim(item.value)
    local expected_name, _, _, unresolved = gear_display(item.value)

    if unresolved then
        return 'Unknown', 'Unknown ref', cfg.row_fg_red
    end

    if expected == 'empty' then
        if equipped and equipped.empty then
            return 'Equipped', 'Empty', cfg.row_fg_green
        end
        return 'Missing', 'Should be empty', cfg.row_fg_red
    end

    if equipped and not equipped.empty and same_name(equipped.name, expected_name) then
        return 'Equipped', bag_label(equipped.bag), cfg.row_fg_green
    end

    local location, unavailable = best_location(expected_name)
    if location and unavailable then
        return 'Unavailable', location.label, cfg.row_fg_red
    end

    return 'Missing', location and location.label or 'Not found', cfg.row_fg_red
end

local function gear_table_layout(width)
    local total = cols(width) - 1
    local slot_w = 7
    local aug_w = 4
    local status_w = 11
    local location_w = 12
    local item_w = math.max(12, total - slot_w - aug_w - status_w - location_w - 4)
    return {
        total = total,
        slot = slot_w,
        item = item_w,
        aug = aug_w,
        status = status_w,
        location = location_w,
        aug_col = slot_w + 1 + item_w + 1,
    }
end

local function gear_table_cell(text, width)
    return pad(truncate(text, width), width)
end

local function add_gear_header(out, width)
    local l = gear_table_layout(width)
    add_line(out,
        gear_table_cell('Slot', l.slot) .. ' ' ..
        gear_table_cell('Item', l.item) .. ' ' ..
        gear_table_cell('Mod', l.aug) .. ' ' ..
        gear_table_cell('Status', l.status) .. ' ' ..
        truncate('Location', l.location),
        cfg.row_fg_gold)
end

local function changed_slot_lookup(path)
    local slots = {}

    if path and state.live_changes.path == path then
        for _, row in ipairs(state.live_changes.rows or {}) do
            if row.slot then
                slots[gear_slots.canonical(row.slot) or row.slot] = true
            end
        end
    end

    if path and state.recent_saved.path == path then
        for slot in pairs(state.recent_saved.slots or {}) do
            slots[gear_slots.canonical(slot) or slot] = true
        end
    end

    return slots
end

local function add_gear_line(out, item, width, show_augments, color, set_path, changed_slots)
    local name, augments, augmented = gear_display(item and item.value or '')
    local l = gear_table_layout(width)
    local status, location, status_color = gear_line_status(item, set_path)
    local canonical_slot = gear_slots.canonical(item and item.slot) or (item and item.slot)
    local just_changed = changed_slots and canonical_slot and changed_slots[canonical_slot]
    color = color or status_color or cfg.row_fg_set

    add_line(out,
        gear_table_cell(slot_label(item and item.slot), l.slot) .. ' ' ..
        gear_table_cell(name, l.item) .. ' ' ..
        gear_table_cell('', l.aug) .. ' ' ..
        gear_table_cell(status, l.status) .. ' ' ..
        truncate(location, l.location),
        color)

    if just_changed then
        out[#out].bg = cfg.row_bg_changed
    end

    if augmented then
        out[#out].aug_tag = 'Aug'
        out[#out].aug_tag_col = l.aug_col
        out[#out].aug_tag_color = cfg.row_fg_blue
    elseif just_changed then
        out[#out].aug_tag = 'Chg'
        out[#out].aug_tag_col = l.aug_col
        out[#out].aug_tag_color = cfg.row_fg_violet
    end

    if show_augments and augments and augments ~= '' then
        wrap_into(out, '         Aug: ' .. augments, cfg.row_fg_dim, width)
    end
end

local PREVIEW_TABS = { 'gear', 'changes', 'summary', 'evidence' }
local SOURCE_LEFT_EDGE_HOLD_SECONDS = 0.35
local SOURCE_LEFT_EDGE_REPEAT_SECONDS = 0.25

local function preview_tab_index()
    for index, name in ipairs(PREVIEW_TABS) do
        if state.preview_card == name then return index end
    end
    return 1
end

local function cycle_preview_tab(delta)
    if not is_equippable_leaf(selected_node()) then
        state.preview_card = 'summary'
        state.preview_scroll = 0
        state.preview_lines = state.preview_cards.summary or {}
        if state.visible then ui.refresh() end
        return
    end

    local index = preview_tab_index() + delta
    if index < 1 then
        index = #PREVIEW_TABS
    elseif index > #PREVIEW_TABS then
        index = 1
    end

    state.preview_card = PREVIEW_TABS[index]
    state.focus = 'tree'
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    state.preview_lines = state.preview_cards[state.preview_card] or {}
    if state.visible then ui.refresh() end
end

local function build_changes_card(node, width)
    local out = {}
    local path = path_string(node)

    add_line(out, node and node.key or 'No selection', cfg.title_fg)
    add_section(out, 'Live Changes')

    if not is_equippable_leaf(node) then
        wrap_into(out, 'Highlight a gear set to track live changes.', cfg.row_fg_dim, width)
        return out
    end

    if state.live_changes.path ~= path then
        wrap_into(out, 'No edit baseline captured for this set yet.', cfg.row_fg_dim, width)
        return out
    end

    if (state.live_changes.count or 0) == 0 then
        wrap_into(out, 'No changed gear slots.', cfg.row_fg_green, width)
        return out
    end

    for _, row in ipairs(state.live_changes.rows or {}) do
        wrap_into(out, string.format('%-8s %s -> %s', row.slot, row.before, row.after), cfg.row_fg_cursor, width)
    end

    return out
end

local function build_preview_cards(node)
    local summary = {}
    local gear_card = {}
    local changes_card = {}
    local evidence = {}
    local info = semantics.build_set_info(node) or {}
    local gear = node and tree.gear_preview(node) or {}
    local inheritance = info.inheritance or {}
    local set_path = path_string(node)
    local changed_slots = changed_slot_lookup(set_path)
    local width = cfg.preview_width
    local summary_only = info.summary_only or info.node_kind == 'category'
        or (node and not node.has_gear and (node.virtual or (node.children and #node.children > 0)))

    add_line(summary, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)

    -- CATEGORY SUMMARY LAYOUT v3
    -- Category/container nodes get one clean explanation instead of the old
    -- duplicate top paragraph + "Summary" section + empty gear count.
    if summary_only then
        if info.category then
            wrap_into(summary, tostring(info.category), cfg.row_fg_gold, width)
        end

        add_line(summary, '', cfg.row_fg_set)

        local purpose_text = tostring(info.purpose or '')
        local explanation_text = tostring(info.plain_english or '')
        local overview_text = ''

        if purpose_text ~= '' and explanation_text ~= '' then
            if explanation_text:find(purpose_text, 1, true) then
                overview_text = explanation_text
            else
                overview_text = purpose_text .. ' ' .. explanation_text
            end
        elseif explanation_text ~= '' then
            overview_text = explanation_text
        elseif purpose_text ~= '' then
            overview_text = purpose_text
        else
            overview_text = 'Select a set or category to inspect it.'
        end

        wrap_into(summary, overview_text, cfg.row_fg_set, width)

        if info.typical_use and tostring(info.typical_use) ~= '' then
            add_line(summary, '', cfg.row_fg_set)
            wrap_into(summary, 'Common use: ' .. tostring(info.typical_use), cfg.row_fg_set, width)
        end

        if info.conditions and #info.conditions > 0 then
            add_section(summary, 'Conditions')
            for _, condition in ipairs(info.conditions) do
                wrap_into(summary, '- ' .. tostring(condition), cfg.row_fg_set, width)
            end
        end

        return {
            summary = summary,
            gear = summary,
            changes = summary,
            evidence = summary,
            summary_only = true,
        }
    end

    -- Normal gear-set Summary card. Keep this separate from category summaries
    -- so real sets still get the existing Gear / Changes / Summary / Data flow.
    local purpose_text = tostring(info.purpose or '')
    local explanation_text = tostring(info.plain_english or '')
    local overview_text = ''

    if purpose_text ~= '' and explanation_text ~= '' then
        if explanation_text:find(purpose_text, 1, true) then
            overview_text = explanation_text
        else
            overview_text = purpose_text .. ' ' .. explanation_text
        end
    elseif explanation_text ~= '' then
        overview_text = explanation_text
    elseif purpose_text ~= '' then
        overview_text = purpose_text
    else
        overview_text = 'Select a set or category to inspect it.'
    end

    wrap_into(summary, overview_text, cfg.row_fg_set, width)

    if info.category or info.trigger or info.confidence or info.typical_use then
        add_line(summary, '', cfg.row_fg_set)
        if info.category then wrap_into(summary, 'Category: ' .. tostring(info.category), cfg.row_fg_gold, width) end
        if info.trigger then wrap_into(summary, 'Trigger: ' .. tostring(info.trigger), cfg.row_fg_set, width) end
        if info.typical_use and tostring(info.typical_use) ~= '' then
            wrap_into(summary, 'Common use: ' .. tostring(info.typical_use), cfg.row_fg_set, width)
        end
        if info.confidence then wrap_into(summary, 'Confidence: ' .. tostring(info.confidence), cfg.row_fg_green, width) end
    end

    if info.conditions and #info.conditions > 0 then
        add_section(summary, 'Conditions')
        for _, condition in ipairs(info.conditions) do
            wrap_into(summary, '- ' .. tostring(condition), cfg.row_fg_set, width)
        end
    end

    add_line(gear_card, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)
    add_section(gear_card, 'Defined Gear (' .. tostring(#gear) .. ')')
    if #gear == 0 then
        wrap_into(gear_card, 'No direct gear slots detected.', cfg.row_fg_dim, width)
    else
        add_gear_header(gear_card, width)
        for _, item in ipairs(gear) do
            add_gear_line(gear_card, item, width, false, nil, set_path, changed_slots)
        end
    end

    changes_card = build_changes_card(node, width)

    add_line(evidence, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)
    add_lua_source(evidence, node, width)

    add_section(evidence, 'Evidence')
    if info.evidence and #info.evidence > 0 then
        for _, item in ipairs(info.evidence) do
            wrap_into(evidence, '- ' .. tostring(item), cfg.row_fg_dim, width)
        end
    else
        wrap_into(evidence, 'No semantic evidence recorded for this node.', cfg.row_fg_dim, width)
    end

    add_section(evidence, 'Source / Debug')
    wrap_into(evidence, 'Lua Path: ' .. path_string(node), cfg.row_fg_set, width)
    wrap_into(evidence, 'Source: ' .. source_line(node, info), cfg.row_fg_cursor, width)
    wrap_into(evidence, 'Type: ' .. (node and tree.describe(node) or 'none'), cfg.row_fg_dim, width)

    add_section(evidence, 'Inheritance')
    if list_count(inheritance.bases) == 0 and list_count(inheritance.references) == 0 and list_count(inheritance.override_slots) == 0 then
        wrap_into(evidence, 'Direct set definition', cfg.row_fg_dim, width)
    else
        for _, ref in ipairs(inheritance.bases or {}) do
            wrap_into(evidence, 'Base: ' .. tostring(ref), cfg.row_fg_set, width)
        end
        for _, ref in ipairs(inheritance.references or {}) do
            wrap_into(evidence, 'Reference: ' .. tostring(ref), cfg.row_fg_set, width)
        end
        if inheritance.override_slots and #inheritance.override_slots > 0 then
            wrap_into(evidence, 'Overrides: ' .. table.concat(inheritance.override_slots, ', '), cfg.row_fg_set, width)
        end
    end

    return {
        summary = summary,
        gear = gear_card,
        changes = changes_card,
        evidence = evidence,
    }
end

local function update_positions()
    local d = dims()
    local icon_x_offset = 6
    local icon_y_offset = 3
    local text_x_offset = cfg.show_icons and 24 or 6

    state.header_bg:pos(d.x, d.y)
    fill_panel(state.header_bg, d.total_w, 1)
    state.header_bg:visible(false)
    state.header:pos(d.x + 4, d.y)
    state.header:text(truncate('GearTree | End Equip | Esc Hide | Arrows Move/View | //gt help', cols(d.total_w) - 2))

    state.tree_bg:pos(d.x, d.body_y)
    fill_panel(state.tree_bg, d.total_w, cfg.visible_rows + 1)
    state.list_bg:visible(false)
    state.preview_bg:visible(false)

    state.tree_title:pos(d.tree_x, d.body_y)
    state.list_title:pos(d.list_x, d.body_y)
    set_title_active(state.tree_title, true)

    local tabs = {
        { card = 'gear', label = 'Gear', obj = state.preview_title },
        { card = 'changes', label = 'Changes', obj = state.preview_changes_title },
        { card = 'summary', label = 'Summary', obj = state.preview_gear_title },
        { card = 'evidence', label = 'Data', obj = state.preview_data_title },
    }
    local tab_count = #tabs
    local tab_bar_cols = cols(d.preview_w)
    local tab_cols = math.floor(tab_bar_cols / tab_count)
    local used_cols = 0

    -- Draw one full-width inactive tab strip first. Individual tab labels are
    -- then placed on top. This avoids making four independent padded text
    -- backgrounds overlap each other.
    if state.preview_tab_bg then
        state.preview_tab_bg:pos(d.preview_x, d.body_y)
        state.preview_tab_bg:bg_visible(true)
        state.preview_tab_bg:bg_color(cfg.title_bg[2], cfg.title_bg[3], cfg.title_bg[4])
        state.preview_tab_bg:bg_alpha(cfg.title_bg[1])
        state.preview_tab_bg:text(string.rep(' ', tab_bar_cols))
    end

    for index, tab in ipairs(tabs) do
        local width_cols = tab_cols
        if index == tab_count then
            width_cols = tab_bar_cols - used_cols
        end

        local x = d.preview_x + (used_cols * 7)
        local active = state.preview_card == tab.card

        tab.obj:pos(x, d.body_y)
        tab.obj:bg_visible(active)
        set_title_active(tab.obj, active)
        tab.obj:text(center_pad(tab.label, width_cols))

        used_cols = used_cols + width_cols
    end

    local row_y = d.body_y + cfg.row_height
    for i, obj in ipairs(state.tree_rows) do
        local y = row_y + (i - 1) * cfg.row_height
        obj:pos(d.tree_x + text_x_offset, y)
        if state.tree_icons[i] then
            if cfg.show_icons then
                state.tree_icons[i]:pos(d.tree_x + icon_x_offset, y + icon_y_offset)
                state.tree_icons[i]:size(cfg.icon_size, cfg.icon_size)
            else
                state.tree_icons[i]:visible(false)
            end
        end
    end
    for i, obj in ipairs(state.list_rows) do
        local y = row_y + (i - 1) * cfg.row_height
        obj:pos(d.list_x + text_x_offset, y)
        if state.list_icons[i] then
            if cfg.show_icons then
                state.list_icons[i]:pos(d.list_x + icon_x_offset, y + icon_y_offset)
                state.list_icons[i]:size(cfg.icon_size, cfg.icon_size)
            else
                state.list_icons[i]:visible(false)
            end
        end
    end
    for i, obj in ipairs(state.preview_rows) do
        obj:pos(d.preview_x + 4, row_y + (i - 1) * cfg.row_height)
    end

    state.footer_bg:pos(d.x, d.footer_y)
    fill_panel(state.footer_bg, d.total_w, 1)
    state.footer_bg:visible(false)
    state.footer:pos(d.x + 4, d.footer_y)
    state.footer:text(truncate(state.status_text or '', cols(d.total_w) - 2))
end

function ui.create(root, save_pos_callback)
    state.root = root
    state.save_pos_callback = save_pos_callback
    state.flat = tree.flatten(root)
    state.cursor = #state.flat > 0 and 1 or 0

    local d = dims()
    state.header_bg = panel_obj(d.total_w, 1)
    state.header = text_obj()
    state.header:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    state.tree_bg = panel_obj(d.tree_w, cfg.visible_rows + 1)
    state.list_bg = panel_obj(d.list_w, cfg.visible_rows + 1)
    state.preview_bg = panel_obj(d.preview_w, cfg.visible_rows + 1)
    state.tree_title = title_obj()
    state.list_title = title_obj()
    state.preview_tab_bg = title_obj()
    state.preview_title = title_obj()
    state.preview_gear_title = title_obj()
    state.preview_changes_title = title_obj()
    state.preview_data_title = title_obj()
    state.footer_bg = panel_obj(d.total_w, 1)
    state.footer = text_obj()
    state.footer:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])

    for i = 1, cfg.visible_rows do
        state.tree_rows[i] = text_obj()
        state.tree_icons[i] = image_obj()
        state.list_rows[i] = text_obj()
        state.list_icons[i] = image_obj()
        state.preview_rows[i] = text_obj()
        state.preview_aug_tags[i] = text_obj()
        set_color(state.preview_aug_tags[i], cfg.row_fg_blue)
    end

    update_positions()
end

function ui.destroy()
    for _, obj in ipairs(state.objects) do
        obj:destroy()
    end
    for _, obj in ipairs(state.image_objects) do
        obj:destroy()
    end
    state.objects = {}
    state.image_objects = {}
    state.tree_rows = {}
    state.tree_icons = {}
    state.list_rows = {}
    state.list_icons = {}
    state.preview_rows = {}
    state.preview_aug_tags = {}
end

local function set_visible(visible)
    for _, obj in ipairs(state.objects) do
        obj:visible(visible)
    end
    for _, obj in ipairs(state.image_objects) do
        obj:visible(visible and cfg.show_icons)
    end

    if state.preview_bg then state.preview_bg:visible(false) end

    if not cfg.show_list_pane then
        if state.list_bg then state.list_bg:visible(false) end
        if state.list_title then state.list_title:visible(false) end
        for _, obj in ipairs(state.list_rows) do obj:visible(false) end
        for _, obj in ipairs(state.list_icons) do obj:visible(false) end
    end
end

local function render_tree()
    local d = dims()
    state.flat = tree.flatten(state.root)
    if #state.flat > 0 then
        state.cursor = clamp(state.cursor == 0 and 1 or state.cursor, 1, #state.flat)
    else
        state.cursor = 0
    end
    ensure_cursor_visible()

    local label = string.format(' Gear Sets [%d/%d] ', state.cursor, #state.flat)
    state.tree_title:text(pad(label, cols(d.tree_w)))

    for i = 1, cfg.visible_rows do
        local flat_idx = state.scroll + i
        local entry = state.flat[flat_idx]
        local obj = state.tree_rows[i]
        local icon = state.tree_icons[i]
        obj:bg_visible(false)

        if entry then
            local node = entry.node
            local indent = string.rep('  ', entry.depth)
            local is_last_saved = state.last_saved_path ~= '' and not node.virtual and path_string(node) == state.last_saved_path
            local marker = flat_idx == state.cursor and '>' or (is_last_saved and '*' or ' ')
            local text = string.format('%s %s%s %s', marker, indent, node_kind(node), node.key)
            if icon then
                if cfg.show_icons then
                    icon:path(node_icon(node))
                    icon:visible(state.visible)
                else
                    icon:visible(false)
                end
            end
            if flat_idx == state.cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_cursor[2], cfg.row_bg_cursor[3], cfg.row_bg_cursor[4])
                obj:bg_alpha(cfg.row_bg_cursor[1])
                set_color(obj, cfg.row_fg_cursor)
            elseif is_last_saved then
                set_color(obj, cfg.row_fg_gold)
            elseif node.children and #node.children > 0 then
                set_color(obj, cfg.row_fg_cat)
            else
                set_color(obj, cfg.row_fg_set)
            end
            obj:text(truncate(text, cols(d.tree_w) - 4))
        else
            obj:text('')
            if icon then icon:visible(false) end
        end
    end
end

local function render_list()
    if not cfg.show_list_pane then
        if state.list_bg then state.list_bg:visible(false) end
        if state.list_title then state.list_title:visible(false) end
        for _, obj in ipairs(state.list_rows) do
            obj:text('')
            obj:visible(false)
        end
        for _, icon in ipairs(state.list_icons) do
            icon:visible(false)
        end
        return
    end

    local d = dims()
    local list_node = active_list_node()
    local items = active_list_items()
    local title = list_node and list_node.key or 'Sets'
    state.list_title:text(pad(' ' .. title .. '  (' .. tostring(#items) .. ') ', cols(d.list_w)))

    for i = 1, cfg.visible_rows do
        local node = items[i]
        local obj = state.list_rows[i]
        local icon = state.list_icons[i]
        obj:bg_visible(false)

        if node then
            local idx = flat_index_for_node(node)
            local marker = node_kind(node)
            local is_last_saved = state.last_saved_path ~= '' and not node.virtual and path_string(node) == state.last_saved_path
            local saved_marker = is_last_saved and '*' or ' '
            local line = string.format('%s %s %-24s %s', saved_marker, marker, node.key, node.has_gear and tree.describe(node) or '')
            if icon then
                if cfg.show_icons then
                    icon:path(node_icon(node))
                    icon:visible(state.visible)
                else
                    icon:visible(false)
                end
            end
            if idx and idx == state.cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_cursor[2], cfg.row_bg_cursor[3], cfg.row_bg_cursor[4])
                obj:bg_alpha(cfg.row_bg_cursor[1])
                set_color(obj, cfg.row_fg_cursor)
            elseif is_last_saved then
                set_color(obj, cfg.row_fg_gold)
            elseif node.children and #node.children > 0 then
                set_color(obj, cfg.row_fg_cat)
            else
                set_color(obj, cfg.row_fg_set)
            end
            obj:text(truncate(line, cols(d.list_w) - 4))
        else
            obj:text('')
            if icon then icon:visible(false) end
        end
    end
end

local function first_source_line_index()
    for index, meta in ipairs(state.preview_cards.evidence or {}) do
        if meta.source_line then return index end
    end
    return 1
end

local function source_pan_limit()
    local d = dims()
    local visible_cols = math.max(1, cols(d.preview_w) - 1)
    local max_len = 0
    for _, meta in ipairs(state.preview_cards.evidence or {}) do
        if meta.source_line and meta.text then
            max_len = math.max(max_len, #meta.text)
        end
    end
    return math.max(0, max_len - visible_cols)
end

local function render_preview()
    local d = dims()
    state.preview_lines = state.preview_cards[state.preview_card] or {}

    local max_scroll = math.max(0, #state.preview_lines - cfg.visible_rows)
    if state.preview_card == 'evidence' then
        if #state.preview_lines == 0 then
            state.source_cursor = 0
        else
            if state.source_cursor == 0 then
                state.source_cursor = first_source_line_index()
            end
            state.source_cursor = clamp(state.source_cursor, 1, #state.preview_lines)
        end
        state.source_pan = clamp(state.source_pan or 0, 0, source_pan_limit())
    else
        state.source_cursor = 0
        state.source_pan = 0
        clear_source_left_guard()
    end
    state.preview_scroll = clamp(state.preview_scroll, 0, max_scroll)

    for i = 1, cfg.visible_rows do
        local row_index = state.preview_scroll + i
        local meta = state.preview_lines[row_index]
        local obj = state.preview_rows[i]
        local tag = state.preview_aug_tags[i]
        obj:bg_visible(false)
        if tag then
            tag:text('')
            tag:visible(false)
        end
        if meta then
            if meta.bg then
                obj:bg_visible(true)
                obj:bg_color(meta.bg[2], meta.bg[3], meta.bg[4])
                obj:bg_alpha(meta.bg[1])
            end
            local text = meta.text
            local color = meta.color or cfg.row_fg_set
            if state.preview_card == 'evidence' and row_index == state.source_cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_changed[2], cfg.row_bg_changed[3], cfg.row_bg_changed[4])
                obj:bg_alpha(cfg.row_bg_changed[1])
                color = cfg.row_fg_cursor
            end
            if meta.source_line and state.preview_card == 'evidence' then
                if state.source_pan > 0 then
                    text = text:sub(state.source_pan + 1)
                end
            end
            obj:text(truncate(text, cols(d.preview_w) - 1))
            set_color(obj, color)
            if tag and meta.aug_tag and meta.aug_tag_col then
                tag:pos(d.preview_x + 4 + (meta.aug_tag_col * 7), d.body_y + cfg.row_height + (i - 1) * cfg.row_height)
                tag:text(meta.aug_tag)
                set_color(tag, meta.aug_tag_color or cfg.row_fg_blue)
                tag:visible(state.visible)
            end
        else
            obj:text('')
        end
    end
end

function ui.refresh()
    if not state.visible then return end
    update_positions()
    render_tree()
    render_list()
    render_preview()
end

function ui.show()
    state.visible = true
    if state.cursor == 0 and #state.flat > 0 then state.cursor = 1 end
    auto_preview()
    set_visible(true)
    ui.refresh()
end

function ui.hide()
    state.visible = false
    state.focus = 'tree'
    state.preview_card = 'gear'
    set_visible(false)
end

function ui.toggle()
    if state.visible then ui.hide() else ui.show() end
end

function ui.is_visible()
    return state.visible
end

function ui.show_preview(node)
    if not is_equippable_leaf(node) then
        state.preview_card = 'summary'
    elseif state.preview_card == 'summary' then
        state.preview_card = 'gear'
    end
    state.preview_cards = build_preview_cards(node)
    if state.preview_cards.summary_only then
        state.preview_card = 'summary'
    end
    state.preview_lines = state.preview_cards[state.preview_card] or {}
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    if state.visible then render_preview() end
end

function ui.hide_preview()
    state.preview_cards = { summary = {}, gear = {}, changes = {}, evidence = {} }
    state.preview_lines = {}
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    if state.visible then render_preview() end
end

local function scroll_preview(delta)
    state.preview_lines = state.preview_cards[state.preview_card] or {}
    local max_scroll = math.max(0, #state.preview_lines - cfg.visible_rows)
    state.preview_scroll = clamp(state.preview_scroll + delta, 0, max_scroll)
    if state.visible then render_preview() end
end

local function selected_data_line_is_source()
    local lines = state.preview_cards.evidence or {}
    local meta = lines[state.source_cursor]
    return meta and meta.source_line
end

local function move_source_cursor(delta)
    state.preview_lines = state.preview_cards.evidence or {}
    if #state.preview_lines == 0 then return end

    clear_source_left_guard()
    if state.source_cursor == 0 then
        state.source_cursor = first_source_line_index()
    end
    state.source_cursor = clamp(state.source_cursor + delta, 1, #state.preview_lines)

    if state.source_cursor <= state.preview_scroll then
        state.preview_scroll = math.max(0, state.source_cursor - 1)
    elseif state.source_cursor > state.preview_scroll + cfg.visible_rows then
        state.preview_scroll = state.source_cursor - cfg.visible_rows
    end
    if not selected_data_line_is_source() then
        state.source_pan = 0
    end
    if state.visible then render_preview() end
end

local function pan_source(delta)
    local before = state.source_pan or 0
    state.source_pan = clamp((state.source_pan or 0) + delta, 0, source_pan_limit())
    if delta > 0 then clear_source_left_guard() end
    if state.visible then render_preview() end
    return before, state.source_pan
end

function ui.toggle_preview_focus()
    state.focus = 'tree'
    if state.preview_cards.summary_only then
        state.preview_card = 'summary'
    else
        state.preview_card = 'gear'
    end
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    state.preview_lines = state.preview_cards[state.preview_card] or {}
    if state.visible then ui.refresh() end
end

function ui.is_preview_focused()
    return false
end

auto_preview = function()
    local node = selected_node()
    if node then
        ui.show_preview(node)
    else
        ui.hide_preview()
    end
    notify_selection_changed()
end

local function activate_node(node)
    if not node then return end

    select_node(node)
    if node.has_gear then
        local cmd = tree.equip_command(node)
        if cmd then
            if state.equip_callback then
                state.equip_callback(node, cmd)
            else
                windower.send_command(cmd)
            end
        end
    elseif node.children and #node.children > 0 then
        tree.toggle(node)
    end

    auto_preview()
    ui.refresh()
end

function ui.cursor_up()
    if not state.visible or #state.flat == 0 then return end
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' then
            move_source_cursor(-1)
        else
            scroll_preview(-1)
        end
        return
    end
    if state.cursor <= 1 then
        state.cursor = #state.flat
        state.scroll = math.max(0, #state.flat - cfg.visible_rows)
    else
        state.cursor = state.cursor - 1
    end
    ensure_cursor_visible()
    auto_preview()
    ui.refresh()
end

function ui.cursor_down()
    if not state.visible or #state.flat == 0 then return end
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' then
            move_source_cursor(1)
        else
            scroll_preview(1)
        end
        return
    end
    if state.cursor >= #state.flat then
        state.cursor = 1
        state.scroll = 0
    else
        state.cursor = state.cursor + 1
    end
    ensure_cursor_visible()
    auto_preview()
    ui.refresh()
end

function ui.cursor_select()
    activate_node(selected_node())
end

function ui.cursor_equip()
    local node = selected_node()
    if not node or not node.has_gear then return end
    local cmd = tree.equip_command(node)
    if not cmd then return end
    if state.equip_callback then
        state.equip_callback(node, cmd)
    else
        windower.send_command(cmd)
    end
end

function ui.cursor_back()
    local entry = selected_entry()
    if not entry then return end
    local node = entry.node

    if node.children and #node.children > 0 and node.expanded then
        tree.toggle(node)
        state.flat = tree.flatten(state.root)
        state.cursor = math.min(state.cursor, #state.flat)
        auto_preview()
        ui.refresh()
        return
    end

    local parent = find_parent(node)
    if parent then
        select_node(parent)
        auto_preview()
        ui.refresh()
    end
end

function ui.cursor_right(is_repeat)
    local node = selected_node()
    if not node then return end
    clear_source_left_guard()

    if is_equippable_leaf(node) and state.preview_card == 'evidence' then
        if selected_data_line_is_source() then
            pan_source(8)
        elseif not is_repeat then
            cycle_preview_tab(1)
        end
        return
    end

    if is_repeat then return end

    if node.children and #node.children > 0 then
        if not node.expanded then
            tree.toggle(node)
            state.flat = tree.flatten(state.root)
            ensure_cursor_visible()
            auto_preview()
            ui.refresh()
        end
        return
    end

    if is_equippable_leaf(node) then
        cycle_preview_tab(1)
    end
end

function ui.cursor_left(is_repeat)
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' and selected_data_line_is_source() then
            if (state.source_pan or 0) > 0 then
                local _, after = pan_source(-8)
                if after == 0 then
                    state.source_left_edge_until = os.clock() + SOURCE_LEFT_EDGE_HOLD_SECONDS
                end
                return
            end

            if (state.source_left_edge_until or 0) > os.clock() then
                state.source_left_edge_until = os.clock() + SOURCE_LEFT_EDGE_REPEAT_SECONDS
                return
            end
        end
        if is_repeat then return end
        clear_source_left_guard()
        cycle_preview_tab(-1)
        return
    end

    if is_repeat then return end
    clear_source_left_guard()
    ui.cursor_back()
end

local function hit_test(mx, my)
    if not state.visible then return nil end
    local d = dims()

    local drag_bottom = d.body_y + cfg.row_height
    if mx >= d.x and mx <= d.x + d.total_w and my >= d.y and my < drag_bottom then
        return 'header'
    end

    local row_top = d.body_y + cfg.row_height
    local row_bottom = row_top + cfg.visible_rows * cfg.row_height

    if my >= row_top and my < row_bottom then
        local row = math.floor((my - row_top) / cfg.row_height) + 1
        if mx >= d.tree_x and mx <= d.tree_x + d.tree_w then
            local flat_idx = state.scroll + row
            local entry = state.flat[flat_idx]
            if entry then return 'tree_row', entry.node, flat_idx end
        elseif mx >= d.list_x and mx <= d.list_x + d.list_w then
            local node = active_list_items()[row]
            if node then return 'list_row', node end
        elseif mx >= d.preview_x and mx <= d.preview_x + d.preview_w then
            return 'preview'
        end
    end

    return nil
end

function ui.on_left_click(mx, my)
    local kind, node, flat_idx = hit_test(mx, my)
    if kind == 'header' then
        state.drag = { mx = mx, my = my, x = cfg.pos_x, y = cfg.pos_y }
        return true
    elseif kind == 'tree_row' then
        state.cursor = flat_idx
        activate_node(node)
        return true
    elseif kind == 'list_row' then
        activate_node(node)
        return true
    elseif kind == 'preview' then
        return true
    end
    return false
end

function ui.on_left_up()
    if state.drag then
        state.drag = nil
        if state.save_pos_callback then
            state.save_pos_callback(cfg.pos_x, cfg.pos_y)
        end
        return true
    end
    return false
end

function ui.on_mouse_move(mx, my)
    if state.drag then
        local dx = mx - state.drag.mx
        local dy = my - state.drag.my
        ui.set_position(state.drag.x + dx, state.drag.y + dy)
        return true
    end
    return false
end

function ui.on_right_click(mx, my)
    local kind, node, flat_idx = hit_test(mx, my)
    if kind == 'tree_row' then
        state.cursor = flat_idx
        auto_preview()
        ui.refresh()
        return true
    elseif kind == 'list_row' then
        select_node(node)
        auto_preview()
        ui.refresh()
        return true
    elseif kind == 'preview' then
        return true
    end
    return false
end

function ui.on_scroll(mx, my, delta)
    if not state.visible then return false end

    local kind = hit_test(mx, my)
    if kind == 'preview' then
        if delta > 0 then
            scroll_preview(3)
        else
            scroll_preview(-3)
        end
        return true
    end

    if delta > 0 then
        ui.cursor_down()
    else
        ui.cursor_up()
    end
    return true
end

function ui.set_position(x, y)
    cfg.pos_x = x
    cfg.pos_y = y
    update_positions()
    if state.visible then ui.refresh() end
end

function ui.get_position()
    return cfg.pos_x, cfg.pos_y
end

function ui.set_equip_callback(callback)
    state.equip_callback = callback
end

function ui.set_selection_callback(callback)
    state.selection_callback = callback
end

function ui.get_selected_node()
    return selected_node()
end

function ui.select_path(path)
    local node = find_node_by_path(path)
    if not node then return false end

    select_node(node)
    auto_preview()
    if state.visible then ui.refresh() end
    return true
end

function ui.select_virtual_folder(id)
    local node = find_virtual_folder(id)
    if not node then return false end

    select_node(node)
    auto_preview()
    if state.visible then ui.refresh() end
    return true
end

local function query_matches_node(node, query)
    query = tostring(query or ''):lower()
    if query == '' or not node then return false end

    local key = tostring(node.key or ''):lower()
    local path = path_string(node):lower()
    if key:find(query, 1, true) or path:find(query, 1, true) then
        return true
    end

    if node.has_gear then
        local desc = tostring(tree.describe(node) or ''):lower()
        if desc:find(query, 1, true) then return true end

        for _, item in ipairs(tree.gear_preview(node)) do
            local slot = tostring(item.slot or ''):lower()
            local value = tostring(item.value or ''):lower()
            if slot:find(query, 1, true) or value:find(query, 1, true) then
                return true
            end
        end
    end

    return false
end

function ui.find(text)
    local query = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if query == '' or not state.root then return false end

    local nodes = {}
    walk_display(state.root, function(node)
        if node ~= state.root then nodes[#nodes + 1] = node end
        return nil
    end)

    if #nodes == 0 then return false end

    local current = selected_node()
    local start = 0
    for i, node in ipairs(nodes) do
        if node == current then
            start = i
            break
        end
    end

    for offset = 1, #nodes do
        local idx = ((start + offset - 1) % #nodes) + 1
        local node = nodes[idx]
        if query_matches_node(node, query) then
            select_node(node)
            auto_preview()
            if state.visible then ui.refresh() end
            return true
        end
    end

    return false
end

function ui.set_status(text)
    state.status_text = tostring(text or '')
    if state.footer then
        local d = dims()
        state.footer:text(truncate(state.status_text, cols(d.total_w) - 2))
    end
end

function ui.set_last_saved(path)
    state.last_saved_path = tostring(path or '')
    if state.visible then ui.refresh() end
end

local function refresh_preview_cards_preserving_source()
    local old_card = state.preview_card
    local old_cursor = state.source_cursor
    local old_pan = state.source_pan
    local old_scroll = state.preview_scroll

    state.preview_cards = build_preview_cards(selected_node())
    if state.preview_cards.summary_only then
        state.preview_card = 'summary'
        state.source_cursor = 0
        state.source_pan = 0
        clear_source_left_guard()
    end
    state.preview_lines = state.preview_cards[state.preview_card] or {}

    if old_card == 'evidence' and state.preview_card == 'evidence' then
        state.source_cursor = old_cursor
        state.source_pan = old_pan
        state.preview_scroll = old_scroll
    end
end

function ui.set_recent_saved_slots(path, slots)
    local lookup = {}
    for _, slot in ipairs(slots or {}) do
        if slot then lookup[gear_slots.canonical(slot) or slot] = true end
    end

    state.recent_saved = {
        path = path,
        slots = lookup,
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_changes(path, rows, count)
    state.live_changes = {
        path = path,
        rows = rows or {},
        count = count or 0,
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_changes()
    state.live_changes = { path = nil, rows = {}, count = 0 }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_current_equipment(path, equipment)
    state.current_equipment = {
        path = path,
        slots = equipment or {},
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_current_equipment()
    state.current_equipment = { path = nil, slots = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_gear_reference_items(references)
    state.gear_reference_items = references or {}
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_inventory_locations(locations)
    state.inventory_locations = locations or { items = {}, bags = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_inventory_locations()
    state.inventory_locations = { items = {}, bags = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.rebuild(new_root)
    local previous = selected_node()
    local previous_path = previous and not previous.virtual and path_string(previous) or ''

    state.root = new_root
    state.flat = tree.flatten(state.root)
    state.scroll = 0

    local preferred_path = state.last_saved_path ~= '' and state.last_saved_path or previous_path
    if preferred_path ~= '' and ui.select_path(preferred_path) then
        return
    end

    state.cursor = #state.flat > 0 and math.max(1, math.min(state.cursor, #state.flat)) or 0
    auto_preview()
    ui.refresh()
end

return ui
