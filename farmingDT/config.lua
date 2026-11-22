Config = {}

-- Gameplay values stay here so they can be changed without touching UI or logic.
Config.MaxPlotsPerPlayer = 3
Config.InteractionDistance = 2.0
Config.DrawDistance = 22.0
Config.MinPlotDistance = 8.0
Config.PlacementDistance = 2.5
Config.PlacementItem = 'farm_plot_kit'
Config.DefaultLayout = 'medium'
Config.InteractControl = 0xCEFD9220 -- INPUT_CONTEXT (E by default)
Config.CancelControl = 0x156F7119 -- INPUT_FRONTEND_CANCEL (Backspace by default)
Config.AdminAce = 'farm.admin'
Config.Debug = false

-- Set `model` to the streamed/known tilled-earth prop supplied by the art team.
-- It is intentionally disabled until a valid RedM model name is available.
Config.PlotVisual = {
    model = false,
    zOffset = 0.0
}

-- Optional area restriction. Leave empty to permit any valid ground location.
-- Each entry is a circle measured in game units: { label = 'Valentine Fields', x = 0.0, y = 0.0, radius = 80.0 }
Config.AllowedPlacementZones = {}

-- Crop visuals are separate from the tilled-land prop. Set enabled to true only
-- after every crop prop has been confirmed/streamed on your server.
Config.CropVisuals = {
    enabled = false,
    slotSpacing = 1.15,
    zOffset = 0.0
}

-- Every action can use a native scenario, an RDR animation dictionary/clip, a
-- local client event, or another resource's client export. `arguments` are
-- passed first; farmingDT sends a final context table with action, duration,
-- plotId, and slotId.
--
-- Dictionary/clip example (from femga/rdr3_discoveries ingameanims_list.lua):
-- provider = 'anim', dictionary = 'your_anim_dictionary', clip = 'your_anim_clip', flags = 1
-- Event example:
-- provider = 'event', event = 'my_animations:client:playFarmAction', arguments = { 'watering' }
-- Export example:
-- provider = 'export', resource = 'my_animations', export = 'playEmote', arguments = { 'watering' }
-- Set `stopEvent` or `stopExport` when an external resource needs a matching
-- explicit stop call. Set fallbackToNative to retain the native scenario if the
-- configured resource is not started or its export fails.
Config.ActionAnimations = {
    seed = { provider = 'native', scenario = 'WORLD_HUMAN_FARMER_WEEDING', duration = 5500, label = 'Planting seeds', arguments = {}, clearTasks = true, fallbackToNative = true },
    water = { provider = 'native', scenario = 'WORLD_HUMAN_BUCKET', duration = 4500, label = 'Watering crop', arguments = {}, clearTasks = true, fallbackToNative = true },
    fertilizer = { provider = 'native', scenario = 'WORLD_HUMAN_FARMER_WEEDING', duration = 5000, label = 'Fertilizing crop', arguments = {}, clearTasks = true, fallbackToNative = true },
    treatment = { provider = 'native', scenario = 'WORLD_HUMAN_FARMER_WEEDING', duration = 4500, label = 'Treating crop', arguments = {}, clearTasks = true, fallbackToNative = true },
    diagnose = { provider = 'native', scenario = 'WORLD_HUMAN_FARMER_WEEDING', duration = 4000, label = 'Diagnosing crop', arguments = {}, clearTasks = true, fallbackToNative = true },
    harvest = { provider = 'native', scenario = 'WORLD_HUMAN_FARMER_WEEDING', duration = 5000, label = 'Harvesting crop', arguments = {}, clearTasks = true, fallbackToNative = true }
}

Config.Farming = {
    moistureDecayMinutes = 12,
    thirstyAt = 20,
    maxMoisture = 100,
    maxFertility = 100,
    fertilityGrowthBonus = 0.20,
    fertilityYieldBonus = 0.25
}

-- Public access remains the default requested behavior. Set an action to false
-- to restrict it to the plot owner (or an admin); add VORP job names only when
-- your server wants job-gated farming.
Config.Access = {
    publicPlant = true,
    publicTend = true,
    publicHarvest = true,
    jobs = {
        seed = {}, water = {}, fertilizer = {}, treatment = {}, harvest = {}
    }
}

Config.Seasons = {
    enabled = false,
    default = 'summer',
    values = {
        spring = { label = 'Spring', growthMultiplier = 1.10, yieldMultiplier = 1.00 },
        summer = { label = 'Summer', growthMultiplier = 1.00, yieldMultiplier = 1.05 },
        autumn = { label = 'Autumn', growthMultiplier = 0.90, yieldMultiplier = 1.00 },
        winter = { label = 'Winter', growthMultiplier = 0.65, yieldMultiplier = 0.80 }
    }
}

-- Another weather resource can set the active value through the farmadmin
-- command or the `farmingDT:server:setWeather` event.
Config.Weather = {
    enabled = false,
    default = 'clear',
    values = {
        clear = { label = 'Clear', growthMultiplier = 1.00, moistureDelta = 0 },
        rain = { label = 'Rain', growthMultiplier = 1.10, moistureDelta = 15 },
        drought = { label = 'Drought', growthMultiplier = 0.80, moistureDelta = -15 },
        storm = { label = 'Storm', growthMultiplier = 0.90, moistureDelta = 5 }
    }
}

Config.Disease = {
    enabled = false,
    checkIntervalMinutes = 20
}

-- Only these VORP job names may reveal diseases that set
-- `requiresDiagnosis = true`. Adjust names to match your server's jobs.
Config.Diagnosis = {
    jobs = { 'farmer' },
    label = 'Farmer'
}

-- Disease checks run in this order. Add a disease key here after defining it
-- below to make it eligible for crops. Chance is evaluated once per check.
Config.DiseaseOrder = { 'wilt', 'root_rot', 'mildew', 'pests', 'blight' }
Config.Diseases = {
    wilt = {
        label = 'Drought Wilt',
        description = 'The plant has been left too dry for too long.',
        maxMoisture = 20,
        chance = 0.14,
        growthMultiplier = 0.70
    },
    root_rot = {
        label = 'Root Rot',
        description = 'Saturated soil is damaging the crop roots.',
        requiresDiagnosis = true,
        minMoisture = 90,
        chance = 0.10,
        growthMultiplier = 0.55
    },
    mildew = {
        label = 'Powdery Mildew',
        description = 'Persistent wet conditions have caused mildew.',
        minMoisture = 68,
        chance = 0.08,
        growthMultiplier = 0.75
    },
    pests = {
        label = 'Field Pests',
        description = 'Pests are feeding on this crop.',
        requiresDiagnosis = true,
        chance = 0.035,
        growthMultiplier = 0.80
    },
    blight = {
        label = 'Crop Blight',
        description = 'A severe infection is spreading through the plant.',
        requiresDiagnosis = true,
        chance = 0.015,
        growthMultiplier = 0.50
    }
}

-- These optional market commands are disabled until the server owner sets
-- prices and item names that exist in their VORP item database.
Config.Market = {
    enabled = false,
    currency = 0, -- VORP 0 = cash, 1 = gold, 2 = rol
    sellPrices = { corn = 2, wheat = 3 },
    shopPrices = {
        farm_plot_kit = 20, corn_seed = 1, wheat_seed = 1,
        water_bucket = 1, field_compost = 2, bone_meal = 4,
        plant_tonic = 3, root_remedy = 4, copper_fungicide = 5, field_pesticide = 4
    }
}
Config.PlotRemoval = {
    ownerOnly = true,
    adminAce = 'farm.admin'
}

-- The placement/backend code selects one of these layouts when a plot is placed.
-- The NUI receives the matching `rows` and `columns` values and renders every
-- returned slot; it is not hard-coded to a fixed number of furrows.
Config.PlotLayouts = {
    small = { label = 'Kitchen Plot', width = 9, length = 12, rows = 2, columns = 3, maxSlots = 6 },
    medium = { label = 'Field Plot', width = 12, length = 18, rows = 3, columns = 4, maxSlots = 12 },
    large = { label = 'Homestead Field', width = 18, length = 24, rows = 4, columns = 5, maxSlots = 20 }
}

-- Growth timings are expressed in minutes. The farming backend should use these
-- values when it calculates the plant state from its planted timestamp.
Config.Crops = {
    corn = {
        label = 'Corn Seed',
        item = 'corn_seed',
        description = 'A hardy field crop suited to open soil.',
        cropType = 'corn',
        harvestItem = 'corn',
        harvestAmount = { min = 2, max = 5 },
        stages = { sprout = 20, young = 45, mature = 90 },
        propByStage = {
            sprout = 'p_corn01x',
            young = 'p_corn02x',
            mature = 'p_corn03x'
        }
    },
    wheat = {
        label = 'Wheat Seed',
        item = 'wheat_seed',
        description = 'A dependable crop with a steady yield.',
        cropType = 'wheat',
        harvestItem = 'wheat',
        harvestAmount = { min = 2, max = 4 },
        stages = { sprout = 18, young = 40, mature = 80 },
        propByStage = {
            sprout = 'p_wheat01x',
            young = 'p_wheat02x',
            mature = 'p_wheat03x'
        }
    }
}

-- Add or remove any entries here. The NUI automatically creates a supply card
-- from every entry it receives; no JavaScript or CSS change is needed for a new
-- seed, water source, or fertilizer.
Config.Consumables = {
    water_bucket = {
        category = 'water',
        label = 'Water Bucket',
        item = 'water_bucket',
        description = 'Raises soil moisture by 35 points.',
        icon = 'W',
        effect = { moisture = 35 },
        consumeAmount = 1
    },
    rain_barrel = {
        category = 'water',
        label = 'Rain Barrel Water',
        item = 'rain_barrel_water',
        description = 'Raises soil moisture by 60 points.',
        icon = 'W',
        effect = { moisture = 60 },
        consumeAmount = 1
    },
    field_compost = {
        category = 'fertilizer',
        label = 'Field Compost',
        item = 'field_compost',
        description = 'Adds fertility and improves the eventual yield.',
        icon = 'F',
        effect = { fertility = 20 },
        consumeAmount = 1
    },
    bone_meal = {
        category = 'fertilizer',
        label = 'Bone Meal',
        item = 'bone_meal',
        description = 'A stronger fertilizer for established plants.',
        icon = 'F',
        effect = { fertility = 40 },
        consumeAmount = 1
    },
    plant_tonic = {
        category = 'treatment',
        label = 'Plant Tonic',
        item = 'plant_tonic',
        description = 'Restores crops suffering from drought wilt.',
        icon = 'T',
        effect = { cures = { 'wilt' } },
        consumeAmount = 1
    },
    root_remedy = {
        category = 'treatment',
        label = 'Root Remedy',
        item = 'root_remedy',
        description = 'Treats crops with root rot.',
        icon = 'R',
        effect = { cures = { 'root_rot' } },
        consumeAmount = 1
    },
    copper_fungicide = {
        category = 'treatment',
        label = 'Copper Fungicide',
        item = 'copper_fungicide',
        description = 'Treats powdery mildew and crop blight.',
        icon = 'F',
        effect = { cures = { 'mildew', 'blight' } },
        consumeAmount = 1
    },
    field_pesticide = {
        category = 'treatment',
        label = 'Field Pesticide',
        item = 'field_pesticide',
        description = 'Removes field pests from a crop.',
        icon = 'P',
        effect = { cures = { 'pests' } },
        consumeAmount = 1
    }
}

Config.UI = {
    title = 'FARMLAND',
    eyebrow = 'PUBLIC FARMING',
    subtitle = 'PUBLIC PLOT MANAGEMENT · SELECT A FURROW TO TEND',
    -- Replace this with a streamed asset URL if the art team provides one.
    -- Example: 'nui://your_resource/html/assets/farmstead-bg.webp'
    backgroundImage = ''
}
