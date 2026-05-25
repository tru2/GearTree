-- Captures and compares the player's currently equipped gear.
--
-- This module is intentionally conservative: it reads Windower's live
-- equipment table, normalizes it into GearTree's canonical slot names, and
-- reports only real slot changes. It does not equip anything and does not
-- write files.

local extdata = require('extdata')
local res     = require('resources')
local slots   = require('gear_slots')

local snapshot = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function has_windower_items_api()
    return windower
       and windower.ffxi
       and windower.ffxi.get_items
end

local function safe_item_resource(item)
    if not item or not item.id or item.id == 0 then return nil end
    return res.items[item.id]
end

local function item_name(item)
    local r = safe_item_resource(item)
    if not r then return nil end
    return r.english or r.en or r.name
end

local function normalize_augment_text(augment)
    if augment == nil then return nil end
    augment = tostring(augment)
    if augment == '' or augment == 'none' then return nil end
    return augment
end

local function item_augments(item)
    local ok, decoded = pcall(extdata.decode, item)
    if not ok or not decoded or type(decoded.augments) ~= 'table' then
        return {}
    end

    local out = {}
    for _, augment in ipairs(decoded.augments) do
        augment = normalize_augment_text(augment)
        if augment then
            out[#out + 1] = augment
        end
    end
    return out
end

local function make_empty(slot)
    return { slot = slot, empty = true }
end

local function make_item(slot, item, bag, index)
    local name = item_name(item)
    if not name then return make_empty(slot) end
    return {
        slot = slot,
        name = name,
        id = item.id,
        bag = bag,
        index = index,
        augments = item_augments(item),
    }
end

----------------------------------------------------------------------
-- Windower equipment access
----------------------------------------------------------------------

local function equipment_table()
    -- Some Windower versions expose get_items('equipment'), while others
    -- require get_items() and then reading .equipment. Support both.
    local ok, equipment = pcall(windower.ffxi.get_items, 'equipment')
    if ok and type(equipment) == 'table' then
        return equipment
    end

    local ok_all, all_items = pcall(windower.ffxi.get_items)
    if ok_all and type(all_items) == 'table' and type(all_items.equipment) == 'table' then
        return all_items.equipment
    end

    return nil
end

local function equipped_slot(equipment, slot)
    local index = equipment[slot]
    local bag = equipment[slot .. '_bag']
    if index and index > 0 and bag ~= nil and bag >= 0 then
        return bag, index
    end

    for _, alias in ipairs(slots.aliases_by_canonical[slot] or {}) do
        index = equipment[alias]
        bag = equipment[alias .. '_bag']
        if index and index > 0 and bag ~= nil and bag >= 0 then
            return bag, index
        end
    end

    return nil, nil
end

local function get_bag_item(bag, index)
    if not bag or not index then return nil end
    local ok, item = pcall(windower.ffxi.get_items, bag, index)
    if ok and type(item) == 'table' and item.id and item.id ~= 0 then
        return item
    end
    return nil
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function snapshot.capture()
    if not has_windower_items_api() then
        return nil, 'Windower item API is not available.'
    end

    local equipment = equipment_table()
    if type(equipment) ~= 'table' then
        return nil, 'Could not read current equipment.'
    end

    local out = {}
    for _, slot in ipairs(slots.order) do
        local bag, index = equipped_slot(equipment, slot)
        local item = get_bag_item(bag, index)
        if item then
            out[slot] = make_item(slot, item, bag, index)
        else
            out[slot] = make_empty(slot)
        end
    end

    return out
end

local function same_augments(a, b)
    a = a or {}
    b = b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        if tostring(a[i]) ~= tostring(b[i]) then return false end
    end
    return true
end

local function same_item(a, b)
    a = a or {}
    b = b or {}

    if a.empty or b.empty then
        return a.empty == b.empty
    end

    -- Name comparison is the important part for normal GearSwap output.
    -- ID is kept as metadata but not required for equality because some
    -- resources/addon environments can omit or normalize IDs differently.
    return a.name == b.name and same_augments(a.augments, b.augments)
end

function snapshot.diff(before, after)
    local changes = {}
    local count = 0

    for _, slot in ipairs(slots.order) do
        local new_item = after and after[slot] or make_empty(slot)
        if not same_item(before and before[slot], new_item) then
            changes[slot] = new_item
            count = count + 1
        end
    end

    return changes, count
end

function snapshot.describe_item(item)
    if not item or item.empty then return 'empty' end
    if item.augments and #item.augments > 0 then
        return item.name .. ' (augmented)'
    end
    return item.name or 'unknown'
end

function snapshot.describe_changes(changes)
    local out = {}
    for _, slot in ipairs(slots.order) do
        if changes and changes[slot] then
            out[#out + 1] = string.format('%s=%s', slot, snapshot.describe_item(changes[slot]))
        end
    end
    return table.concat(out, ', ')
end

return snapshot
