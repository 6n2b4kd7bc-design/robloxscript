-- Wind UIローダー
local cloneref = cloneref or function(i) return i end
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))

local WindUI
do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)
    if ok then
        WindUI = result
    else
        if RunService:IsStudio() then
            WindUI = require(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init"))
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end
    end
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

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
local cachedBosses = {}

-- ============================================================
-- HUD (共通) - 「UI」ボタンなし
-- ============================================================
local pgui = CoreGui or LocalPlayer:WaitForChild("PlayerGui")
if pgui:FindFirstChild("TrollHubHUD") then pgui.TrollHubHUD:Destroy() end
local hudGui = Instance.new("ScreenGui", pgui)
hudGui.Name = "TrollHubHUD"
hudGui.ResetOnSpawn = false

local espFolder = pgui:FindFirstChild("TrollBossESPFolder")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", pgui)
espFolder.Name = "TrollBossESPFolder"

-- FPS/Ping表示
local sF = Instance.new("Frame", hudGui)
sF.Size = UDim2.new(0,120,0,50)
sF.Position = UDim2.new(0.02,0,0.2,0)
sF.BackgroundColor3 = Color3.new(0,0,0)
sF.BackgroundTransparency = 0.5
sF.Visible = config.showStats
Instance.new("UICorner", sF)
local fL = Instance.new("TextLabel", sF)
fL.Size = UDim2.new(1,0,0.5,0); fL.BackgroundTransparency = 1; fL.TextColor3 = Color3.new(0,1,0); fL.Text = "FPS: --"
local pL = Instance.new("TextLabel", sF)
pL.Size = UDim2.new(1,0,0.5,0); pL.Position = UDim2.new(0,0,0.5,0); pL.BackgroundTransparency = 1; pL.TextColor3 = Color3.new(1,1,0); pL.Text = "Ping: --"

-- ============================================================
-- Wind UI 初期化
-- ============================================================
local Window = WindUI:CreateWindow({
    Title = "Troll Hub v9.2 (Wind UI)",
    Icon = "solar:skull-bold",
    NewElements = true,
    HideSearchBar = true,
    OpenButton = {
        Title = "Troll Hub",
        CornerRadius = UDim.new(1,0),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.6,
        Color = ColorSequence.new(Color3.fromHex("#30FF6A"), Color3.fromHex("#e7ff2f"))
    },
    Topbar = { Height = 44, ButtonsType = "Mac" }
})

local MainTab = Window:Tab({ Title = "Main (Game)", Icon = "solar:gamepad-bold" })
local PlayerTab = Window:Tab({ Title = "Player", Icon = "solar:user-bold" })
local EspTab = Window:Tab({ Title = "ESP", Icon = "solar:eye-bold" })
local MiscTab = Window:Tab({ Title = "Misc", Icon = "solar:settings-bold" })
local ScriptTab = Window:Tab({ Title = "Scripts", Icon = "solar:code-bold" })

-- ============================================================
-- ゲーム別機能 (PlaceId 13946738101)
-- ============================================================
if game.PlaceId == 13946738101 then
    MainTab:Section({ Title = "Target Game: 13946738101" })

    -- Auto Chest
    MainTab:Toggle({
        Title = "AUTO CHEST (TP: BANリスク高)",
        Value = config.autoChest,
        Callback = function(v) config.autoChest = v end
    })
    MainTab:Toggle({
        Title = "SAFE AUTO CHEST (無重力 + TPWalk)",
        Value = config.safeAutoChest,
        Callback = function(v)
            config.safeAutoChest = v
            if not v then workspace.Gravity = 196.2 end
        end
    })
    MainTab:Slider({
        Title = "TPWalk Speed",
        Step = 1,
        Value = { Min = 1, Max = 20, Default = config.tpwalkSpeed },
        Callback = function(v) config.tpwalkSpeed = v end
    })

    MainTab:Toggle({
        Title = "AUTO KILL",
        Value = config.autoKill,
        Callback = function(v) config.autoKill = v end
    })

    -- ゲーム固有 ESP
    EspTab:Section({ Title = "Game Specific ESP" })
    EspTab:Toggle({
        Title = "BOSS / NPC ESP",
        Value = config.npcEsp,
        Callback = function(v) config.npcEsp = v; if not v then for _, tag in pairs(activeBossTags) do if tag then tag:Destroy() end end; table.clear(activeBossTags) end end
    })
    EspTab:Toggle({
        Title = "CHEST ESP",
        Value = config.chestEsp,
        Callback = function(v) config.chestEsp = v end
    })
    EspTab:Toggle({
        Title = "ITEM ESP (チェスト以外)",
        Value = config.itemEsp,
        Callback = function(v) config.itemEsp = v end
    })

    -- チェスト数表示用UI
    local bigChestUI = Instance.new("Frame", hudGui)
    bigChestUI.Size = UDim2.new(0, 300, 0, 150)
    bigChestUI.Position = UDim2.new(0.5, -150, 0.5, -75)
    bigChestUI.BackgroundColor3 = Color3.fromRGB(20,20,25)
    bigChestUI.Visible = config.autoChest or config.safeAutoChest
    Instance.new("UICorner", bigChestUI)

    local chestCountLabel = Instance.new("TextLabel", bigChestUI)
    chestCountLabel.Size = UDim2.new(1,0,0.6,0)
    chestCountLabel.Text = "残りチェスト: 検索中..."
    chestCountLabel.TextColor3 = Color3.new(1,1,1)
    chestCountLabel.TextScaled = true
    chestCountLabel.BackgroundTransparency = 1

    local chestOffBtn = Instance.new("TextButton", bigChestUI)
    chestOffBtn.Size = UDim2.new(0.6,0,0.3,0)
    chestOffBtn.Position = UDim2.new(0.2,0,0.65,0)
    chestOffBtn.Text = "OFF"
    chestOffBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
    chestOffBtn.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", chestOffBtn)
    chestOffBtn.MouseButton1Click:Connect(function()
        config.autoChest = false
        config.safeAutoChest = false
        bigChestUI.Visible = false
    end)

    -- 自動ファームループ
    task.spawn(function()
        while true do
            pcall(function()
                if not (config.autoChest or config.safeAutoChest or config.autoKill) then task.wait(0.1) return end
                local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not root then task.wait(0.1) return end

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
                                VirtualUser:Button1Down(Vector2.new(0,0))
                            end
                        end
                    else
                        root.CFrame = isChest and target.CFrame or target.CFrame * CFrame.new(0,0,3)
                        if isChest then
                            task.wait(0.1)
                            fireproximityprompt(target:FindFirstChildOfClass("ProximityPrompt") or target.Parent:FindFirstChildOfClass("ProximityPrompt"))
                        else
                            VirtualUser:Button1Down(Vector2.new(0,0))
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
                    local folders = { workspace:FindFirstChild("ActiveNPCs"), workspace:FindFirstChild("boss's"), workspace:FindFirstChild("Map Boss"), workspace:FindFirstChild("Map folder") }
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
            local displayName, espColor = "", Color3.new(1,1,1)
            if target.Name == "Chest_Spawn" then displayName = "📦 Chest"; espColor = Color3.fromRGB(255,215,0)
            elseif target.Name == "LightChest_Spawn" then displayName = "✨ Light Chest"; espColor = Color3.fromRGB(255,255,150)
            elseif target.Name == "DarkChest_Spawn" then displayName = "🌑 Dark Chest"; espColor = Color3.fromRGB(180,50,255)
            elseif target.Name == "RadioactiveChest_Spawn" then displayName = "☢️ Radioactive Chest"; espColor = Color3.fromRGB(50,255,50)
            elseif target.Name == "MachineChest_p" then displayName = "⚙️ Machine Chest"; espColor = Color3.fromRGB(0,200,255)
            else return end
            local attachPart = target:FindFirstChild("Handle") or target:FindFirstChild("MachineChest_p") or target:FindFirstChildWhichIsA("BasePart", true)
            if not attachPart and target:IsA("Model") then
                for i=1,10 do task.wait(0.2); if not target.Parent then return end; attachPart = target:FindFirstChild("Handle") or target:FindFirstChild("MachineChest_p") or target:FindFirstChildWhichIsA("BasePart", true); if attachPart then break end end
            end
            if not attachPart and target:IsA("BasePart") then attachPart = target end
            if not attachPart then return end
            local billboard = Instance.new("BillboardGui"); billboard.Name = "ChestLabel"; billboard.Adornee = attachPart; billboard.Size = UDim2.new(0,200,0,30); billboard.StudsOffset = Vector3.new(0,3,0); billboard.AlwaysOnTop = true
            local label = Instance.new("TextLabel", billboard); label.Size = UDim2.new(1,0,1,0); label.BackgroundTransparency = 1; label.Text = displayName; label.TextColor3 = espColor; label.TextStrokeTransparency = 0; label.Font = Enum.Font.GothamBold; label.TextSize = 14
            billboard.Parent = chestEspFolder
            local conn
            conn = RunService.RenderStepped:Connect(function()
                if not target or not target.Parent or not attachPart or not attachPart.Parent then billboard:Destroy(); conn:Disconnect(); return end
                billboard.Enabled = config.chestEsp
                if config.chestEsp then
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root then label.Text = displayName .. " [" .. math.floor((root.Position - attachPart.Position).Magnitude) .. "m]" end
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
            local displayName, espColor = "", Color3.new(1,1,1)
            if target.Name:match("Chest") or target.Name:match("chest") then return end
            if target.Name == "WeepSoul_P" then displayName = "👻 Weep Soul"; espColor = Color3.fromRGB(150,255,255)
            elseif target.Name:match("_P$") or target.Name:match("_p$") then displayName = "🔹 " .. target.Name:gsub("_[Pp]$", ""); espColor = Color3.fromRGB(200,200,255)
            else return end
            local attachPart = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart", true)
            if not attachPart then return end
            local billboard = Instance.new("BillboardGui"); billboard.Name = "ItemLabel"; billboard.Adornee = attachPart; billboard.Size = UDim2.new(0,200,0,30); billboard.StudsOffset = Vector3.new(0,2,0); billboard.AlwaysOnTop = true
            local label = Instance.new("TextLabel", billboard); label.Size = UDim2.new(1,0,1,0); label.BackgroundTransparency = 1; label.Text = displayName; label.TextColor3 = espColor; label.TextStrokeTransparency = 0; label.Font = Enum.Font.GothamBold; label.TextSize = 12
            billboard.Parent = itemEspFolder
            local conn
            conn = RunService.RenderStepped:Connect(function()
                if not target or not target.Parent or not attachPart or not attachPart.Parent then billboard:Destroy(); conn:Disconnect(); return end
                billboard.Enabled = config.itemEsp
                if config.itemEsp then
                    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root then label.Text = displayName .. " [" .. math.floor((root.Position - attachPart.Position).Magnitude) .. "m]" end
                end
            end)
        end)
    end
    for _, v in pairs(workspace:GetDescendants()) do createItemESP(v) end
    workspace.DescendantAdded:Connect(createItemESP)
else
    MainTab:Section({ Title = "Universal Game" })
    MainTab:Button({ Title = "このゲーム専用機能はありません", Callback = function() end })
end

-- ============================================================
-- プレイヤー機能 (共通)
-- ============================================================
PlayerTab:Section({ Title = "Movement" })

PlayerTab:Toggle({ Title = "VFly", Value = config.vfly, Callback = function(v) config.vfly = v end })
PlayerTab:Slider({ Title = "VFly Speed", Step = 5, Value = { Min = 10, Max = 300, Default = config.vflySpeed }, Callback = function(v) config.vflySpeed = v end })

PlayerTab:Toggle({ Title = "TPFly", Value = config.tpfly, Callback = function(v) config.tpfly = v end })
PlayerTab:Slider({ Title = "TPFly Speed", Step = 1, Value = { Min = 1, Max = 50, Default = config.tpflySpeed }, Callback = function(v) config.tpflySpeed = v end })

PlayerTab:Toggle({
    Title = "Fly (Standard)",
    Value = config.fly,
    Callback = function(v)
        config.fly = v
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            if v then
                flyBodyVelocity = Instance.new("BodyVelocity", root); flyBodyVelocity.MaxForce = Vector3.new(100000,100000,100000); flyBodyVelocity.Velocity = Vector3.zero
                flyBodyGyro = Instance.new("BodyGyro", root); flyBodyGyro.MaxTorque = Vector3.new(100000,100000,100000); flyBodyGyro.P = 9e4
            else
                if flyBodyVelocity then flyBodyVelocity:Destroy() end
                if flyBodyGyro then flyBodyGyro:Destroy() end
            end
        end
    end
})
PlayerTab:Slider({ Title = "Fly Speed", Step = 5, Value = { Min = 10, Max = 300, Default = config.flySpeed }, Callback = function(v) config.flySpeed = v end })

PlayerTab:Toggle({ Title = "Noclip", Value = config.noclip, Callback = function(v) config.noclip = v end })
PlayerTab:Toggle({ Title = "Freeze (Anchored)", Value = config.freeze, Callback = function(v)
    config.freeze = v
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then root.Anchored = v end
end })
PlayerTab:Toggle({ Title = "Anti-Fling (衝突無効)", Value = config.antiFling, Callback = function(v) config.antiFling = v end })
PlayerTab:Toggle({ Title = "SPEED HACK", Value = config.speedHack, Callback = function(v)
    config.speedHack = v
    if not v and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.WalkSpeed = 16 end
end })

-- ============================================================
-- ESP (共通)
-- ============================================================
EspTab:Section({ Title = "Universal ESP" })
EspTab:Toggle({ Title = "PLAYER ESP", Value = config.esp, Callback = function(v) config.esp = v end })

-- ============================================================
-- Misc
-- ============================================================
MiscTab:Section({ Title = "Utility" })
MiscTab:Toggle({ Title = "ANTI AFK", Value = config.antiAFK, Callback = function(v) config.antiAFK = v end })
MiscTab:Button({
    Title = "ANTI LAG (軽量化)",
    Callback = function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and not v:IsA("MeshPart") then v.Material = Enum.Material.SmoothPlastic
            elseif v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then v.Enabled = false end
        end
        Lighting.GlobalShadows = false
    end
})
MiscTab:Toggle({ Title = "REMOVE SHADOWS", Value = config.removeShadows, Callback = function(v) config.removeShadows = v end })
MiscTab:Toggle({ Title = "REMOVE FOG", Value = config.removeFog, Callback = function(v) config.removeFog = v end })
MiscTab:Toggle({ Title = "FULL BRIGHT", Value = config.fullBright, Callback = function(v) config.fullBright = v; if not v then Lighting.Brightness = 1; Lighting.ClockTime = 12 end end })
MiscTab:Toggle({ Title = "STATS HUD", Value = config.showStats, Callback = function(v) config.showStats = v; sF.Visible = v end })

-- ============================================================
-- Scripts
-- ============================================================
ScriptTab:Button({
    Title = "Unstability || Universal",
    Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/ILOVETHECOFFINOFANDYANDLEYLEY/THE-HACK-/main/script%20omg"))()
    end
})

-- ============================================================
-- 共通ループ処理
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
        fL.Text = "FPS: " .. math.floor(1/dt)
        pL.Text = "Ping: " .. math.floor(LocalPlayer:GetNetworkPing() * 1000) .. "ms"
    end

    -- プレイヤーESP
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Head") then
            local tag = p.Character.Head:FindFirstChild("TrollTag") or Instance.new("BillboardGui", p.Character.Head)
            tag.Name = "TrollTag"; tag.AlwaysOnTop = true; tag.Size = UDim2.new(0,100,0,40); tag.Enabled = config.esp
            local lbl = tag:FindFirstChild("Label") or Instance.new("TextLabel", tag)
            lbl.Name = "Label"; lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.TextColor3 = Color3.new(1,1,1); lbl.TextStrokeTransparency = 0
            local hp = p.Character:FindFirstChild("Humanoid") and math.floor(p.Character.Humanoid.Health) or 0
            lbl.Text = p.DisplayName .. "\nHP: " .. hp
        end
    end

    -- Boss ESP更新
    if config.npcEsp and game.PlaceId == 13946738101 then
        local currentList = {}
        for _, obj in pairs(cachedBosses) do
            local head = obj:FindFirstChild("Head") or obj:FindFirstChild("Torso") or obj:FindFirstChild("HumanoidRootPart")
            local hum = obj:FindFirstChild("Humanoid")
            if head and hum and hum.Health > 0 then
                currentList[obj] = true
                local tag = activeBossTags[obj]
                if not tag or not tag.Parent then
                    tag = Instance.new("BillboardGui"); tag.Name = "BossTag"; tag.AlwaysOnTop = true; tag.Size = UDim2.new(0,100,0,40); tag.Adornee = head; tag.Parent = espFolder
                    local lbl = Instance.new("TextLabel", tag); lbl.Name = "Label"; lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.TextColor3 = Color3.fromRGB(255,50,50); lbl.TextStrokeTransparency = 0; lbl.Font = Enum.Font.SourceSansBold
                    activeBossTags[obj] = tag
                end
                local displayName = obj.Name
                local healthBar = head:FindFirstChild("BossHealthBar")
                if healthBar then
                    local bossText = healthBar:FindFirstChild("boss")
                    if bossText and bossText:IsA("TextLabel") and bossText.Text ~= "" then displayName = bossText.Text end
                end
                tag.Label.Text = "[" .. displayName .. "]\nHP: " .. math.floor(hum.Health)
            end
        end
        for obj, tag in pairs(activeBossTags) do
            if not currentList[obj] or not obj.Parent then if tag then tag:Destroy() end; activeBossTags[obj] = nil end
        end
    end

    -- 飛行ロジック
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
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
            if moveDir.Magnitude > 0 then root.Velocity = dir3D * config.vflySpeed else root.Velocity = Vector3.new(0,0.1,0) end
        end
        if config.tpfly then
            if moveDir.Magnitude > 0 then root.CFrame = root.CFrame + (dir3D * (config.tpflySpeed * (dt*60))) end
            root.Velocity = Vector3.zero
        end
        if config.speedHack then hum.WalkSpeed = config.walkSpeed end
    end

    if config.removeShadows then Lighting.GlobalShadows = false end
    if config.removeFog then
        Lighting.FogEnd = 100000; Lighting.FogStart = 0
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if atm then atm.Density = 0 end
    end
    if config.fullBright then Lighting.Brightness = 2; Lighting.ClockTime = 14 end
end)
