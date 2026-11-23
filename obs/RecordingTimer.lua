local obs = obslua
local status_path = script_path() .. "recording-status.json"
local previous_status

local function publish(status)
    if status == previous_status then
        return
    end

    local temporary_path = status_path .. ".tmp"
    local file = io.open(temporary_path, "w")
    if not file then
        return
    end

    local wrote = file:write(status, "\n")
    local closed = file:close()
    if wrote and closed and os.rename(temporary_path, status_path) then
        previous_status = status
    end
end

local function update()
    if not obs.obs_frontend_recording_active() then
        publish("null")
        return
    end

    local output = obs.obs_frontend_get_recording_output()
    if not output then
        publish("null")
        return
    end

    local frames = obs.obs_output_get_total_frames(output)
    obs.obs_output_release(output)
    local fps = obs.obs_get_active_fps()
    publish(fps > 0 and tostring(math.floor(frames / fps)) or "null")
end

function script_description()
    return "Liefert die laufende OBS-Aufnahmezeit für die lokale Browserquelle."
end

function script_load()
    update()
    obs.timer_add(update, 250)
end

function script_unload()
    obs.timer_remove(update)
    publish("null")
end
