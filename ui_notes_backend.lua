-- GearTree notes integration layer
-- Wraps the facelift backend so personal notes can be displayed and edited
-- without changing GearSwap Lua source files.

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

local function find_upvalue(fn, target_name)
    if type(debug) ~= 'table' or type(debug.getupvalue) ~= 'function' then return nil end
    if type(fn) ~= 'function' then return nil end

    for i = 1, 80 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == target_name then return value end
    end
    return nil
end

local backend_state = find_upvalue(original_show_preview, 'state')

local function selected_path()
    local node = backend.get_selected_node and backend.get_selected_node() or nil
    if not node or node.virtual or not node.path then
        return nil, 'Highlight a real Lua set first.'
    end
    if not node.has_gear then
        return nil, 'Highlight a gear set first.'
    end
    return tree.path_string(node), nil
end

local function note_for_node(node)
    if not node or node.virtual or not node.path then return '' end
    local path = tree.path_string(node)
    if path == '' then return '' end
    return notes.get(path) or ''
end

local function add_note_metadata(node, info)
    info = info or {}
    -- Keep notes as metadata only. Do not inject them into plain_english,
    -- because that makes the note look like it overwrote the generated summary.
    info.user_note = note_for_node(node)
    return info
end

semantics.build_set_info = function(node)
    return add_note_metadata(node, original_build_set_info(node) or {})
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
    for raw in text:gmatch('(.-)\n') do
        append_one(raw)
    end
end

local function append_notes_section(node)
    local state = backend_state
    if not state or type(state.preview_cards) ~= 'table' then return end

    local summary = state.preview_cards.summary
    if type(summary) ~= 'table' then return end

    append_line(summary, '', NOTE_TEXT_COLOR)
    append_line(summary, '== Notes ==', NOTE_HEADER_COLOR)

    local note = note_for_node(node)
    if note == '' then
        append_wrapped(summary, 'No note saved. Use //gt note <text> to add one.', NOTE_DIM_COLOR)
    else
        append_wrapped(summary, note, NOTE_TEXT_COLOR)
    end

    if state.preview_card == 'summary' or state.preview_card == nil then
        state.preview_lines = summary
    end
end

backend.show_preview = function(node)
    local result = original_show_preview(node)
    append_notes_section(node)

    -- original_show_preview renders before the note section exists. Refresh once
    -- after appending so the overlay redraws with the finished Summary card.
    if backend_state and backend_state.visible and backend.refresh then
        backend.refresh()
    end

    return result
end

local function refresh_preview()
    local node = backend.get_selected_node and backend.get_selected_node() or nil
    if node and backend.show_preview then
        backend.show_preview(node)
    elseif backend.refresh then
        backend.refresh()
    end
end

local function handle_note_command(args)
    local path, path_err = selected_path()
    if not path then
        gt_chat(CHAT.warn, path_err or 'Highlight a gear set first.')
        return true
    end

    local text = table.concat(args or {}, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local lower = text:lower()

    if text == '' or lower == 'show' then
        local note = notes.get(path)
        if note == '' then
            gt_chat(CHAT.info, 'No note for ' .. path)
        else
            gt_chat(CHAT.info, 'Note for ' .. path)
            gt_chat(CHAT.detail, note)
        end
        return true
    end

    if lower == 'clear' or lower == 'delete' or lower == 'remove' then
        local ok, err = notes.clear(path)
        if not ok then
            gt_chat(CHAT.error, 'Note clear failed: ' .. tostring(err))
            return true
        end
        gt_chat(CHAT.success, 'Cleared note for ' .. path)
        refresh_preview()
        return true
    end

    local ok, err = notes.set(path, text)
    if not ok then
        gt_chat(CHAT.error, 'Note save failed: ' .. tostring(err))
        return true
    end

    gt_chat(CHAT.success, 'Saved note for ' .. path)
    refresh_preview()
    return true
end

-- Register the real note handler here. Windower still calls every addon-command
-- handler registered by this addon, so we also wrap later registrations to keep
-- the main GearTree command dispatcher from printing "Unknown command: note".
if original_register_event then
    original_register_event('addon command', function(cmd, ...)
        if not is_note_command(cmd) then return false end
        return handle_note_command({ ... })
    end)

    windower.register_event = function(event_name, callback)
        if event_name == 'addon command' and type(callback) == 'function' then
            return original_register_event(event_name, function(cmd, ...)
                if is_note_command(cmd) then
                    return true
                end
                return callback(cmd, ...)
            end)
        end
        return original_register_event(event_name, callback)
    end
end

return backend
