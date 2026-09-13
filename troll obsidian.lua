-- language: Lua, target: Roblox
-- Troll Hub v9.2 — Obsidian UI (deividcomsono/Obsidian)
-- Wind UI 撤去 / 全機能保持

-- ============================================================
-- Services
-- ============================================================
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local RunService       = game:GetService("RunService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
-- グローバル設定
-- ============================================================
_G.TrollConfig = _G.TrollConfig or {
    antiAFK = true, showStats = true,
    vfly = false, tpfly = false, fly = false, noclip = false, freeze = false, antiFling = false,
    vflySpeed = 50, tpflySpeed = 5, flySpeed = 50, speedHack = false, walkSpeed = 100,
    esp = false, fullBright = false, removeShadows = false, removeFog = false,
    autoChest = false, safeAutoChest = false, autoKill = false, npcEsp = false, chestEsp = false, itemEsp = false,
    scanRange = 2500, tpwalkSpeed = 5
}
local config = _G.TrollConfig

local flyBodyVelocity, flyBodyGyro
local activeBossTags = {}
local cachedBosses  = {}

-- ============================================================
-- Obsidian UI ロード
-- ============================================================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

-- ============================================================
-- Window
-- ============================================================
local Window = Library:CreateWindow({
    Title = "Troll Hub v9.2",
    Footer = "v9.2 | Obsidian",
    NotifySide = "Right",
    ShowCustomCursor = true,
    Resizable = true,
})

local Tabs = {
    Main           = Window:AddTab("Main", "gamepad-2"),
    Player         = Window:AddTab("Player", "user"),
    ESP            = Window:AddTab("ESP", "eye"),
    Misc           = Window:AddTab("Misc", "wrench"),
    Scripts        = Window:AddTab("Scripts", "code-2"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ============================================================
-- HUD (Obsidian とは独立、自前 ScreenGui で維持)
-- ============================================================
local pgui = CoreGui or LocalPlayer:WaitForChild("PlayerGui")
if pgui:FindFirstChild("TrollHubHUD") then pgui.TrollHubHUD:Destroy() end
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "TrollHubHUD"
hudGui.ResetOnSpawn = false
hudGui.Parent = pgui

local espFolder = pgui:FindFirstChild("TrollBossESPFolder")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder")
espFolder.Name = "TrollBossESPFolder"
espFolder.Parent = pgui

-- FPS/Ping HUD
local sF = Instance.new("Frame", hudGui)
sF.Size = UDim2.new(0, 130, 0, 52)
sF.Position = UDim2.new(0.02, 0, 0.2, 0)
sF.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
sF.BackgroundTransparency = 0.15
sF.BorderSizePixel = 0
sF.Visible = config.showStats
local sFCorner = Instance.new("UICorner", sF); sFCorner.CornerRadius = UDim.new(0, 6)
local sFStroke = Instance.new("UIStroke", sF); sFStroke.Color = Color3.fromRGB(60, 60, 70); sFStroke.Thickness = 1

local fL = Instance.new("TextLabel", sF)
fL.Size = UDim2.new(1, -16, 0, 22); fL.Position = UDim2.new(0, 10, 0, 4)
fL.BackgroundTransparency = 1; fL.TextColor3 = Color3.new(0.86, 0.86, 0.86)
fL.Font = Enum.Font.Gotham; fL.TextSize = 13; fL.TextXAlignment = Enum.TextXAlignment.Left
fL.Text = "FPS  --"

local pL = Instance.new("TextLabel", sF)
pL.Size = UDim2.new(1, -16, 0, 22); pL.Position = UDim2.new(0, 10, 0, 26)
pL.BackgroundTransparency = 1; pL.TextColor3 = Color3.new(0.6, 0.6, 0.6)
pL.Font = Enum.Font.Gotham; pL.TextSize = 13; pL.TextXAlignment = Enum.TextXAlignment.Left
pL.Text = "Ping  --"

-- ============================================================
-- ゲーム別機能 (PlaceId 13946738101)
-- ============================================================
local chestCountLabel, bigChestUI  -- 後で参照するため前方宣言

if game.PlaceId == 13946738101 then
    local MainGameGB = Tabs.Main:AddLeftGroupbox("Target Game: 13946738101", "crosshair")

    MainGameGB:AddToggle("AutoChest", {
        Text = "AUTO CHEST (TP: BANリスク高)",
        Default = config.autoChest,
        Risky = true,
        Tooltip = "テレポートでチェストを回収 — BAN リスクあり",
        Callback = function(v) config.autoChest = v end,
    })
    MainGameGB:AddToggle("SafeAutoChest", {
        Text = "SAFE AUTO CHEST (無重力 + TPWalk)",
        Default = config.safeAutoChest,
        Tooltip = "無重力 + TPWalk で移動 — 検出されにくい",
        Callback = function(v)
            config.safeAutoChest = v
            if not v then workspace.Gravity = 196.2 end
        end,
    })
    MainGameGB:AddSlider("TPWalkSpeed", {
        Text = "TPWalk Speed",
        Default = config.tpwalkSpeed,
        Min = 1, Max = 20,
        Rounding = 0,
        Compact = false,
        Callback = function(v) config.tpwalkSpeed = v end,
    })
    MainGameGB:AddDivider()
    MainGameGB:AddToggle("AutoKill", {
        Text = "AUTO KILL",
        Default = config.autoKill,
        Callback = function(v) config.autoKill = v end,
    })

    -- ゲーム固有 ESP
    local GameEspGB = Tabs.ESP:AddLeftGroupbox("Game Specific ESP", "scan-eye")
    GameEspGB:AddToggle("NpcEsp", {
        Text = "BOSS / NPC ESP",
        Default = config.npcEsp,
        Callback = function(v)
            config.npcEsp = v
            if not v then
                for _, tag in pairs(activeBossTags) do if tag then tag:Destroy() end end
                table.clear(activeBossTags)
            end
        end,
    })
    GameEspGB:AddToggle("ChestEsp", {
        Text = "CHEST ESP",
        Default = config.chestEsp,
        Callback = function(v) config.chestEsp = v end,
    })
    GameEspGB:AddToggle("ItemEsp", {
        Text = "ITEM ESP (チェスト以外)",
        Default = config.itemEsp,
        Callback = function(v) config.itemEsp = v end,
    })

    -- ============================================================
    -- チェスト数表示 UI
    -- ============================================================
    bigChestUI = Instance.new("Frame", hudGui)
    bigChestUI.Size = UDim2.new(0, 300, 0, 150)
    bigChestUI.Position = UDim2.new(0.5, -150, 0.5, -75)
    bigChestUI.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
    bigChestUI.BackgroundTransparency = 0.1
    bigChestUI.BorderSizePixel = 0
    bigChestUI.Visible = config.autoChest or config.safeAutoChest
    local bcCorner = Instance.new("UICorner", bigChestUI); bcCorner.CornerRadius = UDim.new(0, 8)
    local bcStroke = Instance.new("UIStroke", bigChestUI); bcStroke.Color = Color3.fromRGB(60, 60, 70); bcStroke.Thickness = 1

    local bcTitle = Instance.new("TextLabel", bigChestUI)
    bcTitle.Size = UDim2.new(1, -28, 0, 22); bcTitle.Position = UDim2.new(0, 14, 0, 12)
    bcTitle.BackgroundTransparency = 1; bcTitle.Text = "AUTO CHEST"
    bcTitle.TextColor3 = Color3.fromRGB(0.6, 0.6, 0.6); bcTitle.Font = Enum.Font.GothamBold
    bcTitle.TextSize = 11; bcTitle.TextXAlignment = Enum.TextXAlignment.Left

    chestCountLabel = Instance.new("TextLabel", bigChestUI)
    chestCountLabel.Size = UDim2.new(1, -28, 0, 32); chestCountLabel.Position = UDim2.new(0, 14, 0, 38)
    chestCountLabel.BackgroundTransparency = 1
    chestCountLabel.Text = "残りチェスト: 検索中..."
    chestCountLabel.TextColor3 = Color3.new(1, 1, 1); chestCountLabel.Font = Enum.Font.GothamBold
    chestCountLabel.TextSize = 18; chestCountLabel.TextXAlignment = Enum.TextXAlignment.Left

    local chestOffBtn = Instance.new("TextButton", bigChestUI)
    chestOffBtn.Size = UDim2.new(1, -28, 0, 40); chestOffBtn.Position = UDim2.new(0, 14, 1, -52)
    chestOffBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); chestOffBtn.Text = "STOP"
    chestOffBtn.TextColor3 = Color3.new(1, 1, 1); chestOffBtn.Font = Enum.Font.GothamBold
    chestOffBtn.TextSize = 13; chestOffBtn.AutoButtonColor = false
    local cobCorner = Instance.new("UICorner", chestOffBtn); cobCorner.CornerRadius = UDim.new(0, 6)
    chestOffBtn.MouseEnter:Connect(function() chestOffBtn.BackgroundColor3 = Color3.fromRGB(240, 90, 90) end)
    chestOffBtn.MouseLeave:Connect(function() chestOffBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60) end)
    chestOffBtn.MouseButton1Click:Connect(function()
        config.autoChest = false
        config.safeAutoChest = false
        bigChestUI.Visible = false
        if Toggles.AutoChest  then Toggles.AutoChest:SetValue(false)  end
        if Toggles.SafeAutoChest then Toggles.SafeAutoChest:SetValue(false) end
    end)

    -- ============================================================
    -- 自動ファームループ
    -- ============================================================
    task.spawn(function()
        while true do
            pcall(function()
                if not (config.autoChest or config.safeAutoChest or config.autoKill) then
                    task.wait(0.1); return
                end
                local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not root then task.wait(0.1); return end

                local target, isChest, dist = nil, false, config.scanRange
                local currentChestCount = 0

                if config.autoChest or config.safeAutoChest then
                    for _, p in pairs(workspace:GetDescendants()) do
                        if p:IsA("ProximityPrompt") and p.Enabled then
                            local obj = p.Parent
                            if obj:IsA("BasePart") then
                                local txt = (obj.Name .. obj.Parent.Name .. p.ActionText):lower()
                                if (txt:find("chest") or txt:find("drop") or txt:find("loot")) and
                                   not (txt:find("shop") or txt:find("npc") or txt:find("buy") or txt:find("talk")) then
                                    currentChestCount = currentChestCount + 1
                                    local d = (root.Position - obj.Position).Magnitude
                                    if d < dist then target = obj; dist = d; isChest = true end
                                end
                            end
                        end
                    end
                end

                if chestCountLabel and (config.autoChest or config.safeAutoChest) then
                    local displayCount = currentChestCount - 3
                    if displayCount < 0 then displayCount = 0 end
                    chestCountLabel.Text = "残りチェスト: " .. displayCount
                end

                if not target and config.autoKill then
                    for _, p in pairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                            if p.Character.Humanoid.Health > 0 then
                                local d = (root.Position - p.Character.HumanoidRootPart.Position).Magnitude
                                if d < dist then target = p.Character.HumanoidRootPart; dist = d; isChest = false end
                            end
                        end
                    end
                end

                if target then
                    if config.safeAutoChest then
                        workspace.Gravity = 0
                        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                            if part:IsA("BasePart") then part.CanCollide = false end
                        end
                        local distToTarget = (target.Position - root.Position).Magnitude
                        if distToTarget > 4 then
                            local dir = (target.Position - root.Position).Unit
                            if dir.X == dir.X and dir.Y == dir.Y and dir.Z == dir.Z then
                                local moveDist = math.min(config.tpwalkSpeed, distToTarget)
                                local nextPos = root.Position + dir * moveDist
                                if (target.Position - nextPos).Magnitude > 0.5 then
                                    root.CFrame = CFrame.lookAt(nextPos, target.Position)
                                else
                                    root.CFrame = CFrame.new(nextPos) * (root.CFrame - root.Position)
                                end
                            end
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                        else
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                            if isChest then
                                task.wait(0.1)
                                fireproximityprompt(target:FindFirstChildOfClass("ProximityPrompt") or target.Parent:FindFirstChildOfClass("ProximityPrompt"))
                            else
                                VirtualUser:Button1Down(Vector2.new(0, 0))
                            end
                        end
                    else
                        root.CFrame = isChest and target.CFrame or target.CFrame * CFrame.new(0, 0, 3)
                        if isChest then
                            task.wait(0.1)
                            fireproximityprompt(target:FindFirstChildOfClass("ProximityPrompt") or target.Parent:FindFirstChildOfClass("ProximityPrompt"))
                        else
                            VirtualUser:Button1Down(Vector2.new(0, 0))
                        end
                    end
                end
            end)
            task.wait(0.05)
        end
    end)

    -- NPCスキャナー
    task.spawn(function()
        while true do
            pcall(function()
                if config.npcEsp then
                    local found = {}
                    local folders = {
                        workspace:FindFirstChild("ActiveNPCs"),
                        workspace:FindFirstChild("boss's"),
                        workspace:FindFirstChild("Map Boss"),
                        workspace:FindFirstChild("Map folder")
                    }
                    for _, folder in pairs(folders) do
                        if folder then
                            for _, obj in pairs(folder:GetDescendants()) do
                                if obj:IsA("Model") and (obj:FindFirstChild("Humanoid") or obj:FindFirstChild("Head")) then
                                    if not Players:GetPlayerFromCharacter(obj) then table.insert(found, obj) end
                                end
                            end
                        end
                    end
                    cachedBosses = found
                end
            end)
            task.wait(1)
        end
    end)

    -- Chest ESP
    local chestEspFolder = Instance.new("Folder", pgui)
    chestEspFolder.Name = "AllChestESP_Folder"
    local function createChestESP(target)
        task.spawn(function()
            local displayName, espColor = "", Color3.new(1, 1, 1)
            if target.Name == "Chest_Spawn" then displayName = "📦 Chest"; espColor = Color3.fromRGB(255, 215, 0)
            elseif target.Name == "LightChest_Spawn" then displayName = "✨ Light Chest"; espColor = Color3.fromRGB(255, 255, 150)
            elseif target.Name == "DarkChest_Spawn" then displayName = "🌑 Dark Chest"; espColor = Color3.fromRGB(180, 50, 255)
            elseif target.Name == "RadioactiveChest_Spawn" then displayName = "☢️ Radioactive Chest"; espColor = Color3.fromRGB(50, 255, 50)
            elseif target.Name == "MachineChest_p" then displayName = "⚙️ Machine Chest"; espColor = Color3.fromRGB(0, 200, 255)
            else return end
            local attachPart = target:FindFirstChild("Handle") or target:FindFirstChild("MachineChest_p") or target:FindFirstChildWhichIsA("BasePart", true)
            if not attachPart and target:IsA("Model") then
                for _ = 1, 10 do
                    task.wait(0.2)
                    if not target.Parent then return end
                    attachPart = target:FindFirstChild("Handle") or target:FindFirstChild("MachineChest_p") or target:FindFirstChildWhichIsA("BasePart", true)
                    if attachPart then break end
                end
            end
            if not attachPart and target:IsA("BasePart") then attachPart = target end
            if not attachPart then return end

            local billboard = Instance.new("BillboardGui")
            billboard.Name = "ChestLabel"
            billboard.Adornee = attachPart
            billboard.Size = UDim2.new(0, 200, 0, 30)
            billboard.StudsOffset = Vector3.new(0, 3, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = chestEspFolder

            local label = Instance.new("TextLabel", billboard)
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Text = displayName
            label.TextColor3 = espColor
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBold
            label.TextSize = 14

            local conn
            conn = RunService.RenderStepped:Connect(function()
                if not target or not target.Parent or not attachPart or not attachPart.Parent then
                    billboard:Destroy(); conn:Disconnect(); return
                end
                billboard.Enabled = config.chestEsp
                if config.chestEsp then
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        label.Text = displayName .. " [" .. math.floor((root.Position - attachPart.Position).Magnitude) .. "m]"
                    end
                end
            end)
        end)
    end
    for _, v in pairs(workspace:GetDescendants()) do createChestESP(v) end
    workspace.DescendantAdded:Connect(createChestESP)

    -- Item ESP
    local itemEspFolder = Instance.new("Folder", pgui)
    itemEspFolder.Name = "AllItemESP_Folder"
    local function createItemESP(target)
        task.spawn(function()
            local displayName, espColor = "", Color3.new(1, 1, 1)
            if target.Name:match("Chest") or target.Name:match("chest") then return end
            if target.Name == "WeepSoul_P" then
                displayName = "👻 Weep Soul"; espColor = Color3.fromRGB(150, 255, 255)
            elseif target.Name:match("_P$") or target.Name:match("_p$") then
                displayName = "🔹 " .. target.Name:gsub("_[Pp]$", ""); espColor = Color3.fromRGB(200, 200, 255)
            else return end
            local attachPart = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart", true)
            if not attachPart then return end

            local billboard = Instance.new("BillboardGui")
            billboard.Name = "ItemLabel"
            billboard.Adornee = attachPart
            billboard.Size = UDim2.new(0, 200, 0, 30)
            billboard.StudsOffset = Vector3.new(0, 2, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = itemEspFolder

            local label = Instance.new("TextLabel", billboard)
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Text = displayName
            label.TextColor3 = espColor
            label.TextStrokeTransparency = 0
            label.Font = Enum.Font.GothamBold
            label.TextSize = 12

            local conn
            conn = RunService.RenderStepped:Connect(function()
                if not target or not target.Parent or not attachPart or not attachPart.Parent then
                    billboard:Destroy(); conn:Disconnect(); return
                end
                billboard.Enabled = config.itemEsp
                if config.itemEsp then
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        label.Text = displayName .. " [" .. math.floor((root.Position - attachPart.Position).Magnitude) .. "m]"
                    end
                end
            end)
        end)
    end
    for _, v in pairs(workspace:GetDescendants()) do createItemESP(v) end
    workspace.DescendantAdded:Connect(createItemESP)
else
    local MainGameGB = Tabs.Main:AddLeftGroupbox("Universal Game", "gamepad-2")
    MainGameGB:AddLabel("このゲーム専用機能はありません", false)
end

-- ============================================================
-- プレイヤー機能 (共通)
-- ============================================================
local MovementGB = Tabs.Player:AddLeftGroupbox("Movement", "footprints")

MovementGB:AddToggle("VFly", {
    Text = "VFly",
    Default = config.vfly,
    Callback = function(v) config.vfly = v end,
})
MovementGB:AddSlider("VFlySpeed", {
    Text = "VFly Speed", Default = config.vflySpeed,
    Min = 10, Max = 300, Rounding = 0, Compact = false,
    Callback = function(v) config.vflySpeed = v end,
})
MovementGB:AddToggle("TPFly", {
    Text = "TPFly",
    Default = config.tpfly,
    Callback = function(v) config.tpfly = v end,
})
MovementGB:AddSlider("TPFlySpeed", {
    Text = "TPFly Speed", Default = config.tpflySpeed,
    Min = 1, Max = 50, Rounding = 0, Compact = false,
    Callback = function(v) config.tpflySpeed = v end,
})
MovementGB:AddToggle("Fly", {
    Text = "Fly (Standard)",
    Default = config.fly,
    Callback = function(v)
        config.fly = v
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if v then
                flyBodyVelocity = Instance.new("BodyVelocity", root)
                flyBodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
                flyBodyVelocity.Velocity = Vector3.zero
                flyBodyGyro = Instance.new("BodyGyro", root)
                flyBodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
                flyBodyGyro.P = 9e4
            else
                if flyBodyVelocity then flyBodyVelocity:Destroy() end
                if flyBodyGyro then flyBodyGyro:Destroy() end
            end
        end
    end,
})
MovementGB:AddSlider("FlySpeed", {
    Text = "Fly Speed", Default = config.flySpeed,
    Min = 10, Max = 300, Rounding = 0, Compact = false,
    Callback = function(v) config.flySpeed = v end,
})
MovementGB:AddDivider()
MovementGB:AddToggle("Noclip", {
    Text = "Noclip",
    Default = config.noclip,
    Callback = function(v) config.noclip = v end,
})
MovementGB:AddToggle("Freeze", {
    Text = "Freeze (Anchored)",
    Default = config.freeze,
    Callback = function(v)
        config.freeze = v
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then root.Anchored = v end
    end,
})
MovementGB:AddToggle("AntiFling", {
    Text = "Anti-Fling (衝突無効)",
    Default = config.antiFling,
    Callback = function(v) config.antiFling = v end,
})
MovementGB:AddToggle("SpeedHack", {
    Text = "SPEED HACK",
    Default = config.speedHack,
    Callback = function(v)
        config.speedHack = v
        if not v and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = 16
        end
    end,
})

-- ============================================================
-- ESP (共通)
-- ============================================================
local UniversalEspGB = Tabs.ESP:AddRightGroupbox("Universal ESP", "users")
UniversalEspGB:AddToggle("PlayerEsp", {
    Text = "PLAYER ESP",
    Default = config.esp,
    Callback = function(v) config.esp = v end,
})

-- ============================================================
-- Misc
-- ============================================================
local UtilityGB = Tabs.Misc:AddLeftGroupbox("Utility", "sliders-horizontal")

UtilityGB:AddToggle("AntiAfk", {
    Text = "ANTI AFK",
    Default = config.antiAFK,
    Callback = function(v) config.antiAFK = v end,
})
UtilityGB:AddButton({
    Text = "ANTI LAG (軽量化)",
    Func = function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and not v:IsA("MeshPart") then
                v.Material = Enum.Material.SmoothPlastic
            elseif v:IsA("Decal") or v:IsA("Texture") then
                v.Transparency = 1
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Enabled = false
            end
        end
        Lighting.GlobalShadows = false
    end,
    DoubleClick = false,
    Tooltip = "描画負荷を下げる",
})
UtilityGB:AddDivider()
UtilityGB:AddToggle("RemoveShadows", {
    Text = "REMOVE SHADOWS",
    Default = config.removeShadows,
    Callback = function(v) config.removeShadows = v end,
})
UtilityGB:AddToggle("RemoveFog", {
    Text = "REMOVE FOG",
    Default = config.removeFog,
    Callback = function(v) config.removeFog = v end,
})
UtilityGB:AddToggle("FullBright", {
    Text = "FULL BRIGHT",
    Default = config.fullBright,
    Callback = function(v)
        config.fullBright = v
        if not v then Lighting.Brightness = 1; Lighting.ClockTime = 12 end
    end,
})
UtilityGB:AddToggle("StatsHud", {
    Text = "STATS HUD",
    Default = config.showStats,
    Callback = function(v)
        config.showStats = v
        sF.Visible = v
    end,
})

-- ============================================================
-- Scripts
-- ============================================================
local ExternalGB = Tabs.Scripts:AddLeftGroupbox("External", "download")
ExternalGB:AddButton({
    Text = "Unstability || Universal",
    Func = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/ILOVETHECOFFINOFANDYANDLEYLEY/THE-HACK-/main/script%20omg"))()
    end,
    DoubleClick = false,
    Tooltip = "外部スクリプトを実行",
})

-- ============================================================
-- UI Settings タブ
-- ============================================================
local MenuGB = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "settings-2")

MenuGB:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})
MenuGB:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = Library.ShowCustomCursor,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})
MenuGB:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value) Library:SetNotifySide(Value) end,
})
MenuGB:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})
MenuGB:AddSlider("UICornerSlider", {
    Text = "Corner Radius",
    Default = Library.CornerRadius,
    Min = 0, Max = 20, Rounding = 0, Compact = false,
    Callback = function(value) Window:SetCornerRadius(value) end,
})
MenuGB:AddDivider()
MenuGB:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

MenuGB:AddButton({
    Text = "Unload",
    Func = function() Library:Unload() end,
    DoubleClick = false,
})

Library.ToggleKeybind = Options.MenuKeybind

-- ============================================================
-- Addons: ThemeManager / SaveManager
-- ============================================================
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("TrollHub")
SaveManager:SetFolder("TrollHub/specific-game")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

-- ============================================================
-- 共通ループ
-- ============================================================
RunService.Stepped:Connect(function()
    if (config.noclip or (config.safeAutoChest and game.PlaceId == 13946738101)) and LocalPlayer.Character then
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
    if config.antiFling then
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                for _, part in pairs(p.Character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if config.showStats then
        fL.Text = "FPS  " .. math.floor(1 / dt)
        pL.Text = "Ping  " .. math.floor(LocalPlayer:GetNetworkPing() * 1000) .. "ms"
    end

    -- プレイヤーESP
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Head") then
            local tag = p.Character.Head:FindFirstChild("TrollTag") or Instance.new("BillboardGui", p.Character.Head)
            tag.Name = "TrollTag"
            tag.AlwaysOnTop = true
            tag.Size = UDim2.new(0, 100, 0, 40)
            tag.Enabled = config.esp
            local lbl = tag:FindFirstChild("Label") or Instance.new("TextLabel", tag)
            lbl.Name = "Label"
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = Color3.new(1, 1, 1)
            lbl.TextStrokeTransparency = 0
            local hp = p.Character:FindFirstChild("Humanoid") and math.floor(p.Character.Humanoid.Health) or 0
            lbl.Text = p.DisplayName .. "\nHP: " .. hp
        end
    end

    -- Boss ESP 更新
    if config.npcEsp and game.PlaceId == 13946738101 then
        local currentList = {}
        for _, obj in pairs(cachedBosses) do
            local head = obj:FindFirstChild("Head") or obj:FindFirstChild("Torso") or obj:FindFirstChild("HumanoidRootPart")
            local hum  = obj:FindFirstChild("Humanoid")
            if head and hum and hum.Health > 0 then
                currentList[obj] = true
                local tag = activeBossTags[obj]
                if not tag or not tag.Parent then
                    tag = Instance.new("BillboardGui")
                    tag.Name = "BossTag"
                    tag.AlwaysOnTop = true
                    tag.Size = UDim2.new(0, 100, 0, 40)
                    tag.Adornee = head
                    tag.Parent = espFolder
                    local lbl = Instance.new("TextLabel", tag)
                    lbl.Name = "Label"
                    lbl.Size = UDim2.new(1, 0, 1, 0)
                    lbl.BackgroundTransparency = 1
                    lbl.TextColor3 = Color3.fromRGB(255, 50, 50)
                    lbl.TextStrokeTransparency = 0
                    lbl.Font = Enum.Font.SourceSansBold
                    activeBossTags[obj] = tag
                end
                local displayName = obj.Name
                local healthBar = head:FindFirstChild("BossHealthBar")
                if healthBar then
                    local bossText = healthBar:FindFirstChild("boss")
                    if bossText and bossText:IsA("TextLabel") and bossText.Text ~= "" then
                        displayName = bossText.Text
                    end
                end
                tag.Label.Text = "[" .. displayName .. "]\nHP: " .. math.floor(hum.Health)
            end
        end
        for obj, tag in pairs(activeBossTags) do
            if not currentList[obj] or not obj.Parent then
                if tag then tag:Destroy() end
                activeBossTags[obj] = nil
            end
        end
    end

    -- 飛行
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChild("Humanoid")
    if root and hum then
        local moveDir = hum.MoveDirection
        local dir3D = Vector3.zero
        if moveDir.Magnitude > 0 then
            local camCFrame = Camera.CFrame
            local flatLook = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
            if flatLook.Magnitude > 0 then flatLook = flatLook.Unit end
            local flatRight = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)
            if flatRight.Magnitude > 0 then flatRight = flatRight.Unit end
            local forwardAmt = moveDir:Dot(flatLook)
            local rightAmt = moveDir:Dot(flatRight)
            dir3D = (camCFrame.LookVector * forwardAmt) + (camCFrame.RightVector * rightAmt)
            if dir3D.Magnitude > 0 then dir3D = dir3D.Unit end
        end
        if config.fly and flyBodyVelocity and flyBodyGyro then
            flyBodyGyro.CFrame = Camera.CFrame
            flyBodyVelocity.Velocity = dir3D * config.flySpeed
        end
        if config.vfly then
            if moveDir.Magnitude > 0 then
                root.Velocity = dir3D * config.vflySpeed
            else
                root.Velocity = Vector3.new(0, 0.1, 0)
            end
        end
        if config.tpfly then
            if moveDir.Magnitude > 0 then
                root.CFrame = root.CFrame + (dir3D * (config.tpflySpeed * (dt * 60)))
            end
            root.Velocity = Vector3.zero
        end
        if config.speedHack then hum.WalkSpeed = config.walkSpeed end
    end

    if config.removeShadows then Lighting.GlobalShadows = false end
    if config.removeFog then
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if atm then atm.Density = 0 end
    end
    if config.fullBright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
    end
end)

Library:OnUnload(function()
    if hudGui then hudGui:Destroy() end
    if espFolder then espFolder:Destroy() end
    print("[Troll Hub] Unloaded")
end)
