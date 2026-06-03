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

local function is_help_command(cmd)
    cmd = tostring(cmd or ''):lower()
    return cmd == 'help' or cmd == '?'
end

local function help_log(message)
    if log then
        log(message)
    else
        gt_chat(CHAT.info, message)
    end
end

local function print_note_help()
    help_log('  //gt note <text>     - save a personal note on highlighted set/folder')
    help_log('  //gt note            - show the note for highlighted set/folder')
    help_log('  //gt note clear      - clear the note for highlighted set/folder')
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

local function append_lua_notes_section_to_cards(cards, node)
    if type(cards) ~= 'table' or type(cards.summary) ~= 'table' then return end
    local lua_notes = node and node.assignment and node.assignment.lua_notes
    if not lua_notes or #lua_notes == 0 then return end

    local summary = cards.summary
    append_line(summary, '', NOTE_TEXT_COLOR)
    append_line(summary, 'Lua Notes', NOTE_HEADER_COLOR)
    for _, line in ipairs(lua_notes) do
        append_wrapped(summary, line, NOTE_TEXT_COLOR)
    end

    if cards.summary_only then
        cards.gear = summary
        cards.changes = summary
        cards.evidence = summary
    end
end

local function append_notes_section_to_cards(cards, node)
    if type(cards) ~= 'table' or type(cards.summary) ~= 'table' then return cards end

    local summary = cards.summary
    append_line(summary, '', NOTE_TEXT_COLOR)
    append_line(summary, 'Notes', NOTE_HEADER_COLOR)

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

local function augment_label(kind)
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

    -- Path/rank tags ([A/R5], [B/R20], [C], etc.) are set by augment_tag_for_row and have
    -- the highest display priority. Never overwrite or append alongside them.
    if left:match('%[[ABCD][^%]]*%]%s*$') then
        return
    end

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

local function copies_are_heterogeneous(item_id)
    if not item_id then return false end
    local locations = backend_state
        and backend_state.inventory_locations
        and backend_state.inventory_locations.items_by_id
        and backend_state.inventory_locations.items_by_id[item_id]
    if type(locations) ~= 'table' or #locations < 2 then return false end
    local first_key = nil
    for _, location in ipairs(locations) do
        local augs = location.augments or {}
        local key = table.concat(augs, '\31')
        if first_key == nil then
            first_key = key
        elseif key ~= first_key then
            return true
        end
    end
    return false
end

local function augment_hints_for_row(row)
    if not row or not row.text then return end

    local expected_augments = row.expected_augments or {}
    if has_augments(expected_augments) then
        -- Case 2: Lua specifies augments, item ID matched, but equipped augments differ.
        if row.id_match == true and row.augment_match == false and has_augments(row.equipped_augments) then
            apply_augment_label_to_row(row, augment_label('aug!'))
            local reason = tostring(row.status_reason or '')
            if not reason:find('wrong augment', 1, true) then
                row.status_reason = (reason ~= '' and (reason .. ' ') or '') ..
                    'Item ID matched but equipped augments differ from Lua specification.'
            end
        else
            apply_augment_label_to_row(row, augment_label('aug'))
        end
        return
    end

    local actual_augments
    if row.id_match == true and has_augments(row.equipped_augments) then
        actual_augments = row.equipped_augments
    elseif row.expected_item_id ~= nil then
        actual_augments = first_augments_for_item_id(row.expected_item_id)
    end

    if has_augments(actual_augments) then
        -- actual_augments came from decoded extdata (equipped snapshot or inventory scan),
        -- so the augment data is confirmed readable. Use [aug] not [aug?].
        apply_augment_label_to_row(row, augment_label('aug'))
        local reason = tostring(row.status_reason or '')
        if not reason:find('augmented copy', 1, true) then
            row.status_reason = (reason ~= '' and (reason .. ' ') or '') ..
                'Lua does not require augments, but an augmented copy was found.'
        end
    elseif copies_are_heterogeneous(row.expected_item_id) then
        -- Case 4: No augment spec in Lua, multiple inventory copies have different augments.
        apply_augment_label_to_row(row, augment_label('aug?'))
        local reason = tostring(row.status_reason or '')
        if not reason:find('multiple augmented', 1, true) then
            row.status_reason = (reason ~= '' and (reason .. ' ') or '') ..
                'Multiple copies with different augments exist; Lua does not specify which.'
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
        append_lua_notes_section_to_cards(cards, node)   -- Lua source comments (read-only)
        append_notes_section_to_cards(cards, node)        -- GearTree user notes (editable)
        add_augment_hints_to_cards(cards)
        return cards
    end

    debug.setupvalue(holder.owner, holder.index, build_preview_cards_with_integrations)
    return true
end

patch_preview_builder()
patch_lookup_cache()

local function force_summary_after_note_refresh()
    local state = backend_state
    if not state or type(state.preview_cards) ~= 'table' then return end

    if state.preview_cards.summary_only then
        -- Category cards are summary-only. ui_facelift uses nil internally for
        -- that mode, so do not force the literal Summary tab.
        state.preview_card = nil
        state.preview_lines = state.preview_cards.summary or state.preview_lines
    else
        state.preview_card = 'summary'
        state.preview_lines = state.preview_cards.summary or state.preview_lines
    end

    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
end

local function refresh_preview(prefer_summary)
    local node = backend.get_selected_node and backend.get_selected_node() or nil
    if node and backend.show_preview then
        backend.show_preview(node)
        if prefer_summary then
            force_summary_after_note_refresh()
            if backend.refresh then backend.refresh() end
        end
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
        refresh_preview(true)
        return true
    end

    if lower == 'clear' or lower == 'delete' or lower == 'remove' then
        local ok, err = notes.clear(key)
        if not ok then
            gt_chat(CHAT.error, 'Note clear failed: ' .. tostring(err))
            return true
        end
        gt_chat(CHAT.success, 'Cleared note for ' .. key)
        refresh_preview(true)
        return true
    end

    local ok, err = notes.set(key, text)
    if not ok then
        gt_chat(CHAT.error, 'Note save failed: ' .. tostring(err))
        return true
    end

    gt_chat(CHAT.success, 'Saved note for ' .. key)
    refresh_preview(true)
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
                -- Note: //gt note help is included in GearTree.lua's //gt help block.
                -- print_note_help() is not appended here to avoid duplicating it.
                local handled = callback(cmd, ...)
                return handled
            end)
        end
        return original_register_event(event_name, callback)
    end
end

return backend
