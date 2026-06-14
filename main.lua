-- GAG2 Stock Prediction Tracker v4
-- Reads directly from ReplicatedStorage.StockValues
-- Accurate stock counts + exact restock timers

local WEBHOOK_URL = "https://discord.com/api/webhooks/1515704094419980338/XlFD0Y1xCfvEVagK8kznLxcEX4LDNHjyMZws41WU1DjAcm-ZIAh_0WjN0qhBpM5eQWAX"
local CHECK_INTERVAL = 10

-- =====================
-- ROLE NOTIFICATIONS
-- =====================
local ROLE_IDS = {
    legendary = "1234567890123456789",   -- Role for LEGENDARY items
    super = "1234567890123456789",       -- Role for SUPER items
    seeds = "1234567890123456789",       -- Role for seed restocks
    gears = "1234567890123456789",       -- Role for gear restocks
    crates = "1234567890123456789",      -- Role for crate restocks
    exclusive = "1234567890123456789",   -- Role for exclusive restocks
}

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
-- Items with quantity > 0 get shown, these get @everyone ping
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

-- =====================
-- DATA
-- =====================
local data = {
    lastHash = "",
    totalRestocks = 0,
    rareRestocks = 0,
    hourlyRare = {},
    hourlyTotal = {},
    itemFrequency = {},
    intervals = {},
    lastRestockTime = nil,
}
for i = 0, 23 do
    data.hourlyRare[i] = 0
    data.hourlyTotal[i] = 0
end

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
-- READ STOCK VALUES
-- =====================
local function readShop(folder, rareList)
    local inStock = {}
    local outOfStock = {}
    local nextRestock = nil
    local lastRestock = nil

    if not folder then return inStock, outOfStock, nextRestock, lastRestock end

    local items = folder:FindFirstChild("Items")
    if items then
        for _, v in ipairs(items:GetChildren()) do
            if v:IsA("NumberValue") then
                if v.Value > 0 then
                    table.insert(inStock, {
                        name = v.Name,
                        qty = v.Value,
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

    -- Sort: rares first, then alphabetical
    table.sort(inStock, function(a, b)
        if a.rare ~= b.rare then return a.rare end
        return a.name < b.name
    end)

    return inStock, outOfStock, nextRestock, lastRestock
end

local function readAllStock()
    local rs = game:GetService("ReplicatedStorage")
    local sv = rs:FindFirstChild("StockValues")
    if not sv then return nil end

    local result = {}

    local shops = {
        {key = "seeds", folder = sv:FindFirstChild("SeedShop"), rare = RARE_SEEDS, label = "🌱 Seeds"},
        {key = "gears", folder = sv:FindFirstChild("GearShop"), rare = RARE_GEARS, label = "⚙️ Gears"},
        {key = "crates", folder = sv:FindFirstChild("CrateShop"), rare = RARE_CRATES, label = "📦 Crates"},
        {key = "exclusive", folder = sv:FindFirstChild("ExclusiveShop"), rare = {}, label = "⭐ Exclusive"},
    }

    for _, shop in ipairs(shops) do
        local inStock, outOfStock, nextRestock, lastRestock = readShop(shop.folder, shop.rare)
        result[shop.key] = {
            label = shop.label,
            inStock = inStock,
            outOfStock = outOfStock,
            nextRestock = nextRestock,
            lastRestock = lastRestock
        }
    end

    return result
end

local function hashStock(stock)
    if not stock then return "" end
    local parts = {}
    for _, key in ipairs({"seeds", "gears", "crates", "exclusive"}) do
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

    -- Add restock time
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
-- PREDICTION STATS
-- =====================
local function recordRestock(hasRare)
    local now = os.time()
    local hour = tonumber(os.date("%H", now))

    if data.lastRestockTime then
        local interval = now - data.lastRestockTime
        if interval > 30 and interval < 1800 then
            table.insert(data.intervals, interval)
            if #data.intervals > 30 then table.remove(data.intervals, 1) end
        end
    end

    data.totalRestocks = data.totalRestocks + 1
    if hasRare then data.rareRestocks = data.rareRestocks + 1 end
    data.hourlyTotal[hour] = data.hourlyTotal[hour] + 1
    if hasRare then data.hourlyRare[hour] = data.hourlyRare[hour] + 1 end
    data.lastRestockTime = now
end

-- =====================
-- ENHANCED PREDICTIONS
-- =====================
local function analyzeTrend()
    if #data.intervals < 5 then return nil end
    
    local recent = {}
    for i = math.max(1, #data.intervals - 9), #data.intervals do
        table.insert(recent, data.intervals[i])
    end
    
    local recentAvg = avg(recent)
    local allAvg = avg(data.intervals)
    
    if recentAvg < allAvg * 0.9 then
        return "📉 Restocks getting faster"
    elseif recentAvg > allAvg * 1.1 then
        return "📈 Restocks getting slower"
    end
    return nil
end

local function predictNextRare()
    if data.totalRestocks < 3 then return nil end
    
    local rareRate = data.rareRestocks / data.totalRestocks
    local restocksUntilRare = math.ceil(1 / rareRate)
    
    return {
        rate = rareRate,
        untilRare = restocksUntilRare,
        confidence = data.totalRestocks >= 10
    }
end

local function predictionField(stock)
    local lines = {}
    
    -- Rare chance percentage
    local prob = data.totalRestocks >= 2
        and round((data.rareRestocks / data.totalRestocks) * 100, 1)
        or nil

    if prob then
        table.insert(lines, "🎲 Rare chance: **" .. prob .. "%** (" .. data.rareRestocks .. "/" .. data.totalRestocks .. ")")
    else
        table.insert(lines, "🎲 Rare chance: _collecting data..._")
    end

    -- Next restock times
    local seedNext = stock and stock.seeds and stock.seeds.nextRestock
    if seedNext and seedNext > 0 then
        local remaining = seedNext - os.time()
        table.insert(lines, "🌱 Seed restock in: **" .. formatTime(remaining) .. "**")
    end

    local gearNext = stock and stock.gears and stock.gears.nextRestock
    if gearNext and gearNext > 0 then
        local remaining = gearNext - os.time()
        table.insert(lines, "⚙️ Gear restock in: **" .. formatTime(remaining) .. "**")
    end

    -- Average interval
    if #data.intervals > 0 then
        local avgInterval = avg(data.intervals)
        table.insert(lines, "⏱️ Avg restock interval: **" .. formatTime(avgInterval) .. "**")
    end

    -- Trend analysis
    local trend = analyzeTrend()
    if trend then
        table.insert(lines, trend)
    end

    -- Predict next rare
    local prediction = predictNextRare()
    if prediction and prediction.confidence then
        table.insert(lines, "🎯 Rare ~every **" .. prediction.untilRare .. " restocks**")
    end

    -- Best hours
    local bestHour, bestRate = nil, 0
    for h = 0, 23 do
        if data.hourlyTotal[h] >= 3 then
            local rate = data.hourlyRare[h] / data.hourlyTotal[h]
            if rate > bestRate then
                bestRate = rate
                bestHour = h
            end
        end
    end
    if bestHour then
        table.insert(lines, string.format("🏆 Best hour: **%02d:00** (%.0f%% rare)", bestHour, bestRate * 100))
    end

    -- Alert level
    if prob then
        if prob >= 40 then
            table.insert(lines, "✅ **HIGH RATE — Watch closely!**")
        elseif prob >= 25 then
            table.insert(lines, "⚠️ **MODERATE — Check restocks**")
        else
            table.insert(lines, "😴 **LOW RATE — Set alarms**")
        end
    end

    return table.concat(lines, "\n")
end

-- =====================
-- DISCORD SENDER
-- =====================
local function sendToDiscord(payload)
    local ok, err = pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
    if not ok then warn("[GAG2] " .. tostring(err)) else print("[GAG2] Sent ✓") end
end

local function sendStockReport(stock)
    local content = ""
    local hasLegendary = false
    local hasSuper = false
    
    -- Check for legendary and super items
    for _, shopKey in ipairs({"seeds", "gears", "crates", "exclusive"}) do
        local shop = stock[shopKey]
        if shop and shop.inStock then
            for _, item in ipairs(shop.inStock) do
                if item.name:find("Legendary") then
                    hasLegendary = true
                end
                if item.name:find("Super") then
                    hasSuper = true
                end
            end
        end
    end
    
    -- Add role pings based on stock
    if hasLegendary and hasSuper then
        content = "<@&" .. ROLE_IDS.legendary .. "> <@&" .. ROLE_IDS.super .. "> 👑 **LEGENDARY & SUPER ITEMS!**"
    elseif hasLegendary then
        content = "<@&" .. ROLE_IDS.legendary .. "> 👑 **LEGENDARY ITEM IN STOCK!**"
    elseif hasSuper then
        content = "<@&" .. ROLE_IDS.super .. "> ⚡ **SUPER ITEM IN STOCK!**"
    else
        local roles = {}
        if stock.seeds and #stock.seeds.inStock > 0 then
            table.insert(roles, "<@&" .. ROLE_IDS.seeds .. ">")
        end
        if stock.gears and #stock.gears.inStock > 0 then
            table.insert(roles, "<@&" .. ROLE_IDS.gears .. ">")
        end
        if stock.crates and #stock.crates.inStock > 0 then
            table.insert(roles, "<@&" .. ROLE_IDS.crates .. ">")
        end
        if stock.exclusive and #stock.exclusive.inStock > 0 then
            table.insert(roles, "<@&" .. ROLE_IDS.exclusive .. ">")
        end
        if #roles > 0 then
            content = table.concat(roles, " ") .. " 🔄 Stock Restocked!"
        end
    end
    
    sendToDiscord({
        content = content,
        username = "GAG2 Stock Tracker",
        embeds = {{
            title = (hasLegendary or hasSuper) and "👑 PREMIUM ITEM!" or "🔄 Shop Restocked",
            color = (hasLegendary or hasSuper) and 0xFF6B6B or 0x57F287,
            fields = {
                {
                    name = stock.seeds.label,
                    value = formatShopField(stock.seeds),
                    inline = false
                },
                {
                    name = stock.gears.label,
                    value = formatShopField(stock.gears),
                    inline = false
                },
                {
                    name = stock.crates.label,
                    value = formatShopField(stock.crates),
                    inline = true
                },
                {
                    name = stock.exclusive.label,
                    value = formatShopField(stock.exclusive),
                    inline = true
                },
                {
                    name = "🔮 Predictions",
                    value = predictionField(stock),
                    inline = false
                },
                {
                    name = "📈 Session",
                    value = "Restocks tracked: **" .. data.totalRestocks .. "**",
                    inline = false
                }
            },
            footer = {text = "v4 • Direct StockValues read • " .. os.date("%H:%M:%S")},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    })
end

-- =====================
-- MAIN LOOP
-- =====================
print("[GAG2] v4 started")

sendToDiscord({
    username = "GAG2 Stock Tracker",
    embeds = {{
        title = "✅ GAG2 Stock Tracker v4 Online",
        description = "Now reading directly from **ReplicatedStorage.StockValues**\n\nTracking:\n🌱 Seeds\n⚙️ Gears\n📦 Crates\n⭐ Exclusive\n🔮 Restock predictions",
        color = 0x5865F2,
        footer = {text = "Started " .. os.date("%H:%M:%S")}
    }}
})

while true do
    local ok, stock = pcall(readAllStock)
    if ok and stock then
        local hash = hashStock(stock)
        if hash ~= data.lastHash and hash ~= "" then
            data.lastHash = hash
            recordRestock(stock.hasRare)
            sendStockReport(stock)  -- Sends on EVERY restock
        end
    end
    task.wait(CHECK_INTERVAL)
end
