-- ============================================================
-- Rayfield UI 統合版: Static Gun 専用 サイレントエイム + サウンド + ESP + 射撃ボタン
-- Delta Executor 対応 / 主様専用
-- ============================================================

-- Rayfield UI の読み込み
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

-- ============================================================
-- ★★★ 設定・ステート変数 ★★★
-- ============================================================
local SCAN_INTERVAL = 0.15
local FOV_RADIUS = 80
local MAX_DIST = 999
local PROXIMITY_THRESHOLD = 5
local GUN_NAME = "Gun"

local SOUND_IDS = {
    Kill = "rbxassetid://112320102716623",
    Shot = "rbxassetid://132673746791429",
}

local ESP_Enabled = true

-- キャッシュ
local currentTarget = nil
local lastScan = 0
local ShootRemote = nil
local LockRemote = nil
local character = nil
local humanoid = nil
local gun = nil

-- 射撃関数用プレースホルダー
local FireGun = nil

-- ============================================================
-- ★★★ 武器検索（強化版） ★★★
-- ============================================================
local function FindGun()
    if character then
        local equipped = character:FindFirstChild(GUN_NAME)
        if equipped then return equipped end
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        local inBackpack = backpack:FindFirstChild(GUN_NAME)
        if inBackpack then return inBackpack end
    end
    local starterGear = LocalPlayer:FindFirstChild("StarterGear")
    if starterGear then
        local inStarter = starterGear:FindFirstChild(GUN_NAME)
        if inStarter then return inStarter end
    end
    local function searchWorkspace(obj)
        for _, child in ipairs(obj:GetChildren()) do
            if child.Name == GUN_NAME and child:IsA("Tool") then
                return child
            end
            if child:IsA("Model") or child:IsA("Folder") then
                local found = searchWorkspace(child)
                if found then return found end
            end
        end
        return nil
    end
    return searchWorkspace(workspace)
end

-- ============================================================
-- ★★★ GUI 射撃ボタン作成 ★★★
-- ============================================================
local fireButtonGui = nil
local function createFireButton()
    if fireButtonGui then return end
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "CustomFireButton"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true

    local parent = nil
    if gethui then
        parent = gethui()
    else
        local success, result = pcall(function() return game:GetService("CoreGui") end)
        if success and result then
            parent = result
        else
            parent = LocalPlayer:WaitForChild("PlayerGui")
        end
    end
    gui.Parent = parent
    fireButtonGui = gui

    local button = Instance.new("ImageButton")
    button.Name = "FireButton"
    button.Size = UDim2.new(0, 120, 0, 120)
    button.Position = UDim2.new(1, -140, 0.5, -60)
    button.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    button.BackgroundTransparency = 0.3
    button.Image = "rbxassetid://0"
    button.AutoButtonColor = true
    button.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button

    local label = Instance.new("TextLabel")
    label.Text = "🔥"
    label.TextSize = 40
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.TextScaled = true
    label.Font = Enum.Font.SourceSansBold
    label.Parent = button

    button.MouseButton1Click:Connect(function()
        if FireGun then FireGun() end
    end)

    button.TouchTap:Connect(function()
        if FireGun then FireGun() end
    end)

    print("✅ 右側射撃ボタン作成完了")
end

local function removeFireButton()
    if fireButtonGui then
        fireButtonGui:Destroy()
        fireButtonGui = nil
    end
end

-- ============================================================
-- ★★★ 味方判定 ★★★
-- ============================================================
local function IsProximity(targetPart)
    if not character then return false end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    return (targetPart.Position - root.Position).Magnitude <= PROXIMITY_THRESHOLD
end

-- ============================================================
-- ★★★ サウンド変更 ★★★
-- ============================================================
local function changeSoundRecursive(container, soundName, newId, depth)
    if depth and depth > 10 then return end
    depth = depth or 0
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Sound") and child.Name == soundName then
            if child.SoundId ~= newId then
                child.SoundId = newId
                pcall(function()
                    child:Stop()
                    child:Play()
                end)
            end
            return
        end
        if child:IsA("Model") or child:IsA("Folder") or child:IsA("Tool") or child:IsA("Part") then
            changeSoundRecursive(child, soundName, newId, depth + 1)
        end
    end
end

local function changeAllSounds()
    if not gun then
        gun = FindGun()
        if not gun then return end
    end
    local handle = gun:FindFirstChild("Handle")
    if handle then
        for name, id in pairs(SOUND_IDS) do
            changeSoundRecursive(handle, name, id)
        end
    else
        for name, id in pairs(SOUND_IDS) do
            changeSoundRecursive(gun, name, id)
        end
    end
end

-- ============================================================
-- ★★★ リモート取得 ★★★
-- ============================================================
local function GetRemotes()
    if not gun then
        gun = FindGun()
        if not gun then
            task.delay(1, GetRemotes)
            return
        end
    end
    if gun and gun.Parent ~= character and humanoid then
        humanoid:EquipTool(gun)
        task.wait(0.5)
    end
    local gunServer = gun:FindFirstChild("GunServer")
    if not gunServer then return end
    ShootRemote = gunServer:FindFirstChild("ShootStart")
    LockRemote = gunServer:FindFirstChild("Lock")
    changeAllSounds()
end

-- ============================================================
-- ★★★ ターゲットスキャン ★★★
-- ============================================================
local function ScanTarget()
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local origin = root.Position
    local center = Camera.ViewportSize / 2
    local best = nil
    local bestDist = FOV_RADIUS

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local pchar = player.Character
        if not pchar then continue end
        local hum = pchar:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local target = pchar:FindFirstChild("Head") or pchar:FindFirstChild("UpperTorso") or pchar:FindFirstChild("HumanoidRootPart")
        if not target then continue end
        if IsProximity(target) then continue end
        local dist = (target.Position - origin).Magnitude
        if dist > MAX_DIST then continue end
        local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
        if not onScreen then continue end
        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
        if screenDist < bestDist then
            bestDist = screenDist
            best = target
        end
    end
    return best
end

RunService.Heartbeat:Connect(function()
    if tick() - lastScan >= SCAN_INTERVAL then
        currentTarget = ScanTarget()
        lastScan = tick()
    end
end)

-- ============================================================
-- ★★★ 射撃関数 ★★★
-- ============================================================
function FireGun()
    if not ShootRemote or not currentTarget then return end
    if LockRemote then pcall(function() LockRemote:FireServer(9999) end) end
    pcall(function()
        ShootRemote:FireServer(currentTarget.Position, currentTarget)
    end)
end

-- ============================================================
-- ★★★ リスポーン監視 ★★★
-- ============================================================
local function onCharacterAdded(newChar)
    character = newChar
    humanoid = character:FindFirstChild("Humanoid")
    gun = nil
    currentTarget = nil
    lastScan = 0
    task.wait(1.0)
    gun = FindGun()
    if not gun then
        task.wait(1.0)
        gun = FindGun()
    end
    if gun and humanoid then
        humanoid:EquipTool(gun)
        task.wait(0.5)
    end
    GetRemotes()
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
end

-- ============================================================
-- ★★★ ESPシステム ★★★
-- ============================================================
local function getParent()
    if gethui then return gethui() end
    local success, result = pcall(function() return game:GetService("CoreGui") end)
    if success and result then return result end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local espGui = Instance.new("ScreenGui")
espGui.Name = "CustomGUI_ESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.Parent = getParent()

local espObjects = {}

local function createEspForPlayer(player)
    local objects = {}
    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.Parent = espGui
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 0, 0)
    stroke.Thickness = 1.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = box
    objects.Box = box

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.TextSize = 14
    label.Font = Enum.Font.SourceSansBold
    label.Visible = false
    label.Parent = espGui
    objects.Label = label

    local tracer = Instance.new("Frame")
    tracer.BackgroundColor3 = Color3.new(1, 0, 0)
    tracer.BorderSizePixel = 0
    tracer.AnchorPoint = Vector2.new(0.5, 0.5)
    tracer.Visible = false
    tracer.Parent = espGui
    objects.Tracer = tracer

    espObjects[player] = objects
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        createEspForPlayer(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        createEspForPlayer(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if espObjects[player] then
        for _, obj in pairs(espObjects[player]) do
            obj:Destroy()
        end
        espObjects[player] = nil
    end
end)

RunService.RenderStepped:Connect(function()
    for player, objects in pairs(espObjects) do
        local char = player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if ESP_Enabled and char and humanoid and humanoid.Health > 0 and hrp then
            local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            if onScreen then
                local headPos = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                local legPos = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.5, 0))
                local height = math.abs(headPos.Y - legPos.Y)
                local width = height / 1.5
                objects.Box.Size = UDim2.new(0, width, 0, height)
                objects.Box.Position = UDim2.new(0, pos.X - (width / 2), 0, pos.Y - (height / 2))
                objects.Box.Visible = true

                local dist = math.floor((Camera.CFrame.Position - hrp.Position).Magnitude)
                objects.Label.Text = string.format("%s\n%dHP | %dm", player.Name, humanoid.Health, dist)
                objects.Label.Size = UDim2.new(0, 100, 0, 30)
                objects.Label.Position = UDim2.new(0, pos.X - 50, 0, pos.Y - (height / 2) - 35)
                objects.Label.Visible = true

                local screenX, screenY = Camera.ViewportSize.X, Camera.ViewportSize.Y
                local startPos = Vector2.new(screenX / 2, screenY)
                local endPos = Vector2.new(pos.X, pos.Y)
                local distance = (endPos - startPos).Magnitude
                local center = (startPos + endPos) / 2
                local angle = math.atan2(endPos.Y - startPos.Y, endPos.X - startPos.X)
                objects.Tracer.Size = UDim2.new(0, distance, 0, 1.5)
                objects.Tracer.Position = UDim2.new(0, center.X, 0, center.Y)
                objects.Tracer.Rotation = math.deg(angle)
                objects.Tracer.Visible = true
            else
                objects.Box.Visible = false
                objects.Label.Visible = false
                objects.Tracer.Visible = false
            end
        else
            objects.Box.Visible = false
            objects.Label.Visible = false
            objects.Tracer.Visible = false
        end
    end
end)

-- ============================================================
-- ★★★ Rayfield UI の構築 ★★★
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = "Static Gun Hub | 主様 専用",
    LoadingTitle = "Static Gun Script",
    LoadingSubtitle = "by Delta Executor",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "StaticGunConfig",
        FileName = "Config"
    },
    KeySystem = false,
})

-- タブの作成
local CombatTab = Window:CreateTab("Combat (Silent Aim)", 4483362458)
local VisualsTab = Window:CreateTab("Visuals (ESP)", 4483362458)
local SettingsTab = Window:CreateTab("Settings / UI", 4483362458)

-- --- Combat Tab ---
CombatTab:CreateSection("Silent Aim Settings")

CombatTab:CreateSlider({
    Name = "FOV Radius",
    Range = {100, 1500},
    Increment = 5,
    CurrentValue = FOV_RADIUS,
    Flag = "FOV_Radius",
    Callback = function(Value)
        FOV_RADIUS = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Max Distance",
    Range = {50, 1000},
    Increment = 10,
    CurrentValue = MAX_DIST,
    Flag = "Max_Dist",
    Callback = function(Value)
        MAX_DIST = Value
    end,
})

CombatTab:CreateButton({
    Name = "今すぐ武器 & リモートを再取得",
    Callback = function()
        GetRemotes()
        Rayfield:Notify({
            Title = "リロード完了",
            Content = "Static Gun のリモートを再スキャンしました。",
            Duration = 3,
        })
    end,
})

-- --- Visuals Tab ---
VisualsTab:CreateSection("ESP Settings")

VisualsTab:CreateToggle({
    Name = "ESP 有効化 (Box / Name / Tracer)",
    CurrentValue = true,
    Flag = "ESP_Toggle",
    Callback = function(Value)
        ESP_Enabled = Value
    end,
})

-- --- Settings Tab ---
SettingsTab:CreateSection("Mobile Controls")

SettingsTab:CreateToggle({
    Name = "画面右側の射撃ボタン表示",
    CurrentValue = true,
    Flag = "FireButton_Toggle",
    Callback = function(Value)
        if Value then
            createFireButton()
        else
            removeFireButton()
        end
    end,
})

SettingsTab:CreateButton({
    Name = "サウンドを強制適用 (Kill/Shot)",
    Callback = function()
        changeAllSounds()
        Rayfield:Notify({
            Title = "サウンド変更",
            Content = "サウンドIDを再適用しました。",
            Duration = 3,
        })
    end,
})

-- 初回起動時にボタンを作成
createFireButton()

Rayfield:Notify({
    Title = "Static Gun Hub 起動成功",
    Content = "すべての機能がRayfield UIに統合されました。",
    Duration = 5,
})
