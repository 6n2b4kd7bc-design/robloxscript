-- 殺人決闘 プレイヤーオンリー ナイフ投擲サイレントエイム（チームチェック付き）
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
    WallbangOffset = 9999,           -- 壁貫通オフセット
    HeadshotRate = 1,           -- ヘッドショット率
    FOV_Degrees = 999,            -- 全方位（制限したい場合は数値を減らす）
    MaxDistance = 999,            -- 最大射程（m）
    TeamCheck = true,             -- チームチェック有効（味方を攻撃しない）
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
-- ★★★ 敵プレイヤー検出（チームチェック＋FOV＋距離） ★★★
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

        -- ★ チームチェック（有効時）
        if SETTINGS.TeamCheck then
            if player.Team == LocalPlayer.Team then continue end
        end

        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        local targetRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not targetRoot then continue end

        local targetPos = targetRoot.Position
        local dist = (targetPos - root.Position).Magnitude
        if dist > SETTINGS.MaxDistance then continue end

        -- ★ FOVチェック（360度ならスキップ）
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
-- ★★★ ハイライト（ターゲットを視覚化） ★★★
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
-- ★★★ ナイフ投擲送信（プレイヤー用） ★★★
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

    -- ★ プレイヤーにはUserIdが存在する
    local targetUserId = target.Player and target.Player.UserId or 0

    -- ThrowReplicate
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

    -- ReportHit
    local reportData = {
        hitPos = hitPos,
        ownerUserId = LocalPlayer.UserId,
        origin = origin,
        vel = (hitPos - origin).Unit * 400,
        headshot = isHeadshot,
        targetUserId = targetUserId,
        targetModel = target.Model,
        to = hitPos + Vector3.new(0, 0.5, 0),
        throwId = math.random(1, 99999),
        kind = "throw",
        at = 0.5,
        hitPart = targetPart,
    }

    pcall(function()
        throwRemote:FireServer(throwData)
        task.wait(0.02)
        reportHitRemote:FireServer(reportData)
    end)

    -- デバッグ表示（20回に1回）
    if math.random(1, 20) == 1 then
        print(string.format("🔪 %s に投擲 (ID:%d) 距離:%.1fm", target.Player.Name, throwData.id, target.Distance))
    end

    -- ターゲットハイライト
    highlightTarget(target.Model)
end

-- ============================================================
-- ★★★ メインループ（自動投擲） ★★★
-- ============================================================
local lastThrow = 0
RunService.RenderStepped:Connect(function()
    local target = findEnemyPlayer()
    if target then
        if tick() - lastThrow >= SETTINGS.ThrowInterval then
            throwKnife(target)
            lastThrow = tick()
        end
    else
        -- ターゲットがいなければハイライト消去
        if currentHighlight then
            currentHighlight:Destroy()
            currentHighlight = nil
        end
    end
end)

print("✅ プレイヤーオンリー ナイフ投擲サイレントエイム 起動")
print("📌 チームチェック: " .. (SETTINGS.TeamCheck and "有効（味方を無視）" or "無効（全員攻撃）"))
print("📌 投擲間隔: " .. SETTINGS.ThrowInterval .. "秒")
print("📌 壁貫通オフセット: " .. SETTINGS.WallbangOffset)
print("📌 ヘッドショット率: " .. (SETTINGS.HeadshotRate * 100) .. "%")
