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

function adapter.set_scale(s)
    if backend.set_scale then return backend.set_scale(s) end
end

function adapter.get_scale()
    if backend.get_scale then return backend.get_scale() end
    return 1.0
end

function adapter.set_opacity(pct)
    if backend.set_opacity then return backend.set_opacity(pct) end
end

function adapter.get_opacity()
    if backend.get_opacity then return backend.get_opacity() end
    return 100
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

function adapter.set_mouse_mode(mode)
    if backend.set_mouse_mode then
        return backend.set_mouse_mode(mode)
    end
    return false
end

function adapter.get_mouse_mode()
    if backend.get_mouse_mode then
        return backend.get_mouse_mode()
    end
    return 'left'
end

function adapter.set_cursor_overlay(on)
    if backend.set_cursor_overlay then
        return backend.set_cursor_overlay(on)
    end
    return false
end

function adapter.get_cursor_overlay()
    if backend.get_cursor_overlay then
        return backend.get_cursor_overlay()
    end
    return false
end

function adapter.set_layout_mode(on)
    if backend.set_layout_mode then return backend.set_layout_mode(on) end
    return false
end

function adapter.get_layout_mode()
    if backend.get_layout_mode then return backend.get_layout_mode() end
    return false
end

function adapter.get_layout()
    if backend.get_layout then return backend.get_layout() end
    return {}
end

function adapter.set_layout(t)
    if backend.set_layout then return backend.set_layout(t) end
end

function adapter.reset_layout()
    if backend.reset_layout then return backend.reset_layout() end
    return {}
end

function adapter.layout_lines()
    if backend.layout_lines then return backend.layout_lines() end
    return {}
end

function adapter.bounds_lines()
    if backend.bounds_lines then return backend.bounds_lines() end
    return {}
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

-- Click-lock panel hit-test: true when (mx, my) is inside the full visible
-- GearTree window rectangle (header through footer, all panes).
function adapter.is_mouse_inside_panel(mx, my)
    if backend.is_mouse_inside_panel then
        return backend.is_mouse_inside_panel(mx, my)
    end
    return false
end

-- ── Theme switching pass-throughs ──────────────────────────────────────────
-- These forward to the same-named functions in ui_facelift.lua.
-- ui_notes_backend returns the facelift module directly so backend has them.

function adapter.set_theme_name(name)
    if backend.set_theme_name then return backend.set_theme_name(name) end
    return false
end

function adapter.set_theme_dir(dir)
    if backend.set_theme_dir then return backend.set_theme_dir(dir) end
end

function adapter.get_theme_name()
    if backend.get_theme_name then return backend.get_theme_name() end
    return 'unknown'
end

function adapter.list_themes()
    if backend.list_themes then return backend.list_themes() end
    return {}
end

function adapter.available_themes()
    if backend.available_themes then return backend.available_themes() end
    return {}
end

return adapter
