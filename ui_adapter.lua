local backend = require('ui_notes_backend')

local adapter = {}

adapter.backend_name = 'text_facelift'

adapter.capabilities = {
    mouse = true,
    keyboard = true,
    drag = true,
    preview = true,
    external_window = false,
    multi_pane = true,
}

function adapter.get_backend_info()
    local capabilities = {}

    for name, enabled in pairs(adapter.capabilities) do
        capabilities[name] = enabled
    end

    return {
        name = adapter.backend_name,
        capabilities = capabilities,
    }
end

function adapter.configure(overrides)
    return backend.configure(overrides)
end

function adapter.create(root, save_pos_callback)
    return backend.create(root, save_pos_callback)
end

function adapter.destroy()
    return backend.destroy()
end

function adapter.rebuild(root)
    return backend.rebuild(root)
end

function adapter.refresh()
    return backend.refresh()
end

function adapter.show()
    return backend.show()
end

function adapter.hide()
    return backend.hide()
end

function adapter.toggle()
    return backend.toggle()
end

function adapter.is_visible()
    return backend.is_visible()
end

function adapter.set_position(x, y)
    return backend.set_position(x, y)
end

function adapter.get_position()
    return backend.get_position()
end

function adapter.set_equip_callback(callback)
    return backend.set_equip_callback(callback)
end

function adapter.set_selection_callback(callback)
    if backend.set_selection_callback then
        return backend.set_selection_callback(callback)
    end
end

function adapter.get_selected_node()
    return backend.get_selected_node()
end

function adapter.debug_selected_gear()
    if backend.debug_selected_gear then
        return backend.debug_selected_gear()
    end
end

function adapter.debug_selected_slot(slot)
    if backend.debug_selected_slot then
        return backend.debug_selected_slot(slot)
    end
end

function adapter.select_path(path)
    if backend.select_path then
        return backend.select_path(path)
    end
    return false
end

function adapter.select_virtual_folder(id)
    if backend.select_virtual_folder then
        return backend.select_virtual_folder(id)
    end
    return false
end

function adapter.find(text)
    if backend.find then
        return backend.find(text)
    end
    return false
end

function adapter.set_status(text)
    if backend.set_status then
        return backend.set_status(text)
    end
end

function adapter.set_last_saved(path)
    if backend.set_last_saved then
        return backend.set_last_saved(path)
    end
end

function adapter.set_recent_saved_slots(path, slots)
    if backend.set_recent_saved_slots then
        return backend.set_recent_saved_slots(path, slots)
    end
end

function adapter.cursor_up()
    return backend.cursor_up()
end

function adapter.cursor_down()
    return backend.cursor_down()
end

function adapter.cursor_select()
    return backend.cursor_select()
end

function adapter.cursor_equip()
    return backend.cursor_equip()
end

function adapter.cursor_back()
    return backend.cursor_back()
end

function adapter.cursor_right(repeated)
    if backend.cursor_right then
        return backend.cursor_right(repeated == true)
    end
    return backend.cursor_select()
end

function adapter.cursor_left(repeated)
    if backend.cursor_left then
        return backend.cursor_left(repeated == true)
    end
    return backend.cursor_back()
end

function adapter.toggle_preview_focus()
    if backend.toggle_preview_focus then
        return backend.toggle_preview_focus()
    end
end

function adapter.is_preview_focused()
    if backend.is_preview_focused then
        return backend.is_preview_focused()
    end
    return false
end

function adapter.set_changes(path, rows, count)
    if backend.set_changes then
        return backend.set_changes(path, rows, count)
    end
end

function adapter.clear_changes()
    if backend.clear_changes then
        return backend.clear_changes()
    end
end

function adapter.set_current_equipment(path, equipment)
    if backend.set_current_equipment then
        return backend.set_current_equipment(path, equipment)
    end
end

function adapter.clear_current_equipment()
    if backend.clear_current_equipment then
        return backend.clear_current_equipment()
    end
end

function adapter.set_inventory_locations(locations)
    if backend.set_inventory_locations then
        return backend.set_inventory_locations(locations)
    end
end

function adapter.clear_inventory_locations()
    if backend.clear_inventory_locations then
        return backend.clear_inventory_locations()
    end
end

function adapter.set_gear_reference_items(references)
    if backend.set_gear_reference_items then
        return backend.set_gear_reference_items(references)
    end
end

function adapter.on_mouse_move(mx, my)
    return backend.on_mouse_move(mx, my)
end

function adapter.on_left_click(mx, my)
    return backend.on_left_click(mx, my)
end

function adapter.on_left_up(mx, my)
    return backend.on_left_up(mx, my)
end

function adapter.on_right_click(mx, my)
    return backend.on_right_click(mx, my)
end

function adapter.on_scroll(mx, my, delta)
    return backend.on_scroll(mx, my, delta)
end

return adapter
