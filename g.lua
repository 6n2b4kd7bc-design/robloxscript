-- サイレントエイム (CombatNet Buffer + Model Target)
-- 製作者: CAT (Interdimensional Coding Champion)
-- 動作環境: Roblox Executor (Delta / Synapse X / ScriptWare 等)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ★★★ 設定 ★★★
-- ============================================================
local SETTINGS = {
    Enabled = true,
    FOV_Radius = 200,               -- 画面中心からの半径（ピクセル）
    MaxDistance = 500,
    TeamCheck = true,
    WallCheck = true,
    Prediction = true,
    PredictionFactor = 0.2,
    ShowESP = true,
    AutoShoot = true,              -- オート射撃（trueで自動連射）
    ShootInterval = 0.2,
    -- バッファ内の位置/方向ベクトルオフセット（0-based、不明なら nil でモデル置換のみ）
    BufferPositionOffset = nil,     -- 例: 54 (4 floats = 16 bytes)
    BufferDirectionOffset = nil,    -- 例: 8 (3 floats = 12 bytes)
    -- オフセットを設定すれば、対応するfloat値を書き換える
}

-- ============================================================
-- ★★★ リモートイベント取得 ★★★
-- ============================================================
local CombatNet = ReplicatedStorage:FindFirstChild("CombatNet")
if not CombatNet then
    warn("CombatNet フォルダが見つかりません")
    return
end

local function findRemoteEvent()
    for _, child in ipairs(CombatNet:GetChildren()) do
        if child:IsA("RemoteEvent") then
            return child
        end
    end
    return nil
end

local ShootRemote = findRemoteEvent()
if not ShootRemote then
    warn("射撃リモートイベントが見つかりません")
    return
end
print("射撃リモート取得成功: " .. ShootRemote:GetFullName())

-- ============================================================
-- ★★★ 変数 ★★★
-- ============================================================
local CurrentTarget = nil
local LastTargetScan = 0
local LastShootTime = 0
local LocalCharacter = LocalPlayer.Character
local LocalRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(char)
    LocalCharacter = char
    LocalRoot = char:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
-- ★★★ ユーティリティ ★★★
-- ============================================================
local function isTeammate(player)
    if not SETTINGS.TeamCheck then return false end
    if LocalPlayer.Team and player.Team then
        return LocalPlayer.Team == player.Team
    end
    local mySide = LocalPlayer:GetAttribute("MatchSide")
    local theirSide = player:GetAttribute("MatchSide")
    if mySide and theirSide then
        return mySide == theirSide
    end
    return false
end

local function canSee(targetPos)
    if not SETTINGS.WallCheck then return true end
    if not LocalRoot then return false end
    local origin = LocalRoot.Position + Vector3.new(0, 1.5, 0)
    local direction = (targetPos - origin).Unit
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalCharacter}
    rayParams.IgnoreWater = true
    local ray = Workspace:Raycast(origin, direction * SETTINGS.MaxDistance, rayParams)
    if ray and ray.Instance then
        local hitChar = ray.Instance:FindFirstAncestorOfClass("Model")
        return hitChar ~= nil
    end
    return true
end

local function getPredictedPosition(targetPart)
    local vel = targetPart.Velocity
    if SETTINGS.Prediction and vel.Magnitude > 0 then
        local distance = (targetPart.Position - LocalRoot.Position).Magnitude
        local time = distance / 100
        return targetPart.Position + vel * (time * SETTINGS.PredictionFactor)
    end
    return targetPart.Position
end

-- ============================================================
-- ★★★ ターゲット検出（距離＋画面中心） ★★★
-- ============================================================
local function findTarget()
    if not SETTINGS.Enabled then return nil end
    if not LocalRoot then return nil end
    if tick() - LastTargetScan < 0.1 then return CurrentTarget end
    LastTargetScan = tick()

    local bestTarget = nil
    local bestScore = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local myPos = LocalRoot.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer or isTeammate(player) then continue end
        local char = player.Character
        if not char then continue end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        local targetPart = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not targetPart then continue end

        local targetPos = targetPart.Position
        local dist = (targetPos - myPos).Magnitude
        if dist > SETTINGS.MaxDistance then continue end
        if not canSee(targetPos) then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
        if not onScreen then continue end
        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if screenDist > SETTINGS.FOV_Radius then continue end

        local score = screenDist + dist * 0.1
        if score < bestScore then
            bestScore = score
            bestTarget = {
                Player = player,
                Character = char,
                Part = targetPart,
                Position = targetPos,
                Distance = dist,
            }
        end
    end

    CurrentTarget = bestTarget
    return bestTarget
end

-- ============================================================
-- ★★★ ESPハイライト ★★★
-- ============================================================
local currentHighlight = nil
local function updateHighlight(target)
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    if not target or not SETTINGS.ShowESP then return end
    local highlight = Instance.new("Highlight")
    highlight.Parent = target.Character
    highlight.Adornee = target.Character
    highlight.FillColor = Color3.fromRGB(255, 50, 50)
    highlight.FillTransparency = 0.3
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0
    currentHighlight = highlight
end

-- ============================================================
-- ★★★ バッファ改変関数 ★★★
-- ============================================================
local function modifyBuffer(bufferData, targetPos, targetPart)
    local origin = LocalRoot.Position + Vector3.new(0, 1.5, 0)
    local direction = (targetPos - origin).Unit

    -- 位置オフセット（設定があれば）
    if SETTINGS.BufferPositionOffset then
        local offset = SETTINGS.BufferPositionOffset
        pcall(function()
            buffer.writef32(bufferData, offset, targetPos.X)
            buffer.writef32(bufferData, offset + 4, targetPos.Y)
            buffer.writef32(bufferData, offset + 8, targetPos.Z)
        end)
    end

    -- 方向オフセット（設定があれば）
    if SETTINGS.BufferDirectionOffset then
        local offset = SETTINGS.BufferDirectionOffset
        pcall(function()
            buffer.writef32(bufferData, offset, direction.X)
            buffer.writef32(bufferData, offset + 4, direction.Y)
            buffer.writef32(bufferData, offset + 8, direction.Z)
        end)
    end

    return bufferData
end

-- ============================================================
-- ★★★ サイレントエイム：リモートフック ★★★
-- ============================================================
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if SETTINGS.Enabled and method == "FireServer" and self == ShootRemote then
        local target = findTarget()
        if target then
            -- 第二引数のモデルを最寄りの敵に置き換える（最も確実）
            if type(args[2]) == "userdata" or type(args[2]) == "Instance" then
                args[2] = target.Character
            end

            -- 第一引数がバッファなら、可能な限り改変
            if type(args[1]) == "userdata" and buffer and buffer.isbuffer(args[1]) then
                local targetPos = getPredictedPosition(target.Part)
                args[1] = modifyBuffer(args[1], targetPos, target.Part)
            end
        end
    end

    return oldNamecall(self, unpack(args))
end)

-- ============================================================
-- ★★★ オート射撃（任意） ★★★
-- ============================================================
local function autoShoot()
    if not SETTINGS.AutoShoot or not SETTINGS.Enabled then return end
    if not LocalRoot then return end
    local target = findTarget()
    if not target then return end
    local now = tick()
    if now - LastShootTime < SETTINGS.ShootInterval then return end
    LastShootTime = now

    -- 射撃処理を呼び出す（実際のゲームに合わせて実装が必要）
    -- ここでは何もしない（既存の射撃ボタン等に依存）
end

-- ============================================================
-- ★★★ メインループ ★★★
-- ============================================================
RunService.RenderStepped:Connect(function()
    local target = findTarget()
    updateHighlight(target)
    autoShoot()
end)

print("✅ サイレントエイム (CombatNet + Model Target) 起動完了")
print("📌 最寄りの敵にモデルを置換し、バッファも改変します")
print("⚠️ バッファオフセット未設定の場合、モデル置換のみで動作します")
