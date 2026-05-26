-- GearTree virtual UI layout.
-- This never rewrites GearSwap sets. It only saves display folders, moves,
-- and ordering preferences under GearTree's data folder.

local layout = {}

local data = nil
local layout_file = nil

local function quote(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function is_array(t)
    local max = 0
    local count = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then return false end
        if k > max then max = k end
        count = count + 1
    end
    return max == count
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function serialize(value, indent)
    indent = indent or ''
    local next_indent = indent .. '    '
    if type(value) == 'string' then return quote(value) end
    if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
    if type(value) ~= 'table' then return 'nil' end

    local parts = { '{' }
    if is_array(value) then
        for _, item in ipairs(value) do
            parts[#parts + 1] = '\n' .. next_indent .. serialize(item, next_indent) .. ','
        end
    else
        for _, key in ipairs(sorted_keys(value)) do
            parts[#parts + 1] = '\n' .. next_indent .. '[' .. serialize(key) .. '] = ' ..
                serialize(value[key], next_indent) .. ','
        end
    end
    parts[#parts + 1] = '\n' .. indent .. '}'
    return table.concat(parts)
end

local function read_layout(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if ok and type(result) == 'table' then return result end
    return nil
end

local function ensure_dir()
    local base = (windower and windower.addon_path) or ''
    local dir = base .. 'data/layouts/'
    if windower and windower.dir_exists and not windower.dir_exists(dir) then
        windower.create_dir(dir)
    end
    return dir
end

local function basename(path)
    return path:match('[^/\\]+$') or 'gear'
end

local function sanitize(name)
    return tostring(name):gsub('[^%w_%-%.]', '_')
end

local function normalize(raw)
    raw = type(raw) == 'table' and raw or {}
    raw.version = raw.version or 1
    raw.next_id = raw.next_id or 1
    raw.folders = type(raw.folders) == 'table' and raw.folders or {}
    raw.moves = type(raw.moves) == 'table' and raw.moves or {}
    raw.orders = type(raw.orders) == 'table' and raw.orders or {}
    return raw
end

local function path_string(node)
    if not node or not node.path then return '' end
    local s = node.path[1]
    for i = 2, #node.path do
        local k = node.path[i]
        if k:match('^[%a_][%w_]*$') then
            s = s .. '.' .. k
        else
            s = s .. '["' .. k .. '"]'
        end
    end
    return s
end

local function folder_ref(id)
    return 'folder:' .. tostring(id)
end

local function path_ref(path)
    return 'path:' .. tostring(path)
end

local function ref_id(ref)
    return ref and ref:match('^folder:(.+)$')
end

local function path_from_ref(ref)
    return ref and ref:match('^path:(.+)$')
end

local function folder_by_id(id)
    if not data then return nil end
    for _, folder in ipairs(data.folders) do
        if folder.id == id then return folder end
    end
    return nil
end

local function node_ref(node, root)
    if not node or node == root or (node.path and #node.path == 1 and node.path[1] == 'sets') then
        return 'root'
    end
    if node.virtual then return folder_ref(node.virtual_id) end
    return path_ref(path_string(node))
end

function layout.load_for(file_path)
    local dir = ensure_dir()
    layout_file = dir .. sanitize(basename(file_path)) .. '.layout.lua'
    data = normalize(read_layout(layout_file))
    return data
end

function layout.save()
    if not layout_file then return false, 'No layout file is loaded.' end
    ensure_dir()
    local f, err = io.open(layout_file, 'w+')
    if not f then return false, err end
    f:write('return ' .. serialize(data) .. '\n')
    f:close()
    return true
end

function layout.reset()
    data = normalize({})
end

function layout.ref_for_node(node, root)
    return node_ref(node, root)
end

function layout.path_for_node(node)
    if not node or node.virtual then return nil end
    return path_string(node)
end

function layout.folder_ref(id)
    return folder_ref(id)
end

function layout.find_folder(name)
    if not data then return nil, 'No layout is loaded.' end
    local q = tostring(name or ''):lower()
    local matches = {}
    for _, folder in ipairs(data.folders) do
        if folder.name:lower() == q then
            matches[#matches + 1] = folder
        end
    end
    if #matches == 0 then
        for _, folder in ipairs(data.folders) do
            if folder.name:lower():find(q, 1, true) then
                matches[#matches + 1] = folder
            end
        end
    end
    if #matches == 0 then return nil, 'Virtual folder not found: ' .. tostring(name) end
    if #matches > 1 then return nil, 'Multiple virtual folders match: ' .. tostring(name) end
    return matches[1]
end

function layout.make_folder(name, parent_ref)
    if not data then data = normalize({}) end
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return nil, 'Folder name is empty.' end
    local id = 'f' .. tostring(data.next_id)
    data.next_id = data.next_id + 1
    local folder = { id = id, name = name, parent = parent_ref or 'root' }
    data.folders[#data.folders + 1] = folder
    return folder
end

function layout.rename_folder(id, name)
    local folder = folder_by_id(id)
    if not folder then return nil, 'Virtual folder not found.' end
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return nil, 'Folder name is empty.' end
    folder.name = name
    return true
end

local function collect_folder_ids(id, out)
    out[id] = true
    local ref = folder_ref(id)
    for _, folder in ipairs(data.folders) do
        if folder.parent == ref then collect_folder_ids(folder.id, out) end
    end
end

local function filter_order_refs(remove_ids)
    for container, refs in pairs(data.orders) do
        if remove_ids[ref_id(container)] then
            data.orders[container] = nil
        else
            local kept = {}
            for _, ref in ipairs(refs) do
                if not remove_ids[ref_id(ref)] then kept[#kept + 1] = ref end
            end
            data.orders[container] = kept
        end
    end
end

function layout.remove_folder(id)
    local folder = folder_by_id(id)
    if not folder then return nil, 'Virtual folder not found.' end

    local remove_ids = {}
    collect_folder_ids(id, remove_ids)

    local folders = {}
    for _, item in ipairs(data.folders) do
        if not remove_ids[item.id] then folders[#folders + 1] = item end
    end
    data.folders = folders

    for path, target_id in pairs(data.moves) do
        if remove_ids[target_id] then data.moves[path] = nil end
    end
    filter_order_refs(remove_ids)
    return true
end

function layout.move_path_to_folder(path, folder_id)
    if not folder_by_id(folder_id) then return nil, 'Virtual folder not found.' end
    data.moves[path] = folder_id
    return true
end

function layout.unmove_path(path)
    data.moves[path] = nil
    return true
end

function layout.set_order(container_ref, refs)
    data.orders[container_ref or 'root'] = refs or {}
    return true
end

function layout.item_refs(children, root)
    local refs = {}
    for _, child in ipairs(children or {}) do
        refs[#refs + 1] = node_ref(child, root)
    end
    return refs
end

local function new_virtual_node(folder)
    return {
        key = folder.name,
        path = { 'virtual', folder.id },
        children = {},
        child_map = {},
        assignment = nil,
        has_gear = false,
        expanded = false,
        virtual = true,
        virtual_id = folder.id,
    }
end

local function rebuild(node, parent)
    node.parent = parent
    node.child_map = {}
    for _, child in ipairs(node.children or {}) do
        child.parent = node
        node.child_map[child.key] = child
        rebuild(child, node)
    end
end

local function walk(node, fn)
    fn(node)
    for _, child in ipairs(node.children or {}) do walk(child, fn) end
end

local function detach(node)
    local parent = node and node.parent
    if not parent then return end
    for i, child in ipairs(parent.children) do
        if child == node then
            table.remove(parent.children, i)
            return
        end
    end
end

local function append(parent, child)
    if parent and child then
        parent.children[#parent.children + 1] = child
        child.parent = parent
    end
end

local function is_descendant(node, possible_parent)
    local parent = node and node.parent
    while parent do
        if parent == possible_parent then return true end
        parent = parent.parent
    end
    return false
end

local function prune_empty_virtual_folders(node)
    if not node or not node.children then return false end

    for i = #node.children, 1, -1 do
        local child = node.children[i]
        if prune_empty_virtual_folders(child) then
            table.remove(node.children, i)
        end
    end

    return node.virtual == true and not node.has_gear and #node.children == 0
end

local function apply_order(parent, ref, root)
    local order = data.orders[ref]
    if not order then return end

    local rank = {}
    for i, item_ref in ipairs(order) do rank[item_ref] = i end
    local original = {}
    for i, child in ipairs(parent.children) do original[child] = i end

    table.sort(parent.children, function(a, b)
        local ra = rank[node_ref(a, root)] or 100000 + original[a]
        local rb = rank[node_ref(b, root)] or 100000 + original[b]
        return ra < rb
    end)
end

function layout.apply(root)
    if not data then return root end

    local original_by_path = {}
    walk(root, function(node)
        if node.path and node.path[1] == 'sets' then
            original_by_path[path_string(node)] = node
        end
    end)
    rebuild(root, nil)

    local folder_nodes = {}
    local pending = {}
    for _, folder in ipairs(data.folders) do pending[#pending + 1] = folder end

    local made_progress = true
    while #pending > 0 and made_progress do
        made_progress = false
        local remaining = {}
        for _, folder in ipairs(pending) do
            local parent
            if folder.parent == 'root' then
                parent = root
            else
                local fid = ref_id(folder.parent)
                local ppath = path_from_ref(folder.parent)
                parent = (fid and folder_nodes[fid]) or (ppath and original_by_path[ppath])
            end
            if parent then
                local node = new_virtual_node(folder)
                folder_nodes[folder.id] = node
                append(parent, node)
                made_progress = true
            else
                remaining[#remaining + 1] = folder
            end
        end
        pending = remaining
    end

    rebuild(root, nil)

    for path, folder_id in pairs(data.moves) do
        local node = original_by_path[path]
        local folder = folder_nodes[folder_id]
        if node and folder and not is_descendant(folder, node) then
            detach(node)
            append(folder, node)
        end
    end

    rebuild(root, nil)
    prune_empty_virtual_folders(root)
    rebuild(root, nil)
    walk(root, function(node)
        apply_order(node, node_ref(node, root), root)
    end)
    rebuild(root, nil)

    return root
end

return layout
