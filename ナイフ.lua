-- 殺人決闘 バランス調整ミニガン（スパム回避） + 飛び回り（Orion UI版／モバイル最適化）
-- Delta Executor 対応 / 主様専用

-- ★ 既存の競合スクリプトを停止
for _, v in pairs(getconnections(game:GetService("RunService").RenderStepped)) do
    if v.Function and string.find(debug.getinfo(v.Function).source or "", "Noob") then
        v:Disable()
    end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ★ キャッシュ
local character = LocalPlayer.Character
local characterRoot = character and character:FindFirstChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(newChar)
    character = newChar
    characterRoot = newChar and newChar:FindFirstChild("HumanoidRootPart")
end)

-- ============================================================
-- ★★★ マッチングキャンセル・ブロック 自動無効化 ★★★
-- ============================================================
local blockedRemotes = {}
local function autoBlockCancellers()
    print("🔍 マッチングキャンセル/ブロックリモートをスキャン中...")
    local function processObject(obj)
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name = obj.Name:lower()
            local keywords = {"cancel", "leave", "abort", "stop", "unqueue", "block", "ban", "kick"}
            local shouldBlock = false
            for _, kw in ipairs(keywords) do
                if name:find(kw) then shouldBlock = true; break end
            end
            if shouldBlock and not blockedRemotes[obj] then
                blockedRemotes[obj] = true
                pcall(function()
                    if obj:IsA("RemoteEvent") then
                        local oldFire = obj.FireServer
                        if oldFire then
                            obj.FireServer = function(self, ...) return end
                        end
                    elseif obj:IsA("RemoteFunction") then
                        local oldInvoke = obj.InvokeServer
                        if oldInvoke then
                            obj.InvokeServer = function(self, ...) return nil end
                        end
                    end
                end)
            end
        end
        for _, child in ipairs(obj:GetChildren()) do processObject(child) end
    end
    processObject(ReplicatedStorage)
    print("✅ キャンセル/ブロックリモートの無効化完了（", #blockedRemotes, "個）")
end
autoBlockCancellers()

-- ============================================================
-- ★★★ 設定（スパム回避済み） ★★★
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
    AutoMatchmaking = true,
    MatchmakingModes = {"1v1", "2v2", "3v3", "4v4"},
    MatchmakingRetryInterval = 3,
    FlyAround = true,
    FlyRadius = 150,
    FlyHeight = 150,
    FlySpeed = 300,
}
SETTINGS.Wallbang = true

-- ============================================================
-- ★★★ リモート取得 ★★★
-- ============================================================
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local shootRemote = remotes and remotes:FindFirstChild("ShootReplicate")
local throwRemote = remotes and remotes:FindFirstChild("ThrowReplicate")
local reportHitRemote = remotes and remotes:FindFirstChild("ReportHit")

local matchmakingShared = ReplicatedStorage:FindFirstChild("MatchmakingShared")
local queueModes = matchmakingShared and matchmakingShared:FindFirstChild("Remotes") and 
                   matchmakingShared.Remotes:FindFirstChild("QueueModes")

if not shootRemote then warn("ShootReplicate が見つかりません（射撃不可）") end
if not throwRemote or not reportHitRemote then warn("ThrowReplicate/ReportHit が見つかりません（ナイフ不可）") end
if not queueModes then warn("QueueModes が見つかりません。強制マッチング機能は無効です") end

local shotId = 0
local throwId = 0
local lastTarget = nil
local isMatchmaking = false
local flyAngle = 0

-- ============================================================
-- ★★★ 武器判定 ★★★
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
-- ★★★ 強制マッチング ★★★
-- ============================================================
local function forceMatchmaking()
    if not queueModes or isMatchmaking then return end
    isMatchmaking = true
    print("🔄 強制マッチング開始...")
    local success, result = pcall(function()
        return queueModes:InvokeServer(SETTINGS.MatchmakingModes)
    end)
    if success then
        print("✅ マッチングキューイング成功:", result)
    else
        print("❌ マッチングキューイング失敗:", result)
        isMatchmaking = false
        task.delay(1, function()
            isMatchmaking = false
            if SETTINGS.AutoMatchmaking then forceMatchmaking() end
        end)
    end
end

if LocalPlayer then
    LocalPlayer:GetAttributeChangedSignal("LobbySpectateMatchId"):Connect(function()
        local id = LocalPlayer:GetAttribute("LobbySpectateMatchId")
        if (not id or id == "") then
            isMatchmaking = false
            if SETTINGS.AutoMatchmaking then task.wait(0.5); forceMatchmaking() end
        else
            isMatchmaking = true
        end
    end)
end

task.spawn(function()
    while SETTINGS.AutoMatchmaking do
        task.wait(SETTINGS.MatchmakingRetryInterval)
        local lobby = LocalPlayer:GetAttribute("LobbySpectateMatchId")
        if (not lobby or lobby == "") and not isMatchmaking then
            forceMatchmaking()
        end
    end
end)

if SETTINGS.AutoMatchmaking and queueModes then
    task.wait(1.5)
    forceMatchmaking()
end

-- ============================================================
-- ★★★ FOV円 ★★★
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
-- ★★★ 敵対判定 ★★★
-- ============================================================
local myTeam = LocalPlayer.Team
local mySide = LocalPlayer:GetAttribute("MatchSide")

local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not SETTINGS.TeamCheck then return true end
    local pTeam = player.Team
    local pSide = player:GetAttribute("MatchSide")
    if myTeam and pTeam then return myTeam ~= pTeam end
    if mySide and pSide then return mySide ~= pSide end
    return true
end

-- ============================================================
-- ★★★ ターゲット検出（全方位） ★★★
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
                Name = player.Name,
                Player = player,
            }
        end
    end

    return bestTarget
end

-- ============================================================
-- ★★★ ハイライト ★★★
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
-- ★★★ バースト射撃 ★★★
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

-- ============================================================
-- ★★★ バースト投擲 ★★★
-- ============================================================
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

-- ============================================================
-- ★★★ 統合バースト ★★★
-- ============================================================
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
-- ★★★ ESP（Orion UIの設定と連動） ★★★
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
-- ★★★ 高速飛び回り ★★★
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
-- ★★★ メインループ（間隔制御付き） ★★★
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
        lastTarget = nil
    end
end)

print("✅ バランス調整ミニガン + 飛び回り 起動（スパム回避）")
print("📌 バースト数: " .. SETTINGS.BurstCount .. "発/回")
print("📌 バースト間隔: " .. SETTINGS.BurstInterval .. "秒（約" .. math.floor(1 / SETTINGS.BurstInterval) .. "バースト/秒）")
print("📌 飛び回り: " .. (SETTINGS.FlyAround and "ON" or "OFF"))

-- ============================================================
-- ★★★ Orion UI（新しいURL対応版／モバイル最適化） ★★★
-- ============================================================
local function loadOrion()
    local OrionLib = nil
    local success, err = pcall(function()
        -- ★ ここが修正ポイント（新しい有効なURLに差し替え）
        OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/jadpy/suki/refs/heads/main/orion"))()
    end)
    if not success or not OrionLib then
        warn("Orion読み込み失敗: " .. tostring(err))
        return
    end

    -- 既存のOrionウィンドウがあれば削除
    if OrionLib and OrionLib.Unload then
        OrionLib.Unload()
    end

    local Window = OrionLib:MakeWindow({
        Name = "⚙️ ミニガン設定",
        HidePremium = true,
        SaveConfig = false,
        IntroEnabled = false,
        ConfigFolder = "MiniGunSettings"
    })

    -- メインタブ
    local MainTab = Window:MakeTab({
        Name = "メイン",
        Icon = "rbxassetid://4483345998"
    })

    local SettingTab = Window:MakeTab({
        Name = "詳細設定",
        Icon = "rbxassetid://6031095904"
    })

    -- メインタブのセクション
    local AttackSection = MainTab:AddSection({
        Name = "攻撃設定"
    })

    AttackSection:AddToggle({
        Name = "🛸 飛び回り",
        Default = SETTINGS.FlyAround,
        Callback = function(Value)
            SETTINGS.FlyAround = Value
        end
    })

    AttackSection:AddToggle({
        Name = "👁️ ESP表示",
        Default = SETTINGS.ShowESP,
        Callback = function(Value)
            SETTINGS.ShowESP = Value
        end
    })

    AttackSection:AddToggle({
        Name = "🛡️ チームキル防止",
        Default = SETTINGS.TeamCheck,
        Callback = function(Value)
            SETTINGS.TeamCheck = Value
        end
    })

    AttackSection:AddToggle({
        Name = "🧱 壁貫通",
        Default = SETTINGS.Wallbang,
        Callback = function(Value)
            SETTINGS.Wallbang = Value
        end
    })

    AttackSection:AddToggle({
        Name = "⭕ FOV円表示",
        Default = SETTINGS.ShowFOVCircle,
        Callback = function(Value)
            SETTINGS.ShowFOVCircle = Value
        end
    })

    AttackSection:AddToggle({
        Name = "🎮 自動マッチング",
        Default = SETTINGS.AutoMatchmaking,
        Callback = function(Value)
            SETTINGS.AutoMatchmaking = Value
        end
    })

    AttackSection:AddDropdown({
        Name = "🎯 エイムモード",
        Options = {"FOV", "Nearest"},
        Default = SETTINGS.AttackMode,
        Callback = function(Value)
            SETTINGS.AttackMode = Value
        end
    })

    -- 詳細設定タブ
    local FlySection = SettingTab:AddSection({
        Name = "飛び回り設定"
    })

    FlySection:AddSlider({
        Name = "回転半径",
        Min = 0,
        Max = 300,
        Default = SETTINGS.FlyRadius,
        Increment = 1,
        Callback = function(Value)
            SETTINGS.FlyRadius = Value
        end
    })

    FlySection:AddSlider({
        Name = "回転高さ",
        Min = 0,
        Max = 300,
        Default = SETTINGS.FlyHeight,
        Increment = 1,
        Callback = function(Value)
            SETTINGS.FlyHeight = Value
        end
    })

    FlySection:AddSlider({
        Name = "回転速度",
        Min = 0,
        Max = 500,
        Default = SETTINGS.FlySpeed,
        Increment = 1,
        Callback = function(Value)
            SETTINGS.FlySpeed = Value
        end
    })

    local AttackDetail = SettingTab:AddSection({
        Name = "攻撃詳細設定"
    })

    AttackDetail:AddSlider({
        Name = "バースト数",
        Min = 1,
        Max = 50,
        Default = SETTINGS.BurstCount,
        Increment = 1,
        Callback = function(Value)
            SETTINGS.BurstCount = Value
        end
    })

    AttackDetail:AddSlider({
        Name = "バースト間隔 (秒)",
        Min = 0.01,
        Max = 0.5,
        Default = SETTINGS.BurstInterval,
        Increment = 0.01,
        Callback = function(Value)
            SETTINGS.BurstInterval = Value
        end
    })

    AttackDetail:AddSlider({
        Name = "ヘッドショット率 (0.0~1.0)",
        Min = 0,
        Max = 1,
        Default = SETTINGS.HeadshotRate,
        Increment = 0.05,
        Callback = function(Value)
            SETTINGS.HeadshotRate = Value
        end
    })

    AttackDetail:AddSlider({
        Name = "FOV範囲 (度)",
        Min = 0,
        Max = 360,
        Default = SETTINGS.FOV_Degrees,
        Increment = 1,
        Callback = function(Value)
            SETTINGS.FOV_Degrees = Value
        end
    })

    AttackDetail:AddSlider({
        Name = "最大距離",
        Min = 50,
        Max = 2000,
        Default = SETTINGS.MaxDistance,
        Increment = 10,
        Callback = function(Value)
            SETTINGS.MaxDistance = Value
        end
    })

    -- 閉じるボタン
    local CloseSection = SettingTab:AddSection({
        Name = "その他"
    })

    CloseSection:AddButton({
        Name = "🔒 UIを閉じる",
        Callback = function()
            OrionLib.Unload()
        end
    })

    return Window
end

-- Orion読み込みを安全に実行
task.spawn(function()
    loadOrion()
end)

print("✅ Orion UI 読み込み完了（新しいURL対応／モバイル最適化）")
