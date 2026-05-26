-- GearTree notes integration layer
-- Wraps the facelift backend so notes can be displayed and edited without
-- changing GearSwap Lua source files.

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

local original_build_set_info = semantics.build_set_info

local function gt_chat(color, message)
    if windower and windower.add_to_chat then
        windower.add_to_chat(color, '[GearTree] ' .. message)
    end
end

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

local function add_note_to_info(node, info)
    info = info or {}
    local path = node and node.path and not node.virtual and tree.path_string(node) or nil
    local note = path and notes.get(path) or ''

    if note ~= '' then
        info.user_note = note

        -- Keep the generated summary intact. Notes are appended after the
        -- normal explanation with a clear section-style header instead of
        -- replacing or leading the top summary paragraph.
        local existing = tostring(info.plain_english or ''):gsub('%s+$', '')
        local note_block = '== Personal Note ==\n' .. note
        if existing ~= '' then
            info.plain_english = existing .. '\n\n' .. note_block
        else
            info.plain_english = note_block
        end
    end

    return info
end

semantics.build_set_info = function(node)
    return add_note_to_info(node, original_build_set_info(node) or {})
end

local function refresh_preview()
    if backend.refresh then backend.refresh() end
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

if windower and windower.register_event then
    windower.register_event('addon command', function(cmd, ...)
        cmd = tostring(cmd or ''):lower()
        if cmd ~= 'note' and cmd ~= 'notes' then return false end
        return handle_note_command({ ... })
    end)
end

return backend
