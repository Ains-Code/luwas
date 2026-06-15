-- GAG2 Stock Prediction Tracker v5 FIXED
-- Reads directly from ReplicatedStorage.StockValues
-- Pet spawn notifier + Legendary/Super-only predictions
-- FIXED: Better pet spawning detection with debugging
-- UPDATED: Accurate GAG2 weather only, Exclusive shop removed

local WEBHOOK_URL = "https://discord.com/api/webhooks/1515704094419980338/XlFD0Y1xCfvEVagK8kznLxcEX4LDNHjyMZws41WU1DjAcm-ZIAh_0WjN0qhBpM5eQWAX"
local CHECK_INTERVAL = 10

-- =====================
-- ROLE NOTIFICATIONS
-- =====================
local ROLE_IDS = {
    legendary  = "1515830958941798583",
    super      = "1515831424005967972",
    seeds      = "1515831556826992812",
    gears      = "1515831500199825591",
    crates     = "1515831743146492106", 
    exclusive  = "1515831743146492106",
    -- Pet rarity roles
    pet_mythic    = "1515831783248101396",
    pet_legendary = "1515831783248101396",
    pet_epic      = "1515831783248101396",
    pet_rare      = "1515831783248101396",
}

-- =====================
-- PET SPAWN SETTINGS
-- =====================
local PET_FOLDER_NAME = "PetValues"

local PET_RARITY = {
    ["Mythic"]    = { label = "Mythic",    color = 0xFF0000, emoji = "💀", roleKey = "pet_mythic"    },
    ["Legendary"] = { label = "Legendary", color = 0xFFD700, emoji = "👑", roleKey = "pet_legendary" },
    ["Epic"]      = { label = "Epic",      color = 0x9B59B6, emoji = "💜", roleKey = "pet_epic"      },
    ["Rare"]      = { label = "Rare",      color = 0x3498DB, emoji = "💎", roleKey = "pet_rare"      },
}

local DEFAULT_PET_RARITY = { label = "Common", color = 0x95A5A6, emoji = "🐾", roleKey = nil }

local NOTIFY_PET_RARITIES = { Mythic = true, Legendary = true, Epic = true }

-- =====================
-- LEGENDARY & SUPER ITEMS
-- =====================
local LEGENDARY_ITEMS = {
    ["Legendary Sprinkler"] = true,
    ["Legendary Guild Crate"] = true,
    ["Epic Guild Crate"] = true,
    ["Mythic Guild Crate"] = true,
}

local SUPER_ITEMS = {
    ["Super Sprinkler"] = true,
    ["Super Watering Can"] = true,
    ["Super Guild Crate"] = true,
}

-- =====================
-- RARE DEFINITIONS
-- =====================
local RARE_SEEDS = {
    ["Pomegranate"] = true, ["Poison Apple"] = true, ["Moon Bloom"] = true,
    ["Ghost Pepper"] = true, ["Poison Ivy"] = true, ["Baby Cactus"] = true,
    ["Glow Mushroom"] = true, ["Romanesco"] = true, ["Horned Melon"] = true,
    ["Gold"] = true, ["Rainbow"] = true, ["Dragon Fruit"] = true,
    ["Dragon's Breath"] = true, ["Venus Fly Trap"] = true,
    ["Sunflower"] = true, ["Coconut"] = true
}

local RARE_GEARS = {
    ["Rare Sprinkler"] = true, ["Legendary Sprinkler"] = true,
    ["Super Sprinkler"] = true, ["Invisibility Mushroom"] = true,
    ["Speed Mushroom"] = true, ["Super Watering Can"] = true,
    ["Teleporter"] = true, ["Gnome"] = true, ["Flashbang"] = true,
    ["Shrink Mushroom"] = true, ["Jump Mushroom"] = true,
    ["Supersize Mushroom"] = true
}

local RARE_CRATES = {
    ["Mythic Guild Crate"] = true, ["Epic Guild Crate"] = true,
    ["Legendary Guild Crate"] = true, ["Super Guild Crate"] = true
}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- =====================
-- DATA
-- =====================
local data = {
    lastHash       = "",
    totalRestocks  = 0,
    legendaryRestocks = 0,
    superRestocks     = 0,
    hourlyLegendary   = {},
    hourlySuper       = {},
    hourlyTotal       = {},
    intervals         = {},
    legendaryIntervals = {},
    superIntervals     = {},
    lastRestockTime       = nil,
    lastLegendaryTime     = nil,
    lastSuperTime         = nil,
    seenPets = {},
}
for i = 0, 23 do
    data.hourlyLegendary[i] = 0
    data.hourlySuper[i]     = 0
    data.hourlyTotal[i]     = 0
end

local data_weather = { lastWeather = nil }

-- =====================
-- HELPERS
-- =====================
local function formatTime(seconds)
    if not seconds then return "?" end
    seconds = math.floor(seconds)
    if seconds < 0 then return "now!" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%dm %02ds", m, s)
end

local function formatUnix(unix)
    if not unix or unix == 0 then return "Unknown" end
    return os.date("%H:%M:%S", unix)
end

local function avg(t)
    if #t == 0 then return nil end
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    return s / #t
end

local function round(n, d)
    local m = 10^(d or 0)
    return math.floor(n * m + 0.5) / m
end

-- =====================
-- WEATHER SYSTEM
-- =====================
-- ── Actual GAG2 weather events only ───────────────────────
-- Special/rare events
local WEATHER_EMOJIS = {
    ["Bloodmoon"]  = "🩸",   -- Bloodlit mutation (80x multiplier) — rarest
    ["Starfall"]   = "🌟",   -- Starstruck mutation on random crops
    ["Midas"]      = "✨",   -- Spawns golden seeds + Gold mutation chance
    ["Rainbow"]    = "🌈",   -- Spawns rainbow seeds (collect with E)
    -- Standard weather events
    ["Lightning"]  = "⚡",   -- Shocked/Electric mutation on random crops
    ["Snowfall"]   = "❄️",   -- Frozen mutation on random crops
    ["Rain"]       = "🌧️",  -- 2x growth speed for all plants
    -- Day/night cycle states
    ["Day"]        = "☀️",
    ["Sunset"]     = "🌇",
    ["Night"]      = "🌙",
}

-- Special event weather that deserves bigger alerts + role pings
local SPECIAL_WEATHER = {
    ["Bloodmoon"] = { emoji = "🩸", color = 0xFF0000, roleKey = "legendary" },  -- Bloodlit = 80x
    ["Starfall"]  = { emoji = "🌟", color = 0xFFD700, roleKey = "legendary" },  -- Starstruck = very valuable
    ["Midas"]     = { emoji = "✨", color = 0xFFAA00, roleKey = "legendary" },  -- Golden seeds
    ["Rainbow"]   = { emoji = "🌈", color = 0xFF00FF, roleKey = "legendary" },  -- Rainbow seeds
    ["Lightning"] = { emoji = "⚡", color = 0x9B59B6, roleKey = "gears"    },  -- Electric mutation
    ["Snowfall"]  = { emoji = "❄️", color = 0xADD8E6, roleKey = "seeds"    },  -- Frozen mutation
}

local function getWeatherEmoji(weatherName)
    if not weatherName then return "❓" end
    for wName, emoji in pairs(WEATHER_EMOJIS) do
        if weatherName:find(wName) then
            return emoji
        end
    end
    return "🌍"
end

local function readWeather()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    if not sv then return nil end

    local weatherNode = sv:FindFirstChild("Weather")
                     or sv:FindFirstChild("CurrentWeather")
                     or sv:FindFirstChild("WeatherData")

    if weatherNode then
        if weatherNode:IsA("StringValue") then
            return weatherNode.Value
        end
        local weatherValue = weatherNode:FindFirstChild("Type")
                          or weatherNode:FindFirstChild("Current")
                          or weatherNode:FindFirstChild("Name")
        if weatherValue and weatherValue:IsA("StringValue") then
            return weatherValue.Value
        end
        if weatherNode:IsA("Folder") then
            for _, child in ipairs(weatherNode:GetChildren()) do
                if child:IsA("StringValue") then
                    return child.Value
                end
            end
        end
    end

    local directWeather = sv:FindFirstChild("CurrentWeather")
                       or sv:FindFirstChild("Weather")
    if directWeather and directWeather:IsA("StringValue") then
        return directWeather.Value
    end

    return nil
end

-- Forward-declare sendToDiscord so weather watcher can use it
local sendToDiscord

local function startWeatherWatcher()
    print("[GAG2] 🌤️  Setting up weather tracking...")
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    if not sv then return end

    local weatherNode = sv:FindFirstChild("Weather")
                     or sv:FindFirstChild("CurrentWeather")
                     or sv:FindFirstChild("WeatherData")

    if not weatherNode then
        print("[GAG2] ⚠️  No weather node found – weather watcher inactive")
        return
    end

    local function checkWeatherChange()
        local currentWeather = readWeather()
        if currentWeather and currentWeather ~= data_weather.lastWeather then
            print("[GAG2] 🌤️  Weather changed: " .. currentWeather)
            data_weather.lastWeather = currentWeather

            local isSpecial = SPECIAL_WEATHER[currentWeather]
            local emoji = getWeatherEmoji(currentWeather)

            if isSpecial then
                print("[GAG2] 🚨 SPECIAL WEATHER: " .. currentWeather .. "!")

                local rolePing = ""
                local roleKey = isSpecial.roleKey
                if roleKey and ROLE_IDS[roleKey] then
                    rolePing = "<@&" .. ROLE_IDS[roleKey] .. "> "
                end

                sendToDiscord({
                    content  = rolePing .. emoji .. " **🚨 SPECIAL WEATHER EVENT: " .. currentWeather:upper() .. "! 🚨**",
                    username = "GAG2 Stock Tracker",
                    embeds   = {{
                        title       = emoji .. " ⚡ RARE WEATHER: " .. currentWeather,
                        description = "**A special weather event is happening!**\n\nThis is a rare occurrence. Check the game now!",
                        color       = isSpecial.color,
                        fields      = {
                            { name = "Weather", value = emoji .. " " .. currentWeather, inline = true },
                            { name = "Time",    value = os.date("%H:%M:%S"),            inline = true },
                        },
                        footer    = { text = "SPECIAL EVENT ALERT" },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }}
                })
            else
                sendToDiscord({
                    content  = emoji .. " **Weather Changed!**",
                    username = "GAG2 Stock Tracker",
                    embeds   = {{
                        title       = emoji .. " Weather Update",
                        description = "**New Weather:** " .. emoji .. " " .. currentWeather,
                        color       = 0x3498DB,
                        footer      = { text = os.date("%H:%M:%S") },
                        timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }}
                })
            end
        end
    end

    -- Poll for changes on the same interval as stock
    task.spawn(function()
        while true do
            pcall(checkWeatherChange)
            task.wait(CHECK_INTERVAL)
        end
    end)

    -- Also hook into value-changed events if possible
    if weatherNode:IsA("StringValue") then
        weatherNode.Changed:Connect(function()
            pcall(checkWeatherChange)
        end)
    end

    print("[GAG2] ✅ Weather watcher ACTIVE")
end

-- =====================
-- PET RARITY DETECTION
-- =====================
local function getPetRarity(petName)
    local lowerName = petName:lower()
    for keyword, info in pairs(PET_RARITY) do
        if lowerName:find(keyword:lower()) then
            return info
        end
    end
    return DEFAULT_PET_RARITY
end

-- =====================
-- PET SPAWN NOTIFIER
-- =====================
local function sendPetSpawnAlert(petName, rarityInfo, extra)
    local rolePing = ""
    if rarityInfo.roleKey and ROLE_IDS[rarityInfo.roleKey] then
        rolePing = "<@&" .. ROLE_IDS[rarityInfo.roleKey] .. "> "
    end

    local description = rarityInfo.emoji .. " **" .. petName .. "** has spawned!"
    if extra then description = description .. "\n" .. extra end

    local payload = {
        content  = rolePing .. rarityInfo.emoji .. " **" .. rarityInfo.label:upper() .. " PET SPAWNED!**",
        username = "GAG2 Stock Tracker",
        embeds   = {{
            title       = rarityInfo.emoji .. " Pet Spawn Alert",
            description = description,
            color       = rarityInfo.color,
            fields      = {
                { name = "Pet",    value = "**" .. petName .. "**",                        inline = true },
                { name = "Rarity", value = rarityInfo.emoji .. " " .. rarityInfo.label,   inline = true },
                { name = "Time",   value = os.date("%H:%M:%S"),                            inline = true },
            },
            footer    = { text = "v5 Fixed • Pet Spawn Tracker • " .. os.date("%H:%M:%S") },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    }
    sendToDiscord(payload)
end

-- =====================
-- PET WATCHER
-- =====================
local function startPetWatcher()
    print("[GAG2] 🔍 Scanning ReplicatedStorage for pet folders...")

    for _, item in ipairs(ReplicatedStorage:GetChildren()) do
        print("[GAG2]   Found: " .. item.Name .. " (" .. item.ClassName .. ")")
    end

    local petFolder = ReplicatedStorage:FindFirstChild(PET_FOLDER_NAME)

    if petFolder then
        print("[GAG2] ✓ Found pet folder: ReplicatedStorage." .. PET_FOLDER_NAME)

        local function onPetAdded(child)
            task.delay(0.1, function()
                local id = child:GetFullName()
                if data.seenPets[id] then return end

                local petName = child.Name
                local rarity  = getPetRarity(petName)

                print("[GAG2] 🐾 Pet detected: " .. petName .. " (Rarity: " .. rarity.label .. ")")

                if NOTIFY_PET_RARITIES and not NOTIFY_PET_RARITIES[rarity.label] then
                    print("[GAG2]    ⊘ Skipped (not in notify list)")
                    data.seenPets[id] = true
                    return
                end

                data.seenPets[id] = true
                print("[GAG2]    📤 ALERT: Sending to Discord")
                sendPetSpawnAlert(petName, rarity)
            end)
        end

        for _, child in ipairs(petFolder:GetChildren()) do
            task.spawn(onPetAdded, child)
        end

        petFolder.ChildAdded:Connect(onPetAdded)
        print("[GAG2] ✅ Pet watcher ACTIVE on ReplicatedStorage." .. PET_FOLDER_NAME)
    else
        print("[GAG2] ⚠️  " .. PET_FOLDER_NAME .. " not found, checking fallbacks...")

        local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
        if stockValues then
            print("[GAG2] Found StockValues, scanning for pet nodes...")
            for _, child in ipairs(stockValues:GetChildren()) do
                print("[GAG2]   - " .. child.Name)
            end

            local petsNode = stockValues:FindFirstChild("Pets")
            if petsNode then
                print("[GAG2] ✓ Found: ReplicatedStorage.StockValues.Pets")

                local function onPetValueChanged(v)
                    local id = v:GetFullName()
                    if data.seenPets[id] then return end

                    local petName = v.Name
                    local rarity  = getPetRarity(petName)

                    print("[GAG2] 🐾 Pet value: " .. petName .. " = " .. tostring(v.Value) .. " (Rarity: " .. rarity.label .. ")")

                    if NOTIFY_PET_RARITIES and not NOTIFY_PET_RARITIES[rarity.label] then
                        data.seenPets[id] = true
                        return
                    end

                    data.seenPets[id] = true
                    sendPetSpawnAlert(petName, rarity, "Qty: " .. tostring(v.Value))
                end

                for _, v in ipairs(petsNode:GetChildren()) do
                    if v:IsA("NumberValue") or v:IsA("StringValue") then
                        task.spawn(onPetValueChanged, v)
                    end
                end

                petsNode.ChildAdded:Connect(onPetValueChanged)
                print("[GAG2] ✅ Pet watcher ACTIVE on StockValues.Pets")
            else
                warn("[GAG2] ❌ No 'Pets' folder in StockValues")
                for _, child in ipairs(stockValues:GetChildren()) do
                    warn("[GAG2]    └─ " .. child.Name)
                end
            end
        else
            warn("[GAG2] ❌ StockValues not found!")
        end
    end
end

-- =====================
-- READ STOCK VALUES
-- =====================
local function readShop(folder, rareList)
    local inStock    = {}
    local outOfStock = {}
    local nextRestock, lastRestock = nil, nil

    if not folder then return inStock, outOfStock, nextRestock, lastRestock end

    local items = folder:FindFirstChild("Items")
    if items then
        for _, v in ipairs(items:GetChildren()) do
            if v:IsA("NumberValue") then
                if v.Value > 0 then
                    table.insert(inStock, {
                        name = v.Name,
                        qty  = v.Value,
                        rare = rareList and rareList[v.Name] or false
                    })
                else
                    table.insert(outOfStock, v.Name)
                end
            end
        end
    end

    local nr = folder:FindFirstChild("UnixNextRestock")
    local lr = folder:FindFirstChild("UnixLastRestock")
    if nr then nextRestock = nr.Value end
    if lr then lastRestock = lr.Value end

    table.sort(inStock, function(a, b)
        if a.rare ~= b.rare then return a.rare end
        return a.name < b.name
    end)

    return inStock, outOfStock, nextRestock, lastRestock
end

local function readAllStock()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    if not sv then return nil end

    local result = {}
    local shops  = {
        { key = "seeds",     folder = sv:FindFirstChild("SeedShop"),      rare = RARE_SEEDS,  label = "🌱 Seeds"     },
        { key = "gears",     folder = sv:FindFirstChild("GearShop"),      rare = RARE_GEARS,  label = "⚙️ Gears"    },
        { key = "crates",    folder = sv:FindFirstChild("CrateShop"),     rare = RARE_CRATES, label = "📦 Crates"    },
        { key = "exclusive", folder = sv:FindFirstChild("ExclusiveShop"), rare = {},          label = "⭐ Exclusive" },
    }

    for _, shop in ipairs(shops) do
        local inStock, outOfStock, nextRestock, lastRestock = readShop(shop.folder, shop.rare)
        result[shop.key] = {
            label       = shop.label,
            inStock     = inStock,
            outOfStock  = outOfStock,
            nextRestock = nextRestock,
            lastRestock = lastRestock,
        }
    end

    return result
end

local function hashStock(stock)
    if not stock then return "" end
    local parts = {}
    -- NOTE: Exclusive is intentionally excluded from the hash so its changes
    -- do NOT trigger a restock event or affect predictions.
    for _, key in ipairs({"seeds", "gears", "crates"}) do
        local s = stock[key]
        if s then
            for _, item in ipairs(s.inStock) do
                table.insert(parts, item.name .. "=" .. item.qty)
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- =====================
-- CHECK FOR LEGENDARY / SUPER IN STOCK
-- NOTE: Exclusive shop is excluded from legendary/super detection
-- =====================
local function stockHasLegendary(stock)
    for _, shopKey in ipairs({"seeds", "gears", "crates"}) do  -- no "exclusive"
        local shop = stock[shopKey]
        if shop and shop.inStock then
            for _, item in ipairs(shop.inStock) do
                if LEGENDARY_ITEMS[item.name] or item.name:find("Legendary") then
                    return true
                end
            end
        end
    end
    return false
end

local function stockHasSuper(stock)
    for _, shopKey in ipairs({"seeds", "gears", "crates"}) do  -- no "exclusive"
        local shop = stock[shopKey]
        if shop and shop.inStock then
            for _, item in ipairs(shop.inStock) do
                if SUPER_ITEMS[item.name] or item.name:find("Super") then
                    return true
                end
            end
        end
    end
    return false
end

-- =====================
-- FORMAT DISCORD FIELDS
-- =====================
local function formatShopField(shopData)
    if not shopData then return "_Not available_" end
    local lines = {}

    for _, item in ipairs(shopData.inStock) do
        local prefix = item.rare and "⭐" or "•"
        table.insert(lines, prefix .. " **" .. item.name .. "** x" .. item.qty)
    end

    if #lines == 0 then
        table.insert(lines, "_Out of stock_")
    end

    if shopData.nextRestock and shopData.nextRestock > 0 then
        local remaining = shopData.nextRestock - os.time()
        table.insert(lines, "")
        table.insert(lines, "⏰ Next restock: **" .. formatTime(remaining) .. "** (" .. formatUnix(shopData.nextRestock) .. ")")
    end

    local text = table.concat(lines, "\n")
    if #text > 1000 then text = text:sub(1, 1000) .. "..." end
    return text
end

-- =====================
-- RECORD RESTOCK
-- =====================
local function recordRestock(hasLegendary, hasSuper)
    local now  = os.time()
    local hour = tonumber(os.date("%H", now))

    if data.lastRestockTime then
        local interval = now - data.lastRestockTime
        if interval > 30 and interval < 1800 then
            table.insert(data.intervals, interval)
            if #data.intervals > 30 then table.remove(data.intervals, 1) end
        end
    end

    data.totalRestocks         = data.totalRestocks + 1
    data.hourlyTotal[hour]     = data.hourlyTotal[hour] + 1
    data.lastRestockTime       = now

    if hasLegendary then
        data.legendaryRestocks      = data.legendaryRestocks + 1
        data.hourlyLegendary[hour]  = data.hourlyLegendary[hour] + 1
        if data.lastLegendaryTime then
            local interval = now - data.lastLegendaryTime
            if interval > 30 and interval < 7200 then
                table.insert(data.legendaryIntervals, interval)
                if #data.legendaryIntervals > 20 then table.remove(data.legendaryIntervals, 1) end
            end
        end
        data.lastLegendaryTime = now
    end

    if hasSuper then
        data.superRestocks      = data.superRestocks + 1
        data.hourlySuper[hour]  = data.hourlySuper[hour] + 1
        if data.lastSuperTime then
            local interval = now - data.lastSuperTime
            if interval > 30 and interval < 7200 then
                table.insert(data.superIntervals, interval)
                if #data.superIntervals > 20 then table.remove(data.superIntervals, 1) end
            end
        end
        data.lastSuperTime = now
    end
end

-- =====================
-- LEGENDARY / SUPER PREDICTIONS ONLY
-- (Exclusive shop is NOT included in prediction logic)
-- =====================
local function predictionField(stock)
    local lines = {}

    table.insert(lines, "👑 **LEGENDARY PREDICTIONS**")

    if data.totalRestocks >= 3 then
        local rate = data.legendaryRestocks / data.totalRestocks
        local pct  = round(rate * 100, 1)
        table.insert(lines, "  Chance per restock: **" .. pct .. "%** (" .. data.legendaryRestocks .. "/" .. data.totalRestocks .. ")")

        if rate > 0 then
            local untilNext = math.ceil(1 / rate)
            table.insert(lines, "  ~Every **" .. untilNext .. " restocks**")
        end

        if #data.legendaryIntervals >= 2 then
            local avgInterval = avg(data.legendaryIntervals)
            table.insert(lines, "  Avg time between: **" .. formatTime(avgInterval) .. "**")
            if data.lastLegendaryTime then
                local elapsed   = os.time() - data.lastLegendaryTime
                local remaining = avgInterval - elapsed
                if remaining > 0 then
                    table.insert(lines, "  Est. next legendary: **~" .. formatTime(remaining) .. "**")
                else
                    table.insert(lines, "  Est. next legendary: **OVERDUE — check now!**")
                end
            end
        end

        local bestHour, bestRate = nil, 0
        for h = 0, 23 do
            if data.hourlyTotal[h] >= 3 then
                local hr = data.hourlyLegendary[h] / data.hourlyTotal[h]
                if hr > bestRate then bestRate = hr; bestHour = h end
            end
        end
        if bestHour then
            table.insert(lines, string.format("  Best hour: **%02d:00** (%.0f%% chance)", bestHour, bestRate * 100))
        end

        if pct >= 30 then
            table.insert(lines, "  ✅ **HIGH — Watch closely!**")
        elseif pct >= 15 then
            table.insert(lines, "  ⚠️ **MODERATE — Stay alert**")
        else
            table.insert(lines, "  😴 **LOW — Set alarms**")
        end
    else
        table.insert(lines, "  _Collecting data... (" .. data.totalRestocks .. "/3 restocks)_")
    end

    table.insert(lines, "")
    table.insert(lines, "⚡ **SUPER PREDICTIONS**")

    if data.totalRestocks >= 3 then
        local rate = data.superRestocks / data.totalRestocks
        local pct  = round(rate * 100, 1)
        table.insert(lines, "  Chance per restock: **" .. pct .. "%** (" .. data.superRestocks .. "/" .. data.totalRestocks .. ")")

        if rate > 0 then
            local untilNext = math.ceil(1 / rate)
            table.insert(lines, "  ~Every **" .. untilNext .. " restocks**")
        end

        if #data.superIntervals >= 2 then
            local avgInterval = avg(data.superIntervals)
            table.insert(lines, "  Avg time between: **" .. formatTime(avgInterval) .. "**")
            if data.lastSuperTime then
                local elapsed   = os.time() - data.lastSuperTime
                local remaining = avgInterval - elapsed
                if remaining > 0 then
                    table.insert(lines, "  Est. next super: **~" .. formatTime(remaining) .. "**")
                else
                    table.insert(lines, "  Est. next super: **OVERDUE — check now!**")
                end
            end
        end

        local bestHour, bestRate = nil, 0
        for h = 0, 23 do
            if data.hourlyTotal[h] >= 3 then
                local hr = data.hourlySuper[h] / data.hourlyTotal[h]
                if hr > bestRate then bestRate = hr; bestHour = h end
            end
        end
        if bestHour then
            table.insert(lines, string.format("  Best hour: **%02d:00** (%.0f%% chance)", bestHour, bestRate * 100))
        end

        if pct >= 30 then
            table.insert(lines, "  ✅ **HIGH — Watch closely!**")
        elseif pct >= 15 then
            table.insert(lines, "  ⚠️ **MODERATE — Stay alert**")
        else
            table.insert(lines, "  😴 **LOW — Set alarms**")
        end
    else
        table.insert(lines, "  _Collecting data... (" .. data.totalRestocks .. "/3 restocks)_")
    end

    table.insert(lines, "")
    local seedNext = stock and stock.seeds and stock.seeds.nextRestock
    if seedNext and seedNext > 0 then
        table.insert(lines, "🌱 Seed restock in: **" .. formatTime(seedNext - os.time()) .. "**")
    end
    local gearNext = stock and stock.gears and stock.gears.nextRestock
    if gearNext and gearNext > 0 then
        table.insert(lines, "⚙️ Gear restock in: **" .. formatTime(gearNext - os.time()) .. "**")
    end

    local text = table.concat(lines, "\n")
    if #text > 1024 then text = text:sub(1, 1024) end
    return text
end

-- =====================
-- DISCORD SENDER
-- =====================
sendToDiscord = function(payload)
    local ok, err = pcall(function()
        request({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload),
        })
    end)
    if not ok then warn("[GAG2] Discord error: " .. tostring(err)) else print("[GAG2] Sent to Discord ✓") end
end

local function sendStockReport(stock)
    local content      = ""
    local hasLegendary = stockHasLegendary(stock)
    local hasSuper     = stockHasSuper(stock)

    if hasLegendary and hasSuper then
        content = "<@&" .. ROLE_IDS.legendary .. "> <@&" .. ROLE_IDS.super .. "> 👑 **LEGENDARY & SUPER ITEMS!**"
    elseif hasLegendary then
        content = "<@&" .. ROLE_IDS.legendary .. "> 👑 **LEGENDARY ITEM IN STOCK!**"
    elseif hasSuper then
        content = "<@&" .. ROLE_IDS.super .. "> ⚡ **SUPER ITEM IN STOCK!**"
    else
        local roles = {}
        if stock.seeds  and #stock.seeds.inStock  > 0 then table.insert(roles, "<@&" .. ROLE_IDS.seeds  .. ">") end
        if stock.gears  and #stock.gears.inStock  > 0 then table.insert(roles, "<@&" .. ROLE_IDS.gears  .. ">") end
        if stock.crates and #stock.crates.inStock > 0 then table.insert(roles, "<@&" .. ROLE_IDS.crates .. ">") end
        -- Exclusive gets a ping in Discord but does NOT affect predictions
        if stock.exclusive and #stock.exclusive.inStock > 0 then table.insert(roles, "<@&" .. ROLE_IDS.exclusive .. ">") end
        if #roles > 0 then content = table.concat(roles, " ") .. " 🔄 Stock Restocked!" end
    end

    -- Current weather
    local currentWeather = readWeather()
    local weatherEmoji   = currentWeather and getWeatherEmoji(currentWeather) or "🌍"
    local weatherDisplay = currentWeather and (weatherEmoji .. " " .. currentWeather) or "❓ No weather data"

    sendToDiscord({
        content  = content,
        username = "GAG2 Stock Tracker",
        embeds   = {{
            title  = (hasLegendary or hasSuper) and "👑 PREMIUM ITEM!" or "🔄 Shop Restocked",
            color  = (hasLegendary or hasSuper) and 0xFF6B6B or 0x57F287,
            fields = {
                { name = stock.seeds.label,     value = formatShopField(stock.seeds),     inline = false },
                { name = stock.gears.label,     value = formatShopField(stock.gears),     inline = false },
                { name = stock.crates.label,    value = formatShopField(stock.crates),    inline = true  },
                { name = stock.exclusive.label, value = formatShopField(stock.exclusive), inline = true  },
                { name = "🌤️ Current Weather", value = weatherDisplay,                  inline = true  },
                { name = "🔮 Legendary & Super Predictions (Seeds/Gears/Crates only)", value = predictionField(stock), inline = false },
                { name = "📈 Session", value = "Restocks tracked: **" .. data.totalRestocks .. "**  |  Legendary: **" .. data.legendaryRestocks .. "**  |  Super: **" .. data.superRestocks .. "**", inline = false },
            },
            footer    = { text = "v5 Fixed • Exclusive excluded from predictions • Weather tracking • " .. os.date("%H:%M:%S") },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

-- =====================
-- MAIN
-- =====================
print("[GAG2] v5 FIXED started - Exclusive excluded from predictions, expanded weather")

sendToDiscord({
    username = "GAG2 Stock Tracker",
    embeds   = {{
        title       = "✅ GAG2 Stock Tracker v5 FIXED Online",
        description = "Reading from **ReplicatedStorage.StockValues**\n\nTracking:\n🌱 Seeds  ⚙️ Gears  📦 Crates  ⭐ Exclusive (display only)\n\n👑 Legendary & Super predictions\n🐾 Pet spawn notifier\n🌤️ Weather events",
        color       = 0x5865F2,
        footer      = { text = "Started " .. os.date("%H:%M:%S") },
    }}
})

task.spawn(startPetWatcher)
task.spawn(startWeatherWatcher)

while true do
    local ok, stock = pcall(readAllStock)
    if ok and stock then
        local hash = hashStock(stock)
        if hash ~= data.lastHash and hash ~= "" then
            data.lastHash = hash
            local hasLegendary = stockHasLegendary(stock)
            local hasSuper     = stockHasSuper(stock)
            recordRestock(hasLegendary, hasSuper)
            sendStockReport(stock)
        end
    end
    task.wait(CHECK_INTERVAL)
end
