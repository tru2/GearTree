-- GearTree UI integration layer
-- Wraps the facelift backend so personal notes and small preview enhancements
-- can be added without changing GearSwap Lua source files.
--
-- This is intentionally kept as a single bridge layer. Do not add more wrapper
-- backends for future UI behavior; fold new UI work into ui_facelift.lua during
-- the next cleanup/refactor pass.

local tree = require('tree')
local notes = require('notes')
local semantics = require('semantics')
local backend = require('ui_facelift')

local CHAT = {
    info = 207,
    success = 158,
    warn = 57,
    error = 167,
    detail = 160,
}

local NOTE_HEADER_COLOR = { 245, 210, 120 }
local NOTE_TEXT_COLOR = { 220, 220, 215 }
local NOTE_DIM_COLOR = { 132, 138, 145 }
local NOTE_WRAP_COLS = 52

local original_build_set_info = semantics.build_set_info
local original_show_preview = backend.show_preview
local original_register_event = windower and windower.register_event or nil

local function gt_chat(color, message)
    if windower and windower.add_to_chat then
        windower.add_to_chat(color, '[GearTree] ' .. message)
    end
end

local function is_note_command(cmd)
    cmd = tostring(cmd or ''):lower()
    return cmd == 'note' or cmd == 'notes'
end

local function can_patch_upvalues()
    return type(debug) == 'table'
        and type(debug.getupvalue) == 'function'
        and type(debug.setupvalue) == 'function'
end

local function find_upvalue_holder(fn, target_name)
    if not can_patch_upvalues() or type(fn) ~= 'function' then return nil end

    local seen = {}
    local function walk(current, depth)
        if type(current) ~= 'function' or seen[current] or depth > 12 then return nil end
        seen[current] = true

        for i = 1, 120 do
            local name, value = debug.getupvalue(current, i)
            if not name then break end
            if name == target_name then
                return { owner = current, index = i, value = value }
            end
            if type(value) == 'function' then
                local found = walk(value, depth + 1)
                if found then return found end
            end
        end
        return nil
    end

    return walk(fn, 0)
end

local function find_upvalue_value(fn, target_name)
    local holder = find_upvalue_holder(fn, target_name)
    return holder and holder.value or nil
end

local backend_state = find_upvalue_value(original_show_preview, 'state')

local function note_key_for_node(node)
    if not node then return nil end

    if node.path then
        local key = tree.path_string(node)
        if key and key ~= '' then return key end
    end

    if node.virtual and node.virtual_id then
        return 'virtual:' .. tostring(node.virtual_id)
    end

    if node.key then
        return 'node:' .. tostring(node.key)
    end

    return nil
end

local function selected_note_key()
    local node = backend.get_selected_node and backend.get_selected_node() or nil
    if not node then return nil, 'Highlight a set or folder first.' end

    local key = note_key_for_node(node)
    if not key or key == '' then
        return nil, 'Could not make a stable note key for the highlighted item.'
    end

    return key, nil
end

local function note_for_node(node)
    local key = note_key_for_node(node)
    if not key or key == '' then return '' end
    return notes.get(key) or ''
end

semantics.build_set_info = function(node)
    local info = original_build_set_info(node) or {}
    -- Keep notes as metadata only. Do not inject them into plain_english.
    info.user_note = note_for_node(node)
    return info
end

local function append_line(out, text, color)
    out[#out + 1] = { text = tostring(text or ''), color = color }
end

local function append_wrapped(out, text, color)
    text = tostring(text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')

    local function append_one(raw)
        raw = tostring(raw or '')
        if raw == '' then
            append_line(out, '', color)
            return
        end

        local line = raw
        while #line > NOTE_WRAP_COLS do
            local cut = nil
            for i = NOTE_WRAP_COLS, 12, -1 do
                local ch = line:sub(i, i)
                if ch == ' ' or ch == ',' or ch == '/' then
                    cut = i
                    break
                end
            end
            cut = cut or NOTE_WRAP_COLS
            append_line(out, line:sub(1, cut):gsub('%s+$', ''), color)
            line = line:sub(cut + 1):gsub('^%s+', '')
        end
        append_line(out, line, color)
    end

    if text:sub(-1) ~= '\n' then text = text .. '\n' end
    for raw in text:gmatch('(.-)\n') do append_one(raw) end
end

local function append_notes_section_to_cards(cards, node)
    if type(cards) ~= 'table' or type(cards.summary) ~= 'table' then return cards end

    local summary = cards.summary
    append_line(summary, '', NOTE_TEXT_COLOR)
    append_line(summary, '== Notes ==', NOTE_HEADER_COLOR)

    local note = note_for_node(node)
    if note == '' then
        append_wrapped(summary, 'No note saved. Use //gt note <text> to add one.', NOTE_DIM_COLOR)
    else
        append_wrapped(summary, note, NOTE_TEXT_COLOR)
    end

    if cards.summary_only then
        cards.gear = summary
        cards.changes = summary
        cards.evidence = summary
    end

    return cards
end

local function has_augments(value)
    return type(value) == 'table' and #value > 0
end

local function clean_augment_text(value)
    local text = tostring(value or '')
    text = text:gsub('\r', ' '):gsub('\n', ' ')
    text = text:gsub('[_%-]+', ' ')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

local function compact_path_rank(augments)
    if type(augments) ~= 'table' then return nil end

    local path
    local rank
    local combined_parts = {}

    for _, augment in ipairs(augments) do
        local text = clean_augment_text(augment)
        combined_parts[#combined_parts + 1] = text
    end

    local combined = table.concat(combined_parts, ' / ')
    local lower = combined:lower()

    -- Odyssey and Unity augment tooltips commonly show as:
    --   Type:A/Rank:15[15]/NextRP:0
    -- Treat Type as the displayed augment path, because the game uses Type here
    -- instead of the older Path wording.
    path = lower:match('type%s*:%s*([a-z])')
        or lower:match('type%s+([a-z])')
        or lower:match('path%s*:%s*([a-z])')
        or lower:match('path%s+([a-z])')
        or lower:match('^%s*([a-z])%s*path')

    rank = lower:match('rank%s*:%s*(%d+)')
        or lower:match('rank%s+(%d+)')
        or lower:match('[/%s]r%s*:%s*(%d+)')
        or lower:match('[/%s]r%s*(%d+)')
        or lower:match('^r%s*:%s*(%d+)$')
        or lower:match('^r%s*(%d+)$')

    if path then path = path:upper() end
    if rank then rank = tostring(tonumber(rank) or rank) end

    if path and rank then return path .. '/R' .. rank end
    if path then return path end
    if rank then return 'R' .. rank end
    return nil
end

local function augment_label(kind, augments)
    local compact = compact_path_rank(augments)
    if compact then return '[' .. kind .. ' ' .. compact .. ']' end
    return '[' .. kind .. ']'
end

local function fit_text(text, width)
    text = tostring(text or '')
    width = tonumber(width) or #text
    if width <= 0 then return '' end
    if #text > width then
        if width <= 3 then return text:sub(1, width) end
        return text:sub(1, width - 3) .. '...'
    end
    return text .. string.rep(' ', width - #text)
end

local function apply_augment_label_to_row(row, label)
    if not row or not row.text or not label then return end

    local text = tostring(row.text or '')
    local where_col = tonumber(row.aug_tag_col)
    local item_width = where_col and math.max(1, where_col - 2) or nil
    local left = item_width and text:sub(1, item_width) or text
    local right = item_width and text:sub(item_width + 1) or ''

    if left:find('%[aug[^%]]*%]') then
        left = left:gsub('%[aug[^%]]*%]', label, 1)
    else
        left = left:gsub('%s+$', '') .. ' ' .. label
    end

    row.text = item_width and (fit_text(left, item_width) .. right) or left
end

local function first_augments_for_item_id(item_id)
    local locations = backend_state
        and backend_state.inventory_locations
        and backend_state.inventory_locations.items_by_id
        and backend_state.inventory_locations.items_by_id[item_id]

    if type(locations) ~= 'table' then return nil end
    for _, location in ipairs(locations) do
        if has_augments(location and location.augments) then return location.augments end
    end
    return nil
end

local function augment_hints_for_row(row)
    if not row or not row.text then return end

    local expected_augments = row.expected_augments or {}
    if has_augments(expected_augments) then
        apply_augment_label_to_row(row, augment_label('aug', expected_augments))
        return
    end

    local actual_augments
    if row.id_match == true and has_augments(row.equipped_augments) then
        actual_augments = row.equipped_augments
    elseif row.expected_item_id ~= nil then
        actual_augments = first_augments_for_item_id(row.expected_item_id)
    end

    if has_augments(actual_augments) then
        apply_augment_label_to_row(row, augment_label('aug?', actual_augments))
        local reason = tostring(row.status_reason or '')
        if not reason:find('augmented copy', 1, true) then
            row.status_reason = (reason ~= '' and (reason .. ' ') or '') ..
                'Lua does not require augments, but an augmented copy was found.'
        end
    end
end

local function add_augment_hints_to_cards(cards)
    if type(cards) ~= 'table' or type(cards.gear) ~= 'table' then return cards end
    for _, row in ipairs(cards.gear) do augment_hints_for_row(row) end
    return cards
end

local function patch_lookup_cache()
    local holder = find_upvalue_holder(original_show_preview, 'resource_lookup_result_for_name')
    if not holder or type(holder.value) ~= 'function' then return false end

    local original_lookup = holder.value
    local current_resource_language = find_upvalue_value(original_show_preview, 'current_resource_language')
    local cache = {}

    local function language_key()
        if type(current_resource_language) == 'function' then
            local ok, value = pcall(current_resource_language)
            if ok and value then return tostring(value) end
        end
        return 'unknown'
    end

    local function cached_lookup(name)
        local key = language_key() .. '\31' .. tostring(name or '')
        local cached = cache[key]
        if cached ~= nil then return cached ~= false and cached or nil end

        local result = original_lookup(name)
        cache[key] = result or false
        return result
    end

    debug.setupvalue(holder.owner, holder.index, cached_lookup)
    return true
end

local function patch_preview_builder()
    local holder = find_upvalue_holder(original_show_preview, 'build_preview_cards')
    if not holder or type(holder.value) ~= 'function' then
        gt_chat(CHAT.warn, 'Preview hook was not installed; build_preview_cards not found.')
        return false
    end

    local original_build_preview_cards = holder.value
    local function build_preview_cards_with_integrations(node)
        local cards = original_build_preview_cards(node)
        append_notes_section_to_cards(cards, node)
        add_augment_hints_to_cards(cards)
        return cards
    end

    debug.setupvalue(holder.owner, holder.index, build_preview_cards_with_integrations)
    return true
end

patch_preview_builder()
patch_lookup_cache()

local function refresh_preview()
    local node = backend.get_selected_node and backend.get_selected_node() or nil
    if node and backend.show_preview then
        backend.show_preview(node)
    elseif backend.refresh then
        backend.refresh()
    end
end

local function handle_note_command(args)
    local key, key_err = selected_note_key()
    if not key then
        gt_chat(CHAT.warn, key_err or 'Highlight a set or folder first.')
        return true
    end

    local text = table.concat(args or {}, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local lower = text:lower()

    if text == '' or lower == 'show' then
        local note = notes.get(key)
        if note == '' then
            gt_chat(CHAT.info, 'No note for ' .. key)
        else
            gt_chat(CHAT.info, 'Note for ' .. key)
            gt_chat(CHAT.detail, note)
        end
        return true
    end

    if lower == 'clear' or lower == 'delete' or lower == 'remove' then
        local ok, err = notes.clear(key)
        if not ok then
            gt_chat(CHAT.error, 'Note clear failed: ' .. tostring(err))
            return true
        end
        gt_chat(CHAT.success, 'Cleared note for ' .. key)
        refresh_preview()
        return true
    end

    local ok, err = notes.set(key, text)
    if not ok then
        gt_chat(CHAT.error, 'Note save failed: ' .. tostring(err))
        return true
    end

    gt_chat(CHAT.success, 'Saved note for ' .. key)
    refresh_preview()
    return true
end

if original_register_event then
    original_register_event('addon command', function(cmd, ...)
        if not is_note_command(cmd) then return false end
        return handle_note_command({ ... })
    end)

    windower.register_event = function(event_name, callback)
        if event_name == 'addon command' and type(callback) == 'function' then
            return original_register_event(event_name, function(cmd, ...)
                if is_note_command(cmd) then return true end
                return callback(cmd, ...)
            end)
        end
        return original_register_event(event_name, callback)
    end
end

return backend
