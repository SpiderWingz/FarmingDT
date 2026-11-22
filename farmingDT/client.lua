local isOpen = false
local activePlotId = nil
local placingLayout = nil
local plots = {}
local plotObjects = {}
local cropObjects = {}
local actionInProgress = false

local function distance(a, b)
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z)
end

local function drawText3D(coords, text)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 0.85)
    if not onScreen then return end
    SetTextScale(0.35, 0.35)
    SetTextColor(235, 218, 181, 215)
    SetTextCentre(true)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', text), x, y)
end

local function deletePlotObject(id)
    local object = plotObjects[id]
    if object and DoesEntityExist(object) then DeleteObject(object) end
    plotObjects[id] = nil
end

local function createPlotObject(plot)
    if not Config.PlotVisual.model or plotObjects[plot.id] then return end
    local model = joaat(Config.PlotVisual.model)
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local object = CreateObject(model, plot.coords.x, plot.coords.y, plot.coords.z + (Config.PlotVisual.zOffset or 0.0), false, false, false, false, false)
    SetEntityHeading(object, plot.heading or 0.0)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(model)
    plotObjects[plot.id] = object
end

local function cropObjectKey(plotId, slotIndex)
    return ('%s:%s'):format(plotId, slotIndex)
end

local function deleteCropObject(key)
    local entry = cropObjects[key]
    if entry and DoesEntityExist(entry.object) then DeleteObject(entry.object) end
    cropObjects[key] = nil
end

local function cropPosition(plot, slotIndex)
    local layout = Config.PlotLayouts[plot.layoutKey]
    if not layout then return plot.coords end
    local zeroIndex = slotIndex - 1
    local row = math.floor(zeroIndex / layout.columns)
    local column = zeroIndex % layout.columns
    local spacing = Config.CropVisuals.slotSpacing
    local forward = (row - ((layout.rows - 1) / 2)) * spacing
    local lateral = (column - ((layout.columns - 1) / 2)) * spacing
    local heading = math.rad(plot.heading or 0.0)
    return {
        x = plot.coords.x + forward * math.sin(heading) + lateral * math.cos(heading),
        y = plot.coords.y + forward * math.cos(heading) - lateral * math.sin(heading),
        z = plot.coords.z + (Config.CropVisuals.zOffset or 0.0)
    }
end

local function syncCropObjects(incoming)
    if not Config.CropVisuals.enabled then
        for key in pairs(cropObjects) do deleteCropObject(key) end
        return
    end

    local desired = {}
    for _, plot in pairs(incoming) do
        for _, cropVisual in ipairs(plot.crops or {}) do
            local crop = Config.Crops[cropVisual.cropKey]
            local modelName = crop and crop.propByStage and crop.propByStage[cropVisual.stage]
            if modelName then
                local key = cropObjectKey(plot.id, cropVisual.index)
                desired[key] = { stage = cropVisual.stage, model = modelName }
                local current = cropObjects[key]
                if not current or current.stage ~= cropVisual.stage or current.model ~= modelName then
                    deleteCropObject(key)
                    local model = joaat(modelName)
                    RequestModel(model)
                    local deadline = GetGameTimer() + 5000
                    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
                    if HasModelLoaded(model) then
                        local coords = cropPosition(plot, cropVisual.index)
                        local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false, false, false)
                        SetEntityHeading(object, plot.heading or 0.0)
                        FreezeEntityPosition(object, true)
                        SetModelAsNoLongerNeeded(model)
                        cropObjects[key] = { object = object, stage = cropVisual.stage, model = modelName }
                    end
                end
            end
        end
    end
    for key in pairs(cropObjects) do
        if not desired[key] then deleteCropObject(key) end
    end
end

local function closestPlot(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance
    for _, plot in pairs(plots) do
        local plotDistance = distance(coords, plot.coords)
        if plotDistance <= maxDistance and (not closestDistance or plotDistance < closestDistance) then
            closest, closestDistance = plot, plotDistance
        end
    end
    return closest, closestDistance
end

RegisterNetEvent('public_farming:client:syncPlots', function(payload)
    local incoming = {}
    for _, plot in ipairs(payload or {}) do
        incoming[plot.id] = plot
        createPlotObject(plot)
    end
    for id in pairs(plots) do
        if not incoming[id] then deletePlotObject(id) end
    end
    plots = incoming
    syncCropObjects(incoming)
end)

RegisterNetEvent('public_farming:client:openPlot', function(payload)
    isOpen = true
    activePlotId = payload.plot.id
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = payload })
end)

RegisterNetEvent('public_farming:client:plotChanged', function(plotId)
    if isOpen and tonumber(plotId) == tonumber(activePlotId) then
        TriggerServerEvent('public_farming:server:openPlot', activePlotId)
    end
end)

RegisterNetEvent('public_farming:client:beginPlacement', function(layoutKey)
    if not Config.PlotLayouts[layoutKey] then return end
    placingLayout = layoutKey
end)

RegisterNetEvent('public_farming:client:beginRemove', function()
    local plot = closestPlot(Config.InteractionDistance + 4.0)
    if plot then TriggerServerEvent('public_farming:server:removePlot', plot.id) end
end)

RegisterNUICallback('close', function(_, callback)
    isOpen = false
    activePlotId = nil
    SetNuiFocus(false, false)
    callback({ ok = true })
end)

RegisterNUICallback('farmAction', function(request, callback)
    TriggerEvent('farmingDT:client:performAction', request)
    callback({ ok = true })
end)

local function buildProviderArguments(animation, context)
    local arguments = {}
    for _, value in ipairs(animation.arguments or {}) do arguments[#arguments + 1] = value end
    arguments[#arguments + 1] = context
    return arguments
end

local function startConfiguredAnimation(ped, animation, context)
    local provider = animation.provider or 'native'
    local started = false
    local clearTasks = animation.clearTasks == true

    if provider == 'native' and animation.scenario then
        TaskStartScenarioInPlace(ped, animation.scenario, -1, true, false, false, false)
        started = true
    elseif provider == 'anim' and animation.dictionary and animation.clip then
        RequestAnimDict(animation.dictionary)
        local deadline = GetGameTimer() + (animation.loadTimeout or 5000)
        while not HasAnimDictLoaded(animation.dictionary) and GetGameTimer() < deadline do Wait(0) end
        if HasAnimDictLoaded(animation.dictionary) then
            TaskPlayAnim(
                ped,
                animation.dictionary,
                animation.clip,
                animation.blendIn or 1.0,
                animation.blendOut or 1.0,
                animation.duration or -1,
                animation.flags or 1,
                animation.playbackRate or 1.0,
                false, false, false,
                animation.ikFlags or 0,
                false, '', false
            )
            started = true
        end
    elseif provider == 'event' and animation.event then
        if not animation.resource or GetResourceState(animation.resource) == 'started' then
            TriggerEvent(animation.event, table.unpack(buildProviderArguments(animation, context)))
            started = true
        end
    elseif provider == 'export' and animation.resource and animation.export then
        if GetResourceState(animation.resource) == 'started' then
            local ok = pcall(function()
                exports[animation.resource][animation.export](table.unpack(buildProviderArguments(animation, context)))
            end)
            started = ok
        end
    elseif provider == 'none' then
        started = true
    end

    if not started and animation.fallbackToNative and animation.scenario then
        TaskStartScenarioInPlace(ped, animation.scenario, -1, true, false, false, false)
        started, clearTasks = true, true
    end
    return started, clearTasks
end

local function stopConfiguredAnimation(ped, animation, context, clearTasks)
    if animation.stopEvent then
        TriggerEvent(animation.stopEvent, table.unpack(buildProviderArguments(animation, context)))
    elseif animation.stopExport and animation.resource and GetResourceState(animation.resource) == 'started' then
        pcall(function()
            exports[animation.resource][animation.stopExport](table.unpack(buildProviderArguments(animation, context)))
        end)
    end
    if clearTasks then ClearPedTasks(ped) end
end

RegisterNetEvent('farmingDT:client:performAction', function(request)
    if actionInProgress or type(request) ~= 'table' then return end
    local animation = Config.ActionAnimations[request.action]
    if not animation then return end

    actionInProgress = true
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    CreateThread(function()
        local ped = PlayerPedId()
        local context = {
            action = request.action,
            duration = animation.duration,
            label = animation.label,
            plotId = request.plotId,
            slotId = request.slotId,
            request = request
        }
        local started, clearTasks = startConfiguredAnimation(ped, animation, context)
        if not started then
            actionInProgress = false
            return
        end
        TriggerEvent('farmingDT:client:animationStarted', context)
        local endsAt = GetGameTimer() + animation.duration
        local cancelled = false
        while GetGameTimer() < endsAt do
            drawText3D(GetEntityCoords(ped), ('%s  ·  [Backspace] Cancel'):format(animation.label))
            if IsControlJustReleased(0, Config.CancelControl) then
                cancelled = true
                break
            end
            Wait(0)
        end
        stopConfiguredAnimation(ped, animation, context, clearTasks)
        TriggerEvent('farmingDT:client:animationStopped', context, cancelled)
        actionInProgress = false
        if not cancelled then TriggerServerEvent('public_farming:server:requestAction', request) end
    end)
end)

-- Keep this preview command for UI work. It never changes inventory or database state.
RegisterCommand('farmui', function()
    TriggerEvent('public_farming:client:openPlot', {
        plot = {
            id = 'preview', label = 'Public Field 01', access = 'PUBLIC',
            layout = { rows = 3, columns = 4 }, dimensions = { width = 12, length = 18, unit = 'FT' },
            slots = {
                { id = 1, number = '01', state = 'empty', label = 'Empty Soil' },
                { id = 2, number = '02', state = 'growing', label = 'Young Corn', crop = 'Corn', growth = 48, moisture = 38, fertility = 45 },
                { id = 3, number = '03', state = 'ready', label = 'Mature Wheat', crop = 'Wheat', growth = 100, moisture = 64, fertility = 77 },
                { id = 4, number = '04', state = 'thirsty', label = 'Thirsty Corn', crop = 'Corn', growth = 72, moisture = 14, fertility = 56 },
                { id = 5, number = '05', state = 'empty', label = 'Empty Soil' },
                { id = 6, number = '06', state = 'growing', label = 'Young Corn', crop = 'Corn', growth = 31, moisture = 67, fertility = 35 },
                { id = 7, number = '07', state = 'empty', label = 'Empty Soil' },
                { id = 8, number = '08', state = 'ready', label = 'Mature Wheat', crop = 'Wheat', growth = 100, moisture = 57, fertility = 62 },
                { id = 9, number = '09', state = 'empty', label = 'Empty Soil' },
                { id = 10, number = '10', state = 'growing', label = 'Young Corn', crop = 'Corn', growth = 39, moisture = 51, fertility = 28 },
                { id = 11, number = '11', state = 'thirsty', label = 'Thirsty Corn', crop = 'Corn', growth = 42, moisture = 13, fertility = 43 },
                { id = 12, number = '12', state = 'empty', label = 'Empty Soil' }
            }
        },
        supplies = {
            { id = 'corn', category = 'seed', label = 'Corn Seed', description = 'A hardy field crop suited to open soil.', count = 12, icon = 'S' },
            { id = 'wheat', category = 'seed', label = 'Wheat Seed', description = 'A dependable crop with a steady yield.', count = 8, icon = 'S' },
            { id = 'water_bucket', category = 'water', label = 'Water Bucket', description = 'Raises soil moisture by 35 points.', count = 3, icon = 'W' },
            { id = 'rain_barrel', category = 'water', label = 'Rain Barrel Water', description = 'Raises soil moisture by 60 points.', count = 1, icon = 'W' },
            { id = 'field_compost', category = 'fertilizer', label = 'Field Compost', description = 'Adds fertility and improves the eventual yield.', count = 4, icon = 'F' },
            { id = 'bone_meal', category = 'fertilizer', label = 'Bone Meal', description = 'A stronger fertilizer for established plants.', count = 2, icon = 'F' }
        },
        ui = Config.UI
    })
end, false)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('public_farming:server:requestPlots')
    while true do
        local sleep = 1000
        local plot, plotDistance = closestPlot(Config.DrawDistance)
        if plot then
            sleep = 0
            if plotDistance <= Config.InteractionDistance + 1.5 then
                drawText3D(plot.coords, '[E] Public Farm Plot')
                if IsControlJustReleased(0, Config.InteractControl) and not isOpen then
                    TriggerServerEvent('public_farming:server:openPlot', plot.id)
                end
            end
        end

        if placingLayout then
            sleep = 0
            local ped = PlayerPedId()
            local candidate = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.PlacementDistance, 0.0)
            local foundGround, groundZ = GetGroundZFor_3dCoord(candidate.x, candidate.y, candidate.z + 3.0, false)
            if foundGround then candidate = vector3(candidate.x, candidate.y, groundZ) end
            drawText3D(candidate, ('[E] Place %s plot  ·  [Backspace] Cancel'):format(Config.PlotLayouts[placingLayout].label))
            if IsControlJustReleased(0, Config.InteractControl) then
                TriggerServerEvent('public_farming:server:placePlot', { x = candidate.x, y = candidate.y, z = candidate.z }, placingLayout, GetEntityHeading(ped))
                placingLayout = nil
            elseif IsControlJustReleased(0, Config.CancelControl) then
                placingLayout = nil
            end
        end
        Wait(sleep)
    end
end)

-- Refresh an open field periodically so time-based growth and moisture decay do
-- not look stale while a player leaves the farming UI open.
CreateThread(function()
    while true do
        Wait(30000)
        if isOpen and activePlotId and activePlotId ~= 'preview' then
            TriggerServerEvent('public_farming:server:openPlot', activePlotId)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(plotObjects) do deletePlotObject(id) end
    for key in pairs(cropObjects) do deleteCropObject(key) end
    SetNuiFocus(false, false)
end)
