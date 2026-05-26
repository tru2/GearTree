-- GearTree user notes
-- Stores personal notes outside the GearSwap Lua file.

local notes = {}

local data = nil
local notes_file = nil

local function quote(s)
    return '"' .. tostring(s or '')
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\r', '\\r')
        :gsub('\n', '\\n') .. '"'
end

local function sorted_keys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function serialize(raw)
    local out = {
        'return {',
        '    version = 1,',
        '    notes = {',
    }

    for _, key in ipairs(sorted_keys(raw.notes or {})) do
        local value = raw.notes[key]
        if value and tostring(value) ~= '' then
            out[#out + 1] = '        [' .. quote(key) .. '] = ' .. quote(value) .. ','
        end
    end

    out[#out + 1] = '    },'
    out[#out + 1] = '}'
    return table.concat(out, '\n') .. '\n'
end

local function read_table(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if ok and type(result) == 'table' then return result end
    return nil
end

local function ensure_dir()
    local base = (windower and windower.addon_path) or ''
    local data_dir = base .. 'data/'
    local dir = data_dir .. 'notes/'

    if windower and windower.dir_exists and windower.create_dir then
        if not windower.dir_exists(data_dir) then windower.create_dir(data_dir) end
        if not windower.dir_exists(dir) then windower.create_dir(dir) end
    end

    return dir
end

local function normalize(raw)
    raw = type(raw) == 'table' and raw or {}
    raw.version = raw.version or 1
    raw.notes = type(raw.notes) == 'table' and raw.notes or {}
    return raw
end

local function ensure_loaded()
    if data then return end
    local dir = ensure_dir()
    notes_file = dir .. 'set_notes.lua'
    data = normalize(read_table(notes_file))
end

local function clean_text(text)
    text = tostring(text or '')
    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

function notes.get(key)
    ensure_loaded()
    key = tostring(key or '')
    if key == '' then return '' end
    return tostring(data.notes[key] or '')
end

function notes.set(key, text)
    ensure_loaded()
    key = tostring(key or '')
    if key == '' then return nil, 'No note key was provided.' end

    text = clean_text(text)
    if text == '' then
        data.notes[key] = nil
    else
        data.notes[key] = text
    end

    return notes.save()
end

function notes.clear(key)
    return notes.set(key, '')
end

function notes.save()
    ensure_loaded()
    if not notes_file then return nil, 'No notes file is loaded.' end

    local f, err = io.open(notes_file, 'w+')
    if not f then return nil, err end
    f:write(serialize(data))
    f:close()
    return true
end

function notes.all()
    ensure_loaded()
    return data.notes
end

return notes
