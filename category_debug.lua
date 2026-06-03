-- GearTree category debug helper
-- Builds chat-friendly explanation lines for organized-tree category decisions.
-- This module is intentionally read-only: it does not equip, save, parse, or mutate Lua.

local category_debug = {}
local semantics = require('semantics')
local tree = require('tree')

local function add(lines, text)
    lines[#lines + 1] = tostring(text or '')
end

local function join_list(list, sep, fallback)
    if type(list) ~= 'table' or #list == 0 then
        return fallback or 'none'
    end
    local out = {}
    for i, value in ipairs(list) do
        out[i] = tostring(value)
    end
    return table.concat(out, sep or ', ')
end

local function path_for(node)
    if not node then return 'unknown' end
    local ok, value = pcall(function()
        return tree.path_string(node)
    end)
    if ok and value and value ~= '' then return value end

    local path = node.path or (node.assignment and node.assignment.keys) or {}
    return join_list(path, '.', 'unknown')
end

local function route_for(classification, info)
    if classification and classification.route then
        return join_list(classification.route, ' > ', 'Other > Uncategorized')
    end
    if info and info.category then
        return tostring(info.category)
    end
    return 'unknown'
end

local function intent_for(classification, info)
    if classification and classification.trigger then
        return tostring(classification.trigger)
    end
    if info and info.purpose then
        return tostring(info.purpose)
    end
    return 'unknown'
end

local function add_limited(lines, title, values, max_count)
    add(lines, title .. ':')
    if type(values) ~= 'table' or #values == 0 then
        add(lines, '  - none')
        return
    end

    max_count = max_count or #values
    for i = 1, math.min(#values, max_count) do
        add(lines, '  - ' .. tostring(values[i]))
    end
    if #values > max_count then
        add(lines, '  ...and ' .. tostring(#values - max_count) .. ' more')
    end
end

local function collect_warnings(info, classification)
    local warnings = {}

    if not classification then
        warnings[#warnings + 1] = 'No organized classification object was returned.'
    elseif classification.rule == 'no strong path or helper match' then
        warnings[#warnings + 1] = 'Fallback classification; path/reference evidence was weak.'
    end

    if info and info.confidence and tostring(info.confidence):lower() == 'low' then
        warnings[#warnings + 1] = 'Low confidence explanation; verify Lua path and gear content.'
    end

    return warnings
end

function category_debug.explain_node(node)
    if not node then
        return nil, 'Highlight a set or folder first, then use //geartree why.'
    end

    -- Folder nodes (organized categories, virtual user folders) carry no Lua
    -- assignment and no gear. Present them as display folders, not Lua sets,
    -- so the output does not show misleading "Route: Other > Uncategorized" lines.
    if node.has_gear ~= true and node.assignment == nil then
        local lines = {}
        add(lines, 'Selected: ' .. path_for(node))
        add(lines, 'Type: Organized category folder')
        add(lines, 'Lua source: none - virtual GearTree category')
        add(lines, 'Warnings: none')
        return lines, nil
    end

    local info = semantics.build_set_info and semantics.build_set_info(node) or nil
    local classification = semantics.classify_organized and semantics.classify_organized(node) or nil

    if not info and not classification then
        return nil, 'No category explanation is available for the highlighted item.'
    end

    local lines = {}
    add(lines, 'Selected: ' .. path_for(node))
    add(lines, 'Route: ' .. route_for(classification, info))
    add(lines, 'Intent: ' .. intent_for(classification, info))
    add(lines, 'Confidence: ' .. tostring((info and info.confidence) or 'Unknown'))

    if classification then
        add(lines, 'Classifier source: ' .. tostring(classification.source or 'unknown'))
        add(lines, 'Classifier rule: ' .. tostring(classification.rule or 'unknown'))
    end

    if info and info.source then
        add(lines, 'Lua source: ' .. tostring(info.source))
    end

    add_limited(lines, 'Evidence', (info and info.evidence) or {}, 10)

    if classification and classification.debug and #classification.debug > 0 then
        add_limited(lines, 'Classifier debug', classification.debug, 8)
    end

    local warnings = collect_warnings(info, classification)
    if #warnings > 0 then
        add_limited(lines, 'Warnings', warnings, 6)
    else
        add(lines, 'Warnings: none')
    end

    return lines, nil
end

return category_debug
