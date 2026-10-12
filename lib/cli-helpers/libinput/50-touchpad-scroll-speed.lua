-- Slows down two-finger scrolling on touchpads.
--
-- GNOME has no setting for the touchpad scroll speed, so this plugin scales
-- the finger motion libinput sees while exactly two fingers are down: the
-- scroll distance shrinks by FACTOR. One-finger pointer motion and three- or
-- four-finger gestures stay as they are; a two-finger pinch slows down too.
--
-- gnome-apply-settings links it into ~/.config/libinput/plugins, where mutter
-- (GNOME 50, libinput 1.30 or later) loads it on login, so a change takes
-- effect after logging out and in again.

local FACTOR = 0.5

libinput:register({1})

local function scale_touchpad(device)
    local absinfos = device:absinfos()
    local range = {
        [evdev.ABS_MT_POSITION_X] = absinfos[evdev.ABS_MT_POSITION_X],
        [evdev.ABS_MT_POSITION_Y] = absinfos[evdev.ABS_MT_POSITION_Y],
    }

    -- per slot: whether a finger is down, and per axis the last reported
    -- position and the position passed on to libinput
    local slots = {}
    local current = 0

    local function slot(index)
        if not slots[index] then
            slots[index] = { down = false, real = {}, virtual = {} }
        end
        return slots[index]
    end

    device:connect("evdev-frame", function(_, frame, _)
        -- first pass: the number of fingers down once this frame is applied
        local s = current
        for _, event in ipairs(frame) do
            if event.usage == evdev.ABS_MT_SLOT then
                s = event.value
            elseif event.usage == evdev.ABS_MT_TRACKING_ID then
                slot(s).down = event.value >= 0
            elseif range[event.usage] then
                slot(s).down = true
            end
        end
        local fingers = 0
        for _, state in pairs(slots) do
            if state.down then
                fingers = fingers + 1
            end
        end
        local scale = fingers == 2 and FACTOR or 1

        -- second pass: move the positions by the scaled distance
        local modified = false
        for _, event in ipairs(frame) do
            if event.usage == evdev.ABS_MT_SLOT then
                current = event.value
            elseif event.usage == evdev.ABS_MT_TRACKING_ID then
                local state = slot(current)
                state.real = {}
                state.virtual = {}
            elseif range[event.usage] then
                local state = slot(current)
                local axis = event.usage
                local last = state.real[axis]
                state.real[axis] = event.value
                if last == nil then
                    state.virtual[axis] = event.value
                else
                    local info = range[axis]
                    local virtual = state.virtual[axis] + (event.value - last) * scale
                    virtual = math.max(info.minimum, math.min(info.maximum, virtual))
                    state.virtual[axis] = virtual
                    event.value = math.floor(virtual + 0.5)
                    modified = true
                end
            end
        end
        if modified then
            return frame
        end
        return nil
    end)

    device:connect("device-removed", function(_)
        slots = {}
    end)
end

libinput:connect("new-evdev-device", function(device)
    local props = device:udev_properties()
    local usages = device:usages()
    if props.ID_INPUT_TOUCHPAD and usages[evdev.ABS_MT_POSITION_X] and usages[evdev.ABS_MT_POSITION_Y] then
        libinput:log_info("touchpad-scroll-speed: scaling two-finger motion by " .. FACTOR .. " on " .. device:name())
        scale_touchpad(device)
    end
end)
