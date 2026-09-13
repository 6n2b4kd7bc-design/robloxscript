-- 殺人決闘 バランス調整ミニガン + 飛び回り
-- Obsidian UI版 / CAT HUB 用

local cloneref = cloneref or function(i) return i end
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))

-- ============================================================
-- UI ライブラリ読み込み（Obsidian → Wind UI フォールバック）
-- ============================================================
local Library = nil
local UIMode = "obsidian"

do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()
    end)
    if ok and result then
        Library = result
    else
        UIMode = "wind"
        local ok2, result2 = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end)
        if ok2 and result2 then
            Library = result2
        end
    end
end

if not Library then
    warn("UIライブラリの読み込みに失敗しました。")
    return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- 設定
-- ============================================================
local SETTINGS = {
    AttackMode = "FOV",
    FOV_Degrees = 999,
    MaxDistance = 1000,
    BurstCount = 15,
    BurstInterval = 0.02,
    HeadshotRate = 1,
    TeamCheck = true,
    Wallbang = true,
    ShowESP = true,
    ShowFOVCircle = true,
    FlyAround = true,
    FlyRadius = 150,
    FlyHeight = 150,
    FlySpeed = 300,
}

-- ============================================================
-- キャッシュ
-- ============================================================
local character = LocalPlayer.Character
local characterRoot = character and character:FindFirstChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(newChar)
    character = newChar
    characterRoot = newChar and newChar:FindFirstChild("HumanoidRootPart")
end)

-- ============================================================
-- リモート取得
-- ============================================================
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local shootRemote = remotes and remotes:FindFirstChild("ShootReplicate")
local throwRemote = remotes and remotes:FindFirstChild("ThrowReplicate")
local reportHitRemote = remotes and remotes:FindFirstChild("ReportHit")

if not shootRemote then warn("ShootReplicate が見つかりません（射撃不可）") end
if not throwRemote or not reportHitRemote then warn("ThrowReplicate/ReportHit が見つかりません（ナイフ不可）") end

local shotId = 0
local throwId = 0
local flyAngle = 0

-- ============================================================
-- 武器判定
-- ============================================================
local function getCurrentWeapon()
    if not character then return nil end
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then return tool end
    end
    return nil
end

local function isKnifeEquipped()
    local tool = getCurrentWeapon()
    return tool and (tool.Name:lower():find("knife") or tool.Name:lower():find("ナイフ"))
end

-- ============================================================
-- FOV円
-- ============================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 2
fovCircle.Color = Color3.fromRGB(0, 255, 255)
fovCircle.Transparency = 0.5
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Visible = false

local function updateFOVCircle()
    if not SETTINGS.ShowFOVCircle then
        fovCircle.Visible = false
        return
    end
    local viewSize = Camera.ViewportSize
    local centerX = viewSize.X / 2
    local centerY = viewSize.Y / 2
    fovCircle.Position = Vector2.new(centerX, centerY)
    local camFOV = Camera.FieldOfView
    local radius = math.tan(math.rad(SETTINGS.FOV_Degrees) / 2) * (viewSize.Y / 2) / math.tan(math.rad(camFOV) / 2)
    fovCircle.Radius = math.clamp(radius, 10, viewSize.Y * 0.8)
    fovCircle.Visible = true
end
pcall(updateFOVCircle)

-- ============================================================
-- 敵対判定
-- ============================================================
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not SETTINGS.TeamCheck then return true end
    local myTeam = LocalPlayer.Team
    local mySide = LocalPlayer:GetAttribute("MatchSide")
    local pTeam = player.Team
    local pSide = player:GetAttribute("MatchSide")
    if myTeam and pTeam then return myTeam ~= pTeam end
    if mySide and pSide then return mySide ~= pSide end
    return true
end

-- ============================================================
-- ターゲット検出
-- ============================================================
local function findTarget()
    if not characterRoot then return nil end
    local pos = characterRoot.Position
    local bestTarget = nil
    local bestDist = SETTINGS.MaxDistance + 1

    local charactersFolder = Workspace:FindFirstChild("Characters")
    local playerList = charactersFolder and charactersFolder:GetChildren() or Players:GetPlayers()

    for _, item in ipairs(playerList) do
        local player, char
        if charactersFolder then
            char = item
            if char == character then continue end
            if not char:IsA("Model") then continue end
            player = Players:GetPlayerFromCharacter(char)
            if not player then continue end
        else
            player = item
            if player == LocalPlayer then continue end
            char = player.Character
            if not char then continue end
        end

        if not isEnemy(player) then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        local targetRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not targetRoot or not targetRoot:IsA("BasePart") then continue end

        local targetPos = targetRoot.Position
        local dist = (targetPos - pos).Magnitude
        if dist > SETTINGS.MaxDistance then continue end

        if dist < bestDist then
            bestDist = dist
            local headPart = char:FindFirstChild("Head") or char:FindFirstChild("head") or targetRoot
            local torsoPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or targetRoot
            bestTarget = {
                Model = char,
                Head = headPart,
                Torso = torsoPart,
                Position = targetPos,
                Distance = dist,
                Player = player,
            }
        end
    end

    return bestTarget
end

-- ============================================================
-- ハイライト
-- ============================================================
local currentHighlight = nil
local function highlightTarget(targetModel)
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    if not targetModel then return end
    local highlight = Instance.new("Highlight")
    highlight.Parent = targetModel
    highlight.Adornee = targetModel
    highlight.FillColor = Color3.fromRGB(255, 50, 50)
    highlight.FillTransparency = 0.3
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0.1
    currentHighlight = highlight
end

-- ============================================================
-- バースト射撃・投擲
-- ============================================================
local function sendShootBurst(target, count)
    if not target or not target.Head or not shootRemote then return end
    local origin = characterRoot and characterRoot.Position + Vector3.new(0, 1.5, 0) or Vector3.new(0, 0, 0)
    for i = 1, count do
        shotId = shotId + 1
        local isHeadshot = math.random() < SETTINGS.HeadshotRate
        local targetPart = isHeadshot and target.Head or target.Torso
        local basePos = targetPart.Position
        local dirToTarget = (basePos - origin).Unit
        local hitPos = basePos + dirToTarget * 10
        local data = {
            hitPos = hitPos,
            to = hitPos,
            origin = origin,
            id = shotId,
            hitNormal = Vector3.new(0, 1, 0),
            effects = { Frost = 0, Ricochet = 0, Barrage = 0 },
            hitInstance = targetPart,
            kind = "bullet",
            isCharacterHit = true,
            mode = "single",
            ownerUserId = LocalPlayer.UserId,
            isADS = false
        }
        pcall(function() shootRemote:FireServer(data) end)
    end
end

local function sendKnifeBurst(target, count)
    if not target or not target.Head or not throwRemote or not reportHitRemote then return end
    local origin = characterRoot and characterRoot.Position + Vector3.new(0, 1.5, 0) or Vector3.new(0, 0, 0)
    for i = 1, count do
        throwId = throwId + 1
        local isHeadshot = math.random() < SETTINGS.HeadshotRate
        local targetPart = isHeadshot and target.Head or target.Torso
        local basePos = targetPart.Position
        local dirToTarget = (basePos - origin).Unit
        local hitPos = basePos + dirToTarget * 10
        local throwData = {
            toolName = "Knife",
            id = throwId,
            ownerUserId = LocalPlayer.UserId,
            origin = origin,
            isExplosive = false,
            power = 1,
            target = hitPos,
            effects = { Shotgun = 0, Portal = 0, Smoke = 0, Explosive = 0, Flammable = 0 }
        }
        local vel = (hitPos - origin).Unit * 400
        local reportData = {
            hitPos = hitPos,
            ownerUserId = LocalPlayer.UserId,
            origin = origin,
            vel = vel,
            headshot = isHeadshot,
            targetUserId = target.Player and target.Player.UserId or 0,
            targetModel = target.Model,
            to = hitPos + Vector3.new(0, 0.5, 0),
            throwId = throwId,
            kind = "throw",
            at = 0.5,
            hitPart = targetPart,
        }
        pcall(function()
            throwRemote:FireServer(throwData)
            reportHitRemote:FireServer(reportData)
        end)
    end
end

local function sendBurst(target)
    if not target then return end
    local count = math.max(1, SETTINGS.BurstCount or 12)
    if isKnifeEquipped() then
        sendKnifeBurst(target, count)
    else
        sendShootBurst(target, count)
    end
end

-- ============================================================
-- ESP
-- ============================================================
local function createESP(player)
    if player == LocalPlayer or not SETTINGS.ShowESP then return end
    local function setupCharacter(char)
        local head = char:FindFirstChild("Head")
        if not head then return end
        if char:FindFirstChild("PlayerESP_Box") then return end
        local isEnemyFlag = isEnemy(player)
        local outlineColor = isEnemyFlag and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 150, 255)
        if not SETTINGS.TeamCheck then outlineColor = Color3.fromRGB(255, 255, 255) end
        local hl = Instance.new("Highlight")
        hl.Name = "PlayerESP_Box"
        hl.Adornee = char
        hl.FillTransparency = 1
        hl.OutlineColor = outlineColor
        hl.OutlineTransparency = 0
        hl.Parent = char
        local bill = Instance.new("BillboardGui")
        bill.Name = "PlayerESP_Label"
        bill.AlwaysOnTop = true
        bill.Size = UDim2.new(0, 150, 0, 30)
        bill.StudsOffset = Vector3.new(0, 2.5, 0)
        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.Text = player.Name .. (isEnemyFlag and " ⚔️" or " 🤝")
        txt.TextColor3 = isEnemyFlag and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(50, 200, 255)
        txt.TextStrokeTransparency = 0
        txt.TextSize = 14
        txt.Font = Enum.Font.SourceSansBold
        txt.Parent = bill
        bill.Parent = head
    end
    if player.Character then task.spawn(setupCharacter, player.Character) end
    player.CharacterAdded:Connect(setupCharacter)
end

if SETTINGS.ShowESP then
    for _, p in ipairs(Players:GetPlayers()) do createESP(p) end
    Players.PlayerAdded:Connect(createESP)
end

-- ============================================================
-- 飛び回り
-- ============================================================
local function updateFly(targetPos, delta)
    if not SETTINGS.FlyAround then return end
    if not characterRoot then return end
    flyAngle = flyAngle + SETTINGS.FlySpeed * delta
    local radius = SETTINGS.FlyRadius
    local height = SETTINGS.FlyHeight
    local xOff = math.cos(flyAngle) * radius
    local zOff = math.sin(flyAngle) * radius
    local newPos = targetPos + Vector3.new(xOff, height, zOff)
    if newPos.Y < 0 then newPos = Vector3.new(newPos.X, 1, newPos.Z) end
    characterRoot.CFrame = CFrame.new(newPos) * CFrame.Angles(0, -flyAngle, 0)
end

-- ============================================================
-- メインループ
-- ============================================================
local lastBurstTime = 0
RunService.RenderStepped:Connect(function(delta)
    pcall(updateFOVCircle)
    local target = findTarget()
    if target then
        highlightTarget(target.Model)
        pcall(updateFly, target.Position, delta)
        if tick() - lastBurstTime >= SETTINGS.BurstInterval then
            sendBurst(target)
            lastBurstTime = tick()
        end
    else
        if currentHighlight then
            currentHighlight:Destroy()
            currentHighlight = nil
        end
    end
end)

-- ============================================================
-- UI 構築（Obsidian 優先）
-- ============================================================
if UIMode == "obsidian" then
    -- ===== Obsidian =====
    local Window = Library:CreateWindow({
        Title = "CAT HUB - Killing Duel",
        Footer = "CAT HUB",
        AutoShow = true,
        NotifySide = "Right",
    })

    local MainTab = Window:AddTab("メイン")
    local SettingTab = Window:AddTab("詳細設定")

    -- --- メインタブ ---
    local AttackGroup = MainTab:AddLeftGroupbox("攻撃設定")

    AttackGroup:AddToggle("FlyAround", {
        Text = "飛び回り",
        Default = SETTINGS.FlyAround,
        Callback = function(v) SETTINGS.FlyAround = v end,
    })

    AttackGroup:AddToggle("ShowESP", {
        Text = "ESP表示",
        Default = SETTINGS.ShowESP,
        Callback = function(v) SETTINGS.ShowESP = v end,
    })

    AttackGroup:AddToggle("TeamCheck", {
        Text = "チームキル防止",
        Default = SETTINGS.TeamCheck,
        Callback = function(v) SETTINGS.TeamCheck = v end,
    })

    AttackGroup:AddToggle("Wallbang", {
        Text = "壁貫通",
        Default = SETTINGS.Wallbang,
        Callback = function(v) SETTINGS.Wallbang = v end,
    })

    AttackGroup:AddToggle("ShowFOVCircle", {
        Text = "FOV円表示",
        Default = SETTINGS.ShowFOVCircle,
        Callback = function(v) SETTINGS.ShowFOVCircle = v end,
    })

    local AttackGroupR = MainTab:AddRightGroupbox("エイムモード")

    AttackGroupR:AddDropdown("AttackMode", {
        Text = "モード",
        Values = { "FOV", "Nearest" },
        Default = SETTINGS.AttackMode,
        Callback = function(v) SETTINGS.AttackMode = v end,
    })

    -- --- 詳細設定タブ ---
    local FlyGroup = SettingTab:AddLeftGroupbox("飛び回り設定")

    FlyGroup:AddSlider("FlyRadius", {
        Text = "回転半径",
        Default = SETTINGS.FlyRadius,
        Min = 0,
        Max = 300,
        Rounding = 0,
        Callback = function(v) SETTINGS.FlyRadius = v end,
    })

    FlyGroup:AddSlider("FlyHeight", {
        Text = "回転高さ",
        Default = SETTINGS.FlyHeight,
        Min = 0,
        Max = 300,
        Rounding = 0,
        Callback = function(v) SETTINGS.FlyHeight = v end,
    })

    FlyGroup:AddSlider("FlySpeed", {
        Text = "回転速度",
        Default = SETTINGS.FlySpeed,
        Min = 0,
        Max = 500,
        Rounding = 0,
        Callback = function(v) SETTINGS.FlySpeed = v end,
    })

    local AttackDetail = SettingTab:AddRightGroupbox("攻撃詳細設定")

    AttackDetail:AddSlider("BurstCount", {
        Text = "バースト数",
        Default = SETTINGS.BurstCount,
        Min = 1,
        Max = 50,
        Rounding = 0,
        Callback = function(v) SETTINGS.BurstCount = v end,
    })

    AttackDetail:AddSlider("BurstInterval", {
        Text = "バースト間隔 (秒)",
        Default = SETTINGS.BurstInterval,
        Min = 0.01,
        Max = 0.5,
        Rounding = 2,
        Callback = function(v) SETTINGS.BurstInterval = v end,
    })

    AttackDetail:AddSlider("HeadshotRate", {
        Text = "ヘッドショット率",
        Default = SETTINGS.HeadshotRate,
        Min = 0,
        Max = 1,
        Rounding = 2,
        Callback = function(v) SETTINGS.HeadshotRate = v end,
    })

    AttackDetail:AddSlider("FOVDegrees", {
        Text = "FOV範囲 (度)",
        Default = SETTINGS.FOV_Degrees,
        Min = 0,
        Max = 360,
        Rounding = 0,
        Callback = function(v) SETTINGS.FOV_Degrees = v end,
    })

    AttackDetail:AddSlider("MaxDistance", {
        Text = "最大距離",
        Default = SETTINGS.MaxDistance,
        Min = 50,
        Max = 2000,
        Rounding = 0,
        Callback = function(v) SETTINGS.MaxDistance = v end,
    })

    print("✅ Obsidian UI 読み込み完了（CAT HUB / 殺人決闘）")

else
    -- ===== Wind UI フォールバック =====
    local WindUI = Library
    local Window = WindUI:CreateWindow({
        Title = "CAT HUB - Killing Duel",
        Icon = "solar:sword-bold",
        NewElements = true,
        HideSearchBar = true,
        OpenButton = {
            Title = "CAT HUB",
            CornerRadius = UDim.new(1, 0),
            StrokeThickness = 2,
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.6,
            Color = ColorSequence.new(Color3.fromHex("#FF69B4"), Color3.fromHex("#FFB6C1"))
        },
        Topbar = { Height = 44, ButtonsType = "Mac" }
    })

    local MainTab = Window:Tab({ Title = "メイン", Icon = "solar:home-2-bold" })
    local SettingTab = Window:Tab({ Title = "詳細設定", Icon = "solar:settings-bold" })

    local AttackSection = MainTab:Section({ Title = "攻撃設定" })
    AttackSection:Toggle({ Title = "飛び回り", Value = SETTINGS.FlyAround, Callback = function(v) SETTINGS.FlyAround = v end })
    AttackSection:Toggle({ Title = "ESP表示", Value = SETTINGS.ShowESP, Callback = function(v) SETTINGS.ShowESP = v end })
    AttackSection:Toggle({ Title = "チームキル防止", Value = SETTINGS.TeamCheck, Callback = function(v) SETTINGS.TeamCheck = v end })
    AttackSection:Toggle({ Title = "壁貫通", Value = SETTINGS.Wallbang, Callback = function(v) SETTINGS.Wallbang = v end })
    AttackSection:Toggle({ Title = "FOV円表示", Value = SETTINGS.ShowFOVCircle, Callback = function(v) SETTINGS.ShowFOVCircle = v end })
    AttackSection:Dropdown({
        Title = "エイムモード",
        Values = { "FOV", "Nearest" },
        Value = SETTINGS.AttackMode,
        Callback = function(v) SETTINGS.AttackMode = v end
    })

    local FlySection = SettingTab:Section({ Title = "飛び回り設定" })
    FlySection:Slider({ Title = "回転半径", Step = 1, Value = { Min = 0, Max = 300, Default = SETTINGS.FlyRadius }, Callback = function(v) SETTINGS.FlyRadius = v end })
    FlySection:Slider({ Title = "回転高さ", Step = 1, Value = { Min = 0, Max = 300, Default = SETTINGS.FlyHeight }, Callback = function(v) SETTINGS.FlyHeight = v end })
    FlySection:Slider({ Title = "回転速度", Step = 1, Value = { Min = 0, Max = 500, Default = SETTINGS.FlySpeed }, Callback = function(v) SETTINGS.FlySpeed = v end })

    local AttackDetail = SettingTab:Section({ Title = "攻撃詳細設定" })
    AttackDetail:Slider({ Title = "バースト数", Step = 1, Value = { Min = 1, Max = 50, Default = SETTINGS.BurstCount }, Callback = function(v) SETTINGS.BurstCount = v end })
    AttackDetail:Slider({ Title = "バースト間隔 (秒)", Step = 0.01, Value = { Min = 0.01, Max = 0.5, Default = SETTINGS.BurstInterval }, Callback = function(v) SETTINGS.BurstInterval = v end })
    AttackDetail:Slider({ Title = "ヘッドショット率", Step = 0.05, Value = { Min = 0, Max = 1, Default = SETTINGS.HeadshotRate }, Callback = function(v) SETTINGS.HeadshotRate = v end })
    AttackDetail:Slider({ Title = "FOV範囲 (度)", Step = 1, Value = { Min = 0, Max = 360, Default = SETTINGS.FOV_Degrees }, Callback = function(v) SETTINGS.FOV_Degrees = v end })
    AttackDetail:Slider({ Title = "最大距離", Step = 10, Value = { Min = 50, Max = 2000, Default = SETTINGS.MaxDistance }, Callback = function(v) SETTINGS.MaxDistance = v end })

    print("✅ Wind UI 読み込み完了（フォールバック）")
end
