local VorpCore = exports.vorp_core:GetCore()

local Farm = { plots = {}, slotLocks = {} }
local Runtime = { season = Config.Seasons.default, weather = Config.Weather.default }

local function clamp(value, lower, upper)
    return math.max(lower, math.min(upper, value))
end

local function notify(source, message)
    VorpCore.NotifyRightTip(source, message, 4000)
end

local function getCharacter(source)
    local user = VorpCore.getUser(source)
    return user and user.getUsedCharacter or nil
end

local function getCharacterIdentifier(source)
    local character = getCharacter(source)
    return character and tostring(character.charIdentifier or character.identifier) or nil
end

local function inventoryCount(source, itemName)
    local ok, count = pcall(function() return exports.vorp_inventory:getItemCount(source, itemName) end)
    if not ok then return 0 end
    if type(count) == 'table' then return tonumber(count.count or count.amount or 0) or 0 end
    return tonumber(count) or 0
end

local function removeItem(source, itemName, amount)
    local ok, result = pcall(function() return exports.vorp_inventory:subItem(source, itemName, amount) end)
    return ok and result ~= false
end

local function addItem(source, itemName, amount)
    local ok, result = pcall(function() return exports.vorp_inventory:addItem(source, itemName, amount) end)
    return ok and result ~= false
end

local function playerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return coords and { x = coords.x, y = coords.y, z = coords.z } or nil
end

local function planarDistance(a, b)
    local x, y = a.x - b.x, a.y - b.y
    return math.sqrt(x * x + y * y)
end

local function growth(slot)
    if not slot.cropKey or not Config.Crops[slot.cropKey] then
        return { state = 'empty', growth = 0, moisture = 0, fertility = 0, ageMinutes = 0, stage = 'empty', health = 'Prepared' }
    end

    local crop = Config.Crops[slot.cropKey]
    local elapsed = math.max(0, (os.time() - slot.plantedAt) / 60)
    local duration = crop.growthMinutes or crop.stages.mature
    local multiplier = 1 + (slot.fertility / 100) * Config.Farming.fertilityGrowthBonus
    if Config.Seasons.enabled and Config.Seasons.values[Runtime.season] then
        multiplier = multiplier * Config.Seasons.values[Runtime.season].growthMultiplier
    end
    if Config.Weather.enabled and Config.Weather.values[Runtime.weather] then
        multiplier = multiplier * Config.Weather.values[Runtime.weather].growthMultiplier
    end
    local disease = slot.disease and Config.Diseases[slot.disease]
    if disease then multiplier = multiplier * disease.growthMultiplier end
    duration = duration / multiplier
    local progress = clamp(math.floor((elapsed / duration) * 100), 0, 100)
    local weatherMoisture = Config.Weather.enabled and Config.Weather.values[Runtime.weather] and Config.Weather.values[Runtime.weather].moistureDelta or 0
    local moisture = clamp(slot.water - math.floor(elapsed / Config.Farming.moistureDecayMinutes) + weatherMoisture, 0, Config.Farming.maxMoisture)
    local stage = progress >= 100 and 'mature' or (progress >= 25 and 'young' or 'sprout')
    local health = slot.disease and 'Afflicted' or (moisture <= Config.Farming.thirstyAt and 'Thirsty' or 'Healthy')
    return {
        state = slot.disease and 'diseased' or (progress >= 100 and 'ready' or (moisture <= Config.Farming.thirstyAt and 'thirsty' or 'growing')),
        growth = progress,
        moisture = moisture,
        fertility = slot.fertility,
        ageMinutes = math.floor(elapsed),
        stage = stage,
        health = health
    }
end

local function displayName(crop, state, diseaseKey)
    local cropName = crop.label:gsub(' Seed$', '')
    if state == 'diseased' then
        local disease = Config.Diseases[diseaseKey]
        return ('%s %s'):format(disease and disease.label or 'Diseased', cropName)
    end
    if state == 'ready' then return 'Mature ' .. cropName end
    if state == 'thirsty' then return 'Thirsty ' .. cropName end
    return 'Young ' .. cropName
end

local function formatSlot(slot)
    local status = growth(slot)
    local crop = slot.cropKey and Config.Crops[slot.cropKey]
    local disease = slot.disease and Config.Diseases[slot.disease]
    local needsDiagnosis = disease and disease.requiresDiagnosis and not slot.diagnosed
    return {
        id = slot.id,
        number = string.format('%02d', slot.index),
        state = status.state,
        label = crop and (needsDiagnosis and 'Unidentified Crop Problem' or displayName(crop, status.state, slot.disease)) or 'Empty Soil',
        crop = crop and crop.label:gsub(' Seed$', '') or nil,
        disease = needsDiagnosis and nil or slot.disease,
        diseaseLabel = needsDiagnosis and 'Unidentified Crop Problem' or (disease and disease.label or nil),
        needsDiagnosis = needsDiagnosis or false,
        growth = status.growth,
        moisture = status.moisture,
        fertility = status.fertility,
        ageMinutes = status.ageMinutes,
        stage = status.stage,
        health = status.health
    }
end

local function cropVisuals(plot)
    local result = {}
    for _, slot in ipairs(plot.slots) do
        if slot.cropKey and Config.Crops[slot.cropKey] then
            local status = growth(slot)
            local stage = status.growth >= 100 and 'mature' or (status.growth < 25 and 'sprout' or 'young')
            result[#result + 1] = { index = slot.index, cropKey = slot.cropKey, stage = stage }
        end
    end
    return result
end

local function summaries()
    local result = {}
    for _, plot in pairs(Farm.plots) do
        result[#result + 1] = {
            id = plot.id,
            coords = plot.coords,
            heading = plot.heading,
            layoutKey = plot.layoutKey,
            crops = cropVisuals(plot)
        }
    end
    return result
end

local function isInAllowedPlacementZone(position)
    if #Config.AllowedPlacementZones == 0 then return true end
    for _, zone in ipairs(Config.AllowedPlacementZones) do
        if planarDistance(position, zone) <= zone.radius then return true end
    end
    return false
end

local function syncPlots(target)
    TriggerClientEvent('public_farming:client:syncPlots', target or -1, summaries())
end

local function createSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS public_farming_plots (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT, owner_identifier VARCHAR(100) NOT NULL,
        layout_key VARCHAR(32) NOT NULL, x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
        heading FLOAT NOT NULL DEFAULT 0, created_at INT UNSIGNED NOT NULL,
        PRIMARY KEY (id), KEY idx_public_farming_owner (owner_identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS public_farming_slots (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT, plot_id INT UNSIGNED NOT NULL,
        slot_index SMALLINT UNSIGNED NOT NULL, crop_key VARCHAR(64) NULL, planted_at INT UNSIGNED NULL,
        water TINYINT UNSIGNED NOT NULL DEFAULT 0, fertility TINYINT UNSIGNED NOT NULL DEFAULT 0,
        disease VARCHAR(64) NULL, diagnosed TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (id), UNIQUE KEY uq_public_farming_slot (plot_id, slot_index),
        CONSTRAINT fk_public_farming_slots_plot FOREIGN KEY (plot_id)
          REFERENCES public_farming_plots(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local diseaseColumn = MySQL.query.await("SHOW COLUMNS FROM public_farming_slots LIKE 'disease'")
    if not diseaseColumn or not diseaseColumn[1] then
        MySQL.query.await('ALTER TABLE public_farming_slots ADD COLUMN disease VARCHAR(64) NULL AFTER fertility')
    end
    local diagnosisColumn = MySQL.query.await("SHOW COLUMNS FROM public_farming_slots LIKE 'diagnosed'")
    if not diagnosisColumn or not diagnosisColumn[1] then
        MySQL.query.await('ALTER TABLE public_farming_slots ADD COLUMN diagnosed TINYINT(1) NOT NULL DEFAULT 0 AFTER disease')
    end
end

local function loadPlots()
    Farm.plots = {}
    local rows = MySQL.query.await([[SELECT p.id, p.owner_identifier, p.layout_key, p.x, p.y, p.z, p.heading,
        s.id AS slot_id, s.slot_index, s.crop_key, s.planted_at, s.water, s.fertility, s.disease, s.diagnosed
        FROM public_farming_plots p LEFT JOIN public_farming_slots s ON s.plot_id = p.id
        ORDER BY p.id, s.slot_index]]) or {}

    for _, row in ipairs(rows) do
        local plot = Farm.plots[row.id]
        if not plot then
            plot = {
                id = row.id, ownerIdentifier = row.owner_identifier, layoutKey = row.layout_key,
                coords = { x = row.x, y = row.y, z = row.z }, heading = row.heading, slots = {}
            }
            Farm.plots[row.id] = plot
        end
        if row.slot_id then
            plot.slots[#plot.slots + 1] = {
                id = row.slot_id, index = row.slot_index, cropKey = row.crop_key,
                plantedAt = row.planted_at, water = row.water, fertility = row.fertility,
                disease = row.disease, diagnosed = tonumber(row.diagnosed) == 1
            }
        end
    end
end

local function getPlotSlot(plot, slotId)
    for _, slot in ipairs(plot.slots) do
        if tonumber(slot.id) == tonumber(slotId) then return slot end
    end
end

local function playerCanUsePlot(source, plot)
    local coords = playerCoords(source)
    if not coords then return false end
    local layout = Config.PlotLayouts[plot.layoutKey]
    local radius = layout and math.max(layout.width, layout.length) * 0.25 or 4.0
    return planarDistance(coords, plot.coords) <= math.max(Config.InteractionDistance, radius)
end

local function characterJobName(source)
    local character = getCharacter(source)
    local job = character and (character.job or character.jobName)
    if type(job) == 'table' then job = job.name or job.label end
    return job and tostring(job) or nil
end

local function contains(values, value)
    for _, candidate in ipairs(values or {}) do
        if candidate == value then return true end
    end
    return false
end

local function canDiagnose(source)
    return IsPlayerAceAllowed(source, Config.AdminAce) or contains(Config.Diagnosis.jobs, characterJobName(source))
end

local function canPerformAction(source, plot, action)
    if IsPlayerAceAllowed(source, Config.AdminAce) then return true end
    local identifier = getCharacterIdentifier(source)
    local owner = identifier and identifier == plot.ownerIdentifier
    local public = (action == 'seed' and Config.Access.publicPlant)
        or ((action == 'water' or action == 'fertilizer' or action == 'treatment') and Config.Access.publicTend)
        or (action == 'harvest' and Config.Access.publicHarvest)
        or action == 'diagnose'
    if not public and not owner then return false, 'This action is restricted to the plot owner.' end

    local requiredJobs = Config.Access.jobs[action] or {}
    if #requiredJobs > 0 and not contains(requiredJobs, characterJobName(source)) then
        return false, 'Your job is not permitted to perform this action.'
    end
    return true
end

local function suppliesForPlayer(source)
    local result = {}
    for cropKey, crop in pairs(Config.Crops) do
        result[#result + 1] = {
            id = cropKey, category = 'seed', label = crop.label, description = crop.description,
            count = inventoryCount(source, crop.item), icon = 'S'
        }
    end
    for key, supply in pairs(Config.Consumables) do
        result[#result + 1] = {
            id = key, category = supply.category, label = supply.label, description = supply.description,
            count = inventoryCount(source, supply.item), icon = supply.icon or (supply.category == 'water' and 'W' or 'F')
        }
    end
    return result
end

local function openPlot(source, plot)
    local layout = Config.PlotLayouts[plot.layoutKey]
    if not layout then return end
    local slots = {}
    for _, slot in ipairs(plot.slots) do
        local formatted = formatSlot(slot)
        formatted.canDiagnose = not formatted.needsDiagnosis or canDiagnose(source)
        slots[#slots + 1] = formatted
    end
    TriggerClientEvent('public_farming:client:openPlot', source, {
        plot = {
            id = plot.id, label = ('Public Field %02d'):format(plot.id), access = 'PUBLIC',
            layout = { rows = layout.rows, columns = layout.columns },
            dimensions = { width = layout.width, length = layout.length, unit = 'FT' }, slots = slots
        },
        supplies = suppliesForPlayer(source), ui = Config.UI
    })
end

local function refreshOpenPlots(plotId)
    TriggerClientEvent('public_farming:client:plotChanged', -1, plotId)
end

local function withSlotLock(slotId, fn)
    if Farm.slotLocks[slotId] then return false end
    Farm.slotLocks[slotId] = true
    local ok, err = xpcall(fn, debug.traceback)
    Farm.slotLocks[slotId] = nil
    if not ok then print(('[public_farming] slot action failed: %s'):format(err)) end
    return ok
end

RegisterNetEvent('public_farming:server:requestPlots', function()
    syncPlots(source)
end)

RegisterNetEvent('public_farming:server:openPlot', function(plotId)
    local plot = Farm.plots[tonumber(plotId)]
    if plot and playerCanUsePlot(source, plot) then openPlot(source, plot) end
end)

RegisterNetEvent('public_farming:server:requestAction', function(request)
    local source = source
    if type(request) ~= 'table' then return end
    local plot = Farm.plots[tonumber(request.plotId)]
    if not plot or not playerCanUsePlot(source, plot) then return notify(source, 'You are too far from this farm plot.') end
    local allowed, reason = canPerformAction(source, plot, request.action)
    if not allowed then return notify(source, reason) end
    local slot = getPlotSlot(plot, request.slotId)
    if not slot then return end

    withSlotLock(slot.id, function()
        local status = growth(slot)
        if request.action == 'seed' then
            local crop = Config.Crops[request.supplyId]
            if not crop or slot.cropKey then return notify(source, 'This furrow is already occupied.') end
            if inventoryCount(source, crop.item) < 1 then return notify(source, 'You do not have that seed.') end
            if not removeItem(source, crop.item, 1) then return notify(source, 'Unable to use that seed.') end
            slot.cropKey, slot.plantedAt, slot.water, slot.fertility, slot.disease, slot.diagnosed = request.supplyId, os.time(), 60, 0, nil, false
            MySQL.update.await('UPDATE public_farming_slots SET crop_key = ?, planted_at = ?, water = ?, fertility = ?, disease = NULL, diagnosed = 0 WHERE id = ?', {
                slot.cropKey, slot.plantedAt, slot.water, slot.fertility, slot.id
            })
            notify(source, ('Planted %s.'):format(crop.label))

        elseif request.action == 'water' or request.action == 'fertilizer' then
            local supply = Config.Consumables[request.supplyId]
            if not supply or supply.category ~= request.action then return end
            if not slot.cropKey then return notify(source, 'Plant a seed before tending this furrow.') end
            if status.state == 'ready' then return notify(source, 'This crop is ready to harvest.') end
            if inventoryCount(source, supply.item) < (supply.consumeAmount or 1) then return notify(source, 'You do not have that supply.') end
            if not removeItem(source, supply.item, supply.consumeAmount or 1) then return notify(source, 'Unable to use that supply.') end
            if request.action == 'water' then
                slot.water = clamp(slot.water + (supply.effect.moisture or 0), 0, Config.Farming.maxMoisture)
            else
                slot.fertility = clamp(slot.fertility + (supply.effect.fertility or 0), 0, Config.Farming.maxFertility)
            end
            MySQL.update.await('UPDATE public_farming_slots SET water = ?, fertility = ? WHERE id = ?', { slot.water, slot.fertility, slot.id })
            notify(source, ('Used %s.'):format(supply.label))

        elseif request.action == 'treatment' then
            local supply = Config.Consumables[request.supplyId]
            if not supply or supply.category ~= 'treatment' or not supply.effect.cures then return end
            if not slot.cropKey or not slot.disease then return notify(source, 'This crop does not need treatment.') end
            local disease = Config.Diseases[slot.disease]
            if not disease then return notify(source, 'This crop has an unknown disease configuration.') end
            if disease.requiresDiagnosis and not slot.diagnosed then
                return notify(source, ('A %s must diagnose this crop first.'):format(Config.Diagnosis.label))
            end
            if not contains(supply.effect.cures, '*') and not contains(supply.effect.cures, slot.disease) then
                return notify(source, ('%s cannot treat %s.'):format(supply.label, disease.label))
            end
            if inventoryCount(source, supply.item) < (supply.consumeAmount or 1) then return notify(source, 'You do not have that treatment.') end
            if not removeItem(source, supply.item, supply.consumeAmount or 1) then return notify(source, 'Unable to use that treatment.') end
            slot.disease, slot.diagnosed = nil, false
            MySQL.update.await('UPDATE public_farming_slots SET disease = NULL, diagnosed = 0 WHERE id = ?', { slot.id })
            notify(source, ('Treated the crop with %s.'):format(supply.label))

        elseif request.action == 'diagnose' then
            local disease = slot.disease and Config.Diseases[slot.disease]
            if not disease or not disease.requiresDiagnosis or slot.diagnosed then
                return notify(source, 'This crop does not need diagnosis.')
            end
            if not canDiagnose(source) then
                return notify(source, ('Only a %s can diagnose this crop.'):format(Config.Diagnosis.label))
            end
            slot.diagnosed = true
            MySQL.update.await('UPDATE public_farming_slots SET diagnosed = 1 WHERE id = ?', { slot.id })
            notify(source, ('Diagnosed %s.'):format(disease.label))

        elseif request.action == 'harvest' then
            local crop = slot.cropKey and Config.Crops[slot.cropKey]
            if not crop or status.state ~= 'ready' then return notify(source, 'This crop is not ready to harvest.') end
            local amount = math.random(crop.harvestAmount.min, crop.harvestAmount.max)
            amount = math.max(1, math.floor(amount * (1 + (slot.fertility / 100) * Config.Farming.fertilityYieldBonus)))
            local old = { cropKey = slot.cropKey, plantedAt = slot.plantedAt, water = slot.water, fertility = slot.fertility, disease = slot.disease, diagnosed = slot.diagnosed }
            slot.cropKey, slot.plantedAt, slot.water, slot.fertility, slot.disease, slot.diagnosed = nil, nil, 0, 0, nil, false
            MySQL.update.await('UPDATE public_farming_slots SET crop_key = NULL, planted_at = NULL, water = 0, fertility = 0, disease = NULL, diagnosed = 0 WHERE id = ?', { slot.id })
            if not addItem(source, crop.harvestItem, amount) then
                slot.cropKey, slot.plantedAt, slot.water, slot.fertility, slot.disease, slot.diagnosed = old.cropKey, old.plantedAt, old.water, old.fertility, old.disease, old.diagnosed
                MySQL.update.await('UPDATE public_farming_slots SET crop_key = ?, planted_at = ?, water = ?, fertility = ?, disease = ?, diagnosed = ? WHERE id = ?', {
                    old.cropKey, old.plantedAt, old.water, old.fertility, old.disease, old.diagnosed and 1 or 0, slot.id
                })
                return notify(source, 'You cannot carry the harvest.')
            end
            notify(source, ('Harvested %d %s.'):format(amount, crop.harvestItem))
        else
            return
        end
        refreshOpenPlots(plot.id)
    end)
end)

RegisterNetEvent('public_farming:server:placePlot', function(position, layoutKey, heading)
    local source = source
    local identifier = getCharacterIdentifier(source)
    local layout = Config.PlotLayouts[layoutKey or Config.DefaultLayout]
    if not identifier or not layout or type(position) ~= 'table' then return end
    local current = playerCoords(source)
    local requested = { x = tonumber(position.x), y = tonumber(position.y), z = tonumber(position.z) }
    if not current or not requested.x or not requested.y or not requested.z or planarDistance(current, requested) > Config.PlacementDistance then
        return notify(source, 'Place the field closer to you.')
    end
    if not isInAllowedPlacementZone(requested) then
        return notify(source, 'Farm plots may not be placed in this area.')
    end
    local owned = 0
    for _, plot in pairs(Farm.plots) do
        if plot.ownerIdentifier == identifier then owned = owned + 1 end
        if planarDistance(plot.coords, requested) < Config.MinPlotDistance then return notify(source, 'This is too close to another plot.') end
    end
    if owned >= Config.MaxPlotsPerPlayer then return notify(source, ('You may place only %d plots.'):format(Config.MaxPlotsPerPlayer)) end
    if not Config.Debug then
        if inventoryCount(source, Config.PlacementItem) < 1 then return notify(source, 'You need a farm plot kit.') end
        if not removeItem(source, Config.PlacementItem, 1) then return notify(source, 'Unable to use that plot kit.') end
    end

    local plotId = MySQL.insert.await([[INSERT INTO public_farming_plots
        (owner_identifier, layout_key, x, y, z, heading, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        identifier, layoutKey or Config.DefaultLayout, requested.x, requested.y, requested.z, tonumber(heading) or 0, os.time()
    })
    if not plotId then return notify(source, 'The plot could not be saved. Contact an admin.') end

    local plot = { id = plotId, ownerIdentifier = identifier, layoutKey = layoutKey or Config.DefaultLayout, coords = requested, heading = tonumber(heading) or 0, slots = {} }
    for index = 1, layout.maxSlots do
        local slotId = MySQL.insert.await('INSERT INTO public_farming_slots (plot_id, slot_index) VALUES (?, ?)', { plotId, index })
        plot.slots[#plot.slots + 1] = { id = slotId, index = index, water = 0, fertility = 0 }
    end
    Farm.plots[plotId] = plot
    syncPlots()
    notify(source, 'Public farm plot placed.')
end)

RegisterNetEvent('public_farming:server:removePlot', function(plotId)
    local source = source
    local plot = Farm.plots[tonumber(plotId)]
    if not plot or not playerCanUsePlot(source, plot) then return end
    local identifier = getCharacterIdentifier(source)
    if plot.ownerIdentifier ~= identifier and not IsPlayerAceAllowed(source, Config.AdminAce) then
        return notify(source, 'Only the plot owner or an administrator may remove it.')
    end
    MySQL.update.await('DELETE FROM public_farming_plots WHERE id = ?', { plot.id })
    Farm.plots[plot.id] = nil
    syncPlots()
    notify(source, 'Farm plot removed.')
end)

local function getSlotByIndex(plot, index)
    for _, slot in ipairs(plot.slots) do
        if tonumber(slot.index) == tonumber(index) then return slot end
    end
end

local function isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(source, Config.AdminAce)
end

local function setRuntimeValue(kind, value)
    local values = kind == 'season' and Config.Seasons.values or Config.Weather.values
    if not values[value] then return false end
    Runtime[kind] = value
    for id in pairs(Farm.plots) do refreshOpenPlots(id) end
    return true
end

-- Server resources can call these exports when their weather/season state changes.
exports('setSeason', function(value) return setRuntimeValue('season', value) end)
exports('setWeather', function(value) return setRuntimeValue('weather', value) end)

RegisterCommand('farmadmin', function(source, args)
    if not isAdmin(source) then return end
    local command, first, second = args[1], args[2], args[3]
    if command == 'season' and setRuntimeValue('season', first) then
        if source ~= 0 then notify(source, ('Season set to %s.'):format(first)) end
    elseif command == 'weather' and setRuntimeValue('weather', first) then
        if source ~= 0 then notify(source, ('Weather set to %s.'):format(first)) end
    elseif command == 'delete' then
        local plot = Farm.plots[tonumber(first)]
        if not plot then return end
        MySQL.update.await('DELETE FROM public_farming_plots WHERE id = ?', { plot.id })
        Farm.plots[plot.id] = nil
        syncPlots()
        if source ~= 0 then notify(source, 'Farm plot deleted.') end
    elseif command == 'mature' then
        local plot = Farm.plots[tonumber(first)]
        local slot = plot and getSlotByIndex(plot, second)
        local crop = slot and slot.cropKey and Config.Crops[slot.cropKey]
        if not crop then return end
        local duration = crop.growthMinutes or crop.stages.mature
        slot.plantedAt = os.time() - (duration * 60)
        MySQL.update.await('UPDATE public_farming_slots SET planted_at = ? WHERE id = ?', { slot.plantedAt, slot.id })
        refreshOpenPlots(plot.id)
        if source ~= 0 then notify(source, 'Crop set to mature.') end
    elseif command == 'cure' then
        local plot = Farm.plots[tonumber(first)]
        local slot = plot and getSlotByIndex(plot, second)
        if not slot then return end
        slot.disease, slot.diagnosed = nil, false
        MySQL.update.await('UPDATE public_farming_slots SET disease = NULL, diagnosed = 0 WHERE id = ?', { slot.id })
        refreshOpenPlots(plot.id)
        if source ~= 0 then notify(source, 'Crop cured.') end
    elseif source ~= 0 then
        notify(source, 'farmadmin: season, weather, delete, mature, or cure')
    end
end, false)

local function currencyBalance(character, currency)
    if currency == 1 then return tonumber(character.gold) or 0 end
    if currency == 2 then return tonumber(character.rol) or 0 end
    return tonumber(character.money) or 0
end

RegisterCommand('farmsell', function(source, args)
    if source == 0 or not Config.Market.enabled then return end
    local item, amount = args[1], tonumber(args[2])
    local price = item and Config.Market.sellPrices[item]
    if not price or not amount or amount < 1 then return notify(source, 'Usage: /farmsell [item] [amount]') end
    amount = math.floor(amount)
    if inventoryCount(source, item) < amount then return notify(source, 'You do not have enough to sell.') end
    local character = getCharacter(source)
    if not character then return end
    if not removeItem(source, item, amount) then return notify(source, 'Unable to sell that item.') end
    character.addCurrency(Config.Market.currency, price * amount)
    notify(source, ('Sold %d %s for $%d.'):format(amount, item, price * amount))
end, false)

RegisterCommand('farmbuy', function(source, args)
    if source == 0 or not Config.Market.enabled then return end
    local item, amount = args[1], tonumber(args[2])
    local price = item and Config.Market.shopPrices[item]
    if not price or not amount or amount < 1 then return notify(source, 'Usage: /farmbuy [item] [amount]') end
    amount = math.floor(amount)
    local total = price * amount
    local character = getCharacter(source)
    if not character or currencyBalance(character, Config.Market.currency) < total then return notify(source, 'You cannot afford that.') end
    if not addItem(source, item, amount) then return notify(source, 'You cannot carry that item.') end
    character.removeCurrency(Config.Market.currency, total)
    notify(source, ('Bought %d %s for $%d.'):format(amount, item, total))
end, false)

RegisterCommand('farmplace', function(source, args)
    if source ~= 0 then TriggerClientEvent('public_farming:client:beginPlacement', source, args[1] or Config.DefaultLayout) end
end, false)

RegisterCommand('farmremove', function(source)
    if source ~= 0 then TriggerClientEvent('public_farming:client:beginRemove', source) end
end, false)

CreateThread(function()
    createSchema()
    loadPlots()
    exports.vorp_inventory:registerUsableItem(Config.PlacementItem, function(data)
        TriggerClientEvent('public_farming:client:beginPlacement', data.source, Config.DefaultLayout)
    end)
    local count = 0
    for _ in pairs(Farm.plots) do count = count + 1 end
    print(('[public_farming] Loaded %d persistent plots.'):format(count))
end)

CreateThread(function()
    while true do
        Wait(Config.Disease.checkIntervalMinutes * 60000)
        if Config.Disease.enabled then
            for _, plot in pairs(Farm.plots) do
                local changed = false
                for _, slot in ipairs(plot.slots) do
                    withSlotLock(slot.id, function()
                        local status = growth(slot)
                        if slot.cropKey and not slot.disease then
                            for _, diseaseKey in ipairs(Config.DiseaseOrder) do
                                local disease = Config.Diseases[diseaseKey]
                                local meetsMinimum = not disease.minMoisture or status.moisture >= disease.minMoisture
                                local meetsMaximum = not disease.maxMoisture or status.moisture <= disease.maxMoisture
                                if meetsMinimum and meetsMaximum and math.random() < disease.chance then
                                    slot.disease = diseaseKey
                                    slot.diagnosed = not disease.requiresDiagnosis
                                    MySQL.update.await('UPDATE public_farming_slots SET disease = ?, diagnosed = ? WHERE id = ?', {
                                        diseaseKey, slot.diagnosed and 1 or 0, slot.id
                                    })
                                    changed = true
                                    break
                                end
                            end
                        end
                    end)
                end
                if changed then refreshOpenPlots(plot.id) end
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    local joining = source
    SetTimeout(2500, function()
        if GetPlayerName(joining) then syncPlots(joining) end
    end)
end)
