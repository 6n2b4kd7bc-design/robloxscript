-- 殺人決闘 プレイヤーオンリー ナイフ投擲サイレントエイム（即時ターゲット切り替え）
-- Delta Executor 対応 / 主様専用

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ★★★ 設定（チームチェック有効） ★★★
-- ============================================================
local SETTINGS = {
    ThrowInterval = 0,          -- 投擲間隔（秒）
    WallbangOffset = 99999,           -- 壁貫通オフセット
    HeadshotRate = 1,           -- ヘッドショット率
    FOV_Degrees = 999,            -- 全方位
    MaxDistance = 999,            -- 最大射程（m）
    TeamCheck = true,             -- 味方を無視
}

-- ============================================================
-- ★★★ リモート取得 ★★★
-- ============================================================
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local throwRemote = remotes and remotes:FindFirstChild("ThrowReplicate")
local reportHitRemote = remotes and remotes:FindFirstChild("ReportHit")

if not throwRemote or not reportHitRemote then
    warn("ThrowReplicate または ReportHit が見つかりません")
    return
end

-- ============================================================
-- ★★★ 敵プレイヤー検出（生存者のみ） ★★★
-- ============================================================
local function findEnemyPlayer()
    local character = LocalPlayer.Character
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local bestTarget = nil
    local bestDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        if SETTINGS.TeamCheck and player.Team == LocalPlayer.Team then
            continue
        end

        local char = player.Character
        if not char then continue end

        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end  -- ★ 死亡チェック

        local targetRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not targetRoot then continue end

        local targetPos = targetRoot.Position
        local dist = (targetPos - root.Position).Magnitude
        if dist > SETTINGS.MaxDistance then continue end

        if SETTINGS.FOV_Degrees < 360 then
            local dirToTarget = (targetPos - camPos).Unit
            local angle = math.deg(math.acos(math.clamp(camLook:Dot(dirToTarget), -1, 1)))
            if angle > SETTINGS.FOV_Degrees then continue end
        end

        if dist < bestDist then
            bestDist = dist
            local headPart = char:FindFirstChild("Head") or char:FindFirstChild("head") or targetRoot
            bestTarget = {
                Model = char,
                Root = targetRoot,
                Head = headPart,
                Position = targetPos,
                Distance = dist,
                Player = player,
            }
        end
    end

    return bestTarget
end

-- ============================================================
-- ★★★ ハイライト（ターゲット可視化） ★★★
-- ============================================================
local currentHighlight = nil
local currentTarget = nil

local function updateHighlight(targetModel)
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    if not targetModel then return end

    local hl = Instance.new("Highlight")
    hl.Parent = targetModel
    hl.Adornee = targetModel
    hl.FillColor = Color3.fromRGB(255, 50, 50)
    hl.FillTransparency = 0.3
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.OutlineTransparency = 0.1
    currentHighlight = hl
end

-- ============================================================
-- ★★★ ナイフ投擲送信 ★★★
-- ============================================================
local function throwKnife(target)
    if not target or not target.Head then return end

    local character = LocalPlayer.Character
    if not character then return end
    local origin = character:FindFirstChild("HumanoidRootPart").Position + Vector3.new(0, 1.5, 0)

    local isHeadshot = math.random() < SETTINGS.HeadshotRate
    local targetPart = isHeadshot and target.Head or target.Root
    local basePos = targetPart.Position
    local dirToTarget = (basePos - origin).Unit
    local hitPos = basePos + dirToTarget * SETTINGS.WallbangOffset

    local throwData = {
        toolName = "Knife",
        id = math.random(1, 99999),
        ownerUserId = LocalPlayer.UserId,
        origin = origin,
        isExplosive = false,
        power = 1,
        target = hitPos,
        effects = { Shotgun = 0, Portal = 0, Smoke = 0, Explosive = 0, Flammable = 0 }
    }

    local reportData = {
        hitPos = hitPos,
        ownerUserId = LocalPlayer.UserId,
        origin = origin,
        vel = (hitPos - origin).Unit * 400,
        headshot = isHeadshot,
        targetUserId = target.Player and target.Player.UserId or 0,
        targetModel = target.Model,
        to = hitPos + Vector3.new(0, 0.5, 0),
        throwId = math.random(1, 99999),
        kind = "throw",
        at = 0.5,
        hitPart = targetPart,
    }

    pcall(function()
        throwRemote:FireServer(throwData)
        task.wait(0)
        reportHitRemote:FireServer(reportData)
    end)

    if math.random(1, 20) == 1 then
        print(string.format("🔪 %s に投擲 (ID:%d) 距離:%.1fm", target.Player.Name, throwData.id, target.Distance))
    end

    updateHighlight(target.Model)
end

-- ============================================================
-- ★★★ メインループ（毎フレーム生存者を再評価） ★★★
-- ============================================================
local lastThrow = 0

RunService.RenderStepped:Connect(function()
    local target = findEnemyPlayer()

    if target then
        -- ★ ターゲットが変わったらログ出力＆ハイライト更新
        if currentTarget ~= target then
            currentTarget = target
            print("🎯 ターゲット切り替え: " .. target.Player.Name .. " 距離: " .. math.floor(target.Distance) .. "m")
            updateHighlight(target.Model)
        end

        if tick() - lastThrow >= SETTINGS.ThrowInterval then
            throwKnife(target)
            lastThrow = tick()
        end
    else
        -- ★ ターゲット消失（死亡・範囲外）→ ハイライト消去
        if currentTarget then
            print("🎯 ターゲット消失（死亡または範囲外）")
            currentTarget = nil
            if currentHighlight then
                currentHighlight:Destroy()
                currentHighlight = nil
            end
        end
    end
end)

print("✅ プレイヤーオンリー ナイフ投擲サイレントエイム（即時ターゲット切り替え）起動")
print("📌 チームチェック: " .. (SETTINGS.TeamCheck and "有効（味方を無視）" or "無効（全員攻撃）"))
print("📌 投擲間隔: " .. SETTINGS.ThrowInterval .. "秒")
print("📌 壁貫通オフセット: " .. SETTINGS.WallbangOffset)
print("📌 ヘッドショット率: " .. (SETTINGS.HeadshotRate * 100) .. "%")
