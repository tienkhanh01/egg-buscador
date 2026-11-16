-- VORYKEN SCANNER • FIREBASE FIX v4 • bounded HTTP + teleport retries + diagnostics

-- Voryken Egg Finder • Voryken API-only bootstrap
-- Caches this exact build so Server Hop never falls back to an older remote loader.
local __payload = [=[
--==============================================================
-- EGG TOP 3
-- Muestra los 3 mejores huevos actuales y publica coincidencias en Voryken API con fast-path inmediato.
-- Sin robo, Auto Farm ni rutas. Incluye filtro automático, Voryken API y Server Hop con slots RÍGIDOS guardados por usuario.
-- Guarda ajustes en finder.json y el adjunta la foto real del animal
-- y auto-ejecuta el loader después de cada Server Hop.
-- No modifica gráficos ni aplica optimizaciones visuales.
-- Workspace se usa SOLO para saber qué huevos siguen físicamente disponibles.
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Roblox can execute queued scripts before the LocalPlayer is created.
-- Wait for the actual client player before touching PlayerGui.
local player = Players.LocalPlayer
if not player then
    local playerDeadline = os.clock() + 45
    repeat
        task.wait(0.15)
        player = Players.LocalPlayer
    until player or os.clock() >= playerDeadline
end
if not player then
    error("Roblox LocalPlayer did not become available. Execute the scanner after joining the game.")
end
local playerGui = player:FindFirstChildOfClass("PlayerGui")
    or player:WaitForChild("PlayerGui", 45)
if not playerGui then
    error("Roblox PlayerGui did not load for the local player.")
end

--==============================================================
-- TRUE SERVER + EGG READINESS GATE (before starting the scanner)
-- The Roblox loading screen can disappear before EggState receives the actual
-- field egg snapshot.  A fixed 3-second delay cannot guarantee that data.
-- Do NOT start the Voryken API publisher or Server Hop until real eggs can be read.
-- This gate runs on manual launches AND on the cached queued script after hop.
--==============================================================
do
    local loadingGui = Instance.new("ScreenGui")
    loadingGui.Name = "VorykenWaitingForRealEggs"
    loadingGui.ResetOnSpawn = false
    loadingGui.DisplayOrder = 1001
    local previousGui = playerGui:FindFirstChild(loadingGui.Name)
    if previousGui then pcall(function() previousGui:Destroy() end) end
    loadingGui.Parent = playerGui

    local loadingFrame = Instance.new("Frame")
    loadingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    loadingFrame.Position = UDim2.fromScale(0.5, 0.5)
    loadingFrame.Size = UDim2.fromOffset(310, 88)
    loadingFrame.BackgroundColor3 = Color3.fromRGB(13, 15, 23)
    loadingFrame.BorderSizePixel = 0
    loadingFrame.Parent = loadingGui
    local loadingCorner = Instance.new("UICorner")
    loadingCorner.CornerRadius = UDim.new(0, 12)
    loadingCorner.Parent = loadingFrame
    local loadingStroke = Instance.new("UIStroke")
    loadingStroke.Color = Color3.fromRGB(126, 105, 239)
    loadingStroke.Thickness = 1
    loadingStroke.Parent = loadingFrame

    local loadingTitle = Instance.new("TextLabel")
    loadingTitle.BackgroundTransparency = 1
    loadingTitle.Size = UDim2.new(1, -16, 0, 30)
    loadingTitle.Position = UDim2.fromOffset(8, 5)
    loadingTitle.Text = "VORYKEN • WAITING FOR GAME EGGS"
    loadingTitle.TextSize = 12
    loadingTitle.TextColor3 = Color3.fromRGB(239, 241, 250)
    loadingTitle.Font = Enum.Font.GothamBold
    loadingTitle.Parent = loadingFrame

    local loadingText = Instance.new("TextLabel")
    loadingText.BackgroundTransparency = 1
    loadingText.Size = UDim2.new(1, -22, 0, 45)
    loadingText.Position = UDim2.fromOffset(11, 34)
    loadingText.TextWrapped = true
    loadingText.Text = "Waiting for Roblox server..."
    loadingText.TextColor3 = Color3.fromRGB(165, 218, 181)
    loadingText.TextSize = 11
    loadingText.Font = Enum.Font.GothamMedium
    loadingText.Parent = loadingFrame

    local function updateWaiting(message)
        if loadingText.Parent and loadingText.Text ~= message then
            loadingText.Text = message
        end

    end

    local startedAt = os.clock()
    local lastSyncRequest = -10
    local stableSince = nil
    local lastSignature = nil
    local readyEggCount = 0
    local function readSnapshot(module)
        if type(module) ~= "table" then return nil end
        local reader = module.ReadFieldEggs or module.GetAreaEggSnapshot
        if type(reader) ~= "function" then return nil end
        local ok, snapshot = pcall(reader)
        if (not ok or type(snapshot) ~= "table" or type(snapshot.Records) ~= "table") then
            ok, snapshot = pcall(reader, module)
        end
        if ok and type(snapshot) == "table" and type(snapshot.Records) == "table" then
            return snapshot.Records
        end
        return nil
    end

    while true do
        if not game:IsLoaded() then
            updateWaiting("Waiting for Roblox to finish loading...")
        elseif not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            updateWaiting("Waiting for character / world to load...")
        else
            local client = ReplicatedStorage:FindFirstChild("Client")
            local data = ReplicatedStorage:FindFirstChild("Data")
            local eggModule = client and client:FindFirstChild("EggState")
            local assetsModule = data and data:FindFirstChild("Assets")
            local worldFolder = Workspace:FindFirstChild("AreaEggSlotsClient")
            local halloween = Workspace:FindFirstChild("HalloweenDimension")
            local halloweenFolder = halloween and halloween:FindFirstChild("WorldEggs")
            if not eggModule or not assetsModule then
                updateWaiting("Waiting for EggState / Assets modules...")
            else
                local ok, eggState = pcall(require, eggModule)
                local okAssets, assets = pcall(require, assetsModule)
                local records = ok and readSnapshot(eggState) or nil
                if ok and type(eggState) == "table" and os.clock() - lastSyncRequest >= 4 then
                    lastSyncRequest = os.clock()
                    local sync = eggState.SyncFieldEggs or eggState.RequestAreaEggSnapshot
                    if type(sync) == "function" then
                        task.spawn(function()
                            pcall(sync)
                            pcall(sync, eggState)
                        end)
                    end
                end
                if not okAssets or type(assets) ~= "table" then
                    updateWaiting("Waiting for animal data to load...")
                elseif not worldFolder and not halloweenFolder then
                    updateWaiting("Waiting for server egg folders...")
                elseif type(records) ~= "table" then
                    updateWaiting("Waiting for EggState server snapshot...")
                else
                    local ids = {}
                    for key, record in pairs(records) do
                        if type(record) == "table" and record.AssetCategory ~= nil then
                            ids[#ids + 1] = tostring(record.Uid or key)
                        end
                    end
                    local halloweenCount = 0
                    if halloweenFolder then
                        for _, obj in ipairs(halloweenFolder:GetDescendants()) do
                            if obj:IsA("Model") and obj:GetAttribute("HalloweenEggUid") ~= nil then
                                halloweenCount += 1
                            end
                        end
                    end
                    table.sort(ids)
                    local signature = table.concat(ids, ",") .. "|H:" .. tostring(halloweenCount)
                    local total = #ids + halloweenCount
                    local now = os.clock()
                    if total > 0 and (worldFolder or halloweenCount > 0) then
                        if lastSignature ~= signature then
                            stableSince = now
                            lastSignature = signature
                        end
                        if stableSince and now - stableSince >= 0.85 then
                            readyEggCount = total
                            break
                        end
                        updateWaiting("Loading current eggs • " .. tostring(total) .. " detected... ")
                    else
                        lastSignature = nil
                        stableSince = nil
                        updateWaiting("Eggs not loaded yet (0 found) • waiting... " .. tostring(math.floor(now - startedAt)) .. "s")
                    end
                end
            end
        end
        task.wait(0.20)
    end

    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env) == "table" then
        env.__VorykenScannerWorldReadyJob = tostring(game.JobId or "")
        env.__VorykenScannerInitialEggs = readyEggCount
    end
    pcall(function() loadingGui:Destroy() end)
end

--==============================================================
-- V9 RUNTIME SINGLETON + DISCORD DEDUPE
--==============================================================
local runtimeEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(runtimeEnv) ~= "table" then
    runtimeEnv = _G
end

local currentJobId = tostring(game.JobId or "")
local runtimeState = runtimeEnv.__VorykenEggTop3RuntimeV9

if type(runtimeState) ~= "table" then
    runtimeState = {}
    runtimeEnv.__VorykenEggTop3RuntimeV9 = runtimeState
end

if tostring(runtimeState.JobId or "") ~= currentJobId then
    runtimeState.JobId = currentJobId
    runtimeState.Generation = 0
    runtimeState.AutoNotifiedUids = {}
    runtimeState.ApiPublishedUids = {}
end

runtimeState.Generation = (tonumber(runtimeState.Generation) or 0) + 1
local thisRunGeneration = runtimeState.Generation
runtimeState.ActiveGeneration = thisRunGeneration

if type(runtimeState.AutoNotifiedUids) ~= "table" then
    runtimeState.AutoNotifiedUids = {}
end

if type(runtimeState.ApiPublishedUids) ~= "table" then
    runtimeState.ApiPublishedUids = {}
end

if type(runtimeState.EntryFirstSeenAt) ~= "table" then
    runtimeState.EntryFirstSeenAt = {}
end

local function rememberEntryFirstSeen(entry)
    if type(entry) ~= "table" then
        return os.time()
    end

    local uid = tostring(entry.uid or "")
    local ledger = runtimeState.EntryFirstSeenAt
    local nowUnix = os.time()

    if uid == "" then
        return nowUnix
    end

    local savedUnix = tonumber(ledger[uid])
    if savedUnix and savedUnix > 0 then
        return math.floor(savedUnix)
    end

    ledger[uid] = nowUnix
    return nowUnix
end

local function isCurrentVorykenRun()
    return tostring(runtimeState.JobId or "") == currentJobId
        and runtimeState.ActiveGeneration == thisRunGeneration
end

-- Start the finder immediately.
if not isCurrentVorykenRun() then
    return
end


--==============================================================
-- EXTREME FPS BOOST • AUTOMATIC
-- Aggressive client-side visual optimization. The Top 3 UI and its
-- ViewportFrame previews are intentionally left untouched.
--==============================================================
local function startExtremeFPSBoost()
    local Lighting = game:GetService("Lighting")
    local SoundService = game:GetService("SoundService")
    local Terrain = Workspace:FindFirstChildOfClass("Terrain") or Workspace.Terrain

    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env) ~= "table" then
        env = _G
    end

    -- Disconnect a previous copy if this script is executed again in the
    -- same server. This prevents stacked DescendantAdded/AnimationPlayed hooks.
    local oldState = env.__EggTop3ExtremeFPSBoost
    if type(oldState) == "table" and type(oldState.Connections) == "table" then
        for _, connection in ipairs(oldState.Connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local state = {
        Connections = {},
        AnimatorHooked = setmetatable({}, {__mode = "k"}),
    }
    env.__EggTop3ExtremeFPSBoost = state

    local function remember(connection)
        if connection then
            state.Connections[#state.Connections + 1] = connection
        end
        return connection
    end

    local function stopAnimator(animator)
        if state.AnimatorHooked[animator] then
            return
        end
        state.AnimatorHooked[animator] = true

        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function()
                    track:Stop(0)
                end)
            end
        end)

        pcall(function()
            remember(animator.AnimationPlayed:Connect(function(track)
                task.defer(function()
                    pcall(function()
                        track:Stop(0)
                    end)
                end)
            end))
        end)
    end

    local function optimizeObject(object)
        if not object or not object.Parent then
            return
        end

        pcall(function()
            if object:IsA("BasePart") then
                pcall(function() object.CastShadow = false end)
                pcall(function() object.Reflectance = 0 end)
                pcall(function() object.Material = Enum.Material.SmoothPlastic end)
                pcall(function() object.TopSurface = Enum.SurfaceType.Smooth end)
                pcall(function() object.BottomSurface = Enum.SurfaceType.Smooth end)
                pcall(function() object.MaterialVariant = "" end)

                if object:IsA("MeshPart") then
                    pcall(function()
                        object.TextureID = ""
                    end)
                    pcall(function()
                        object.RenderFidelity = Enum.RenderFidelity.Performance
                    end)
                    pcall(function()
                        object.CollisionFidelity = Enum.CollisionFidelity.Box
                    end)
                    pcall(function()
                        object.DoubleSided = false
                    end)
                end

            elseif object:IsA("SpecialMesh") then
                object.TextureId = ""

            elseif object:IsA("Decal") or object:IsA("Texture") then
                pcall(function()
                    object.Transparency = 1
                end)
                pcall(function()
                    object.Texture = ""
                end)

            elseif object:IsA("SurfaceAppearance") then
                object:Destroy()

            elseif object:IsA("ParticleEmitter") then
                object.Enabled = false
                pcall(function()
                    object:Clear()
                end)

            elseif object:IsA("Trail") or object:IsA("Beam") then
                object.Enabled = false

            elseif object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles") then
                object.Enabled = false

            elseif object:IsA("PointLight") or object:IsA("SpotLight") or object:IsA("SurfaceLight") then
                object.Enabled = false
                pcall(function()
                    object.Shadows = false
                end)

            elseif object:IsA("Highlight") then
                object.Enabled = false

            elseif object:IsA("SelectionBox")
                or object:IsA("BoxHandleAdornment")
                or object:IsA("SphereHandleAdornment")
                or object:IsA("CylinderHandleAdornment")
                or object:IsA("ConeHandleAdornment")
                or object:IsA("LineHandleAdornment")
                or object:IsA("ImageHandleAdornment") then
                pcall(function()
                    object.Visible = false
                end)

            elseif object:IsA("BillboardGui") or object:IsA("SurfaceGui") then
                object.Enabled = false

            elseif object:IsA("Explosion") then
                object.Visible = false

            elseif object:IsA("ForceField") then
                object.Visible = false

            elseif object:IsA("Sound") then
                pcall(function()
                    object:Stop()
                end)
                object.Volume = 0
                pcall(function()
                    object.SoundId = ""
                end)

            elseif object:IsA("SoundGroup") then
                object.Volume = 0

            elseif object:IsA("SoundEffect") then
                object.Enabled = false

            elseif object:IsA("VideoFrame") then
                pcall(function()
                    object.Playing = false
                end)
                object.Visible = false

            elseif object:IsA("Animator") then
                stopAnimator(object)

            elseif object:IsA("LocalScript") and string.lower(object.Name) == "animate" then
                -- Stop the default character animation loop so it does not
                -- constantly restart tracks that the FPS boost has stopped.
                object.Disabled = true

            elseif object:IsA("PostEffect") then
                object.Enabled = false

            elseif object:IsA("Atmosphere") or object:IsA("Sky") then
                object:Destroy()

            elseif object:IsA("Clouds") then
                object.Enabled = false

            elseif object:IsA("Shirt") then
                object.ShirtTemplate = ""

            elseif object:IsA("Pants") then
                object.PantsTemplate = ""

            elseif object:IsA("ShirtGraphic") then
                object.Graphic = ""
            end
        end)
    end

    -- Lowest client graphics quality available through normal settings APIs.
    pcall(function()
        local userGameSettings = UserSettings():GetService("UserGameSettings")
        userGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        pcall(function()
            userGameSettings.MasterVolume = 0
        end)
    end)

    pcall(function()
        local engineSettings = settings()
        if engineSettings and engineSettings.Rendering then
            engineSettings.Rendering.QualityLevel = Enum.QualityLevel.Level01
        end
    end)

    -- Flat/simple lighting: no shadows, atmosphere or expensive reflections.
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.ShadowSoftness = 0
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.FogStart = 0
        Lighting.FogEnd = 1000000000
        Lighting.Brightness = 1
        Lighting.ExposureCompensation = 0
    end)

    pcall(function()
        Lighting.Technology = Enum.Technology.Compatibility
    end)

    -- Terrain/water simplified as far as client properties allow.
    if Terrain then
        pcall(function()
            Terrain.Decoration = false
        end)
        pcall(function()
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 1
        end)
    end

    pcall(function()
        SoundService.AmbientReverb = Enum.ReverbType.NoReverb
        SoundService.DistanceFactor = 1
        SoundService.DopplerScale = 0
        SoundService.RolloffScale = 0
    end)

    -- Catch anything the game creates after startup (auras, particles,
    -- textures, sounds, lights, animations, etc.).
    remember(Workspace.DescendantAdded:Connect(function(object)
        task.defer(optimizeObject, object)
    end))
    remember(Lighting.DescendantAdded:Connect(function(object)
        task.defer(optimizeObject, object)
    end))
    remember(SoundService.DescendantAdded:Connect(function(object)
        task.defer(optimizeObject, object)
    end))

    -- Initial cleanup is chunked so a very large map does not freeze for one
    -- giant frame while the menu starts.
    task.spawn(function()
        local function scan(root)
            local descendants = root:GetDescendants()
            for index, object in ipairs(descendants) do
                optimizeObject(object)
                if index % 350 == 0 then
                    task.wait()
                end
            end
        end

        scan(Lighting)
        scan(SoundService)
        scan(Workspace)

        -- Apply once more to Terrain itself after the full scan.
        if Terrain then
            optimizeObject(Terrain)
        end
    end)
end

-- Extreme FPS Boost disabled: keep normal game visuals.

--==============================================================
-- AUTO EXECUTE AFTER SERVER HOP + EARLY-LOAD RECOVERY
--==============================================================

local AUTO_LOADER_URL = "https://codes.voryken.com/raw/qym04a"
local teleportLoaderQueued = false

local function getTeleportQueueFunction()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env) ~= "table" then
        return nil
    end

    local queueFn = env.queue_on_teleport
        or env.queueonteleport
        or env.queue_on_tp

    if type(queueFn) ~= "function" and type(env.syn) == "table" then
        queueFn = env.syn.queue_on_teleport or env.syn.queueonteleport
    end

    if type(queueFn) ~= "function" and type(env.fluxus) == "table" then
        queueFn = env.fluxus.queue_on_teleport or env.fluxus.queueonteleport
    end

    return type(queueFn) == "function" and queueFn or nil
end

local function queueFinderForNextServer()
    if teleportLoaderQueued then
        return true
    end

    local queueFn = getTeleportQueueFunction()
    if type(queueFn) ~= "function" then
        return false
    end

    -- Reuse this exact updated scanner after a hop where local files are
    -- available; fall back to the existing hosted loader otherwise.
    -- The 3-second delay happens before either implementation starts.
    local queuedCode = [[
local started = false
pcall(function()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local read = type(env) == "table" and (env.readfile or env.read_file) or readfile
    if type(read) == "function" then
        local text = read("VorykenEggFinder/EggTop3_current.lua")
        if type(text) == "string" and text ~= "" and type(loadstring) == "function" then
            local fn = loadstring(text)
            if type(fn) == "function" then
                started = pcall(fn)
            end
        end
    end
end)
if not started then
    -- Do not fall back to the old hosted scanner: it may still target Firebase
    -- or the old combined API. Publish this new build at your loader URL first
    -- if your executor cannot use readfile after teleport.
    warn("[VORYKEN] Split API scanner was not cached; run the updated scanner again")
end
    ]]

    local ok = pcall(queueFn, queuedCode)
    if not ok then
        ok = pcall(queueFn, nil, queuedCode)
    end

    if ok then
        teleportLoaderQueued = true
    end

    return ok
end

-- The payload blocks only until real egg data exists. A separate small
-- loading panel explains the reason; Voryken API publishing / Hop start afterward.

local TOP_COUNT = 3
local REFRESH_RATE = 0.03
local DISPATCH_RATE = 0.005

local COLORS = {
    Main = Color3.fromRGB(8, 9, 14),
    Card = Color3.fromRGB(20, 22, 32),
    CardAlt = Color3.fromRGB(27, 29, 42),
    White = Color3.fromRGB(247, 248, 253),
    Gray = Color3.fromRGB(145, 150, 169),
    Green = Color3.fromRGB(70, 225, 153),
    Blue = Color3.fromRGB(89, 181, 255),
    Purple = Color3.fromRGB(138, 88, 255),
}

local RARITY_COLORS = {
    Common = Color3.fromRGB(162, 168, 181),
    Uncommon = Color3.fromRGB(93, 220, 139),
    Rare = Color3.fromRGB(75, 159, 255),
    Epic = Color3.fromRGB(174, 94, 255),
    Legendary = Color3.fromRGB(255, 170, 70),
    Mythic = Color3.fromRGB(220, 91, 255),
    Secret = Color3.fromRGB(235, 238, 247),
    Cosmic = Color3.fromRGB(255, 82, 119),
    Eternal = Color3.fromRGB(160, 108, 255),
    Divine = Color3.fromRGB(255, 221, 85),
}

local MUTATION_VALUES = {
    Silver = 1.20,
    Golden = 2.50,
    Rainbow = 3.50,
    Sakura = 1.25,
    GreatBloom = 2.50,
    Monstrous = 3.00,
    Boss = 2.75,
    Bloom = 1.25,
    SpiritBloom = 2.50,
    Parasite = 3.00,
    Fractured = 2.75,
}

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        pcall(function()
            object.AutoLocalize = false
        end)
    end
    object.Parent = parent
    return object
end

local function corner(object, radius)
    local ui = Instance.new("UICorner")
    ui.CornerRadius = UDim.new(0, radius or 8)
    ui.Parent = object
    return ui
end

local function stroke(object, color, transparency, thickness)
    local ui = Instance.new("UIStroke")
    ui.Color = color
    ui.Transparency = transparency or 0
    ui.Thickness = thickness or 1
    ui.Parent = object
    return ui
end

local function normalize(text)
    return string.lower(tostring(text or "")):gsub("[%s_%-%./]", "")
end

local function safeRequire(...)
    local current = ReplicatedStorage
    for _, name in ipairs({...}) do
        current = current:FindFirstChild(name)
        if not current then
            return nil
        end
    end
    local ok, result = pcall(require, current)
    if ok then
        return result
    end
    return nil
end

local function formatNumber(value)
    value = tonumber(value)
    if not value then
        return "--"
    end

    local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No"}
    local index = 1

    while math.abs(value) >= 1000 and index < #suffixes do
        value = value / 1000
        index += 1
    end

    local text
    if index == 1 then
        text = string.format("%.0f", value)
    elseif math.abs(value) >= 100 then
        text = string.format("%.0f", value)
    elseif math.abs(value) >= 10 then
        text = string.format("%.1f", value)
    else
        text = string.format("%.2f", value)
    end

    text = text:gsub("%.?0+$", "")
    return text .. suffixes[index]
end

local function normalizeImage(value)
    if value == nil then
        return ""
    end

    if type(value) == "number" then
        return "rbxassetid://" .. tostring(math.floor(value))
    end

    local text = tostring(value)
    if text == "" then
        return ""
    end
    if text:match("^%d+$") then
        return "rbxassetid://" .. text
    end
    if text:find("rbxasset", 1, true) then
        return text
    end
    local id = text:match("(%d+)")
    if id then
        return "rbxassetid://" .. id
    end
    return text
end

--==============================================================
-- PERSISTENT SETTINGS (finder.json)
--==============================================================

local WORKSPACE_FOLDER = "VorykenEggFinder"

local function finderPath(name)
    return WORKSPACE_FOLDER .. "/" .. tostring(name or "")
end

local SETTINGS_FILE = finderPath("finder.json")

-- Instance slot is saved separately for each Roblox username so multiple
-- accounts sharing the same executor workspace never overwrite each other.
local slotUserKey = tostring(player.Name or "Player"):gsub("[^%w_%-]", "_")
local SLOT_FILE = finderPath("finder_slot_" .. slotUserKey .. ".json")
local LEGACY_SETTINGS_FILE = "finder.json"
local LEGACY_SLOT_FILE = "finder_slot_" .. slotUserKey .. ".json"
local settings = {
    Webhook = "",
    SelectedUid = "",
    SelectedCategory = "",
    PanelPosition = nil,
    AutoAmount = "100",
    AutoUnit = "M",
    ServerHopEnabled = true,
    InstanceSlot = 1,
}

local fileRead = nil
local fileWrite = nil
local fileExists = nil
local fileDelete = nil
local fileMakeFolder = nil
local fileIsFolder = nil

pcall(function()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env) == "table" then
        fileRead = env.readfile or env.read_file
        fileWrite = env.writefile or env.write_file
        fileExists = env.isfile or env.is_file
        fileDelete = env.delfile or env.deletefile or env.delete_file
        fileMakeFolder = env.makefolder or env.make_folder
        fileIsFolder = env.isfolder or env.is_folder
    end
end)

local function ensureFinderFolder()
    if type(fileIsFolder) == "function" then
        local ok, exists = pcall(fileIsFolder, WORKSPACE_FOLDER)
        if ok and exists == true then
            return true
        end
    end

    if type(fileMakeFolder) == "function" then
        pcall(fileMakeFolder, WORKSPACE_FOLDER)
    end

    if type(fileIsFolder) == "function" then
        local ok, exists = pcall(fileIsFolder, WORKSPACE_FOLDER)
        return ok and exists == true
    end

    return type(fileMakeFolder) == "function"
end

local function migrateLegacyFile(oldPath, newPath)
    if type(fileRead) ~= "function" or type(fileWrite) ~= "function" then
        return
    end

    if type(fileExists) == "function" then
        local okNew, newExists = pcall(fileExists, newPath)
        if okNew and newExists == true then
            return
        end

        local okOld, oldExists = pcall(fileExists, oldPath)
        if not okOld or oldExists ~= true then
            return
        end
    end

    local okRead, raw = pcall(fileRead, oldPath)
    if okRead and type(raw) == "string" and raw ~= "" then
        pcall(fileWrite, newPath, raw)
    end
end

ensureFinderFolder()
migrateLegacyFile(LEGACY_SETTINGS_FILE, SETTINGS_FILE)
migrateLegacyFile(LEGACY_SLOT_FILE, SLOT_FILE)

local function loadSettings()
    if type(fileRead) ~= "function" then
        return
    end

    if type(fileExists) == "function" then
        local ok, exists = pcall(fileExists, SETTINGS_FILE)
        if not ok or exists ~= true then
            return
        end
    end

    local ok, raw = pcall(fileRead, SETTINGS_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then
        return
    end

    local decoded = nil
    local decodedOk = pcall(function()
        decoded = HttpService:JSONDecode(raw)
    end)

    if decodedOk and type(decoded) == "table" then
        for key, value in pairs(decoded) do
            -- InstanceSlot is intentionally NOT shared between accounts.
            if key ~= "InstanceSlot" then
                settings[key] = value
            end
        end
    end
end

local function saveSettings()
    if type(fileWrite) ~= "function" then
        return false
    end

    -- Keep InstanceSlot out of the shared finder.json.
    local sharedSettings = {}
    for key, value in pairs(settings) do
        if key ~= "InstanceSlot" then
            sharedSettings[key] = value
        end
    end

    local encoded = nil
    local okEncode = pcall(function()
        encoded = HttpService:JSONEncode(sharedSettings)
    end)

    if not okEncode or type(encoded) ~= "string" then
        return false
    end

    local okWrite = pcall(fileWrite, SETTINGS_FILE, encoded)
    return okWrite
end

-- Instance slots are now assigned dynamically by Voryken API/Python.
-- The old per-executor slot file loader/saver is intentionally removed.

local function packUDim2(value)
    if typeof(value) ~= "UDim2" then
        return nil
    end
    return {
        XScale = value.X.Scale,
        XOffset = value.X.Offset,
        YScale = value.Y.Scale,
        YOffset = value.Y.Offset,
    }
end

local function unpackUDim2(value, fallback)
    if type(value) ~= "table" then
        return fallback
    end

    local xs = tonumber(value.XScale)
    local xo = tonumber(value.XOffset)
    local ys = tonumber(value.YScale)
    local yo = tonumber(value.YOffset)

    if xs == nil or xo == nil or ys == nil or yo == nil then
        return fallback
    end

    return UDim2.new(xs, xo, ys, yo)
end

loadSettings()
-- v3 preset migration: 100M is now the default; replace any saved 500M
-- preset ONCE while preserving unrelated custom thresholds and other settings.
if tonumber(settings.ScannerDefaultsVersion) ~= 3 then
    local amount = tonumber((tostring(settings.AutoAmount or ""):gsub(",", "."))) or 0
    local multiplier = ({K = 1e3, M = 1e6, B = 1e9})[tostring(settings.AutoUnit or "M"):upper()] or 1e6
    local oldThreshold = amount * multiplier
    if amount <= 0 or math.abs(oldThreshold - 500000000) < 1 then
        settings.AutoAmount = "100"
        settings.AutoUnit = "M"
    end
    settings.ServerHopEnabled = true
    settings.ScannerDefaultsVersion = 3
end
-- Instance slot is assigned by Voryken API/Python dynamically.
saveSettings()

--==============================================================
-- GAME DATA
--==============================================================

local EggState = safeRequire("Client", "EggState")
local AssetsData = safeRequire("Data", "Assets")

-- Contenedor de SOLO lectura: permite saber al instante si un huevo
-- apareció o desapareció del campo. No ejecuta ninguna acción sobre él.
local eggFolder = Workspace:FindFirstChild("AreaEggSlotsClient")

local configsFolder = nil
pcall(function()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local assets = data and data:FindFirstChild("Assets")
    configsFolder = assets and assets:FindFirstChild("Configs")
end)

local configCache = {}

local function getConfig(category)
    if type(category) ~= "string" then
        return nil
    end

    if type(AssetsData) == "table"
        and type(AssetsData.Directory) == "table"
        and type(AssetsData.Directory[category]) == "table" then
        return AssetsData.Directory[category]
    end

    -- Halloween pets, including new-zone pets, live in Data.HalloweenPets.Specs.
    if configCache.__EggTop3HalloweenPetsData == nil then
        configCache.__EggTop3HalloweenPetsData = safeRequire("Data", "HalloweenPets") or false
    end

    local halloweenPetsData = configCache.__EggTop3HalloweenPetsData
    if type(halloweenPetsData) == "table"
        and type(halloweenPetsData.Specs) == "table"
        and type(halloweenPetsData.Specs[category]) == "table" then
        return halloweenPetsData.Specs[category]
    end

    if configCache[category] ~= nil then
        return configCache[category] or nil
    end

    if configsFolder then
        local module = configsFolder:FindFirstChild(category)
        if module and module:IsA("ModuleScript") then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" then
                configCache[category] = result
                return result
            end
        end
    end

    configCache[category] = false
    return nil
end

local function getAnimalName(category)
    local config = getConfig(category)
    if type(config) == "table" and config.DisplayName then
        return tostring(config.DisplayName)
    end
    return tostring(category or "Unknown")
end

local function getRarity(category)
    local config = getConfig(category)
    if type(config) ~= "table" then
        return "Unknown"
    end

    local rarity = config.Rarity
    if type(rarity) == "table" then
        return tostring(rarity.DisplayName or rarity.Name or rarity._id or "Unknown")
    end
    return tostring(rarity or "Unknown")
end

local function getAnimalImage(category)
    local config = getConfig(category)
    if type(config) ~= "table" then
        return ""
    end

    local value = config.Icon or config.Image or config.Thumbnail or config.Portrait or config.ImageId
    if value == nil and type(config.Egg) == "table" then
        value = config.Egg.Icon or config.Egg.Image or config.Egg.Thumbnail
    end
    return normalizeImage(value)
end

local function getBaseIncome(category)
    local config = getConfig(category)
    if type(config) ~= "table" then
        return nil
    end

    local value = tonumber(config.EarningRate)
    if value then
        return value
    end

    if type(config.Egg) == "table" then
        return tonumber(config.Egg.EarningRate)
    end

    return nil
end

-- Official earning helpers used by the TRUE global Top 3.
local OfficialAssetEarnings = safeRequire("Shared", "Util", "AssetEarnings")
local OfficialEggRecords = safeRequire("Shared", "Util", "EggRecords")

local function getOfficialNormalIncome(record)
    if type(record) ~= "table" then
        return nil
    end

    if type(OfficialAssetEarnings) == "table"
        and type(OfficialAssetEarnings.RatePerSecond) == "function"
        and type(OfficialEggRecords) == "table"
        and type(OfficialEggRecords.ToAssetItemData) == "function" then

        local ok, value = pcall(function()
            return OfficialAssetEarnings.RatePerSecond(
                OfficialEggRecords.ToAssetItemData(record)
            )
        end)

        value = tonumber(value)
        if ok and value and value == value
            and value ~= math.huge and value ~= -math.huge then
            return math.max(0, value)
        end
    end

    return nil
end

local function getOfficialHalloweenIncome(category, scale)
    if type(category) ~= "string" then
        return nil
    end

    if type(OfficialAssetEarnings) == "table"
        and type(OfficialAssetEarnings.CatalogRatePerSecond) == "function" then

        local ok, value = pcall(
            OfficialAssetEarnings.CatalogRatePerSecond,
            {
                Category = category,
                Scale = math.max(tonumber(scale) or 1, 0.001),
                Mutations = {},
            }
        )

        value = tonumber(value)
        if ok and value and value == value
            and value ~= math.huge and value ~= -math.huge then
            return math.max(0, value)
        end
    end

    return nil
end

local function sizeFactor(scale)
    scale = math.max(tonumber(scale) or 1, 0.01)
    if scale <= 5 then
        return scale ^ 1.85
    end
    return 19.6378757558 * ((scale / 5) ^ 1.2)
end

local function getMutations(record)
    local list = {}
    local used = {}

    local function add(value)
        local name
        if type(value) == "string" then
            name = value
        elseif type(value) == "table" then
            name = value.Name or value.DisplayName or value._id or value.Id
        end

        if type(name) == "string" and not used[name] then
            used[name] = true
            table.insert(list, name)
        end
    end

    if type(record.Mutations) == "table" then
        for key, value in pairs(record.Mutations) do
            if type(value) == "boolean" then
                if value then
                    add(key)
                end
            else
                add(value)
            end
        end
    end

    add(record.Mutation)
    add(record.BaseMutation)
    return list
end

local function calculateValue(record)
    if type(record) ~= "table" then
        return 0
    end

    local base = getBaseIncome(record.AssetCategory)
    if not base then
        return 0
    end

    local multiplier = 1
    for _, mutation in ipairs(getMutations(record)) do
        local scalar = MUTATION_VALUES[mutation] or 1
        multiplier += math.max(0, scalar - 1)
    end

    local scale = tonumber(record.AssetScale) or 1
    return math.max(0, math.floor(base * sizeFactor(scale) * multiplier + 0.5))
end

local readEggs = nil
local syncEggs = nil

if type(EggState) == "table" then
    readEggs = EggState.ReadFieldEggs or EggState.GetAreaEggSnapshot
    syncEggs = EggState.SyncFieldEggs or EggState.RequestAreaEggSnapshot
end

local function callModuleFunction(func, module)
    if type(func) ~= "function" then
        return nil
    end

    -- Some builds return nil (without throwing) when a module method is
    -- called without self. Retry with the module before treating it as empty.
    local ok, result = pcall(func)
    if ok and type(result) == "table" then
        return result
    end

    ok, result = pcall(func, module)
    if ok and type(result) == "table" then
        return result
    end

    return nil
end

local lastSync = 0
local function requestSync(force)
    if type(syncEggs) ~= "function" then
        return
    end

    local now = os.clock()
    if not force and now - lastSync < 0.45 then
        return
    end
    lastSync = now

    task.spawn(function()
        -- Different game builds expose this as either a plain function
        -- or a module method, so try both safely.
        pcall(syncEggs)
        pcall(syncEggs, EggState)
    end)
end

-- Restore late-loaded modules even if the original require failed.
-- Never touch user settings or Voryken API slot claims during a soft refresh.
function runtimeState._recoverScannerGameData()
    local changed = false

    if type(EggState) ~= "table" or type(readEggs) ~= "function" then
        local freshState = safeRequire("Client", "EggState")
        if type(freshState) == "table" then
            EggState = freshState
            readEggs = EggState.ReadFieldEggs or EggState.GetAreaEggSnapshot
            syncEggs = EggState.SyncFieldEggs or EggState.RequestAreaEggSnapshot
            changed = type(readEggs) == "function" or changed
        end
    end

    if type(AssetsData) ~= "table" then
        local freshAssets = safeRequire("Data", "Assets")
        if type(freshAssets) == "table" then
            AssetsData = freshAssets
            changed = true
        end
    end

    if not configsFolder or not configsFolder.Parent then
        local data = ReplicatedStorage:FindFirstChild("Data")
        local assets = data and data:FindFirstChild("Assets")
        configsFolder = assets and assets:FindFirstChild("Configs") or configsFolder
    end

    local liveFolder = Workspace:FindFirstChild("AreaEggSlotsClient")
    if liveFolder and (not eggFolder or eggFolder ~= liveFolder) then
        eggFolder = liveFolder
        changed = true
        if type(runtimeState._bindEggFolder) == "function" then
            runtimeState._bindEggFolder(liveFolder)
        end
    end

    if changed then
        requestSync(true)
    end
    return changed
end

local function readSnapshotRecords()
    if type(readEggs) ~= "function" then
        return nil
    end

    local snapshot = callModuleFunction(readEggs, EggState)
    if type(snapshot) ~= "table" or type(snapshot.Records) ~= "table" then
        return nil
    end

    local byUid = {}
    for key, record in pairs(snapshot.Records) do
        if type(record) == "table" then
            local uid = tostring(record.Uid or key or "")
            if uid ~= "" then
                byUid[uid] = record
            end
        end
    end
    return byUid
end

-- Resolve the REAL normal-map zone for an egg.
-- Priority: explicit record/slot zone fields -> Workspace.__OBJECTS.Areas
-- spatial GameplayZ match -> AreaId fallback.
local normalAreaNameCache = {}

local function readableZoneValue(value)
    if value == nil then
        return nil
    end

    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or text == "nil" then
        return nil
    end

    -- Turn common technical ids into something Discord can read cleanly.
    local number = text:match("^[Aa]rea[_%-%s]*(%d+)$")
        or text:match("^[Zz]one[_%-%s]*(%d+)$")
    if number then
        return "Zone " .. tostring(tonumber(number) or number)
    end

    return text:gsub("_", " ")
end

local function getObjectWorldPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    end

    local part = object:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function getNormalAreasFolder()
    local objects = Workspace:FindFirstChild("__OBJECTS")
    return objects and objects:FindFirstChild("Areas") or nil
end

local function getAreaDisplayName(area)
    if not area then
        return nil
    end

    for _, attributeName in ipairs({
        "DisplayName", "AreaName", "ZoneName", "LocationName", "Name"
    }) do
        local value = area:GetAttribute(attributeName)
        local readable = readableZoneValue(value)
        if readable then
            return readable
        end
    end

    return readableZoneValue(area.Name)
end

local function pointInsidePartXZ(part, position)
    if not part or not part:IsA("BasePart") or typeof(position) ~= "Vector3" then
        return false
    end

    local localPosition = part.CFrame:PointToObjectSpace(position)
    local half = part.Size * 0.5
    return math.abs(localPosition.X) <= half.X
        and math.abs(localPosition.Z) <= half.Z
end

local function resolveNormalMapLocation(record, slotObject)
    record = type(record) == "table" and record or {}

    -- If the game already exposes a human-readable name, prefer it.
    for _, key in ipairs({
        "AreaName", "ZoneName", "LocationName", "RegionName", "Location", "Zone"
    }) do
        local readable = readableZoneValue(record[key])
        if readable then
            return readable
        end
    end

    if slotObject then
        for _, key in ipairs({
            "AreaName", "ZoneName", "LocationName", "RegionName", "Location", "Zone", "AreaId", "AreaID"
        }) do
            local readable = readableZoneValue(slotObject:GetAttribute(key))
            if readable then
                return readable
            end
        end
    end

    local areaId = record.AreaId or record.AreaID or record.ZoneId or record.ZoneID
    local areaIdText = areaId ~= nil and tostring(areaId) or ""
    local cacheKey = areaIdText

    if cacheKey ~= "" and normalAreaNameCache[cacheKey] then
        return normalAreaNameCache[cacheKey]
    end

    local areas = getNormalAreasFolder()
    if areas then
        -- First map AreaId directly to the game's area object if possible.
        if areaIdText ~= "" then
            local normalizedId = normalize(areaIdText)
            for _, area in ipairs(areas:GetChildren()) do
                local matches = normalize(area.Name) == normalizedId

                if not matches then
                    for _, attrName in ipairs({"AreaId", "AreaID", "Id", "ID", "ZoneId", "ZoneID"}) do
                        local attr = area:GetAttribute(attrName)
                        if attr ~= nil and normalize(attr) == normalizedId then
                            matches = true
                            break
                        end
                    end
                end

                if matches then
                    local name = getAreaDisplayName(area)
                    if name then
                        normalAreaNameCache[cacheKey] = name
                        return name
                    end
                end
            end
        end

        -- If AreaId is not directly name-like, derive the zone from the
        -- physical egg slot and each area's GameplayZ volume.
        local position = getObjectWorldPosition(slotObject)
        if position then
            local bestName = nil
            local bestVolume = math.huge

            for _, area in ipairs(areas:GetChildren()) do
                local gameplayZ = area:FindFirstChild("GameplayZ", true)
                if gameplayZ and gameplayZ:IsA("BasePart") and pointInsidePartXZ(gameplayZ, position) then
                    local volume = gameplayZ.Size.X * gameplayZ.Size.Z
                    if volume < bestVolume then
                        bestVolume = volume
                        bestName = getAreaDisplayName(area)
                    end
                end
            end

            if bestName then
                if cacheKey ~= "" then
                    normalAreaNameCache[cacheKey] = bestName
                end
                return bestName
            end
        end
    end

    -- AreaId came from EggState in previous builds and is still better than
    -- the generic "Main World" fallback when no display-name source exists.
    local fallback = readableZoneValue(areaId)
    return fallback or "Main World"
end

local function entryFromRecord(uid, record, slotObject)
    if type(record) ~= "table" then
        return nil
    end

    local category = tostring(record.AssetCategory or "Unknown")
    return {
        uid = tostring(uid or record.Uid or ""),
        category = category,
        name = getAnimalName(category),
        rarity = getRarity(category),
        image = getAnimalImage(category),
        scale = tonumber(record.AssetScale) or 1,
        value = getOfficialNormalIncome(record) or calculateValue(record),
        location = resolveNormalMapLocation(record, slotObject),
    }
end

local function getHalloweenEggEntries(forceRead)
    local insideHalloween = player:GetAttribute("InHalloweenDimension") == true

    if forceRead ~= true and not insideHalloween then
        return {}
    end

    local dimension = Workspace:FindFirstChild("HalloweenDimension")
    local worldEggs = dimension and dimension:FindFirstChild("WorldEggs") or nil
    local entries = {}

    if not worldEggs then
        return entries
    end

    local meshCategory = {
        ["107483300194220"] = "Candlefang",
        ["88930855838057"] = "Whiskers",
        ["102499305392910"] = "Jesterpop",
        ["117419359159645"] = "Spirit Knight",
        ["139505761879677"] = "Voidseer Pumpkin",
        ["77950428056342"] = "Toadstool",
        ["115585717616216"] = "Patchwork Imp",
        ["114523114225640"] = "Haunted Scorpio",
        ["77321265528523"] = "BloodBloom",
        ["121547002042884"] = "Ghost Reaper",
        ["118219413624888"] = "Crowshade",
        ["105704104295440"] = "Hexed Pumpkin",
        ["132574786315400"] = "Werewolf",
        ["86091949514460"] = "Abomination Kong",
        ["92944033837535"] = "Shelltide Voyager",
        ["114775199674739"] = "Mimic Chest",
    }

    -- Build model/mesh lookup from the CURRENT HalloweenPets Specs so newly
    -- added Halloween zones do not require a hardcoded mesh table update.
    local function getDynamicHalloweenModelMaps()
        local cached = configCache.__EggTop3HalloweenModelMaps
        if type(cached) == "table" then
            return cached
        end

        local maps = {ByModelName = {}, ByMeshId = {}}
        local halloweenPetsData = configCache.__EggTop3HalloweenPetsData
        if type(halloweenPetsData) ~= "table" then
            halloweenPetsData = safeRequire("Data", "HalloweenPets")
            configCache.__EggTop3HalloweenPetsData = halloweenPetsData or false
        end

        local specs = type(halloweenPetsData) == "table" and halloweenPetsData.Specs or nil
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        local models = assets and assets:FindFirstChild("Models") or nil
        local eggs = models and models:FindFirstChild("Eggs") or nil

        if type(specs) == "table" then
            for category, spec in pairs(specs) do
                if type(category) == "string" and type(spec) == "table" then
                    local eggModelName = spec.EggModel
                    if type(eggModelName) == "string" and eggModelName ~= "" then
                        local old = maps.ByModelName[eggModelName]
                        maps.ByModelName[eggModelName] = old == nil and category or (old == category and category or false)

                        local template = eggs and eggs:FindFirstChild(eggModelName) or nil
                        if template then
                            for _, part in ipairs(template:GetDescendants()) do
                                if part:IsA("MeshPart") then
                                    local meshId = tostring(part.MeshId or ""):match("(%d+)")
                                    if meshId then
                                        local list = maps.ByMeshId[meshId]
                                        if type(list) ~= "table" then
                                            list = {}
                                            maps.ByMeshId[meshId] = list
                                        end
                                        local found = false
                                        for _, value in ipairs(list) do
                                            if value == category then found = true break end
                                        end
                                        if not found then table.insert(list, category) end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        configCache.__EggTop3HalloweenModelMaps = maps
        return maps
    end

    local function zoneOf(object)
        local zones = dimension and dimension:FindFirstChild("Zones") or nil
        if not zones or not object then
            return nil
        end

        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if not ok or not pivot then
            return nil
        end

        for _, zone in ipairs(zones:GetChildren()) do
            if zone:IsA("BasePart") then
                local number = tonumber(tostring(zone.Name):match("^Zone(%d+)$"))
                if number then
                    local localPosition = zone.CFrame:PointToObjectSpace(pivot.Position)
                    local half = zone.Size * 0.5
                    if math.abs(localPosition.X) <= half.X
                        and math.abs(localPosition.Z) <= half.Z then
                        return number
                    end
                end
            end
        end

        return nil
    end

    local function explicitCategory(object)
        for _, key in ipairs({
            "AssetCategory",
            "AssetId",
            "PetId",
            "PetName",
            "Category",
        }) do
            local value = object:GetAttribute(key)
            if type(value) == "string"
                and value ~= ""
                and type(getConfig(value)) == "table" then
                return value
            end
        end
        return nil
    end

    local function categoryFromEggModel(object)
        local direct = explicitCategory(object)
        if direct then return direct end

        local maps = getDynamicHalloweenModelMaps()
        local byName = type(maps) == "table" and maps.ByModelName or nil
        if type(byName) == "table" then
            local named = byName[tostring(object.Name or "")]
            if type(named) == "string" and type(getConfig(named)) == "table" then
                return named
            end
        end

        local ambiguousShell = false
        local votes = {}
        for _, descendant in ipairs(object:GetDescendants()) do
            if descendant:IsA("MeshPart") then
                local meshId = tostring(descendant.MeshId or ""):match("(%d+)")
                if meshId then
                    if meshId == "70705556141109" or meshId == "85596455133555" then
                        ambiguousShell = true
                    else
                        local oldCategory = meshCategory[meshId]
                        if oldCategory and type(getConfig(oldCategory)) == "table" then
                            return oldCategory
                        end
                    end

                    local candidates = type(maps) == "table" and maps.ByMeshId and maps.ByMeshId[meshId] or nil
                    if type(candidates) == "table" then
                        for _, category in ipairs(candidates) do
                            if type(getConfig(category)) == "table" then
                                votes[category] = (votes[category] or 0) + 1
                            end
                        end
                    end
                end
            end
        end

        if ambiguousShell then
            local zone = zoneOf(object)
            if zone == 1 and type(getConfig("Graveyard Brute")) == "table" then return "Graveyard Brute" end
            if zone == 2 and type(getConfig("Hooded Gerbil")) == "table" then return "Hooded Gerbil" end
        end

        local best, bestCount, tied = nil, 0, false
        for category, count in pairs(votes) do
            if count > bestCount then
                best, bestCount, tied = category, count, false
            elseif count == bestCount and count > 0 and category ~= best then
                tied = true
            end
        end
        if best and not tied then return best end

        if tied and type(byName) == "table" then
            for _, descendant in ipairs(object:GetDescendants()) do
                local named = byName[tostring(descendant.Name or "")]
                if type(named) == "string" and votes[named] then return named end
            end
        end
        return nil
    end

    local function scaleFromEggModel(object, category)
        local scaleKeys = {
            "AssetScale",
            "Scale",
            "EggScale",
            "SizeScale",
            "GrowthScale",
        }

        local function directScaleFrom(target)
            if not target then
                return nil
            end
            for _, key in ipairs(scaleKeys) do
                local value = target:GetAttribute(key)
                if type(value) == "number" and value > 0 then
                    return value
                end
            end
            return nil
        end

        local direct = directScaleFrom(object)
        if not direct then
            for _, descendant in ipairs(object:GetDescendants()) do
                direct = directScaleFrom(descendant)
                if direct then
                    break
                end
            end
        end

        if direct then
            return math.clamp(direct, 0.002, 200)
        end

        local eggRecords = safeRequire("Shared", "Util", "EggRecords")
        if type(eggRecords) == "table"
            and type(eggRecords.EggModelTemplate) == "function"
            and type(category) == "string" then

            local template = nil
            local okTemplate = pcall(function()
                template = eggRecords.EggModelTemplate(category, nil, nil, nil)
            end)

            if okTemplate and template and template:IsA("Model") then
                local ratios = {}
                local livePart = object.PrimaryPart
                local templatePart = template.PrimaryPart

                if livePart and templatePart
                    and livePart:IsA("BasePart")
                    and templatePart:IsA("BasePart") then
                    local liveSize = livePart.Size
                    local authoredSize = templatePart.Size
                    if authoredSize.X > 0.001 then ratios[#ratios + 1] = liveSize.X / authoredSize.X end
                    if authoredSize.Y > 0.001 then ratios[#ratios + 1] = liveSize.Y / authoredSize.Y end
                    if authoredSize.Z > 0.001 then ratios[#ratios + 1] = liveSize.Z / authoredSize.Z end
                end

                if #ratios == 0 then
                    local okLive, liveSize = pcall(function() return object:GetExtentsSize() end)
                    local okAuthored, authoredSize = pcall(function() return template:GetExtentsSize() end)
                    if okLive and okAuthored
                        and typeof(liveSize) == "Vector3"
                        and typeof(authoredSize) == "Vector3" then
                        if authoredSize.X > 0.001 then ratios[#ratios + 1] = liveSize.X / authoredSize.X end
                        if authoredSize.Y > 0.001 then ratios[#ratios + 1] = liveSize.Y / authoredSize.Y end
                        if authoredSize.Z > 0.001 then ratios[#ratios + 1] = liveSize.Z / authoredSize.Z end
                    end
                end

                if #ratios > 0 then
                    table.sort(ratios)
                    local middle = ratios[math.ceil(#ratios / 2)]
                    if type(middle) == "number" and middle > 0.001 then
                        return math.clamp(middle, 0.002, 200)
                    end
                end
            end
        end

        local okScale, modelScale = pcall(function()
            return object:GetScale()
        end)
        if okScale and type(modelScale) == "number" and modelScale > 0 then
            return math.clamp(modelScale, 0.002, 200)
        end

        return 1
    end

    local seenHalloweenUid = {}

    -- Use Descendants instead of only direct children so eggs from newly added
    -- Halloween zones/folders cannot be skipped.
    local halloweenObjects = {worldEggs}
    for _, descendant in ipairs(worldEggs:GetDescendants()) do
        halloweenObjects[#halloweenObjects + 1] = descendant
    end

    for _, instance in ipairs(halloweenObjects) do
        if instance:IsA("Model") then
            local rawUid = instance:GetAttribute("HalloweenEggUid")
            local uid = rawUid ~= nil and tostring(rawUid) or ""
            local prompt = instance:FindFirstChild("StealPrompt", true)

            if uid ~= "" and not seenHalloweenUid[uid]
                and (
                    (prompt and prompt:IsA("ProximityPrompt") and insideHalloween and prompt.Enabled)
                    or forceRead == true
                ) then

                local category = categoryFromEggModel(instance)
                local config = category and getConfig(category) or nil

                if category and type(config) == "table" then
                    local visualScale = scaleFromEggModel(instance, category)
                    local baseRate = tonumber(config.EarningRate)
                        or tonumber(getBaseIncome(category))
                        or 0

                    -- SAME scale-aware payout formula used by the game.
                    local realEarningRate = getOfficialHalloweenIncome(
                        category,
                        visualScale
                    ) or baseRate

                    realEarningRate = math.max(0, math.floor((tonumber(realEarningRate) or 0) + 0.5))

                    seenHalloweenUid[uid] = true
                    entries[#entries + 1] = {
                        uid = uid,
                        category = category,
                        name = getAnimalName(category),
                        rarity = getRarity(category),
                        image = getAnimalImage(category),
                        scale = visualScale,
                        value = realEarningRate,
                        halloweenDimension = true,
                        location = "Halloween Dimension",
                    }
                end
            end
        end
    end

    return entries
end

local function getAllEggs()
    requestSync(false)

    eggFolder = Workspace:FindFirstChild("AreaEggSlotsClient") or eggFolder

    local recordsByUid = readSnapshotRecords() or {}
    local entries = {}
    local added = {}

    if eggFolder and eggFolder.Parent then
        for _, slot in ipairs(eggFolder:GetChildren()) do
            local uid = tostring(slot.Name or "")
            local record = recordsByUid[uid]
            if record then
                local entry = entryFromRecord(uid, record, slot)
                if entry and not added[uid] then
                    added[uid] = true
                    entry.halloweenDimension = false
                    table.insert(entries, entry)
                end
            end
        end
    end

    -- EggState is the game's field snapshot. Include records that are valid in
    -- that snapshot even when their physical AreaEggSlotsClient model has not
    -- streamed in yet, so a better normal-map egg cannot be missed.
    for uid, record in pairs(recordsByUid) do
        uid = tostring(uid)
        if uid ~= "" and not added[uid] then
            local entry = entryFromRecord(uid, record)
            if entry then
                added[uid] = true
                entry.halloweenDimension = false
                table.insert(entries, entry)
            end
        end
    end

    -- Halloween/New-zone eggs compete against normal eggs in the SAME ranking.
    for _, entry in ipairs(getHalloweenEggEntries(true)) do
        local uid = tostring(entry.uid or "")
        if uid ~= "" and not added[uid] then
            added[uid] = true
            table.insert(entries, entry)
        end
    end

    -- Do not sort here. getTopEggs() performs a finite-number-safe direct
    -- selection of #1/#2/#3 and then orders allEntries with the same comparator.
    return entries
end

local function getComparableEggValue(entry)
    local value = tonumber(entry and entry.value)

    -- NaN / +/-inf must never participate in ranking. A single NaN can make
    -- Lua table.sort produce a non-total order, which is why a 15M card could
    -- appear above a 35.3M card.
    if value == nil
        or value ~= value
        or value == math.huge
        or value == -math.huge then

        return 0
    end

    return value
end

local function isEggBetter(a, b)
    if a == nil then
        return false
    end

    if b == nil then
        return true
    end

    local aValue = getComparableEggValue(a)
    local bValue = getComparableEggValue(b)

    if aValue ~= bValue then
        return aValue > bValue
    end

    local aName = string.lower(tostring(a.name or ""))
    local bName = string.lower(tostring(b.name or ""))

    if aName ~= bName then
        return aName < bName
    end

    return tostring(a.uid or "") < tostring(b.uid or "")
end

local function getTopEggs()
    local entries = getAllEggs()

    -- Do NOT rely on table.sort for the actual three winners. Select them
    -- directly so row 1/2/3 are guaranteed to be numeric max #1/#2/#3 even if
    -- another live record contains malformed data.
    local top = {}

    for _, entry in ipairs(entries) do
        entry.value = getComparableEggValue(entry)

        if isEggBetter(entry, top[1]) then
            top[3] = top[2]
            top[2] = top[1]
            top[1] = entry

        elseif isEggBetter(entry, top[2]) then
            top[3] = top[2]
            top[2] = entry

        elseif isEggBetter(entry, top[3]) then
            top[3] = entry
        end
    end

    -- Keep allEntries in a deterministic descending order too because it is
    -- used for lifetime/dedupe checks elsewhere. This insertion sort uses the
    -- same finite-value comparator as the Top 3.
    for i = 2, #entries do
        local current = entries[i]
        local j = i - 1

        while j >= 1 and isEggBetter(current, entries[j]) do
            entries[j + 1] = entries[j]
            j -= 1
        end

        entries[j + 1] = current
    end

    -- Final hard normalization of the three winners. This is intentionally
    -- redundant: it guarantees #1 >= #2 >= #3 even if another code path ever
    -- mutates the table before the UI uses it.
    local function swapTop(a, b)
        top[a], top[b] = top[b], top[a]
    end

    if top[2] and isEggBetter(top[2], top[1]) then
        swapTop(1, 2)
    end
    if top[3] and isEggBetter(top[3], top[2]) then
        swapTop(2, 3)
    end
    if top[2] and isEggBetter(top[2], top[1]) then
        swapTop(1, 2)
    end

    return top, entries
end

--==============================================================
-- 3D ANIMATED ANIMAL PREVIEWS
-- ReplicatedStorage/config only. No Workspace is used.
--==============================================================

local animalModelCache = {}
local animalModelIndex = {}
local animalModelIndexBuilt = false
local animalModelIndexBuilding = false
local previewMotion = {}

local function looksLikeEggObject(object)
    if not object then
        return true
    end

    local current = object
    while current and current ~= game do
        local name = string.lower(tostring(current.Name))
        if name == "egg"
            or name == "eggs"
            or string.find(name, "eggtool", 1, true)
            or string.find(name, "eggmodel", 1, true) then
            return true
        end
        current = current.Parent
    end

    return false
end

local function modelScore(model, category, animalName)
    if not model or not model:IsA("Model") then
        return -math.huge
    end
    if looksLikeEggObject(model) then
        return -1000
    end
    if not model:FindFirstChildWhichIsA("BasePart", true) then
        return -math.huge
    end

    local categoryKey = normalize(category)
    local animalKey = normalize(animalName)
    local modelKey = normalize(model.Name)
    local score = 0
    local matched = false

    if modelKey == categoryKey then
        score += 250
        matched = true
    end
    if modelKey == animalKey then
        score += 240
        matched = true
    end
    if #categoryKey >= 5 and string.find(modelKey, categoryKey, 1, true) then
        score += 100
        matched = true
    end
    if #animalKey >= 5 and string.find(modelKey, animalKey, 1, true) then
        score += 100
        matched = true
    end

    for _, attrName in ipairs({
        "AssetCategory", "Category", "PetCategory", "AnimalCategory",
        "DisplayName", "PetName", "AnimalName"
    }) do
        local value = model:GetAttribute(attrName)
        local valueKey = normalize(value)
        if valueKey ~= "" and (valueKey == categoryKey or valueKey == animalKey) then
            score += 300
            matched = true
        end
    end

    if not matched then
        return -math.huge
    end

    local path = string.lower(model:GetFullName())
    if string.find(path, "pet", 1, true) then score += 90 end
    if string.find(path, "animal", 1, true) then score += 90 end
    if string.find(path, "creature", 1, true) then score += 70 end
    if string.find(path, "egg", 1, true) then score -= 500 end
    if model:FindFirstChildWhichIsA("Animator", true) then score += 100 end
    if model:FindFirstChildWhichIsA("AnimationController", true) then score += 80 end
    if model:FindFirstChildWhichIsA("Motor6D", true) then score += 70 end

    return score
end

local function findModelInsideConfig(config, path, depth, results, seen)
    if type(config) ~= "table" or depth > 6 then
        return
    end

    for key, value in pairs(config) do
        local keyText = string.lower(tostring(key))
        local newPath = path .. "." .. keyText

        if keyText ~= "egg" then
            if typeof(value) == "Instance" and value:IsA("Model") then
                if not seen[value] and not looksLikeEggObject(value) then
                    seen[value] = true
                    table.insert(results, {model = value, path = newPath})
                end
            elseif type(value) == "table" then
                findModelInsideConfig(value, newPath, depth + 1, results, seen)
            end
        end
    end
end

local function indexModel(model)
    if not model:IsA("Model")
        or looksLikeEggObject(model)
        or not model:FindFirstChildWhichIsA("BasePart", true) then
        return
    end

    local keys = {model.Name}
    for _, attrName in ipairs({
        "AssetCategory", "Category", "PetCategory", "AnimalCategory",
        "DisplayName", "PetName", "AnimalName"
    }) do
        local value = model:GetAttribute(attrName)
        if value ~= nil then
            table.insert(keys, tostring(value))
        end
    end

    for _, key in ipairs(keys) do
        local norm = normalize(key)
        if norm ~= "" then
            animalModelIndex[norm] = animalModelIndex[norm] or {}
            table.insert(animalModelIndex[norm], model)
        end
    end
end

local function buildAnimalIndex()
    if animalModelIndexBuilt then
        return
    end

    if animalModelIndexBuilding then
        while animalModelIndexBuilding and not animalModelIndexBuilt do
            task.wait(0.075)
        end
        return
    end

    animalModelIndexBuilding = true
    local checked = 0

    for _, object in ipairs(ReplicatedStorage:GetDescendants()) do
        if object:IsA("Model") then
            indexModel(object)
        end
        checked += 1
        if checked % 700 == 0 then
            task.wait()
        end
    end

    animalModelIndexBuilt = true
    animalModelIndexBuilding = false
end

local function findAnimalModel(category)
    if animalModelCache[category] ~= nil then
        return animalModelCache[category] or nil
    end

    local config = getConfig(category)
    local animalName = getAnimalName(category)
    local bestModel = nil
    local bestScore = -math.huge

    if type(config) == "table" then
        local results = {}
        local seen = {}
        findModelInsideConfig(config, "config", 0, results, seen)

        for _, item in ipairs(results) do
            local score = modelScore(item.model, category, animalName)
            if score > -math.huge then
                score += 200
                if string.find(item.path, "pet", 1, true)
                    or string.find(item.path, "animal", 1, true) then
                    score += 150
                end
                if score > bestScore then
                    bestScore = score
                    bestModel = item.model
                end
            end
        end
    end

    if not bestModel then
        buildAnimalIndex()

        local candidateLists = {
            animalModelIndex[normalize(category)],
            animalModelIndex[normalize(animalName)],
        }

        for _, list in ipairs(candidateLists) do
            if type(list) == "table" then
                for _, model in ipairs(list) do
                    local score = modelScore(model, category, animalName)
                    if score > bestScore then
                        bestScore = score
                        bestModel = model
                    end
                end
            end
        end
    end

    animalModelCache[category] = bestModel or false
    return bestModel
end

local function findModelIdle(source)
    local fallback = nil
    for _, object in ipairs(source:GetDescendants()) do
        if object:IsA("Animation") and object.AnimationId and object.AnimationId ~= "" then
            local name = string.lower(tostring(object.Name))
            if string.find(name, "idle", 1, true)
                or string.find(name, "stand", 1, true)
                or string.find(name, "fly", 1, true)
                or string.find(name, "hover", 1, true) then
                return object.AnimationId
            end
            fallback = fallback or object.AnimationId
        end
    end
    return fallback
end

local function findConfigIdle(category)
    local config = getConfig(category)
    if type(config) ~= "table" then
        return nil
    end

    local animations = config.Animations
    if type(animations) == "table" then
        local idle = animations.Idle
        if typeof(idle) == "Instance" and idle:IsA("Animation") and idle.AnimationId ~= "" then
            return idle.AnimationId
        end
        if type(idle) == "string" or type(idle) == "number" then
            local id = tostring(idle):match("%d+")
            if id then
                return "rbxassetid://" .. id
            end
        end

        local walk = animations.Walk
        if typeof(walk) == "Instance" and walk:IsA("Animation") and walk.AnimationId ~= "" then
            return walk.AnimationId
        end
        if type(walk) == "string" or type(walk) == "number" then
            local id = tostring(walk):match("%d+")
            if id then
                return "rbxassetid://" .. id
            end
        end
    end

    return nil
end

local function clearViewport(viewport)
    previewMotion[viewport] = nil
    for _, child in ipairs(viewport:GetChildren()) do
        child:Destroy()
    end
    viewport.CurrentCamera = nil
end

local function setupAnimalPreview(viewport, category, generation, row)
    clearViewport(viewport)

    local source = findAnimalModel(category)
    if row.PreviewGeneration ~= generation or row.Category ~= category then
        return
    end
    if not source then
        row.Fallback.Visible = true
        return
    end

    local animationId = findConfigIdle(category) or findModelIdle(source)

    local world = Instance.new("WorldModel")
    world.Parent = viewport

    local clone = nil
    local ok = pcall(function()
        source.Archivable = true
        clone = source:Clone()
    end)

    if not ok or not clone then
        row.Fallback.Visible = true
        return
    end

    clone.Parent = world

    for _, object in ipairs(clone:GetDescendants()) do
        if object:IsA("Script") or object:IsA("LocalScript") then
            object:Destroy()
        end
    end

    local rootPart = clone.PrimaryPart
        or clone:FindFirstChild("HumanoidRootPart", true)
        or clone:FindFirstChild("Root", true)
        or clone:FindFirstChildWhichIsA("BasePart", true)

    if not rootPart or not rootPart:IsA("BasePart") then
        clone:Destroy()
        row.Fallback.Visible = true
        return
    end

    for _, object in ipairs(clone:GetDescendants()) do
        if object:IsA("BasePart") then
            object.CanCollide = false
            object.CanTouch = false
            object.CanQuery = false
            object.Massless = true
            object.Anchored = object == rootPart
        end
    end
    rootPart.Anchored = true

    local boxCF, boxSize
    local boxOK = pcall(function()
        boxCF, boxSize = clone:GetBoundingBox()
    end)

    if not boxOK or not boxCF or not boxSize then
        clone:Destroy()
        row.Fallback.Visible = true
        return
    end

    local currentPivot = clone:GetPivot()
    clone:PivotTo(CFrame.new(-boxCF.Position) * currentPivot)
    pcall(function()
        boxCF, boxSize = clone:GetBoundingBox()
    end)

    viewport.BackgroundTransparency = 1
    viewport.Ambient = Color3.fromRGB(150, 150, 165)
    viewport.LightColor = Color3.fromRGB(255, 250, 240)
    viewport.LightDirection = Vector3.new(-0.35, -1, -0.5)

    local camera = Instance.new("Camera")
    camera.FieldOfView = 30
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    local largest = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)
    local distance = largest * 2.15

    local frontVector = rootPart.CFrame.LookVector
    frontVector = Vector3.new(frontVector.X, 0, frontVector.Z)
    if frontVector.Magnitude < 0.075 then
        frontVector = Vector3.new(0, 0, -1)
    else
        frontVector = frontVector.Unit
    end

    local previewFocus = Vector3.new(0, boxSize.Y * 0.04, 0)
    local previewCameraPosition = previewFocus
        + frontVector * distance
        + Vector3.new(0, boxSize.Y * 0.04, 0)

    camera.CFrame = CFrame.lookAt(previewCameraPosition, previewFocus)

    local animator = clone:FindFirstChildWhichIsA("Animator", true)
    if not animator then
        local host = clone:FindFirstChildWhichIsA("Humanoid", true)
            or clone:FindFirstChildWhichIsA("AnimationController", true)

        if not host then
            host = Instance.new("AnimationController")
            host.Parent = clone
        end

        animator = host:FindFirstChildWhichIsA("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = host
        end
    end

    if animationId and animator then
        pcall(function()
            local animation = Instance.new("Animation")
            animation.AnimationId = animationId
            local track = animator:LoadAnimation(animation)
            track.Looped = true
            track.Priority = Enum.AnimationPriority.Idle
            track:Play(0.10, 1, 1)
        end)
    end

    if row.PreviewGeneration ~= generation or row.Category ~= category then
        clearViewport(viewport)
        return
    end

    row.Fallback.Visible = false

    previewMotion[viewport] = {
        Model = clone,
        Camera = camera,
        Focus = previewFocus,
        Front = frontVector,
        Distance = distance,
        Height = boxSize.Y,
        Offset = math.random() * math.pi * 2,
    }
end

RunService.RenderStepped:Connect(function()
    local now = os.clock()

    for viewport, data in pairs(previewMotion) do
        if not viewport.Parent
            or not data.Model or not data.Model.Parent
            or not data.Camera or not data.Camera.Parent then
            previewMotion[viewport] = nil
        else
            local phase = now + data.Offset
            local bob = math.sin(phase * 1.65) * data.Height * 0.012
            local yaw = math.sin(phase * 0.80) * math.rad(4.0)
            local pitch = math.sin(phase * 0.95) * math.rad(1.25)

            local rotatedFront = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(data.Front)
            local focus = data.Focus + Vector3.new(0, bob, 0)
            local cameraPosition = focus
                + rotatedFront * data.Distance
                + Vector3.new(0, data.Height * 0.04, 0)

            pcall(function()
                data.Camera.CFrame = CFrame.lookAt(cameraPosition, focus)
                    * CFrame.Angles(pitch, 0, 0)
            end)
        end
    end
end)

--==============================================================
-- UI
--==============================================================

local GUI_NAME = "EggTop3Panel"
local old = playerGui:FindFirstChild(GUI_NAME)
if old then
    old:Destroy()
end

local screen = make("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 50,
}, playerGui)

-- Recover a saved menu location if it is no longer visible after a
-- resolution/device change. This does not affect normally placed panels.
local scannerPanelPosition = unpackUDim2(settings.PanelPosition, UDim2.new(0.5, 0, 0.5, 0))
local scannerViewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(390, 844)
local scannerPX = scannerPanelPosition.X.Scale * scannerViewport.X + scannerPanelPosition.X.Offset
local scannerPY = scannerPanelPosition.Y.Scale * scannerViewport.Y + scannerPanelPosition.Y.Offset
if scannerPX < -140 or scannerPY < -180 or scannerPX > scannerViewport.X + 140 or scannerPY > scannerViewport.Y + 180 then
    scannerPanelPosition = UDim2.new(0.5, 0, 0.5, 0)
    settings.PanelPosition = packUDim2(scannerPanelPosition)
    saveSettings()
end

local root = make("Frame", {
    Name = "Panel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = scannerPanelPosition,
    Size = UDim2.fromOffset(300, 452),
    BackgroundColor3 = COLORS.Main,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    Active = true,
}, screen)
corner(root, 18)
stroke(root, COLORS.Purple, 0.20, 1.4)

local header = make("Frame", {
    Name = "Header",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = true,
}, root)

make("TextLabel", {
    Position = UDim2.fromOffset(14, 9),
    Size = UDim2.fromOffset(150, 22),
    BackgroundTransparency = 1,
    Text = "EGG FINDER",
    TextColor3 = COLORS.White,
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local subtitle = make("TextLabel", {
    Position = UDim2.fromOffset(14, 31),
    Size = UDim2.fromOffset(160, 16),
    BackgroundTransparency = 1,
    Text = "Reading current eggs...",
    TextColor3 = COLORS.Gray,
    TextSize = 9,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local serverHopEnabled = settings.ServerHopEnabled == true
local serverHopButton = make("TextButton", {
    Position = UDim2.new(1, -94, 0, 12),
    Size = UDim2.fromOffset(82, 28),
    BackgroundColor3 = Color3.fromRGB(28, 30, 42),
    BorderSizePixel = 0,
    Text = "SERVER HOP",
    TextColor3 = COLORS.Gray,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
    ZIndex = 20,
}, header)
corner(serverHopButton, 9)
local serverHopStroke = stroke(serverHopButton, Color3.fromRGB(66, 69, 88), 0.35, 1)

local function refreshServerHopButton()
    if serverHopEnabled then
        serverHopButton.BackgroundColor3 = Color3.fromRGB(38, 30, 68)
        serverHopButton.TextColor3 = COLORS.White
        serverHopStroke.Color = COLORS.Purple
        serverHopStroke.Transparency = 0.10
        serverHopStroke.Thickness = 1.25
    else
        serverHopButton.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
        serverHopButton.TextColor3 = COLORS.Gray
        serverHopStroke.Color = Color3.fromRGB(66, 69, 88)
        serverHopStroke.Transparency = 0.35
        serverHopStroke.Thickness = 1
    end
end

refreshServerHopButton()

local dragging = false
local dragStart = nil
local startPosition = nil

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = root.Position
    end
end)

header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        settings.PanelPosition = packUDim2(root.Position)
        saveSettings()
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragStart or not startPosition then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart
    root.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

local cardsArea = make("Frame", {
    Name = "Cards",
    Position = UDim2.fromOffset(12, 56),
    Size = UDim2.new(1, -24, 0, 250),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, root)

local rows = {}
local lastTopSignature = nil
local refreshRequested = true
local selectedEntry = nil
local selectedUid = (tostring(settings.SelectedUid or "") ~= "") and tostring(settings.SelectedUid) or nil
local refreshSelectionVisual = nil

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isDiscordWebhook(url)
    url = string.lower(trim(url))
    return url:match("^https://discord%.com/api/webhooks/")
        or url:match("^https://discordapp%.com/api/webhooks/")
        or url:match("^https://canary%.discord%.com/api/webhooks/")
        or url:match("^https://ptb%.discord%.com/api/webhooks/")
end

local function getRequester()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env) ~= "table" then
        return nil
    end

    local requester = env.request or env.http_request or env.httprequest
    if type(requester) == "function" then
        return requester
    end

    if type(env.syn) == "table" and type(env.syn.request) == "function" then
        return env.syn.request
    end

    if type(env.http) == "table" and type(env.http.request) == "function" then
        return env.http.request
    end

    if type(env.fluxus) == "table" and type(env.fluxus.request) == "function" then
        return env.fluxus.request
    end

    return nil
end

--==============================================================
-- API MIRROR • REALTIME EGG FEED
-- Every egg that enters the automatic Discord queue is also
-- published immediately to Voryken API, without waiting for Discord.
--==============================================================
-- VORYKEN Firebase directo: NINGUNA WEB API KEY ni Firebase Auth.
-- Cola publica (servidorespyton); los reportes 100M+ admiten escritura
-- pero no lectura publica (finder-2), segun Rules del proyecto.
local VORYKEN_API_ROOT = "https://servidorespyton-default-rtdb.firebaseio.com"
local VORYKEN_EGGS_API_ROOT = "https://finder-2-d8407-default-rtdb.firebaseio.com"

local function firebaseHttp(method, url, value, headers)
    local requestFn = getRequester()
    if type(requestFn) ~= "function" then return false, nil, 0, "EXECUTOR_HTTP_UNAVAILABLE" end
    local args = {
        Url = url, Method = tostring(method or "GET"), Timeout = 6,
        Headers = headers or { ["Accept"] = "application/json" }
    }
    if value ~= nil then
        args.Body = type(value) == "string" and value or HttpService:JSONEncode(value)
        args.Headers["Content-Type"] = args.Headers["Content-Type"] or "application/json"
    end
    -- Some executors ignore request.Timeout. Bound our wait independently so
    -- a stuck HTTP call never freezes scanning or delays a Roblox teleport.
    local finished, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(requestFn, args)
        finished = true
    end)
    local deadline = os.clock() + 7
    while not finished and os.clock() < deadline do task.wait(0.05) end
    if not finished then return false, nil, 0, "FIREBASE_CLIENT_TIMEOUT_7S" end
    if not ok then return false, nil, 0, tostring(result) end
    local code = type(result) == "table" and tonumber(result.StatusCode or result.Status or result.status) or 200
    local raw = type(result) == "table" and (result.Body or result.body or result.ResponseBody) or result
    if code and (code < 200 or code >= 300) then
        return false, nil, code, "FIREBASE_HTTP_" .. tostring(code) .. " " .. tostring(raw or ""):sub(1, 110)
    end
    if type(raw) ~= "string" or raw == "" or raw == "null" then return true, nil, code, nil end
    local parsedOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not parsedOk then return false, nil, code, "FIREBASE_INVALID_JSON" end
    return true, data, code, nil
end

local FirebaseQueue = {
    uid = tostring(player.UserId or 0), lastError=nil,
    ensureAuth=function() return true end
}
local FirebaseEggs = {
    uid = tostring(player.UserId or 0), lastError=nil,
    ensureAuth=function() return true end
}
local VorykenStore = {}
function VorykenStore.safe(value)
    return tostring(value or ""):gsub("[^%w_%-]", "_")
end
function VorykenStore.request(method, url, value, extraHeaders)
    local input = tostring(url or "")
    local isEggs = input:sub(1, #VORYKEN_EGGS_API_ROOT) == VORYKEN_EGGS_API_ROOT
    local root = isEggs and VORYKEN_EGGS_API_ROOT or VORYKEN_API_ROOT
    if input:sub(1,#root) ~= root then
        return false,nil,400,"INVALID_FIREBASE_HOST",nil
    end
    if isEggs and tostring(method):upper() ~= "PUT" then
        return false,nil,403,"REPORTS_WRITE_ONLY",nil
    end
    local ok, result, status, reason = firebaseHttp(method,input,value,extraHeaders)
    return ok,result,status,reason,nil
end

--==============================================================
-- API CLOCK + 5 MINUTE CYCLE GUARD
-- Keeps startup non-blocking. The clock sync and cleanup run in task.spawn.
--==============================================================
local CycleRuntime = {
    eggTtlMs = 5 * 60 * 1000,
    cycleLengthMs = 5 * 60 * 1000,
    guardMs = 25 * 1000,
    resetWaitMax = 7.0,
    clockOffsetMs = 0,
    clockHasSync = false,
    clockBusy = false,
    clockLastSync = -math.huge,
    boundaryMs = nil,
    oldSignature = nil,
    postStarted = nil,
}

function CycleRuntime.localUnixMs()
    local ok, ms = pcall(function() return DateTime.now().UnixTimestampMillis end)
    if ok and tonumber(ms) then return tonumber(ms) end
    return (tonumber(os.time()) or 0) * 1000
end

function CycleRuntime.request(method, url, body)
    local ok, data, _status, reason = VorykenStore.request(method, url, body)
    return ok, data, reason
end

function CycleRuntime.syncClock(force)
    -- The JSON API does not implement Voryken API /.info/serverTimeOffset.
    -- Roblox DateTime.now provides epoch milliseconds for the 5-minute guard.
    CycleRuntime.clockOffsetMs = 0
    CycleRuntime.clockHasSync = true
    CycleRuntime.clockLastSync = os.clock()
end

function CycleRuntime.nowMs()
    CycleRuntime.syncClock(false)
    return CycleRuntime.localUnixMs() + CycleRuntime.clockOffsetMs
end

function CycleRuntime.eggSignature(entries)
    local parts = {}
    for _, entry in ipairs(entries or {}) do
        parts[#parts + 1] = table.concat({
            tostring(entry.uid or ""),
            tostring(entry.category or ""),
            tostring(tonumber(entry.value) or 0),
            string.format("%.4f", tonumber(entry.scale) or 1),
        }, ":")
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

function CycleRuntime.windowInfo(nowMs)
    nowMs = tonumber(nowMs) or CycleRuntime.nowMs()
    local remainder = nowMs % CycleRuntime.cycleLengthMs
    local remaining = CycleRuntime.cycleLengthMs - remainder
    if remainder == 0 then
        remaining = CycleRuntime.cycleLengthMs
    end
    return remaining <= CycleRuntime.guardMs, remaining
end

function CycleRuntime.hopBlocked()
    local nowMs = CycleRuntime.nowMs()
    local inPreWindow = CycleRuntime.windowInfo(nowMs)
    if inPreWindow then
        return true
    end
    if CycleRuntime.boundaryMs ~= nil then
        return true
    end
    return false
end

-- Returns NORMAL, HOLD, WAIT, READY, or EMPTY.
function CycleRuntime.updateGuard(entries)
    local nowMs = CycleRuntime.nowMs()
    local inPreWindow, remainingMs = CycleRuntime.windowInfo(nowMs)

    if inPreWindow then
        local boundaryMs = nowMs + remainingMs
        if CycleRuntime.boundaryMs ~= boundaryMs then
            CycleRuntime.boundaryMs = boundaryMs
            CycleRuntime.oldSignature = CycleRuntime.eggSignature(entries)
            CycleRuntime.postStarted = nil
        else
            local sig = CycleRuntime.eggSignature(entries)
            if sig ~= "" then
                CycleRuntime.oldSignature = sig
            end
        end
        return "HOLD"
    end

    if CycleRuntime.boundaryMs and nowMs >= CycleRuntime.boundaryMs then
        if not CycleRuntime.postStarted then
            CycleRuntime.postStarted = os.clock()
        end

        local currentSignature = CycleRuntime.eggSignature(entries)
        local changed = currentSignature ~= ""
            and currentSignature ~= tostring(CycleRuntime.oldSignature or "")

        if changed then
            CycleRuntime.boundaryMs = nil
            CycleRuntime.oldSignature = nil
            CycleRuntime.postStarted = nil
            return "READY"
        end

        if os.clock() - CycleRuntime.postStarted >= CycleRuntime.resetWaitMax then
            CycleRuntime.boundaryMs = nil
            CycleRuntime.oldSignature = nil
            CycleRuntime.postStarted = nil
            return "EMPTY"
        end

        return "WAIT"
    end

    return "NORMAL"
end

function CycleRuntime.cleanupOldEggs()
    -- Intentional no-op: thousands of scanners should not all delete records.
    -- One Python collector performs bounded/periodic cleanup if configured.
end

CycleRuntime.syncClock(true)
task.spawn(function()
    task.wait(1)
    pcall(CycleRuntime.cleanupOldEggs)
end)

local function apiSafeKey(value)
    local text = tostring(value or "")
    if text == "" then return "unknown" end
    return VorykenStore.safe(text)
end

local function apiLocationForEntry(entry)
    if entry and type(entry.location) == "string" and entry.location ~= "" then
        return tostring(entry.location)
    end
    if entry and entry.halloweenDimension == true then
        return "Halloween Dimension"
    end
    return "Main World"
end

local function publishEntryToApi(entry, threshold)
    if CycleRuntime.hopBlocked() then
        return false, "CYCLE_GUARD"
    end

    local requester = getRequester()
    if type(requester) ~= "function" or type(entry) ~= "table" then
        return false, "HTTP_REQUEST_UNAVAILABLE"
    end

    local uid = tostring(entry.uid or "")
    local jobId = tostring(game.JobId or "")
    if uid == "" or jobId == "" then
        return false, "MISSING_ID"
    end

    -- Count other players only. The scanner's own account must not
    -- inflate the player count published with each detected egg.
    local otherPlayerCount = 0
    local scannerPlayer = Players.LocalPlayer
    for _, inServerPlayer in ipairs(Players:GetPlayers()) do
        if inServerPlayer ~= scannerPlayer then
            otherPlayerCount += 1
        end
    end

    local payload = {
        uid = uid,
        category = tostring(entry.category or ""),
        name = tostring(entry.name or "Unknown"),
        rarity = tostring(entry.rarity or "Unknown"),
        value = tonumber(entry.value) or 0,
        scale = tonumber(entry.scale) or 1,
        location = apiLocationForEntry(entry),
        placeId = tonumber(game.PlaceId) or 0,
        jobId = jobId,
        threshold = tonumber(threshold) or 0,
        playerCount = otherPlayerCount,
        maxPlayers = tonumber(Players.MaxPlayers) or 0,
        sentAt = CycleRuntime.localUnixMs(),
        detectedAt = CycleRuntime.localUnixMs(),
        updatedAt = CycleRuntime.localUnixMs(),
        source = "Voryken Egg Finder",
        schemaVersion = 2,
    }

    if not FirebaseEggs.ensureAuth() then
        return false, FirebaseEggs.lastError or "FINDER_AUTH_ERROR"
    end
    local url = VORYKEN_EGGS_API_ROOT
        .. "/reports/" .. tostring(FirebaseEggs.uid)
        .. "/" .. apiSafeKey(jobId)
        .. "/" .. apiSafeKey(uid)
        .. ".json"

    -- One request per attempt. Fast failure must not stall the hop forever.
    -- The caller decides whether to retry this UID on a later scan.
    local ok, _data, status, reason = VorykenStore.request("PUT", url, payload)
    if ok then
        runtimeState._lastEggPublishError = nil
        return true, status
    end
    local detail = tostring(reason or ("HTTP_" .. tostring(status or "NO_STATUS")))
    runtimeState._lastEggPublishError = detail
    warn("[VORYKEN REPORT] Finder-2 PUT failed: " .. detail:sub(1, 180))
    return false, detail

end

local thumbnailCache = {}
local animalImageCache = {}

local function extractAssetId(value)
    if value == nil then
        return nil
    end

    local id = tostring(value):match("(%d+)")
    id = tonumber(id)
    if id and id > 0 then
        return math.floor(id)
    end
    return nil
end

local function resolveRobloxThumbnail(raw)
    if raw == nil then
        return nil
    end

    local value = tostring(raw)
    local lower = string.lower(value)

    -- Direct image/CDN URLs can be embedded by Discord immediately.
    if lower:match("^https?://")
        and (
            lower:find("rbxcdn.com", 1, true)
            or lower:find("cdn.discordapp.com", 1, true)
            or lower:find("media.discordapp.net", 1, true)
        ) then
        return value
    end

    local assetId = extractAssetId(raw)
    if not assetId then
        return nil
    end

    local cacheKey = tostring(assetId)
    if thumbnailCache[cacheKey] ~= nil then
        return thumbnailCache[cacheKey] ~= false and thumbnailCache[cacheKey] or nil
    end

    local apiUrl = "https://thumbnails.roblox.com/v1/assets?assetIds="
        .. cacheKey
        .. "&returnPolicy=AutoGenerated&size=420x420&format=Png&isCircular=false"

    local requester = getRequester()

    local function getBody()
        local body = nil

        if type(requester) == "function" then
            local ok, response = pcall(function()
                return requester({
                    Url = apiUrl,
                    Method = "GET",
                    Headers = { ["Accept"] = "application/json" },
                })
            end)

            if ok and type(response) == "table" then
                local statusCode = tonumber(
                    response.StatusCode
                    or response.Status
                    or response.status
                    or response.status_code
                )

                if not statusCode or (statusCode >= 200 and statusCode < 300) then
                    body = response.Body or response.body
                end
            end
        end

        if not body then
            pcall(function()
                body = game:HttpGet(apiUrl)
            end)
        end

        return body
    end

    local function decodeResult(body)
        if type(body) ~= "string" or body == "" then
            return nil, ""
        end

        local decoded = nil
        pcall(function()
            decoded = HttpService:JSONDecode(body)
        end)

        local result = type(decoded) == "table"
            and type(decoded.data) == "table"
            and type(decoded.data[1]) == "table"
            and decoded.data[1]
            or nil

        local imageUrl = result and result.imageUrl or nil
        local state = result and string.lower(tostring(result.state or "")) or ""
        return imageUrl, state
    end

    local imageUrl, state = decodeResult(getBody())

    -- IMPORTANT: never use Roblox's white placeholder image.
    if state == "completed" and type(imageUrl) == "string" and imageUrl ~= "" then
        thumbnailCache[cacheKey] = imageUrl
        return imageUrl
    end

    -- Pending thumbnails get a short retry, exactly like the older working script.
    if state == "pending" then
        task.wait(0.18)
        local retryUrl, retryState = decodeResult(getBody())
        if retryState == "completed" and type(retryUrl) == "string" and retryUrl ~= "" then
            thumbnailCache[cacheKey] = retryUrl
            return retryUrl
        end
    end

    -- Blocked/Error/InReview/Pending-after-retry: mark this candidate bad so
    -- the animal image resolver can test the next model/mesh/icon id.
    thumbnailCache[cacheKey] = false
    return nil
end

local function getWebhookAnimalImage(category)
    category = tostring(category or "")

    local cached = animalImageCache[category]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local config = getConfig(category)
    local candidates = {}
    local usedIds = {}

    local function addCandidate(raw, priority)
        local assetId = extractAssetId(raw)
        if not assetId or usedIds[assetId] then
            return
        end

        usedIds[assetId] = true
        candidates[#candidates + 1] = {
            Raw = raw,
            Priority = tonumber(priority) or 0,
        }
    end

    if type(config) == "table" then
        -- Prefer model/package ids because they produce a recognizable animal.
        addCandidate(config.ModelId, 1100)
        addCandidate(config.AssetId, 1090)
        addCandidate(config.Icon, 1000)
        addCandidate(config.Image, 990)
        addCandidate(config.Thumbnail, 980)
        addCandidate(config.Portrait, 970)

        if type(config.Egg) == "table" then
            addCandidate(config.Egg.Icon, 940)
            addCandidate(config.Egg.Image, 930)
            addCandidate(config.Egg.Thumbnail, 920)
        end

        local seen = {}
        local function scanConfig(value, depth)
            if depth > 6 or type(value) ~= "table" or seen[value] then
                return
            end
            seen[value] = true

            for key, item in pairs(value) do
                local keyText = string.lower(tostring(key))
                local excluded = keyText:find("animation", 1, true)
                    or keyText:find("idle", 1, true)
                    or keyText:find("walk", 1, true)
                    or keyText:find("run", 1, true)

                if not excluded and (type(item) == "string" or type(item) == "number") then
                    local priority = nil
                    if keyText:find("thumbnail", 1, true) then
                        priority = 900
                    elseif keyText:find("portrait", 1, true) then
                        priority = 890
                    elseif keyText:find("icon", 1, true) then
                        priority = 880
                    elseif keyText:find("image", 1, true) then
                        priority = 870
                    elseif keyText:find("model", 1, true) then
                        priority = 860
                    elseif keyText:find("mesh", 1, true) then
                        priority = 850
                    elseif keyText:find("asset", 1, true) then
                        priority = 840
                    end

                    if priority then
                        addCandidate(item, priority)
                    end
                elseif type(item) == "table" then
                    scanConfig(item, depth + 1)
                end
            end
        end

        scanConfig(config, 0)
    end

    local source = findAnimalModel(category)
    if source then
        pcall(function()
            addCandidate(source.SourceAssetId, 1080)
        end)

        for _, attributeName in ipairs({
            "AssetId", "SourceAssetId", "ModelId", "PetAssetId", "PetId"
        }) do
            pcall(function()
                addCandidate(source:GetAttribute(attributeName), 1070)
            end)
        end

        for _, object in ipairs(source:GetDescendants()) do
            if object:IsA("PackageLink") then
                pcall(function()
                    addCandidate(object.PackageId, 1060)
                end)
            elseif object:IsA("MeshPart") then
                pcall(function()
                    addCandidate(object.MeshId, 1050)
                end)
                pcall(function()
                    addCandidate(object.SourceAssetId, 1040)
                end)
                pcall(function()
                    addCandidate(object.TextureID, 500)
                end)
            elseif object:IsA("SpecialMesh") then
                pcall(function()
                    addCandidate(object.MeshId, 1030)
                end)
                pcall(function()
                    addCandidate(object.TextureId, 490)
                end)
            elseif object:IsA("Decal") or object:IsA("Texture") then
                pcall(function()
                    addCandidate(object.Texture, 480)
                end)
            elseif object:IsA("SurfaceAppearance") then
                pcall(function()
                    addCandidate(object.ColorMap, 470)
                end)
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Priority > b.Priority
    end)

    for _, candidate in ipairs(candidates) do
        local imageUrl = resolveRobloxThumbnail(candidate.Raw)
        if imageUrl then
            animalImageCache[category] = imageUrl
            return imageUrl
        end
    end

    animalImageCache[category] = false
    return nil
end

--==============================================================
-- REAL ANIMAL ICON -> PNG ATTACHMENT
-- Same method as the older notifier: config.Icon -> EditableImage -> PNG.
-- This also works when the Roblox image asset is private to the experience.
--==============================================================

local crc32Table = table.create(256)
for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
        if bit32.band(crc, 1) ~= 0 then
            crc = bit32.bxor(bit32.rshift(crc, 1), 0xEDB88320)
        else
            crc = bit32.rshift(crc, 1)
        end
    end
    crc32Table[i + 1] = crc
end

local function u32be(n)
    n = n % 4294967296
    return string.char(
        bit32.band(bit32.rshift(n, 24), 0xFF),
        bit32.band(bit32.rshift(n, 16), 0xFF),
        bit32.band(bit32.rshift(n, 8), 0xFF),
        bit32.band(n, 0xFF)
    )
end

local function crc32(data)
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        local byte = string.byte(data, i)
        local index = bit32.band(bit32.bxor(crc, byte), 0xFF) + 1
        crc = bit32.bxor(bit32.rshift(crc, 8), crc32Table[index])
    end
    return bit32.bxor(crc, 0xFFFFFFFF)
end

local function adler32(data)
    local MOD = 65521
    local a = 1
    local b = 0
    local index = 1

    while index <= #data do
        local last = math.min(index + 4095, #data)
        for i = index, last do
            a = a + string.byte(data, i)
            b = b + a
        end
        a = a % MOD
        b = b % MOD
        index = last + 1
    end

    return b * 65536 + a
end

local function pngChunk(chunkType, data)
    local payload = chunkType .. data
    return u32be(#data) .. payload .. u32be(crc32(payload))
end

local function makeZlibStored(data)
    local parts = { string.char(0x78, 0x01) }
    local offset = 1
    local total = #data

    while offset <= total do
        local count = math.min(65535, total - offset + 1)
        local isFinal = (offset + count - 1) >= total
        local lenLow = count % 256
        local lenHigh = math.floor(count / 256)
        local nlen = 65535 - count
        local nlenLow = nlen % 256
        local nlenHigh = math.floor(nlen / 256)

        parts[#parts + 1] = string.char(
            isFinal and 1 or 0,
            lenLow,
            lenHigh,
            nlenLow,
            nlenHigh
        )
        parts[#parts + 1] = string.sub(data, offset, offset + count - 1)
        offset = offset + count
    end

    parts[#parts + 1] = u32be(adler32(data))
    return table.concat(parts)
end

local function rgbaToPng(pixelBuffer, width, height)
    width = math.floor(width)
    height = math.floor(height)

    if width <= 0 or height <= 0 or type(buffer) ~= "table" then
        return nil
    end

    local rowBytes = width * 4
    local rows = table.create(height)

    for y = 0, height - 1 do
        rows[y + 1] = string.char(0)
            .. buffer.readstring(pixelBuffer, y * rowBytes, rowBytes)
    end

    local raw = table.concat(rows)
    local ihdr = u32be(width)
        .. u32be(height)
        .. string.char(8, 6, 0, 0, 0)

    return "\137PNG\r\n\26\n"
        .. pngChunk("IHDR", ihdr)
        .. pngChunk("IDAT", makeZlibStored(raw))
        .. pngChunk("IEND", "")
end

local function renderAnimalPng(category, useEggIcon)
    category = tostring(category or "")
    if category == "" then
        return nil, "MISSING_CATEGORY"
    end

    local config = getConfig(category)
    if type(config) ~= "table" then
        return nil, "CONFIG_NOT_FOUND"
    end

    local animalIcon = nil

    if useEggIcon == true then
        local eggConfig = type(config.Egg) == "table" and config.Egg or nil
        if eggConfig then
            animalIcon = eggConfig.Icon
                or eggConfig.Image
                or eggConfig.Thumbnail
                or eggConfig.Texture
                or eggConfig.TextureId
                or eggConfig.ImageId
        end

        if animalIcon == nil or tostring(animalIcon) == "" then
            return nil, "EGG_ICON_NOT_FOUND"
        end
    else
        animalIcon = config.Icon
            or config.Image
            or config.Thumbnail
            or config.Texture
            or config.TextureId
            or config.ImageId
            or ""
    end

    animalIcon = tostring(animalIcon)
    if animalIcon == "" then
        return nil, useEggIcon and "EGG_ICON_NOT_FOUND" or "ANIMAL_ICON_NOT_FOUND"
    end

    if type(buffer) ~= "table" then
        return nil, "BUFFER_API_UNAVAILABLE"
    end

    local assetService = game:GetService("AssetService")

    local okContent, contentRef = pcall(function()
        return Content.fromUri(animalIcon)
    end)
    if not okContent or contentRef == nil then
        return nil, "CONTENT_API_UNAVAILABLE"
    end

    local okSource, sourceImage = pcall(function()
        return assetService:CreateEditableImageAsync(contentRef)
    end)
    if not okSource or not sourceImage then
        return nil, "EDITABLE_IMAGE_OPEN_FAILED"
    end

    local targetImage = nil
    local imageToRead = sourceImage
    local TARGET = 256
    local sourceSize = sourceImage.Size

    if sourceSize.X ~= TARGET or sourceSize.Y ~= TARGET then
        local okTarget, created = pcall(function()
            return assetService:CreateEditableImage({
                Size = Vector2.new(TARGET, TARGET),
            })
        end)

        if okTarget and created then
            targetImage = created
            local scale = math.min(
                TARGET / math.max(sourceSize.X, 1),
                TARGET / math.max(sourceSize.Y, 1)
            )

            local okDraw = pcall(function()
                targetImage:DrawImageTransformed(
                    Vector2.new(TARGET / 2, TARGET / 2),
                    Vector2.new(scale, scale),
                    0,
                    sourceImage,
                    {
                        CombineType = Enum.ImageCombineType.Overwrite,
                        SamplingMode = Enum.ResamplerMode.Default,
                        PivotPoint = sourceSize / 2,
                    }
                )
            end)

            if okDraw then
                imageToRead = targetImage
                task.wait()
            end
        end
    end

    local finalSize = imageToRead.Size
    local okRead, pixels = pcall(function()
        return imageToRead:ReadPixelsBuffer(Vector2.zero, finalSize)
    end)

    if not okRead or not pixels then
        if targetImage then
            targetImage:Destroy()
        end
        sourceImage:Destroy()
        return nil, "PIXEL_READ_FAILED"
    end

    local okPng, pngBytes = pcall(
        rgbaToPng,
        pixels,
        finalSize.X,
        finalSize.Y
    )

    if targetImage then
        targetImage:Destroy()
    end
    sourceImage:Destroy()

    if not okPng or typeof(pngBytes) ~= "string" or #pngBytes < 100 then
        return nil, "PNG_ENCODE_FAILED"
    end

    return pngBytes, "OK"
end

local function buildDiscordMultipartFiles(payload, files)
    local boundary = "----------------Finder"
        .. tostring(math.floor(os.clock() * 1000000))
        .. tostring(math.random(100000, 999999))

    local payloadJson = HttpService:JSONEncode(payload)
    local parts = {
        "--" .. boundary .. "\r\n",
        'Content-Disposition: form-data; name="payload_json"\r\n',
        "Content-Type: application/json\r\n\r\n",
        payloadJson,
        "\r\n",
    }

    for index, file in ipairs(files or {}) do
        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = 'Content-Disposition: form-data; name="files['
            .. tostring(index - 1)
            .. ']"; filename="'
            .. tostring(file.filename)
            .. '"\r\n'
        parts[#parts + 1] = "Content-Type: image/png\r\n\r\n"
        parts[#parts + 1] = file.bytes
        parts[#parts + 1] = "\r\n"
    end

    parts[#parts + 1] = "--" .. boundary .. "--\r\n"
    return boundary, table.concat(parts)
end

local function rarityColor(rarity)
    return RARITY_COLORS[tostring(rarity or "")] or COLORS.Gray
end

local function createCard(index)
    local y = (index - 1) * 86

    local frame = make("Frame", {
        Name = "Card" .. tostring(index),
        Position = UDim2.fromOffset(0, y),
        Size = UDim2.new(1, 0, 0, 78),
        BackgroundColor3 = COLORS.Card,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
    }, cardsArea)
    corner(frame, 12)
    local cardStroke = stroke(frame, Color3.fromRGB(67, 70, 88), 0.45, 1)

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 16
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.CardAlt),
        ColorSequenceKeypoint.new(0.55, COLORS.Card),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(31, 25, 46)),
    })
    gradient.Parent = frame

    local viewportShell = make("Frame", {
        Position = UDim2.fromOffset(7, 7),
        Size = UDim2.fromOffset(62, 62),
        BackgroundColor3 = Color3.fromRGB(14, 15, 22),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
    }, frame)
    corner(viewportShell, 10)

    local viewport = make("ViewportFrame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Ambient = Color3.fromRGB(215, 220, 235),
        LightColor = Color3.new(1, 1, 1),
        LightDirection = Vector3.new(-1, -1, -1),
    }, viewportShell)

    local fallback = make("ImageLabel", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        Image = "",
        ScaleType = Enum.ScaleType.Fit,
        Visible = true,
    }, viewportShell)

    local nameLabel = make("TextLabel", {
        Position = UDim2.fromOffset(76, 8),
        Size = UDim2.new(1, -126, 0, 18),
        BackgroundTransparency = 1,
        Text = "--",
        TextColor3 = COLORS.White,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)

    local sizeLabel = make("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(44, 17),
        BackgroundColor3 = Color3.fromRGB(18, 34, 49),
        BorderSizePixel = 0,
        Text = "x--",
        TextColor3 = COLORS.Blue,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
    }, frame)
    corner(sizeLabel, 6)

    local rarityLabel = make("TextLabel", {
        Position = UDim2.fromOffset(76, 48),
        Size = UDim2.fromOffset(110, 16),
        BackgroundTransparency = 1,
        Text = "--",
        TextColor3 = COLORS.Gray,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, frame)

    local valueLabel = make("TextLabel", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -8, 1, -9),
        Size = UDim2.fromOffset(92, 18),
        BackgroundTransparency = 1,
        Text = "$--",
        TextColor3 = COLORS.Green,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    local click = make("TextButton", {
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 50,
    }, frame)

    local row = {
        Index = index,
        Frame = frame,
        Stroke = cardStroke,
        Click = click,
        Viewport = viewport,
        Fallback = fallback,
        Name = nameLabel,
        Size = sizeLabel,
        Rarity = rarityLabel,
        Value = valueLabel,
        Entry = nil,
        Category = nil,
        PreviewGeneration = 0,
        Signature = nil,
    }

    rows[index] = row

    click.Activated:Connect(function()
        if not row.Entry then
            return
        end
        selectedEntry = row.Entry
        selectedUid = tostring(row.Entry.uid)
        settings.SelectedUid = selectedUid
        settings.SelectedCategory = tostring(row.Entry.category or "")
        saveSettings()
        if refreshSelectionVisual then
            refreshSelectionVisual()
        end
    end)
end

for i = 1, TOP_COUNT do
    createCard(i)
end

refreshSelectionVisual = function()
    for _, row in ipairs(rows) do
        local selected = row.Entry
            and selectedUid ~= nil
            and tostring(row.Entry.uid) == tostring(selectedUid)

        if row.Stroke then
            row.Stroke.Color = selected and COLORS.Purple or Color3.fromRGB(67, 70, 88)
            row.Stroke.Transparency = selected and 0.03 or 0.45
            row.Stroke.Thickness = selected and 2 or 1
        end
    end
end

local webhookTitle = make("TextLabel", {
    Position = UDim2.fromOffset(16, 324),
    Size = UDim2.fromOffset(308, 17),
    BackgroundTransparency = 1,
    Text = "DISCORD WEBHOOK",
    TextColor3 = COLORS.Gray,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Visible = false,
}, root)

local webhookBox = make("TextBox", {
    Position = UDim2.fromOffset(14, 344),
    Size = UDim2.fromOffset(314, 34),
    BackgroundColor3 = Color3.fromRGB(17, 19, 28),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "https://discord.com/api/webhooks/...",
    PlaceholderColor3 = Color3.fromRGB(92, 97, 113),
    Text = tostring(settings.Webhook or ""),
    TextColor3 = COLORS.White,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Visible = false,
}, root)
corner(webhookBox, 9)
stroke(webhookBox, Color3.fromRGB(58, 61, 76), 0.35, 1)

local boxPadding = Instance.new("UIPadding")
boxPadding.PaddingLeft = UDim.new(0, 10)
boxPadding.PaddingRight = UDim.new(0, 10)
boxPadding.Parent = webhookBox

make("TextLabel", {
    Position = UDim2.fromOffset(14, 314),
    Size = UDim2.fromOffset(308, 17),
    BackgroundTransparency = 1,
    Text = "AUTO FILTER  •  MINIMUM PRICE",
    TextColor3 = COLORS.Gray,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, root)

local amountBox = make("TextBox", {
    Position = UDim2.fromOffset(12, 334),
    Size = UDim2.fromOffset(194, 32),
    BackgroundColor3 = Color3.fromRGB(17, 19, 28),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "Example: 5",
    PlaceholderColor3 = Color3.fromRGB(92, 97, 113),
    Text = tostring(settings.AutoAmount or ""),
    TextColor3 = COLORS.White,
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, root)
corner(amountBox, 9)
stroke(amountBox, Color3.fromRGB(58, 61, 76), 0.35, 1)
local amountPadding = Instance.new("UIPadding")
amountPadding.PaddingLeft = UDim.new(0, 10)
amountPadding.PaddingRight = UDim.new(0, 10)
amountPadding.Parent = amountBox

local validUnits = {K = true, M = true, B = true}
local currentUnit = string.upper(tostring(settings.AutoUnit or "M"))
if not validUnits[currentUnit] then
    currentUnit = "M"
end
settings.AutoUnit = currentUnit

local unitButton = make("TextButton", {
    Position = UDim2.fromOffset(212, 334),
    Size = UDim2.fromOffset(76, 32),
    BackgroundColor3 = Color3.fromRGB(29, 24, 48),
    BorderSizePixel = 0,
    Text = currentUnit,
    TextColor3 = COLORS.White,
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
}, root)
corner(unitButton, 9)
stroke(unitButton, COLORS.Purple, 0.25, 1)

local currentInstanceSlot = 0
settings.InstanceSlot = 0

make("TextLabel", {
    Position = UDim2.fromOffset(14, 373),
    Size = UDim2.fromOffset(164, 26),
    BackgroundTransparency = 1,
    Text = "AUTO SLOT • " .. tostring(player.Name),
    TextColor3 = COLORS.Gray,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, root)

local slotBox = make("TextLabel", {
    Position = UDim2.fromOffset(210, 373),
    Size = UDim2.fromOffset(78, 26),
    BackgroundColor3 = Color3.fromRGB(24, 26, 37),
    BorderSizePixel = 0,
    Text = "SYNC...",
    TextColor3 = COLORS.White,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    ZIndex = 20,
}, root)
corner(slotBox, 8)
stroke(slotBox, COLORS.Purple, 0.28, 1)

local filterStatus = make("TextLabel", {
    Position = UDim2.fromOffset(14, 404),
    Size = UDim2.fromOffset(274, 16),
    BackgroundTransparency = 1,
    Text = "Firebase filter off • enter an amount",
    TextColor3 = COLORS.Gray,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
}, root)

-- Persistent timer visible throughout a hop, even when the filter status is refreshed.
local hopTimingLabel = make("TextLabel", {
    Position = UDim2.fromOffset(14, 424),
    Size = UDim2.fromOffset(275, 17),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = Color3.fromRGB(146, 193, 245),
    TextSize = 10,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    Visible = false,
}, root)

local sendStatus = make("TextLabel", {
    Position = UDim2.fromOffset(14, 422),
    Size = UDim2.fromOffset(308, 17),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = COLORS.Gray,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    Visible = false,
}, root)

local startButton = make("TextButton", {
    Position = UDim2.fromOffset(14, 422),
    Size = UDim2.fromOffset(314, 42),
    BackgroundColor3 = COLORS.Purple,
    BorderSizePixel = 0,
    Text = "START",
    Visible = false,
    TextColor3 = COLORS.White,
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
}, root)
corner(startButton, 11)
stroke(startButton, Color3.fromRGB(192, 160, 255), 0.22, 1.2)

local function sanitizeAmountText(text)
    text = tostring(text or ""):gsub(",", ".")
    local cleaned = text:gsub("[^%d%.]", "")
    local firstDot = cleaned:find("%.")
    if firstDot then
        cleaned = cleaned:sub(1, firstDot) .. cleaned:sub(firstDot + 1):gsub("%.", "")
    end
    return cleaned
end

local function getAutoThreshold()
    local amount = tonumber(sanitizeAmountText(settings.AutoAmount or ""))
    if not amount or amount <= 0 then
        return nil
    end
    local multipliers = {K = 1e3, M = 1e6, B = 1e9}
    return amount * (multipliers[currentUnit] or 1e6)
end

local autoQueue = {}
local autoQueueBusy = false

-- Shared across re-executions in the SAME server.
local autoNotifiedUids = runtimeState.AutoNotifiedUids
local apiPublishedUids = runtimeState.ApiPublishedUids
runtimeState.ReportRetryAt = runtimeState.ReportRetryAt or {}
local reportRetryAt = runtimeState.ReportRetryAt
local serverHopBusy = false
local serverHopQueuedAfterSend = false
local lastServerHopAttempt = 0
local serverHopRetryQueued = false
local serverHopCurrentTarget = nil
local serverHopCurrentClaimId = nil
local serverHopTeleportAttempts = 0
local serverHopTeleportStarted = false
local serverHopAttemptHandled = 0

local hopClock = {
    id = 0,
    started = 0,
    stageStarted = 0,
    stage = "",
    checkpoints = {},
}

local function hopMeasureStart(reason)
    hopClock.id += 1
    hopClock.started = os.clock()
    hopClock.stageStarted = hopClock.started
    hopClock.stage = "checking eggs"
    hopClock.checkpoints = {}
    hopTimingLabel.Visible = true
    warn("[VORYKEN HOP] START " .. tostring(reason or "UNKNOWN"))
    local thisId = hopClock.id
    task.spawn(function()
        while screen.Parent and serverHopBusy and hopClock.id == thisId do
            hopTimingLabel.Text = string.format(
                "HOP %.1fs | %s %.1fs",
                os.clock() - hopClock.started,
                hopClock.stage,
                os.clock() - hopClock.stageStarted
            )
            task.wait(0.2)
        end
    end)
end

local function hopMeasureStage(stage)
    local now = os.clock()
    local elapsed = now - (hopClock.stageStarted or now)
    if hopClock.stage ~= "" then
        hopClock.checkpoints[hopClock.stage] =
            (hopClock.checkpoints[hopClock.stage] or 0) + elapsed
    end
    hopClock.stage = tostring(stage)
    hopClock.stageStarted = now
    warn(string.format(
        "[VORYKEN HOP] %s | phase %.2fs | total %.2fs",
        hopClock.stage, elapsed, now - hopClock.started
    ))
end

local function hopMeasureStop(label)
    hopMeasureStage(label)
    local total = os.clock() - hopClock.started
    local message = string.format("HOP %.2fs | %s", total, tostring(label))
    hopTimingLabel.Text = message
    warn("[VORYKEN HOP] " .. message)
end

local function refreshFilterStatus()
    local threshold = getAutoThreshold()
    if not threshold then
        filterStatus.Text = "Firebase filter off • enter an amount"
        filterStatus.TextColor3 = COLORS.Gray
        return
    end
    filterStatus.Text = "Firebase ON • " .. formatNumber(threshold) .. "+"
    if serverHopEnabled then
        filterStatus.Text = filterStatus.Text .. " • HOP ON"
    end
    filterStatus.TextColor3 = COLORS.Green
end
-- Discord webhook UI disabled: Voryken API-only finder.

amountBox.FocusLost:Connect(function()
    local cleaned = sanitizeAmountText(amountBox.Text)
    amountBox.Text = cleaned
    settings.AutoAmount = cleaned
    saveSettings()
    refreshFilterStatus()
end)

unitButton.Activated:Connect(function()
    local order = {"K", "M", "B"}
    local nextIndex = 1
    for i, unit in ipairs(order) do
        if unit == currentUnit then
            nextIndex = (i % #order) + 1
            break
        end
    end
    currentUnit = order[nextIndex]
    settings.AutoUnit = currentUnit
    unitButton.Text = currentUnit
    saveSettings()
    refreshFilterStatus()
end)

serverHopButton.Activated:Connect(function()
    serverHopEnabled = not serverHopEnabled
    settings.ServerHopEnabled = serverHopEnabled
    saveSettings()
    refreshServerHopButton()

    if serverHopEnabled then
        -- Re-evaluate current server without clearing Discord dedupe.
        sendStatus.Text = "Server Hop ON • checking current server"
        sendStatus.TextColor3 = COLORS.Green
    else
        sendStatus.Text = "Server Hop OFF"
        sendStatus.TextColor3 = COLORS.Gray
    end

    refreshFilterStatus()
    refreshRequested = true
end)

refreshFilterStatus()

local sending = false

--==============================================================
-- API DYNAMIC USER SLOT + SERVER CLAIM
-- Every Roblox account registers itself in /finder/users/<UserId>.
-- Python assigns slots 1..N based on the registered users and publishes one
-- server at /finder/servers/<slot>. Lua sends a pending intent; Python marks USED only after destination JobId heartbeat.
--==============================================================
runtimeState.ApiQueue = runtimeState.ApiQueue or {}
runtimeState.ApiQueue.userKey = nil
runtimeState.ApiQueue.userUrl = nil
runtimeState.ApiQueue.lastHeartbeat = 0
runtimeState.ApiQueue.sessionStartedAt = CycleRuntime.localUnixMs()
runtimeState.ApiQueue.registeredOnce = false
runtimeState.ApiQueue.expired = false
local failedHopTargetsThisServer = {}

function runtimeState.ApiQueue.rawRequest(method, url, body, extraHeaders)
    local ok, data, status, reason, headers = VorykenStore.request(method, url, body, extraHeaders)
    if not ok then
        runtimeState.ApiQueue.lastError = tostring(reason or "NETWORK_ERROR")
    else
        runtimeState.ApiQueue.lastError = nil
    end
    return ok, data, status, reason, headers
end

function runtimeState.ApiQueue.headerValue(headers, wanted)
    if type(headers) ~= "table" then
        return nil
    end
    wanted = string.lower(tostring(wanted or ""))
    for key, value in pairs(headers) do
        if string.lower(tostring(key)) == wanted then
            return tostring(value)
        end
    end
    return nil
end

function runtimeState.ApiQueue.applySlot(slot)
    slot = math.max(0, math.floor(tonumber(slot) or 0))
    currentInstanceSlot = slot
    settings.InstanceSlot = slot
    if slot > 0 then
        slotBox.Text = "#" .. tostring(slot)
        slotBox.TextColor3 = COLORS.Green
    else
        slotBox.Text = "SYNC..."
        slotBox.TextColor3 = COLORS.White
    end
    return slot
end

-- Registering and polling a new account may happen at the same time.
-- Keep exactly ONE writer per Roblox client to prevent its own requests from
-- racing, and retry registration if the first attempt fails.
runtimeState.ApiQueue.registerBusy = false

local function showPendingSlot(label, color)
    if currentInstanceSlot <= 0 and slotBox.Parent then
        slotBox.Text = label
        slotBox.TextColor3 = color or COLORS.White
    end
end

function runtimeState.ApiQueue.registerOrHeartbeat(force)
    local queue = runtimeState.ApiQueue
    if not FirebaseQueue.ensureAuth() then
        queue.lastError = FirebaseQueue.lastError or "FIREBASE_AUTH"
        showPendingSlot("AUTH ERR", Color3.fromRGB(255, 181, 82))
        return false, nil
    end
    queue.userKey = FirebaseQueue.uid
    queue.userUrl = VORYKEN_API_ROOT .. "/finder/users/" .. queue.userKey .. ".json"
    if queue.expired then
        queue.lastError = "STOCK_EXPIRED_RESTART_SCANNER"
        showPendingSlot("EXPIRED", Color3.fromRGB(255, 181, 82))
        return false, nil
    end
    if not isCurrentVorykenRun() or not screen.Parent then
        return false, nil
    end
    if queue.registerBusy then
        return currentInstanceSlot > 0, currentInstanceSlot
    end

    local nowClock = os.clock()
    local interval = queue.registeredOnce and 8 or 1.5
    if (not force or not queue.registeredOnce)
        and nowClock - (queue.lastHeartbeat or -math.huge) < interval then
        return currentInstanceSlot > 0, currentInstanceSlot
    end
    queue.lastHeartbeat = nowClock
    queue.registerBusy = true
    local createdThisCall = false

    local completed, resultOk, resultSlot = pcall(function()
        -- Read the current user before writing: an existing record has a Python
        -- assigned slot which must NOT be overwritten by a new stock payload.
        local freshHeader = { ["X-Force-Read"] = "true" }
        local okGet, existing = queue.rawRequest("GET", queue.userUrl, nil,
            queue.registeredOnce and nil or freshHeader)
        if not okGet then
            showPendingSlot("API ERR", Color3.fromRGB(255, 181, 82))
            return false, nil
        end

        if type(existing) ~= "table" then
            if queue.registeredOnce then
                -- Do not silently recreate an intentionally removed stock.
                -- Confirm with an uncached read before treating it as expired.
                local okConfirm, confirmed = queue.rawRequest(
                    "GET", queue.userUrl, nil, freshHeader)
                if not okConfirm then
                    showPendingSlot("API ERR", Color3.fromRGB(255, 181, 82))
                    return false, nil
                end
                if type(confirmed) ~= "table" then
                    queue.registeredOnce = false
                    queue.applySlot(0)
                    showPendingSlot("RE-REG", Color3.fromRGB(255, 181, 82))
                    return false, nil
                end
                existing = confirmed
            else
                -- This is a genuinely new account: create it immediately.
                showPendingSlot("REG...", COLORS.White)
                local timestamp = CycleRuntime.localUnixMs()
                local payload = {
                    userId = tostring(player.UserId or 0),
                    username = tostring(player.Name or ""),
                    displayName = tostring(player.DisplayName or player.Name or ""),
                    placeId = tonumber(game.PlaceId) or 0,
                    currentJobId = tostring(game.JobId or ""),
                    registeredAt = timestamp,
                    sessionStartedAt = queue.sessionStartedAt,
                    lastSeen = timestamp,
                    source = "Voryken Finder",
                }
                local wrote = queue.rawRequest("PUT", queue.userUrl, payload)
                if not wrote then
                    showPendingSlot("REG ERR", Color3.fromRGB(255, 181, 82))
                    return false, nil
                end

                -- Only mark registration as successful after the user is
                -- actually visible in the API. Otherwise retry on next tick.
                local checked, confirmed = queue.rawRequest(
                    "GET", queue.userUrl, nil, freshHeader)
                if not checked or type(confirmed) ~= "table" then
                    showPendingSlot("CHECK...", Color3.fromRGB(255, 181, 82))
                    return false, nil
                end
                existing = confirmed
                createdThisCall = true
            end
        end

        queue.registeredOnce = true
        local slot = queue.applySlot(existing.slot)
        if slot <= 0 then
            -- The user IS registered. The remaining step belongs to Python.
            showPendingSlot("WAIT PY", Color3.fromRGB(255, 181, 82))
        end

        -- A newly created stock already includes its initial heartbeat.
        if not createdThisCall then
            local updated = {
                sessionStartedAt = math.max(
                    tonumber(existing.sessionStartedAt) or 0,
                    tonumber(queue.sessionStartedAt) or 0
                ),
                username = tostring(player.Name or ""),
                displayName = tostring(player.DisplayName or player.Name or ""),
                placeId = tonumber(game.PlaceId) or 0,
                currentJobId = tostring(game.JobId or ""),
                lastSeen = CycleRuntime.localUnixMs(),
            }
            -- A failed heartbeat does not erase a valid assigned slot.
            queue.rawRequest("PATCH", queue.userUrl, updated)
        end
        return slot > 0, slot
    end)

    queue.registerBusy = false
    if not completed then
        queue.lastError = "REGISTRATION_EXCEPTION: " .. tostring(resultOk):sub(1, 115)
        showPendingSlot("REG ERR", Color3.fromRGB(255, 181, 82))
        warn("[Voryken] Registration error: " .. tostring(resultOk))
        return false, nil
    end
    return resultOk, resultSlot
end

function runtimeState.ApiQueue.waitForSlot()
    local queue = runtimeState.ApiQueue
    if currentInstanceSlot > 0 and queue.registeredOnce then
        return currentInstanceSlot, nil
    end

    local lastPoll = -math.huge
    local lastRegistrationTry = -math.huge
    while serverHopEnabled and screen.Parent and isCurrentVorykenRun() do
        if currentInstanceSlot > 0 and queue.registeredOnce then
            return currentInstanceSlot, nil
        end
        if queue.expired then
            return nil, "STOCK_EXPIRED_RESTART_SCANNER"
        end

        if not queue.registeredOnce then
            -- Essential regression fix: while waiting for a new slot, retry
            -- REGISTERING, not just reading a user that has never been created.
            if os.clock() - lastRegistrationTry >= 1.5 then
                lastRegistrationTry = os.clock()
                local ok, slot = queue.registerOrHeartbeat(true)
                if ok and tonumber(slot) and slot > 0 then
                    return slot, nil
                end
            end
        elseif os.clock() - lastPoll >= 0.75 then
            lastPoll = os.clock()
            -- A registered user without a slot only needs one cached GET.
            -- Python is responsible for filling that user record with its slot.
            local ok, existing = queue.rawRequest("GET", queue.userUrl)
            if ok and type(existing) == "table" then
                local slot = queue.applySlot(existing.slot)
                if slot > 0 then return slot, nil end
                showPendingSlot("WAIT PY", Color3.fromRGB(255, 181, 82))
            elseif ok then
                -- An old stock can be deliberately removed by the server.
                -- Let the normal heartbeat confirm it before expiring it.
                queue.registerOrHeartbeat(true)
            end
        end

        if queue.lastError then
            filterStatus.Text = "Voryken registration • " .. tostring(queue.lastError):sub(1, 92)
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        elseif not queue.registeredOnce then
            filterStatus.Text = "Registering new Voryken user..."
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        else
            filterStatus.Text = "User registered • waiting for Python slot"
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        end
        task.wait(0.15)
    end
    return nil, "SERVER_HOP_DISABLED"
end

function runtimeState._readMyPublishedServerSlot()
    local slot, slotError = runtimeState.ApiQueue.waitForSlot()
    if not slot then
        return nil, slotError or "NO_USER_SLOT"
    end

    local ok, server = runtimeState.ApiQueue.rawRequest(
        "GET",
        VORYKEN_API_ROOT .. "/finder/assignments/" .. tostring(FirebaseQueue.uid) .. ".json"
    )
    if not ok or type(server) ~= "table" then
        return nil, "SLOT_WAITING"
    end

    local id = tostring(server.jobId or server.id or "")
    if id == "" then
        return nil, "SLOT_WAITING"
    end

    local assignedUserId = tostring(server.assignedUserId or "")
    if assignedUserId ~= "" and assignedUserId ~= tostring(player.UserId or 0) then
        return nil, "SLOT_REASSIGNED"
    end

    return {
        id = id,
        slot = slot,
        playing = tonumber(server.playing) or 0,
        maxPlayers = tonumber(server.maxPlayers) or 0,
        ping = tonumber(server.ping),
        fps = tonumber(server.fps),
        publishedAt = tonumber(server.publishedAt),
    }, nil
end

function runtimeState._waitForMyPublishedServerSlot()
    local lastStatusUpdate = 0
    local waitStarted = os.clock()
    while serverHopEnabled and screen.Parent and isCurrentVorykenRun() do
        local server, slotError = runtimeState._readMyPublishedServerSlot()
        if server then
            return server, nil
        end

        if os.clock() - lastStatusUpdate >= 0.75 then
            lastStatusUpdate = os.clock()
            local elapsed = tostring(math.floor(os.clock() - waitStarted)) .. "s"
            if runtimeState.ApiQueue.lastError then
                filterStatus.Text = "Voryken API error • "
                    .. tostring(runtimeState.ApiQueue.lastError):sub(1, 90)
            elseif not runtimeState.ApiQueue.registeredOnce then
                filterStatus.Text = "Registering new user • " .. elapsed
            elseif currentInstanceSlot <= 0 then
                filterStatus.Text = "Registered • waiting Python slot • " .. elapsed
            else
                filterStatus.Text = "Slot #" .. tostring(currentInstanceSlot)
                    .. " • waiting server • " .. elapsed
            end
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        end

        if slotError == "SCREEN_CLOSED"
            or slotError == "SERVER_HOP_DISABLED"
            or slotError == "STOCK_EXPIRED_RESTART_SCANNER" then
            return nil, slotError
        end
        task.wait(0.35)
    end
    return nil, "SERVER_HOP_DISABLED"
end

function runtimeState._requestServerClaimFromPython()
    local target, targetError = runtimeState._waitForMyPublishedServerSlot()
    if not target then return nil, targetError or "SLOT_WAITING" end
    local id = tostring(target.id or "")
    if id == "" or id == tostring(game.JobId or "") then return nil, "INVALID_TARGET" end
    if failedHopTargetsThisServer[id] then
        return nil, "FAILED_TARGET_WAIT_REFILL"
    end
    hopMeasureStage("firebase intent")
    -- One private write. Python keeps the reservation until the destination scanner confirms arrival.
    -- A failed teleport is NOT a consumed server.
    local claim = {
        jobId = id,
        slot = tonumber(target.slot) or 0,
        claimedAt = CycleRuntime.localUnixMs(),
        claimId = HttpService:GenerateGUID(false),
        userId = tostring(player.UserId or 0),
        originJobId = tostring(game.JobId or ""),
        state = "pending",
    }
    local ok, _response, _status, reason = runtimeState.ApiQueue.rawRequest(
        "PUT", VORYKEN_API_ROOT .. "/finder/claims/" .. tostring(FirebaseQueue.uid) .. ".json", claim)
    if not ok then return nil, reason or "CLAIM_WRITE_FAILED" end
    serverHopCurrentClaimId = claim.claimId
    return target, nil
end

-- One bounded stale-stock cleanup when ANY client starts. Heartbeats do not
-- count as claims. Python performs the same cleanup centrally every 30s.
-- Only queue records are touched, NEVER eggs_servers.json.
function runtimeState.ApiQueue.cleanupStaleUserStocks()
    -- Clients cannot list other users; only Python Admin SDK prunes old accounts.
    return 0
end

-- Python already performs this cleanup centrally every 30 seconds.
-- Do not make every Roblox client scan/download the full server queue on load.
-- Register immediately, then keep a lightweight heartbeat so Python always
-- knows this account still exists and which Roblox server it is currently in.
task.spawn(function()
    -- Keep trying if initial registration fails, even when the hop worker
    -- never runs (e.g. the current server still has qualifying eggs).
    task.wait(0.2)
    while screen.Parent and isCurrentVorykenRun() do
        local ok, err = pcall(runtimeState.ApiQueue.registerOrHeartbeat, true)
        if not ok then
            runtimeState.ApiQueue.lastError = "REGISTER_WORKER: " .. tostring(err):sub(1, 100)
            warn("[Voryken] Registration worker: " .. tostring(err))
        end
        task.wait(runtimeState.ApiQueue.registeredOnce and 10 or 2)
    end
end)


function runtimeState._queueServerHopRetry(reason, delaySeconds)
    if not serverHopEnabled or not screen.Parent then
        serverHopBusy = false
        serverHopCurrentTarget = nil
        return
    end

    local failedJob = serverHopCurrentTarget and tostring(serverHopCurrentTarget) or nil
    local failedClaim = serverHopCurrentClaimId
    if failedJob then
        failedHopTargetsThisServer[failedJob] = true
    end
    serverHopBusy = false
    serverHopCurrentTarget = nil
    serverHopCurrentClaimId = nil
    serverHopTeleportAttempts = 0
    serverHopTeleportStarted = false
    hopMeasureStop("failed / retrying")

    local reasonText = tostring(reason or "ERROR")
    filterStatus.Text = "Teleport failed • " .. reasonText .. " • requesting new JobId"
    -- Do not mark USED on failure. Notify Python, which releases the slot and
    -- picks another server. The local rejection map avoids retrying the old id.
    if failedJob and failedClaim then
        task.spawn(function()
            local claimUrl = VORYKEN_API_ROOT .. "/finder/claims/" .. tostring(FirebaseQueue.uid) .. ".json"
            for attempt = 1, 3 do
                if tostring(game.JobId or "") == failedJob then return end
                local ok, fresh = runtimeState.ApiQueue.rawRequest("GET", claimUrl)
                if ok and type(fresh) == "table" and tostring(fresh.claimId or "") == failedClaim then
                    local wrote = runtimeState.ApiQueue.rawRequest("PATCH", claimUrl, {
                        state = "failed",
                        failureReason = reasonText,
                        failedAt = CycleRuntime.localUnixMs(),
                    })
                    if wrote then return end
                elseif ok then
                    return -- Already consumed/replaced by Python; never overwrite it.
                end
                task.wait(0.6)
            end
        end)
    end
    filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)

    if serverHopRetryQueued then
        return
    end

    serverHopRetryQueued = true
    task.delay(tonumber(delaySeconds) or 1.0, function()
        serverHopRetryQueued = false
        if serverHopEnabled and screen.Parent then
            runtimeState._performServerHop("RETRY_" .. reasonText)
        end
    end)
end

function runtimeState._waitForAllCurrentServerEggs(originJobId)
    local startedAt = os.clock()

    -- No artificial 2-second settling time. As soon as the current normal
    -- egg UIDs have corresponding EggState records and Halloween is scanned,
    -- the server is ready to hop. Unmapped UIDs still wait (up to MAX_WAIT).
    local MAX_WAIT = 9.0

    while serverHopEnabled
        and screen.Parent
        and tostring(game.JobId) == tostring(originJobId) do

        requestSync(true)

        local liveFolder = Workspace:FindFirstChild("AreaEggSlotsClient")
        eggFolder = liveFolder or eggFolder

        local recordsByUid = readSnapshotRecords() or {}
        local names = {}
        local normalCount = 0
        local normalReady = 0

        if liveFolder then
            for _, slot in ipairs(liveFolder:GetChildren()) do
                local uid = tostring(slot.Name or "")
                if uid ~= "" then
                    normalCount += 1
                    names[#names + 1] = "N:" .. uid
                    if recordsByUid[uid] ~= nil then
                        normalReady += 1
                    end
                end
            end
        end

        local halloweenEntries = getHalloweenEggEntries(true)
        local halloweenCount = #halloweenEntries
        for _, entry in ipairs(halloweenEntries) do
            names[#names + 1] = "H:" .. tostring(entry.uid or "")
        end

        local totalCount = normalCount + halloweenCount
        table.sort(names)

        if totalCount == 0 then
            -- A missing folder or an unreadable EggState snapshot does NOT
            -- mean an empty server. Never hop on missing/unloaded egg data.
            local env = (type(getgenv) == "function" and getgenv()) or _G
            local readyJob = type(env) == "table" and tostring(env.__VorykenScannerWorldReadyJob or "") or ""
            if not liveFolder or type(readSnapshotRecords()) ~= "table"
                or readyJob ~= tostring(originJobId) then
                filterStatus.Text = "Waiting for real server eggs / EggState"
                filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
            else
                -- The server WAS confirmed ready before startup. A genuinely
                -- empty later snapshot (after eggs disappear) may now be hopped.
                filterStatus.Text = "Egg scan complete • no eggs remaining"
                filterStatus.TextColor3 = COLORS.Gray
                return true, 0
            end
        end

        if totalCount > 0 and (normalCount == 0 or normalReady == normalCount) then
            filterStatus.Text = "Egg scan complete • " .. tostring(totalCount)
            filterStatus.TextColor3 = COLORS.Green
            return true, totalCount
        end

        filterStatus.Text = "Loading eggs • "
            .. tostring(normalReady + halloweenCount)
            .. "/"
            .. tostring(totalCount)
        filterStatus.TextColor3 = COLORS.Gray

        if os.clock() - startedAt >= MAX_WAIT then
            return false, "EGGS_NOT_READY"
        end

        task.wait(0.20)
    end

    return false, "SERVER_CHANGED"
end


-- Keep a pending claim reserved through transient Roblox failures. A second
-- attempt uses the SAME destination; only the final failure releases the slot.
local attemptTeleportCurrent
local handleTeleportFailure
handleTeleportFailure = function(reason, fatal, delaySeconds)
    if not serverHopBusy or not serverHopCurrentTarget then return end
    local attempt = serverHopTeleportAttempts
    if serverHopAttemptHandled == attempt then return end
    serverHopAttemptHandled = attempt
    local originJob = tostring(game.JobId or "")
    local target = tostring(serverHopCurrentTarget)
    if not fatal and attempt < 2 then
        local retryDelay = tonumber(delaySeconds) or 1.0
        filterStatus.Text = "Roblox teleport retry " .. tostring(attempt + 1)
            .. "/2 • " .. tostring(reason or "NO_TRANSITION")
        warn("[VORYKEN HOP] Retrying same target " .. target .. " after " .. tostring(reason))
        task.delay(retryDelay, function()
            if serverHopBusy and serverHopCurrentTarget == target
                and tostring(game.JobId or "") == originJob then
                attemptTeleportCurrent(originJob)
            end
        end)
    else
        runtimeState._queueServerHopRetry(reason or "TELEPORT_FAILED", 1.25)
    end
end

attemptTeleportCurrent = function(originJob)
    if not serverHopBusy or not serverHopCurrentTarget then return end
    if tostring(game.JobId or "") ~= tostring(originJob) then return end
    local target = tostring(serverHopCurrentTarget)
    serverHopTeleportAttempts += 1
    serverHopTeleportStarted = false
    local attempt = serverHopTeleportAttempts
    filterStatus.Text = "Teleport " .. tostring(attempt) .. "/2 • " .. target:sub(1, 11)
    hopMeasureStage("Roblox teleport attempt " .. tostring(attempt))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, target, player)
    end)
    if not ok then
        warn("[VORYKEN HOP] Roblox rejected teleport: " .. tostring(err))
        handleTeleportFailure("CALL_ERROR " .. tostring(err):sub(1, 65), false, 1.0)
        return
    end

    -- pcall success means the request was STARTED, not that Roblox joined.
    -- The destination scanner heartbeat is what confirms the join in Python.
    hopMeasureStage("waiting for Roblox transfer")
    task.delay(9, function()
        if not serverHopBusy or serverHopCurrentTarget ~= target
            or serverHopTeleportAttempts ~= attempt
            or tostring(game.JobId or "") ~= tostring(originJob) then return end
        if serverHopTeleportStarted then
            -- The engine reported a loading/teleport state; allow extra time.
            task.delay(13, function()
                if serverHopBusy and serverHopCurrentTarget == target
                    and serverHopTeleportAttempts == attempt
                    and tostring(game.JobId or "") == tostring(originJob) then
                    handleTeleportFailure("ROBX_TRANSFER_STUCK", false, 1.0)
                end
            end)
        else
            handleTeleportFailure("NO_TRANSFER_9S", false, 1.0)
        end
    end)
end

pcall(function()
    player.OnTeleport:Connect(function(state)
        if not serverHopBusy or not serverHopCurrentTarget then return end
        if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.WaitingForServer
            or state == Enum.TeleportState.InProgress then
            serverHopTeleportStarted = true
            hopMeasureStage("Roblox transfer started")
        elseif state == Enum.TeleportState.Failed then
            handleTeleportFailure("ROBLOX_TRANSFER_FAILED", false, 1.0)
        end
    end)
end)

runtimeState._performServerHop = function(reason)
    if not serverHopEnabled or serverHopBusy then
        return false
    end

    if CycleRuntime.hopBlocked() then
        filterStatus.Text = "Cycle reset • waiting for new eggs"
        filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        return false
    end

    local now = os.clock()
    if now - lastServerHopAttempt < 0.75 then
        if not serverHopRetryQueued then
            serverHopRetryQueued = true
            task.delay(0.80, function()
                serverHopRetryQueued = false
                if serverHopEnabled and screen.Parent then
                    runtimeState._performServerHop(reason or "THROTTLED_RETRY")
                end
            end)
        end
        return false
    end

    lastServerHopAttempt = now
    serverHopBusy = true
    serverHopCurrentClaimId = nil
    serverHopTeleportAttempts = 0
    serverHopAttemptHandled = 0
    serverHopTeleportStarted = false
    hopMeasureStart(reason)

    filterStatus.Text = "Server Hop • reading current eggs"
    filterStatus.TextColor3 = COLORS.Gray

    task.spawn(function()
        local originJobId = tostring(game.JobId)

        -- Hop as soon as the visible normal UID set is mapped in EggState and
        -- Halloween has been scanned. No 2-second stability pause.
        local eggsReady, eggInfo
        -- When we just published a real egg, the live scan already verified
        -- it. Don't wait a second time for unrelated late EggState UIDs.
        local env = (type(getgenv) == "function" and getgenv()) or _G
        local verifiedStartup = type(env) == "table"
            and tostring(env.__VorykenScannerWorldReadyJob or "") == originJobId
        if verifiedStartup then
            eggsReady = true
            eggInfo = runtimeState._lastScannerEggCount
            hopMeasureStage("eggs previously verified")
        else
            eggsReady, eggInfo = runtimeState._waitForAllCurrentServerEggs(originJobId)
            hopMeasureStage("eggs verified")
        end

        if CycleRuntime.hopBlocked() then
            serverHopBusy = false
            serverHopCurrentTarget = nil
            refreshRequested = true
            filterStatus.Text = "Cycle reset • waiting for new eggs"
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
            return
        end

        if not eggsReady then
            hopMeasureStop("egg data not ready")
            serverHopBusy = false
            serverHopCurrentTarget = nil
            refreshRequested = true

            if tostring(eggInfo) == "EGGS_NOT_READY" then
                filterStatus.Text = "Eggs still loading • hop canceled"
                filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
            end

            return
        end

        -- Re-evaluate the filter after the available egg snapshot was read.
        -- If a qualifying egg appears during this check, refresh and publish it.
        if tostring(reason or "") == "NO_MATCH"
            or tostring(reason or "") == "NO_MATCH_AFTER_RESET" then
            local threshold = getAutoThreshold()

            if threshold then
                local refreshedTop = select(1, getTopEggs())
                local matchingNow = 0

                -- Only the three actual global winners can cancel the hop /
                -- qualify for automatic Discord. Egg #4 or lower is ignored.
                for _, entry in ipairs(refreshedTop or {}) do
                    if (tonumber(entry.value) or 0) >= threshold then
                        matchingNow += 1
                    end
                end

                if matchingNow > 0 then
                    serverHopBusy = false
                    serverHopCurrentTarget = nil
                    refreshRequested = true

                    filterStatus.Text = "Matching egg found • checking Voryken API"
                    filterStatus.TextColor3 = COLORS.Green
                    return
                end
            end
        end

        if tonumber(eggInfo) == 0 then
            filterStatus.Text = "Server Hop • no eggs/folder • using slot "
                .. tostring(currentInstanceSlot)
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        else
            filterStatus.Text = "Server Hop • eggs ready (" .. tostring(eggInfo or "?") .. ")"
            filterStatus.TextColor3 = COLORS.Green
        end

        -- No fixed wait between finishing the scan and claiming the next slot.
        if CycleRuntime.hopBlocked() then
            serverHopBusy = false
            serverHopCurrentTarget = nil
            refreshRequested = true
            filterStatus.Text = "Cycle reset • waiting for new eggs"
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
            return
        end

        filterStatus.Text = "Server Hop • claiming slot " .. tostring(currentInstanceSlot)
        filterStatus.TextColor3 = COLORS.Gray
        hopMeasureStage("waiting on Python/API")

        local target, claimError = runtimeState._requestServerClaimFromPython()

        if not target then
            serverHopBusy = false
            serverHopCurrentTarget = nil
            hopMeasureStop("claim failed")

            local reasonText = tostring(claimError or "NO_SERVER")

            if reasonText == "SLOT_WAITING"
                or reasonText == "SLOT_CHANGED"
                or reasonText == "SLOT_REASSIGNED"
                or reasonText == "NO_USER_SLOT"
                or reasonText == "FAILED_TARGET_WAIT_REFILL" then
                filterStatus.Text = currentInstanceSlot > 0
                    and ("Slot #" .. tostring(currentInstanceSlot) .. " • waiting Voryken API refill")
                    or "Registering user • waiting automatic slot"
            else
                filterStatus.Text = "Voryken API queue • " .. reasonText
            end

            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)

            if serverHopEnabled
                and not serverHopRetryQueued then
                serverHopRetryQueued = true
                task.delay(
                    (reasonText == "SLOT_CHANGED" or reasonText == "SLOT_WAITING") and 0.35 or 2.0,
                    function()
                    serverHopRetryQueued = false
                    if serverHopEnabled and screen.Parent then
                        runtimeState._performServerHop("WAIT_QUEUE_REFILL")
                    end
                end
                )
            end
            return
        end

        local serverId = tostring(target.id)
        hopMeasureStage("queueing teleport")

        if failedHopTargetsThisServer[serverId] then
            serverHopCurrentTarget = serverId
            runtimeState._queueServerHopRetry("LOCAL_DUPLICATE", 1.0)
            return
        end

        serverHopCurrentTarget = serverId

        filterStatus.Text = "Slot "
            .. tostring(currentInstanceSlot)
            .. " • claimed "
            .. tostring(target.playing or "?")
            .. "/"
            .. tostring(target.maxPlayers or "?")
        filterStatus.TextColor3 = COLORS.Green

        if CycleRuntime.hopBlocked() then
            runtimeState._queueServerHopRetry("CYCLE_GUARD_AFTER_CLAIM", 2.0)
            refreshRequested = true
            return
        end

        local queued = queueFinderForNextServer()
        if not queued then
            filterStatus.Text = "HOP WARNING • autoexecute unavailable; configure executor Auto Execute"
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
            warn("[VORYKEN HOP] queue_on_teleport unavailable. Destination scanner will need executor Auto Execute.")
        end

        -- Do not consume Firebase assignment before the destination server
        -- is confirmed. Retry one transient Roblox failure before releasing.
        attemptTeleportCurrent(originJobId)
    end)

    return true
end

TeleportService.TeleportInitFailed:Connect(function(failedPlayer, teleportResult, errorMessage)
    if failedPlayer ~= player or not serverHopBusy then
        return
    end

    local reason = "TELEPORT_ERROR"

    pcall(function()
        if teleportResult then
            reason = tostring(teleportResult.Name or teleportResult)
        end
    end)

    if type(errorMessage) == "string" and errorMessage ~= "" then
        local lowerMessage = string.lower(errorMessage)
        if string.find(lowerMessage, "full", 1, true) then
            reason = "SERVER_FULL"
        end
    end

    local fatal = reason == "SERVER_FULL"
        or reason == "GameFull"
        or reason == "GameNotFound"
        or reason == "Unauthorized"
        or reason == "GameEnded"
    handleTeleportFailure(reason, fatal, reason == "Flooded" and 8.0 or 1.0)
end)

function runtimeState._cloneEntry(entry)
    local location = "Main World"
    if entry and type(entry.location) == "string" and entry.location ~= "" then
        location = tostring(entry.location)
    elseif entry and entry.halloweenDimension == true then
        location = "Halloween Dimension"
    end

    return {
        uid = tostring(entry and entry.uid or ""),
        category = tostring(entry and entry.category or ""),
        name = tostring(entry and entry.name or "Unknown"),
        rarity = tostring(entry and entry.rarity or "Unknown"),
        value = tonumber(entry and entry.value) or 0,
        scale = tonumber(entry and entry.scale) or 1,
        image = tostring(entry and entry.image or ""),
        halloweenDimension = entry and entry.halloweenDimension == true or false,
        location = location,
    }
end

function runtimeState._sendEntryToDiscord(entry, webhook, sourceLabel, fastAutomatic)
    local requester = getRequester()
    if type(requester) ~= "function" then
        return false, nil, false, "HTTP_REQUEST_UNAVAILABLE"
    end

    local entryToSend = runtimeState._cloneEntry(entry)
    local sizeText = string.format("%.2f", entryToSend.scale)

    -- Direct server join link using Multicrew's deeplink format.
    local joinUrl = "https://deeplink.multicrew.dev/?placeId="
        .. tostring(game.PlaceId)
        .. "&jobId="
        .. tostring(game.JobId)

    -- Discord uses a 24-bit integer for the colored stripe on the left.
    -- Keep it matched to the same rarity palette used by the in-game UI.
    local DISCORD_RARITY_COLORS = {
        common = 10660021,
        uncommon = 6151307,
        rare = 4956159,
        epic = 11427583,
        legendary = 16755270,
        mythic = 14441471,
        secret = 15462135,
        cosmic = 16732791,
        eternal = 10513663,
        divine = 16768341,
    }

    local rarityText = tostring(entryToSend.rarity or "Unknown")
    local rarityKey = string.lower(rarityText)
    local embedColor = DISCORD_RARITY_COLORS[rarityKey] or 9539985

    -- Custom Roblox emoji installed in the Discord server used by the webhook.
    local ROBLOX_EMOJI = "<:Roblox:1562058089346244640>"

    local embed = {
        -- Discord does not allow custom title font sizes. author.name is the
        -- closest built-in size: slightly emphasized without the oversized title.
        author = {
            name = rarityText .. " Egg Spawned!",
        },
        description = table.concat({
            "🥚 **Name:** " .. tostring(entryToSend.name),
            "📍 **Location:** " .. tostring(entryToSend.location or "Main World"),
            "💰 **Money:** $" .. formatNumber(entryToSend.value) .. "/s",
            "📏 **Size:** x" .. sizeText,
            ROBLOX_EMOJI .. " **Join Server:** [Click Here](" .. joinUrl .. ")",
        }, "\n"),
        color = embedColor,
        footer = {
            text = "Voryken • Steal An Egg Finder",
        },
    }

    -- Join link is shown inline in the embed description; no Discord button.
    local payload = {
        -- Do not override username: Discord keeps the webhook's normal name.
        embeds = {embed},
    }

    -- Automatic filter keeps the REAL animal photo like the original version.
    -- To reduce delay, automatic sends render only the animal PNG first and
    -- skip the extra egg PNG render; the egg icon falls back to its normal URL.
    local animalPng, animalImageReason = renderAnimalPng(entryToSend.category, false)
    local eggPng, eggImageReason = nil, "FAST_AUTO_EGG_URL"

    if fastAutomatic ~= true then
        eggPng, eggImageReason = renderAnimalPng(entryToSend.category, true)
    end

    local files = {}

    -- Real in-game egg picture remains attached to the heading area.
    if type(eggPng) == "string" and #eggPng >= 100 then
        embed.author.icon_url = "attachment://egg.png"
        files[#files + 1] = {
            filename = "egg.png",
            bytes = eggPng,
            description = entryToSend.name .. " egg",
        }
    else
        local config = getConfig(entryToSend.category)
        local eggRaw = nil
        if type(config) == "table" and type(config.Egg) == "table" then
            eggRaw = config.Egg.Icon
                or config.Egg.Image
                or config.Egg.Thumbnail
                or config.Egg.Texture
                or config.Egg.TextureId
                or config.Egg.ImageId
        end
        local eggUrl = resolveRobloxThumbnail(eggRaw)
        if eggUrl and eggUrl ~= "" then
            embed.author.icon_url = eggUrl
        end
    end

    -- Animal picture stays on the right, like the reference card.
    local sentWithImage = false
    if type(animalPng) == "string" and #animalPng >= 100 then
        embed.thumbnail = {url = "attachment://animal.png"}
        files[#files + 1] = {
            filename = "animal.png",
            bytes = animalPng,
            description = entryToSend.name,
        }
        sentWithImage = true
    else
        local imageUrl = getWebhookAnimalImage(entryToSend.category)
            or resolveRobloxThumbnail(entryToSend.image)
        if imageUrl and imageUrl ~= "" then
            embed.thumbnail = {url = imageUrl}
            sentWithImage = true
        end
    end

    -- Discord ignores webhook components unless with_components=true is present.
    local webhookWithComponents = webhook
        .. (string.find(webhook, "?", 1, true) and "&" or "?")
        .. "with_components=true"

    local requestData = nil
    if #files > 0 then
        payload.attachments = {}
        for i, file in ipairs(files) do
            payload.attachments[i] = {
                id = i - 1,
                filename = file.filename,
                description = file.description,
            }
        end

        local boundary, multipartBody = buildDiscordMultipartFiles(payload, files)
        requestData = {
            Url = webhookWithComponents,
            Method = "POST",
            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
            Body = multipartBody,
        }
    else
        requestData = {
            Url = webhookWithComponents,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        }
    end

    local ok, response = pcall(function()
        return requester(requestData)
    end)

    local statusCode = nil
    if ok and type(response) == "table" then
        statusCode = tonumber(response.StatusCode or response.Status or response.status or response.status_code)
    end

    local success = ok and (statusCode == nil or (statusCode >= 200 and statusCode < 300))
    local imageReason = sentWithImage and "OK" or tostring(animalImageReason or "IMAGE_UNAVAILABLE")


    return success, statusCode, sentWithImage, imageReason
end

function runtimeState._startAutoQueueWorker()
    if autoQueueBusy then
        return
    end
    autoQueueBusy = true

    task.spawn(function()
        local batchFailed = false

        while #autoQueue > 0 and screen.Parent and isCurrentVorykenRun() do
            local item = table.remove(autoQueue, 1)
            local webhook = trim(webhookBox.Text)

            if CycleRuntime.hopBlocked() then
                serverHopQueuedAfterSend = false
                if item and item.entry then
                    autoNotifiedUids[tostring(item.entry.uid or "")] = nil
                end
                filterStatus.Text = "Cycle reset • Discord paused"
                filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
                break
            end

            if item and isDiscordWebhook(webhook) then
                filterStatus.Text = "Auto sending • " .. tostring(item.entry.name)
                filterStatus.TextColor3 = COLORS.Gray

                local ok, statusCode = runtimeState._sendEntryToDiscord(
                    item.entry,
                    webhook,
                    "Automatic minimum filter • " .. formatNumber(item.threshold) .. "+",
                    true
                )

                if ok then
                    filterStatus.Text = "Auto sent • " .. tostring(item.entry.name)
                    filterStatus.TextColor3 = COLORS.Green
                else
                    batchFailed = true
                    -- Keep reservation even if the executor reports timeout/error;
                    -- Discord may already have accepted the request.
                    filterStatus.Text = "Auto Discord failed • duplicate blocked"
                    if statusCode then
                        filterStatus.Text = filterStatus.Text .. " (HTTP " .. tostring(statusCode) .. ")"
                    end
                    filterStatus.TextColor3 = Color3.fromRGB(255, 92, 112)
                end
            end
            -- No artificial delay between automatic Discord notifications.
            -- sendEntryToDiscord itself yields until the HTTP request finishes.
        end
        autoQueueBusy = false
        if #autoQueue == 0 then
            if serverHopQueuedAfterSend and serverHopEnabled and not batchFailed then
                serverHopQueuedAfterSend = false
                runtimeState._performServerHop("MATCH_SENT")
            else
                if batchFailed then
                    serverHopQueuedAfterSend = false
                end
                task.defer(refreshFilterStatus)
            end
        else
            runtimeState._startAutoQueueWorker()
        end
    end)
end

function runtimeState._processAutomaticNotifications(topEntries, allEntries)
    local cycleState = CycleRuntime.updateGuard(allEntries)

    if cycleState == "HOLD" or cycleState == "WAIT" then
        serverHopQueuedAfterSend = false
        filterStatus.Text = cycleState == "HOLD"
            and "Cycle reset soon • waiting"
            or "New cycle • loading new eggs"
        filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)
        return
    end

    if cycleState == "EMPTY" then
        serverHopQueuedAfterSend = false
        if serverHopEnabled then
            runtimeState._performServerHop("NO_MATCH_AFTER_RESET")
        end
        return
    end

    local threshold = getAutoThreshold()
    if not threshold then
        return
    end

    local matchingCount = 0
    local publishFailed = false

    -- Voryken API-only: publish qualifying eggs before leaving the server.
    for _, entry in ipairs(topEntries or {}) do
        local uid = tostring(entry.uid or "")
        local value = tonumber(entry.value) or 0

        if uid ~= "" and value >= threshold then
            matchingCount += 1

            if not apiPublishedUids[uid] then
                -- A 401/403/network timeout is not an instruction to retry
                -- 30+ times per second. Show its reason and continue the hop.
                if os.clock() >= (reportRetryAt[uid] or 0) then
                    apiPublishedUids[uid] = {
                        JobId = currentJobId,
                        ReservedAt = os.clock(),
                        Name = tostring(entry.name or ""),
                    }
                    filterStatus.Text = "Finder-2 • " .. tostring(entry.name)
                    filterStatus.TextColor3 = COLORS.Gray
                    local ok = publishEntryToApi(runtimeState._cloneEntry(entry), threshold)
                    if not ok then
                        publishFailed = true
                        apiPublishedUids[uid] = nil
                        reportRetryAt[uid] = os.clock() + 6
                        filterStatus.Text = "Finder-2 ERROR • " .. tostring(runtimeState._lastEggPublishError or "NETWORK"):sub(1, 72)
                        filterStatus.TextColor3 = Color3.fromRGB(255, 92, 112)
                    end
                else
                    publishFailed = true
                end
            end
        end
    end

    if matchingCount > 0 then
        if publishFailed then
            filterStatus.Text = "Finder-2 report failed • moving on: "
                .. tostring(runtimeState._lastEggPublishError or "retry pending"):sub(1, 60)
            filterStatus.TextColor3 = Color3.fromRGB(255, 92, 112)
            warn("[VORYKEN REPORT] Egg upload failed. Check Finder-2 Rules and /reports writes.")
        else
            filterStatus.Text = "Finder-2 sent • " .. tostring(matchingCount) .. " match" .. (matchingCount == 1 and "" or "es")
            filterStatus.TextColor3 = COLORS.Green
        end
    end

    if serverHopEnabled then
        runtimeState._performServerHop(matchingCount > 0 and "MATCH_SENT" or "NO_MATCH")
    end
end
-- Manual Discord send disabled: Voryken API-only finder.

function runtimeState._updateCard(row, entry)
    row.Entry = entry

    if not entry then
        row.Frame.Visible = false
        row.Category = nil
        row.Signature = nil
        row.PreviewGeneration += 1
        clearViewport(row.Viewport)
        row.Fallback.Image = ""
        row.Fallback.Visible = true
        return
    end

    row.Frame.Visible = true
    row.Name.Text = tostring(entry.name)
    row.Rarity.Text = string.upper(tostring(entry.rarity or "Unknown"))
    row.Rarity.TextColor3 = rarityColor(entry.rarity)

    local sizeText = string.format("%.2f", tonumber(entry.scale) or 1)

    row.Size.Text = "x" .. sizeText
    row.Value.Text = "$" .. formatNumber(entry.value)

    row.Fallback.Image = entry.image or ""
    row.Fallback.Visible = true

    if row.Category ~= entry.category then
        row.Category = entry.category
        row.PreviewGeneration += 1
        local generation = row.PreviewGeneration

        task.spawn(function()
            setupAnimalPreview(row.Viewport, entry.category, generation, row)
        end)
    end

    row.Signature = table.concat({
        tostring(entry.uid),
        tostring(entry.category),
        tostring(entry.value),
        tostring(entry.scale),
    }, "|")
end

function runtimeState._forceTopThreeDescending(top)
    top = top or {}

    local function swap(a, b)
        top[a], top[b] = top[b], top[a]
    end

    -- Exact 3-card sorting network: 1 >= 2 >= 3.
    if top[2] and isEggBetter(top[2], top[1]) then
        swap(1, 2)
    end
    if top[3] and isEggBetter(top[3], top[2]) then
        swap(2, 3)
    end
    if top[2] and isEggBetter(top[2], top[1]) then
        swap(1, 2)
    end

    return top
end

function runtimeState._refresh()
    runtimeState._lastScannerRefreshAt = os.clock()
    local top, allEntries = getTopEggs()
    top = runtimeState._forceTopThreeDescending(top)
    runtimeState._lastScannerEggCount = #(allEntries or {})
    if #(allEntries or {}) > 0 then
        runtimeState._lastScannerEggSeenAt = os.clock()
    end

    for _, entry in ipairs(allEntries or {}) do
        rememberEntryFirstSeen(entry)
    end

    runtimeState._processAutomaticNotifications(top, allEntries)

    local signatureParts = {}
    for i = 1, TOP_COUNT do
        local entry = top[i]
        if entry then
            signatureParts[i] = table.concat({
                tostring(entry.uid),
                tostring(entry.category),
                tostring(entry.value),
                tostring(entry.scale),
            }, ":")
        else
            signatureParts[i] = "-"
        end
    end

    local signature = table.concat(signatureParts, "|")
    if signature ~= lastTopSignature then
        lastTopSignature = signature
        runtimeState._updateCard(rows[1], top[1])
        runtimeState._updateCard(rows[2], top[2])
        runtimeState._updateCard(rows[3], top[3])
    end

    if selectedUid then
        local replacement = nil
        for i = 1, TOP_COUNT do
            local entry = top[i]
            if entry and tostring(entry.uid) == tostring(selectedUid) then
                replacement = entry
                break
            end
        end

        if replacement then
            selectedEntry = replacement
        else
            selectedEntry = nil
            selectedUid = nil
            settings.SelectedUid = ""
            settings.SelectedCategory = ""
            saveSettings()
            sendStatus.Text = "Selected egg is no longer in the Top 3"
            sendStatus.TextColor3 = COLORS.Gray
        end
    end

    refreshSelectionVisual()

    if #top > 0 then
        subtitle.Text = tostring(#top) .. " best current eggs"
    else
        subtitle.Text = "Reading current eggs..."
    end
end

--==============================================================
-- ZERO-DELAY API FAST PATH
-- ChildAdded publishes a qualifying normal-map egg immediately when EggState
-- already contains its UID. If EggState has not caught up yet, a single
-- Heartbeat retry runs on the next rendered frame; there is no artificial
-- task.wait delay before the first publish attempt.
--==============================================================
runtimeState._instantRefreshBusy = false
runtimeState._instantRefreshAgain = false

function runtimeState._runRefreshImmediate()
    if runtimeState._instantRefreshBusy then
        runtimeState._instantRefreshAgain = true
        return
    end

    runtimeState._instantRefreshBusy = true
    repeat
        runtimeState._instantRefreshAgain = false
        local ok, err = pcall(runtimeState._refresh)
        if ok then
            runtimeState._scannerRefreshFailures = 0
            runtimeState._scannerLastRefreshError = nil
        else
            runtimeState._scannerRefreshFailures = (runtimeState._scannerRefreshFailures or 0) + 1
            runtimeState._scannerLastRefreshError = tostring(err or "Unknown refresh error")
            -- Avoid spinning forever if a faulty event keeps requesting refresh.
            runtimeState._instantRefreshAgain = false
        end
    until not runtimeState._instantRefreshAgain
    runtimeState._instantRefreshBusy = false
end

function runtimeState._publishNormalUidImmediate(uid, slotObject)
    uid = tostring(uid or "")
    if uid == "" or apiPublishedUids[uid] or CycleRuntime.hopBlocked()
        or os.clock() < (reportRetryAt[uid] or 0) then
        return false
    end

    local threshold = getAutoThreshold()
    if not threshold then
        return false
    end

    local records = readSnapshotRecords()
    local record = type(records) == "table" and records[uid] or nil
    if type(record) ~= "table" then
        return false
    end

    local entry = entryFromRecord(uid, record, slotObject)
    if type(entry) ~= "table" or (tonumber(entry.value) or 0) < threshold then
        return false
    end

    apiPublishedUids[uid] = {
        JobId = currentJobId,
        ReservedAt = os.clock(),
        Name = tostring(entry.name or ""),
        FastPath = true,
    }

    -- Voryken API is the first network action. UI refresh / hop happens after.
    local ok = publishEntryToApi(runtimeState._cloneEntry(entry), threshold)
    if not ok then
        apiPublishedUids[uid] = nil
        reportRetryAt[uid] = os.clock() + 6
        filterStatus.Text = "Finder-2 SEND ERROR • " .. tostring(runtimeState._lastEggPublishError or "NETWORK"):sub(1, 64)
        filterStatus.TextColor3 = Color3.fromRGB(255, 92, 112)
        return false
    end

    filterStatus.Text = "Finder-2 sent • " .. tostring(entry.name)
    filterStatus.TextColor3 = COLORS.Green
    return true
end

function runtimeState._retryFastPathNextFrame(uid, slotObject)
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if connection then
            connection:Disconnect()
            connection = nil
        end
        if not screen.Parent or not isCurrentVorykenRun() then
            return
        end
        runtimeState._publishNormalUidImmediate(uid, slotObject)
        runtimeState._runRefreshImmediate()
    end)
end

function runtimeState._publishHalloweenImmediate()
    if CycleRuntime.hopBlocked() then
        return false
    end

    local threshold = getAutoThreshold()
    if not threshold then
        return false
    end

    local sentAny = false
    for _, entry in ipairs(getHalloweenEggEntries(true)) do
        local uid = tostring(entry.uid or "")
        if uid ~= ""
            and not apiPublishedUids[uid]
            and (tonumber(entry.value) or 0) >= threshold then

            apiPublishedUids[uid] = {
                JobId = currentJobId,
                ReservedAt = os.clock(),
                Name = tostring(entry.name or ""),
                FastPath = true,
            }

            local ok = publishEntryToApi(runtimeState._cloneEntry(entry), threshold)
            if ok then
                sentAny = true
                filterStatus.Text = "Voryken API sent • " .. tostring(entry.name)
                filterStatus.TextColor3 = COLORS.Green
            else
                apiPublishedUids[uid] = nil
                reportRetryAt[uid] = os.clock() + 6
            end
        end
    end
    return sentAny
end

runtimeState._boundHalloweenWorldEggs = nil
function runtimeState._bindHalloweenFastPath()
    local dimension = Workspace:FindFirstChild("HalloweenDimension")
    local worldEggs = dimension and dimension:FindFirstChild("WorldEggs") or nil
    if not worldEggs or worldEggs == runtimeState._boundHalloweenWorldEggs then
        return
    end

    runtimeState._boundHalloweenWorldEggs = worldEggs
    worldEggs.DescendantAdded:Connect(function()
        -- Immediate attempt first. If the game's UID/value attributes land just
        -- after the instance, the one-frame retry catches them with no fixed delay.
        runtimeState._publishHalloweenImmediate()
        local connection
        connection = RunService.Heartbeat:Connect(function()
            if connection then connection:Disconnect() end
            if screen.Parent and isCurrentVorykenRun() then
                runtimeState._publishHalloweenImmediate()
                runtimeState._runRefreshImmediate()
            end
        end)
    end)
end

runtimeState._bindHalloweenFastPath()
Workspace.ChildAdded:Connect(function(child)
    if child and child.Name == "HalloweenDimension" then
        local connection
        connection = child.ChildAdded:Connect(function(grandchild)
            if grandchild and grandchild.Name == "WorldEggs" then
                if connection then connection:Disconnect() end
                runtimeState._bindHalloweenFastPath()
            end
        end)
        runtimeState._bindHalloweenFastPath()
    end
end)

refreshRequested = true

runtimeState._boundEggFolder = nil
function runtimeState._bindEggFolder(folder)
    if not folder or folder == runtimeState._boundEggFolder then
        return
    end

    eggFolder = folder
    runtimeState._boundEggFolder = folder

    folder.ChildAdded:Connect(function(slot)
        local uid = tostring(slot and slot.Name or "")

        -- First attempt happens immediately, before any UI work or server-hop
        -- verification. This is the lowest-latency path to Voryken API.
        local sentNow = runtimeState._publishNormalUidImmediate(uid, slot)

        -- Ask EggState for a fresh snapshot without blocking this event.
        requestSync(true)

        if not sentNow then
            -- Some builds create the slot one frame before EggState publishes
            -- the matching record. Retry exactly once on the next Heartbeat.
            runtimeState._retryFastPathNextFrame(uid, slot)
        end

        refreshRequested = true
        runtimeState._runRefreshImmediate()
    end)

    folder.ChildRemoved:Connect(function()
        refreshRequested = true
        runtimeState._runRefreshImmediate()
    end)

    requestSync(true)
    refreshRequested = true
end

if eggFolder then
    runtimeState._bindEggFolder(eggFolder)
else
    task.spawn(function()
        local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
            or Workspace:WaitForChild("AreaEggSlotsClient", 60)
        if folder and screen.Parent then
            runtimeState._bindEggFolder(folder)
        end
    end)
end

requestSync(true)
runtimeState._runRefreshImmediate()
refreshRequested = false

task.spawn(function()
    local lastRefresh = os.clock()
    while screen.Parent and isCurrentVorykenRun() do
        task.wait(DISPATCH_RATE)
        local now = os.clock()

        if refreshRequested or now - lastRefresh >= REFRESH_RATE then
            refreshRequested = false
            lastRefresh = now
            runtimeState._runRefreshImmediate()
        end
    end
end)

-- EARLY-EXECUTION AUTO RECOVERY
-- 1) Re-attach the game's modules/egg folder if they replicated late.
-- 2) Force a real data refresh, not only a text-label change.
-- 3) If the UI remains on its initial reading state, restart the SAME local
--    scanner payload with an attempt limit (never teleport or delete Voryken API).
task.spawn(function()
    local startedAt = os.clock()
    local lastSoftRefresh = 0
    local recoveryRequested = false
    while screen.Parent and isCurrentVorykenRun() do
        task.wait(2.5)
        if not screen.Parent or not isCurrentVorykenRun() then break end

        local now = os.clock()
        local changed = runtimeState._recoverScannerGameData()
        if changed or now - lastSoftRefresh >= 6 then
            lastSoftRefresh = now
            requestSync(true)
            runtimeState._runRefreshImmediate()
        end

        local noEggs = (tonumber(runtimeState._lastScannerEggCount) or 0) == 0
        local readingForever = noEggs
            and subtitle.Text == "Reading current eggs..."
            and now - startedAt >= 20
        local refreshBroken = (tonumber(runtimeState._scannerRefreshFailures) or 0) >= 5
        local noRefresh = now - (tonumber(runtimeState._lastScannerRefreshAt) or startedAt) > 12

        if (readingForever or refreshBroken or noRefresh) and not recoveryRequested then
            -- Give a visible explanation while restarting. The Voryken API slot
            -- can only be filled by the Python collector, not by this restart.
            subtitle.Text = "Reloading scanner..."
            filterStatus.Text = "Scanner recovery • reconnecting game data"
            filterStatus.TextColor3 = Color3.fromRGB(255, 181, 82)

            local env = (type(getgenv) == "function" and getgenv()) or _G
            local restart = type(env) == "table" and env.__VorykenScannerRecoveryRestart
            if type(restart) == "function" then
                local ok, accepted = pcall(restart, currentJobId)
                if ok and accepted == true then
                    recoveryRequested = true
                else
                    -- Rate-limited: continue to rebind/refresh without looping.
                    subtitle.Text = "Scanning • waiting for eggs"
                end
            else
                subtitle.Text = "Scanning • retrying game data"
                recoveryRequested = true
            end
        end
    end
end)

--==============================================================
-- END
--==============================================================

]=]

local __env = (type(getgenv) == "function" and getgenv()) or _G
local __make = type(__env) == "table" and (__env.makefolder or __env.make_folder) or makefolder
local __isfolder = type(__env) == "table" and (__env.isfolder or __env.is_folder) or isfolder
local __write = type(__env) == "table" and (__env.writefile or __env.write_file) or writefile

pcall(function()
    if type(__isfolder) == "function" then
        local ok, exists = pcall(__isfolder, "VorykenEggFinder")
        if not ok or exists ~= true then
            if type(__make) == "function" then __make("VorykenEggFinder") end
        end
    elseif type(__make) == "function" then
        pcall(__make, "VorykenEggFinder")
    end
end)

if type(__write) == "function" then
    pcall(__write, "VorykenEggFinder/EggTop3_current.lua", __payload)
end

-- Visible startup/diagnostics BEFORE compiling or running the large payload.
-- Some executors otherwise fail silently and leave no menu on screen.
local __startupScreen, __startupLabel
pcall(function()
    local __players = game:GetService("Players")
    local __localPlayer = __players.LocalPlayer
    local __uiParent = __localPlayer and __localPlayer:FindFirstChildOfClass("PlayerGui")
    if not __uiParent then
        __uiParent = game:GetService("CoreGui")
    end
    local __old = __uiParent:FindFirstChild("VorykenScannerStartup")
    if __old then __old:Destroy() end

    __startupScreen = Instance.new("ScreenGui")
    __startupScreen.Name = "VorykenScannerStartup"
    __startupScreen.ResetOnSpawn = false
    __startupScreen.DisplayOrder = 1000
    __startupScreen.Parent = __uiParent

    local __panel = Instance.new("Frame")
    __panel.Name = "BootPanel"
    __panel.AnchorPoint = Vector2.new(0.5, 0.5)
    __panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    __panel.Size = UDim2.fromOffset(310, 76)
    __panel.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
    __panel.BorderSizePixel = 0
    __panel.Parent = __startupScreen
    local __corner = Instance.new("UICorner")
    __corner.CornerRadius = UDim.new(0, 12)
    __corner.Parent = __panel
    local __stroke = Instance.new("UIStroke")
    __stroke.Color = Color3.fromRGB(132, 91, 245)
    __stroke.Thickness = 1
    __stroke.Parent = __panel

    local __title = Instance.new("TextLabel")
    __title.Position = UDim2.fromOffset(12, 8)
    __title.Size = UDim2.new(1, -24, 0, 24)
    __title.BackgroundTransparency = 1
    __title.Text = "VORYKEN SERVER SCANNER"
    __title.TextColor3 = Color3.fromRGB(245, 245, 250)
    __title.TextSize = 14
    __title.Font = Enum.Font.GothamBold
    __title.Parent = __panel

    __startupLabel = Instance.new("TextLabel")
    __startupLabel.Position = UDim2.fromOffset(10, 35)
    __startupLabel.Size = UDim2.new(1, -20, 0, 34)
    __startupLabel.BackgroundTransparency = 1
    __startupLabel.Text = "Loading scanner • 100M minimum • Hop ON • instant hop"
    __startupLabel.TextColor3 = Color3.fromRGB(151, 218, 170)
    __startupLabel.TextSize = 11
    __startupLabel.TextWrapped = true
    __startupLabel.Font = Enum.Font.GothamMedium
    __startupLabel.Parent = __panel
end)

local function __showScannerError(reason)
    local __message = tostring(reason or "Unknown startup error")
    warn("[Voryken Scanner] " .. __message)
    pcall(function()
        if __startupLabel and __startupLabel.Parent then
            __startupLabel.Text = "Startup error: " .. __message:sub(1, 165)
            __startupLabel.TextColor3 = Color3.fromRGB(255, 119, 125)
        end
    end)
end

if type(loadstring) ~= "function" then
    __showScannerError("loadstring is not available in this executor")
    return
end
local __chunk, __err = loadstring(__payload)
if not __chunk then
    __showScannerError(__err)
    return
end

-- Run the exact same payload again when the early-start watchdog detects
-- a scanner that never bound to its game data.  Max two automatic restarts
-- per JobId, so genuinely empty worlds / an unfilled Python slot don't loop.
local __recovery = nil
if type(__env) == "table" then
    __recovery = __env.__VorykenScannerRecoveryState
    if type(__recovery) ~= "table" then
        __recovery = {}
        __env.__VorykenScannerRecoveryState = __recovery
    end
    -- A fresh manual execution resets the budget. Automatic retries below
    -- reuse this controller and do not re-run this outer bootstrap.
    __recovery.JobId = tostring(game.JobId)
    __recovery.Attempts = 0
    __recovery.LastAt = 0
end

local function __runScannerPayload()
    task.spawn(function()
        local __ok, __reason = xpcall(__chunk, function(__e)
            if type(debug) == "table" and type(debug.traceback) == "function" then
                local __success, __trace = pcall(debug.traceback, tostring(__e), 2)
                if __success then return __trace end
            end
            return tostring(__e)
        end)
        if not __ok then
            __showScannerError(__reason)
        end
    end)
end

if type(__env) == "table" and type(__recovery) == "table" then
    __env.__VorykenScannerRecoveryRestart = function(jobId)
        if tostring(jobId or "") ~= tostring(game.JobId) then return false end
        if __recovery.Attempts >= 2 then return false end
        if os.clock() - (__recovery.LastAt or 0) < 16 then return false end
        __recovery.Attempts += 1
        __recovery.LastAt = os.clock()
        warn("[Voryken Scanner] Auto-recovering startup ("
            .. tostring(__recovery.Attempts) .. "/2)")
        __runScannerPayload()
        return true
    end
end

-- Initial run; the watchdog uses the same compiled code, not a remote loader.
__runScannerPayload()

-- Keep the boot panel visible until the scanner actually creates a NEW GUI.
-- An existing panel from an earlier run must not hide startup errors.
local __priorPanel = nil
pcall(function()
    local __pl = game:GetService("Players").LocalPlayer
    local __pg = __pl and __pl:FindFirstChildOfClass("PlayerGui")
    __priorPanel = __pg and __pg:FindFirstChild("EggTop3Panel")
end)
task.spawn(function()
    local __players = game:GetService("Players")
    for __attempt = 1, 900 do
        local __localPlayer = __players.LocalPlayer
        local __playerGui = __localPlayer and __localPlayer:FindFirstChildOfClass("PlayerGui")
        local __currentPanel = __playerGui and __playerGui:FindFirstChild("EggTop3Panel")
        if __currentPanel and __currentPanel ~= __priorPanel then
            if __startupScreen then pcall(function() __startupScreen:Destroy() end) end
            return
        end
        task.wait(0.1)
    end
    if __startupLabel and __startupLabel.Parent and not tostring(__startupLabel.Text):find("Startup error", 1, true) then
        __showScannerError("The menu did not finish loading. Check executor console.")
    end
end)
