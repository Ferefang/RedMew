local Event = require 'utils.event'
local Gui = require 'utils.gui'
local Token = require 'utils.global_token'
local Task = require 'utils.Task'

local chests = {}
local chests_data = {chests = chests}
local chests_data_token = Token.register_global(chests_data)

Event.on_load(
    function()
        chests_data = Token.get_global(chests_data_token)
        chests = chests_data.chests
    end
)

local chest_gui_frame_name = Gui.uid_name()

local function built_entity(event)
    local entity = event.created_entity
    if not entity or not entity.valid or entity.name ~= 'infinity-chest' then
        return
    end

    local pos = entity.position

    chests[pos.x .. ',' .. pos.y] = {entity = entity, storage = {}}
end

local function mined_entity(event)
    local entity = event.entity
    if not entity or not entity.valid or entity.name ~= 'infinity-chest' then
        return
    end

    local pos = entity.position

    chests[pos.x .. ',' .. pos.y] = nil
end

local function get_stack_size(name)
    local proto = game.item_prototypes[name]
    if not proto then
        log('item prototype ' .. name .. ' not found')
        return 1
    end

    return proto.stack_size
end

local function do_item(name, count, inv, storage)
    local size = get_stack_size(name)
    local diff = count - size

    if diff == 0 then
        return
    end

    local new_amount = 0

    if diff > 0 then
        inv.remove({name = name, count = diff})
        local prev = storage[name] or 0
        new_amount = prev + diff
    elseif diff < 0 then
        local prev = storage[name]
        if not prev then
            return
        end

        diff = math.min(prev, -diff)
        local inserted = inv.insert({name = name, count = diff})
        new_amount = prev - inserted
    end

    if new_amount == 0 then
        storage[name] = nil
    else
        storage[name] = new_amount
    end
end

local function tick()
    local chest
    chests_data.next, chest = next(chests, chests_data.next)

    if not chest then
        return
    end

    local entity = chest.entity
    if not entity or not entity.valid then
        chests[chests_data.next] = nil
    else
        local storage = chest.storage
        local inv = entity.get_inventory(1) --defines.inventory.chest
        local contents = inv.get_contents()

        for name, count in pairs(contents) do
            do_item(name, count, inv, storage)
        end

        for name, _ in pairs(storage) do
            if not contents[name] then
                do_item(name, 0, inv, storage)
            end
        end
    end
end

local function create_chest_gui_content(frame, player, chest)
    local storage = chest.storage
    local inv = chest.entity.get_inventory(1).get_contents()

    local grid = frame.add {type = 'table', column_count = 10, style = 'slot_table'}

    for name, count in pairs(storage) do
        local number = count + (inv[name] or 0)
        grid.add {
            type = 'sprite-button',
            sprite = 'item/' .. name,
            number = number,
            tooltip = name,
            --style = 'slot_button'
            enabled = false
        }
    end

    for name, count in pairs(inv) do
        if not storage[name] then
            grid.add {
                type = 'sprite-button',
                sprite = 'item/' .. name,
                number = count,
                tooltip = name,
                --style = 'slot_button'
                enabled = false
            }
        end
    end

    player.opened = frame
end

local chest_gui_content_callback
chest_gui_content_callback =
    Token.register(
    function(data)
        local player = data.player

        if not player or not player.valid then
            return
        end

        local opened = data.opened
        if not opened or not opened.valid then
            return
        end

        local entity = data.chest.entity
        if not entity.valid then
            player.opened = nil
            opened.destroy()
            return
        end

        if not player.connected then
            player.opened = nil
            opened.destroy()
            return
        end

        opened.clear()
        create_chest_gui_content(opened, player, data.chest)

        Task.set_timeout_in_ticks(60, chest_gui_content_callback, data)
    end
)

local function gui_opened(event)
    if not event.gui_type == defines.gui_type.entity then
        return
    end

    local entity = event.entity
    if not entity or not entity.valid or entity.name ~= 'infinity-chest' then
        return
    end

    local pos = entity.position
    local chest = chests[pos.x .. ',' .. pos.y]

    if not chest then
        return
    end

    local player = game.players[event.player_index]
    if not player or not player.valid then
        return
    end

    local frame =
        player.gui.center.add {type = 'frame', name = chest_gui_frame_name, caption = 'Infinite Storage Chest'}

    create_chest_gui_content(frame, player, chest)

    Task.set_timeout_in_ticks(60, chest_gui_content_callback, {player = player, chest = chest, opened = frame})
end

Event.add(defines.events.on_built_entity, built_entity)
Event.add(defines.events.on_robot_built_entity, built_entity)
Event.add(defines.events.on_player_mined_entity, mined_entity)
Event.add(defines.events.on_robot_mined_entity, mined_entity)
Event.add(defines.events.on_tick, tick)
Event.add(defines.events.on_gui_opened, gui_opened)

Gui.on_custom_close(
    chest_gui_frame_name,
    function(event)
        event.element.destroy()
    end
)

local market_items = require 'resources.market_items'
table.insert(market_items, {price = {{'raw-fish', 100}}, offer = {type = 'give-item', item = 'infinity-chest'}})
