-- GearTree UI
-- Windower text-overlay UI for the gear tree.
-- Maintains a pool of row text objects and re-renders them when the tree
-- state changes (expand/collapse or scroll).

local tree      = require('tree')
local semantics = require('semantics')
local texts     = require('texts')

local ui = {}

----------------------------------------------------------------------
-- Configuration (overrideable via ui.configure)
----------------------------------------------------------------------

local cfg = {
    pos_x = 100,
    pos_y = 100,
    width = 260,
    visible_rows = 22,
    row_height = 16,
    font = 'Consolas',
    font_size = 10,

    -- Colors (a, r, g, b)
    bg_color       = { 220,   8,   8,  16 },
    title_bg       = { 240,  20,  40,  80 },
    title_fg       = {       200, 220, 255 },
    row_fg_set     = {       215, 215, 215 }, -- equippable leaf
    row_fg_cat     = {       120, 160, 210 }, -- category (folder)
    row_fg_hover   = {       255, 255, 180 },
    row_fg_cursor  = {       255, 210,  40 }, -- keyboard-selected row
    row_bg_cursor  = { 100,  80,  65,  20 },
    row_fg_hint    = {       120, 120, 120 }, -- hint bar text
    glyph_fg       = {       180, 180, 100 },

    -- Preview overlay
    preview_gap      = 55,
    preview_offset_x = 315, -- set dynamically to width+preview_gap after cfg is built
    preview_offset_y = 0,
    preview_width    = 270,
    preview_rows     = 28,
}

-- Preview is always placed clear of the main window
cfg.preview_offset_x = cfg.width + cfg.preview_gap

function ui.configure(overrides)
    for k, v in pairs(overrides) do cfg[k] = v end
    cfg.preview_offset_x = cfg.width + cfg.preview_gap
end

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

local state = {
    root = nil,            -- tree root
    flat = {},             -- current flattened list
    scroll = 0,            -- index of first visible row in flat list
    visible = false,       -- master visibility
    title_obj = nil,       -- title bar text object
    bg_obj = nil,          -- background prim (we'll fake with a text object's bg)
    row_objs = {},         -- pool of row text objects
    preview_objs = {},     -- pool for right-click preview
    preview_bg = nil,
    preview_title = nil,
    preview_visible = false,
    cursor = 0,            -- 1-based index into flat list; 0 = no cursor
    drag = nil,            -- { start_mx, start_my, start_x, start_y }
    save_pos_callback = nil, -- function(x, y) for persistence
    equip_callback = nil,  -- function(node, command) for GearTree.lua
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local auto_preview  -- forward declaration; defined after show_preview is available

local function apply_text_style(obj)
    obj:font(cfg.font)
    obj:size(cfg.font_size)
    obj:bg_visible(false)
    obj:stroke_transparency(255)
    obj:bg_alpha(0)
end

local function set_row_text(obj, str, color)
    obj:text(str)
    if color then obj:color(color[1], color[2], color[3]) end
end

-- Build the rendered string for one row: indent + glyph + name
local function row_string(node, depth)
    local indent = string.rep('  ', depth)
    if #node.children > 0 then
        -- Category/folder node
        local glyph = node.expanded and '- ' or '+ '
        return indent .. glyph .. node.key
    else
        -- Equippable gear set (leaf)
        return indent .. '  * ' .. node.key
    end
end

----------------------------------------------------------------------
-- Window construction
----------------------------------------------------------------------

function ui.create(root, save_pos_callback)
    state.root = root
    state.save_pos_callback = save_pos_callback
    state.flat = tree.flatten(root)

    -- Title bar
    state.title_obj = texts.new({flags = {draggable = false}})
    state.title_obj:pos(cfg.pos_x, cfg.pos_y)
    state.title_obj:font(cfg.font)
    state.title_obj:size(cfg.font_size)
    state.title_obj:bg_visible(true)
    state.title_obj:bg_color(cfg.title_bg[2], cfg.title_bg[3], cfg.title_bg[4])
    state.title_obj:bg_alpha(cfg.title_bg[1])
    state.title_obj:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    state.title_obj:text(' GearTree ')
    state.title_obj:visible(false)

    -- Background "card" behind rows — implemented as a row-shaped text object
    -- with bg enabled, filling the row area.
    state.bg_obj = texts.new({flags = {draggable = false}})
    state.bg_obj:pos(cfg.pos_x, cfg.pos_y + cfg.row_height)
    state.bg_obj:font(cfg.font)
    state.bg_obj:size(cfg.font_size)
    state.bg_obj:bg_visible(true)
    state.bg_obj:bg_color(cfg.bg_color[2], cfg.bg_color[3], cfg.bg_color[4])
    state.bg_obj:bg_alpha(cfg.bg_color[1])
    -- A column of spaces that's tall enough to look like a panel.
    -- We fake the height by including newlines.
    local lines = {}
    -- Each space is approximate; this just gives the panel a stable body.
    local cols = math.floor(cfg.width / 7)
    for _ = 1, cfg.visible_rows do
        lines[#lines + 1] = string.rep(' ', cols)
    end
    state.bg_obj:text(table.concat(lines, '\n'))
    state.bg_obj:visible(false)

    -- Row pool
    for i = 1, cfg.visible_rows do
        local obj = texts.new({flags = {draggable = false}})
        obj:pos(cfg.pos_x + 4, cfg.pos_y + cfg.row_height + (i - 1) * cfg.row_height)
        apply_text_style(obj)
        obj:color(cfg.row_fg_set[1], cfg.row_fg_set[2], cfg.row_fg_set[3])
        obj:text('')
        obj:visible(false)
        state.row_objs[i] = obj
    end

    -- Preview pane (background + title + rows)
    state.preview_bg = texts.new({flags = {draggable = false}})
    state.preview_bg:pos(cfg.pos_x + cfg.preview_offset_x, cfg.pos_y + cfg.preview_offset_y + cfg.row_height)
    state.preview_bg:font(cfg.font)
    state.preview_bg:size(cfg.font_size)
    state.preview_bg:bg_visible(true)
    state.preview_bg:bg_color(cfg.bg_color[2], cfg.bg_color[3], cfg.bg_color[4])
    state.preview_bg:bg_alpha(cfg.bg_color[1])
    local plines = {}
    local pcols = math.floor(cfg.preview_width / 7)
    for _ = 1, cfg.preview_rows do
        plines[#plines + 1] = string.rep(' ', pcols)
    end
    state.preview_bg:text(table.concat(plines, '\n'))
    state.preview_bg:visible(false)

    state.preview_title = texts.new({flags = {draggable = false}})
    state.preview_title:pos(cfg.pos_x + cfg.preview_offset_x, cfg.pos_y + cfg.preview_offset_y)
    state.preview_title:font(cfg.font)
    state.preview_title:size(cfg.font_size)
    state.preview_title:bg_visible(true)
    state.preview_title:bg_color(cfg.title_bg[2], cfg.title_bg[3], cfg.title_bg[4])
    state.preview_title:bg_alpha(cfg.title_bg[1])
    state.preview_title:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    state.preview_title:text(' Preview ')
    state.preview_title:visible(false)

    for i = 1, cfg.preview_rows do
        local obj = texts.new({flags = {draggable = false}})
        obj:pos(cfg.pos_x + cfg.preview_offset_x + 4,
                cfg.pos_y + cfg.preview_offset_y + cfg.row_height + (i - 1) * cfg.row_height)
        apply_text_style(obj)
        obj:color(cfg.row_fg_set[1], cfg.row_fg_set[2], cfg.row_fg_set[3])
        obj:text('')
        obj:visible(false)
        state.preview_objs[i] = obj
    end
end

function ui.destroy()
    if state.title_obj   then state.title_obj:destroy()   end
    if state.bg_obj      then state.bg_obj:destroy()      end
    for _, o in ipairs(state.row_objs)     do o:destroy() end
    for _, o in ipairs(state.preview_objs) do o:destroy() end
    if state.preview_bg    then state.preview_bg:destroy()    end
    if state.preview_title then state.preview_title:destroy() end
    state.row_objs = {}
    state.preview_objs = {}
end

----------------------------------------------------------------------
-- Position management (for drag)
----------------------------------------------------------------------

local function reposition(x, y)
    cfg.pos_x = x
    cfg.pos_y = y
    state.title_obj:pos(x, y)
    state.bg_obj:pos(x, y + cfg.row_height)
    for i, obj in ipairs(state.row_objs) do
        obj:pos(x + 4, y + cfg.row_height + (i - 1) * cfg.row_height)
    end
    state.preview_title:pos(x + cfg.preview_offset_x, y + cfg.preview_offset_y)
    state.preview_bg:pos(x + cfg.preview_offset_x, y + cfg.preview_offset_y + cfg.row_height)
    for i, obj in ipairs(state.preview_objs) do
        obj:pos(x + cfg.preview_offset_x + 4,
                y + cfg.preview_offset_y + cfg.row_height + (i - 1) * cfg.row_height)
    end
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

function ui.refresh()
    if not state.visible then return end
    state.flat = tree.flatten(state.root)

    -- Clamp cursor and scroll
    if #state.flat > 0 then
        state.cursor = math.max(1, math.min(state.cursor, #state.flat))
    end
    local max_scroll = math.max(0, #state.flat - cfg.visible_rows)
    if state.scroll > max_scroll then state.scroll = max_scroll end
    if state.scroll < 0 then state.scroll = 0 end

    -- Live title: position counter + controls hint
    local total = #state.flat
    local pos_str = (total > 0 and state.cursor > 0)
        and string.format(' [%d/%d]', state.cursor, total) or ''
    state.title_obj:text(' GearTree' .. pos_str .. ' ')

    for i = 1, cfg.visible_rows do
        local flat_idx = state.scroll + i
        local entry = state.flat[flat_idx]
        local obj = state.row_objs[i]
        if entry then
            local color
            if flat_idx == state.cursor then
                color = cfg.row_fg_cursor
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_cursor[2], cfg.row_bg_cursor[3], cfg.row_bg_cursor[4])
                obj:bg_alpha(cfg.row_bg_cursor[1])
            elseif #entry.node.children > 0 then
                color = cfg.row_fg_cat
                obj:bg_visible(false)
            else
                color = cfg.row_fg_set
                obj:bg_visible(false)
            end
            set_row_text(obj, row_string(entry.node, entry.depth), color)
            obj:visible(true)
        else
            obj:text('')
            obj:bg_visible(false)
            obj:visible(false)
        end
    end
end

function ui.show()
    state.visible = true
    if state.cursor == 0 and #state.flat > 0 then
        state.cursor = 1
    end
    auto_preview()
    state.title_obj:visible(true)
    state.bg_obj:visible(true)
    ui.refresh()
end

function ui.hide()
    state.visible = false
    state.title_obj:visible(false)
    state.bg_obj:visible(false)
    for _, obj in ipairs(state.row_objs) do obj:visible(false) end
    ui.hide_preview()
end

function ui.toggle()
    if state.visible then ui.hide() else ui.show() end
end

function ui.is_visible()
    return state.visible
end


----------------------------------------------------------------------
-- Preview formatting helpers
----------------------------------------------------------------------

local function safe_string(value, fallback)
    if value == nil or value == '' then return fallback or 'Unknown' end
    return tostring(value)
end

local function list_count(t)
    if type(t) ~= 'table' then return 0 end
    return #t
end

local function first_nonempty(...)
    local args = {...}
    for _, v in ipairs(args) do
        if v ~= nil and tostring(v) ~= '' then return v end
    end
    return nil
end

local function node_location(node, info)
    info = info or {}
    local assignment = node and (node.assignment or node.set or node.meta) or nil

    local file = first_nonempty(
        info.source_file,
        info.file,
        assignment and assignment.source_file,
        assignment and assignment.file,
        node and node.source_file,
        node and node.file,
        node and node.source
    )

    local line = first_nonempty(
        info.line,
        info.start_line,
        assignment and assignment.line,
        assignment and assignment.start_line,
        node and node.line,
        node and node.start_line
    )

    local end_line = first_nonempty(
        info.end_line,
        assignment and assignment.end_line,
        node and node.end_line
    )

    if file and line and end_line and tostring(end_line) ~= tostring(line) then
        return string.format('%s:%s-%s', tostring(file), tostring(line), tostring(end_line))
    elseif file and line then
        return string.format('%s:%s', tostring(file), tostring(line))
    elseif line and end_line and tostring(end_line) ~= tostring(line) then
        return string.format('line %s-%s', tostring(line), tostring(end_line))
    elseif line then
        return string.format('line %s', tostring(line))
    elseif info.source and tostring(info.source) ~= '' then
        return tostring(info.source)
    end

    return 'Unknown source line'
end

local function compact_path(node, info)
    local assignment = node and (node.assignment or node.set or node.meta) or nil
    local path = first_nonempty(info and info.lua_path, assignment and assignment.lua_path, node and node.lua_path, node and node.path)
    if path then return tostring(path) end

    local keys = (assignment and assignment.keys) or (node and (node.keys or node.path_keys))
    if type(keys) == 'table' and #keys > 0 then
        return table.concat(keys, '.')
    end

    return safe_string(info and info.title, 'Unknown set')
end

local function short_kind(node, info)
    local rhs = node and node.rhs
    local kind = first_nonempty(info and info.kind, rhs and rhs.kind, node and node.kind)
    if kind then return tostring(kind) end
    if node and node.has_gear then return 'gear set' end
    if node and node.children and #node.children > 0 then return 'category' end
    return 'unknown'
end

----------------------------------------------------------------------
-- Preview overlay
----------------------------------------------------------------------

function ui.show_preview(node)
    local info = semantics.build_set_info(node) or {}
    local lines_meta = {}
    local preview_cols = math.max(24, math.floor(cfg.preview_width / 7) - 2)

    local function add(txt, color)
        lines_meta[#lines_meta + 1] = { txt = txt or '', color = color or cfg.row_fg_set }
    end

    local function add_wrapped(txt, color)
        txt = tostring(txt or '')
        local prefix = txt:match('^(%s*)') or ''
        local line = txt
        while #line > preview_cols do
            local cut = nil
            for i = preview_cols, #prefix + 1, -1 do
                local ch = line:sub(i, i)
                if ch == ' ' or ch == ',' or ch == '>' then
                    cut = i
                    break
                end
            end
            cut = cut or preview_cols
            add(line:sub(1, cut):gsub('%s+$', ''), color)
            line = prefix .. line:sub(cut + 1):gsub('^%s+', '')
        end
        add(line, color)
    end

    local function section(title)
        add('', cfg.row_fg_set)
        add(title .. ':', cfg.row_fg_cat)
    end

    local title = safe_string(info.title, node and node.key or 'Unknown set')
    local lua_path = compact_path(node, info)
    local source_line = node_location(node, info)
    local kind = short_kind(node, info)
    local inheritance = info.inheritance or {}
    local gear = tree.gear_preview(node) or {}

    -- Put the useful/debuggable data first.  The older UI buried this under
    -- semantic prose, which made the card feel generic during real use.
    add(title, cfg.title_fg)
    add_wrapped('Path: ' .. lua_path, cfg.row_fg_set)
    add_wrapped('Line: ' .. source_line, cfg.row_fg_cursor)
    add_wrapped('Type: ' .. kind, cfg.row_fg_hint)

    if list_count(inheritance.bases) > 0 or list_count(inheritance.references) > 0 or list_count(inheritance.override_slots) > 0 then
        section('Inheritance')
        if list_count(inheritance.bases) > 0 then
            add('  Bases:', cfg.row_fg_hint)
            for _, ref in ipairs(inheritance.bases) do
                add_wrapped('    ' .. tostring(ref), cfg.row_fg_set)
            end
        end
        if list_count(inheritance.references) > 0 then
            add('  References:', cfg.row_fg_hint)
            for _, ref in ipairs(inheritance.references) do
                add_wrapped('    ' .. tostring(ref), cfg.row_fg_set)
            end
        end
        if list_count(inheritance.override_slots) > 0 then
            add('  Overrides:', cfg.row_fg_hint)
            add_wrapped('    ' .. table.concat(inheritance.override_slots, ', '), cfg.row_fg_set)
        end
    else
        section('Inheritance')
        add('  Direct set definition', cfg.row_fg_hint)
    end

    section('Gear')
    add_wrapped('  ' .. tree.describe(node), cfg.row_fg_hint)
    if #gear > 0 then
        for _, item in ipairs(gear) do
            add_wrapped(string.format('  %-10s %s', item.slot, item.value), cfg.row_fg_set)
        end
    else
        add('  No gear slots detected', cfg.row_fg_hint)
    end

    -- Semantic explanation is still useful, just lower priority.
    section('Meaning')
    if info.category and tostring(info.category) ~= '' then
        add_wrapped('  Category: ' .. tostring(info.category), cfg.row_fg_set)
    end
    if info.plain_english and tostring(info.plain_english) ~= '' then
        add_wrapped('  ' .. tostring(info.plain_english), cfg.row_fg_set)
    end
    if info.trigger and tostring(info.trigger) ~= '' then
        add_wrapped('  Trigger: ' .. tostring(info.trigger), cfg.row_fg_set)
    end
    if info.purpose and tostring(info.purpose) ~= '' then
        add_wrapped('  Purpose: ' .. tostring(info.purpose), cfg.row_fg_set)
    end

    if info.conditions and #info.conditions > 0 then
        section('Conditions')
        for _, condition in ipairs(info.conditions) do
            add_wrapped('  ' .. tostring(condition), cfg.row_fg_set)
        end
    end

    if info.confidence and tostring(info.confidence) ~= '' then
        section('Confidence')
        add_wrapped('  ' .. tostring(info.confidence), cfg.row_fg_hint)
    end

    if info.evidence and #info.evidence > 0 then
        section('Evidence')
        for _, item in ipairs(info.evidence) do
            add_wrapped('  ' .. tostring(item), cfg.row_fg_hint)
        end
    end

    state.preview_title:text(' Info: ' .. title .. ' ')
    state.preview_title:visible(true)
    state.preview_bg:visible(true)
    for i = 1, cfg.preview_rows do
        local meta = lines_meta[i]
        local obj = state.preview_objs[i]
        if meta then
            obj:text(meta.txt)
            obj:color(meta.color[1], meta.color[2], meta.color[3])
            obj:visible(true)
        else
            obj:text('')
            obj:visible(false)
        end
    end
    state.preview_visible = true
end

function ui.hide_preview()
    state.preview_visible = false
    if state.preview_title then state.preview_title:visible(false) end
    if state.preview_bg    then state.preview_bg:visible(false)    end
    for _, obj in ipairs(state.preview_objs) do obj:visible(false) end
end

----------------------------------------------------------------------
-- Auto preview on cursor
----------------------------------------------------------------------

auto_preview = function()
    if state.cursor < 1 or state.cursor > #state.flat then
        ui.hide_preview()
        return
    end
    local entry = state.flat[state.cursor]
    if entry and (entry.node.has_gear or #entry.node.children > 0) then
        ui.show_preview(entry.node)
    else
        ui.hide_preview()
    end
end

local function activate_node(node)
    if not node then return end

    if node.has_gear then
        local cmd = tree.equip_command(node)
        if cmd then
            if state.equip_callback then
                state.equip_callback(node, cmd)
            else
                windower.send_command(cmd)
            end
        end
    end

    if #node.children > 0 then
        tree.toggle(node)
        state.flat = tree.flatten(state.root)
        state.cursor = math.min(state.cursor, #state.flat)
    end

    ui.refresh()
    auto_preview()
end

----------------------------------------------------------------------
-- Keyboard navigation
----------------------------------------------------------------------

function ui.cursor_up()
    if not state.visible or #state.flat == 0 then return end
    if state.cursor <= 1 then
        state.cursor = #state.flat  -- wrap to bottom
        state.scroll = math.max(0, #state.flat - cfg.visible_rows)
    else
        state.cursor = state.cursor - 1
        if state.cursor <= state.scroll then
            state.scroll = math.max(0, state.cursor - 1)
        end
    end
    ui.refresh()
    auto_preview()
end

function ui.cursor_down()
    if not state.visible or #state.flat == 0 then return end
    if state.cursor >= #state.flat then
        state.cursor = 1  -- wrap to top
        state.scroll = 0
    else
        state.cursor = state.cursor + 1
        if state.cursor > state.scroll + cfg.visible_rows then
            state.scroll = state.cursor - cfg.visible_rows
        end
    end
    ui.refresh()
    auto_preview()
end

function ui.cursor_select()
    if not state.visible then return end
    if state.cursor < 1 or state.cursor > #state.flat then return end
    local entry = state.flat[state.cursor]
    if not entry then return end
    activate_node(entry.node)
end

-- Explicit equip entry point for the addon's End-key binding.
-- Kept separate so the keyboard layer does not need to treat Enter as an
-- implicit equip action.
function ui.cursor_equip()
    if not state.visible then return end
    if state.cursor < 1 or state.cursor > #state.flat then return end
    local entry = state.flat[state.cursor]
    if not entry then return end
    if entry.node and entry.node.has_gear then
        local cmd = tree.equip_command(entry.node)
        if cmd then
            if state.equip_callback then
                state.equip_callback(entry.node, cmd)
            else
                windower.send_command(cmd)
            end
        end
    end
    auto_preview()
end

function ui.cursor_back()
    if not state.visible then return end
    if state.cursor < 1 or state.cursor > #state.flat then return end
    local entry = state.flat[state.cursor]
    if not entry then return end
    local node = entry.node
    -- If node is expanded, collapse it
    if #node.children > 0 and node.expanded then
        tree.toggle(node)
        state.flat = tree.flatten(state.root)
        state.cursor = math.min(state.cursor, #state.flat)
        ui.refresh()
        return
    end
    -- Otherwise jump to parent (first entry above with lesser depth)
    local target_depth = entry.depth - 1
    if target_depth < 0 then return end
    for i = state.cursor - 1, 1, -1 do
        if state.flat[i] and state.flat[i].depth == target_depth then
            state.cursor = i
            if state.cursor <= state.scroll then
                state.scroll = math.max(0, state.cursor - 1)
            end
            ui.refresh()
            return
        end
    end
end

----------------------------------------------------------------------
-- Hit testing
----------------------------------------------------------------------
-- Given mouse x,y, return:
--   'title'                 if in title bar
--   'row', node, row_index  if on a tree row
--   nil                     otherwise

local function hit_test(mx, my)
    if not state.visible then return nil end
    local x, y = cfg.pos_x, cfg.pos_y
    -- Title row
    if mx >= x and mx <= x + cfg.width and my >= y and my < y + cfg.row_height then
        return 'title'
    end
    -- Tree rows
    local body_top = y + cfg.row_height
    local body_bot = body_top + cfg.visible_rows * cfg.row_height
    if mx >= x and mx <= x + cfg.width and my >= body_top and my < body_bot then
        local row_idx = math.floor((my - body_top) / cfg.row_height) + 1
        local flat_idx = state.scroll + row_idx
        local entry = state.flat[flat_idx]
        if entry then return 'row', entry.node, row_idx, flat_idx end
    end
    return nil
end

----------------------------------------------------------------------
-- Event entry points (called from the addon's mouse handler)
----------------------------------------------------------------------

-- Returns true if event was handled (so addon can block).
function ui.on_left_click(mx, my)
    local kind, node, _, flat_idx = hit_test(mx, my)
    if kind == 'title' then
        state.drag = { mx = mx, my = my, x = cfg.pos_x, y = cfg.pos_y }
        return true
    elseif kind == 'row' then
        state.cursor = flat_idx
        activate_node(node)
        return true
    end
    return false
end

function ui.on_left_up(mx, my)
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
        reposition(state.drag.x + dx, state.drag.y + dy)
        return true
    end
    return false
end

function ui.on_right_click(mx, my)
    local kind, node, _, flat_idx = hit_test(mx, my)
    if kind == 'row' then
        state.cursor = flat_idx
        if state.preview_visible then
            -- Toggle off if clicking the same node? For now always show new.
            ui.hide_preview()
        end
        ui.show_preview(node)
        return true
    end
    return false
end

function ui.on_scroll(mx, my, delta)
    if not state.visible then return false end
    if delta > 0 then
        ui.cursor_down()
    else
        ui.cursor_up()
    end
    return true
end

function ui.on_middle_click(mx, my)
    if not state.visible then return false end
    local x, y = cfg.pos_x, cfg.pos_y
    local body_top = y + cfg.row_height
    local body_bot = body_top + cfg.visible_rows * cfg.row_height
    if mx >= x and mx <= x + cfg.width and my >= body_top and my < body_bot then
        local row_idx = math.floor((my - body_top) / cfg.row_height) + 1
        local flat_idx = state.scroll + row_idx
        if state.flat[flat_idx] then
            state.cursor = flat_idx
        end
        ui.cursor_select()
        return true
    end
    return false
end

----------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------

function ui.set_position(x, y)
    reposition(x, y)
end

function ui.get_position()
    return cfg.pos_x, cfg.pos_y
end

function ui.set_equip_callback(callback)
    state.equip_callback = callback
end

function ui.get_selected_node()
    if state.cursor < 1 or state.cursor > #state.flat then return nil end
    local entry = state.flat[state.cursor]
    return entry and entry.node or nil
end

function ui.rebuild(new_root)
    state.root = new_root
    state.flat = tree.flatten(state.root)
    state.scroll = 0
    if #state.flat > 0 then
        state.cursor = math.max(1, math.min(state.cursor, #state.flat))
    else
        state.cursor = 0
    end
    ui.hide_preview()
    ui.refresh()
end

return ui
