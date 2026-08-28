-- オート攻撃 + 銃 + グレネードミニガン + RPGミニガン + 敵ESP + Chunkmover滑空（キャンセル・座標指定） + Anti-Lag + モバイルUI
-- 製作者: CAT (Interdimensional Coding Champion)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ★★★ 設定（UIで変更可、制限なし） ★★★
-- ============================================================
local SETTINGS = {
    -- 近接自動攻撃
    AutoAttackEnabled = true,
    Damage = 13,
    AttackInterval = 0.3,
    AttackRange = 80,
    TargetNPCs = true,
    TargetPlayers = false,

    -- 銃自動射撃
    GunEnabled = true,
    GunDamage = 30,
    GunInterval = 0.2,
    GunFOV = 250,
    GunMaxRange = 500,
    GunAimPart = "Head",
    GunWallCheck = true,

    -- グレネード
    GrenadeEnabled = true,
    GrenadeInterval = 3,
    GrenadeRange = 120,
    GrenadeFlightTime = 0.6,
    GrenadeDamage = 50,
    UseAuthenticGrenade = true,
    HomingStrength = 0.8,
    GrenadeMinigun = false,
    GrenadeMinigunInterval = 0.1,

    -- RPG7
    RPGEnabled = true,
    RPGInterval = 1.5,
    RPGRange = 800,
    RPGAimPart = "HumanoidRootPart",
    RPGWallCheck = false,
    RPGMinigun = false,
    RPGMinigunInterval = 0.3,
    RPGProjectileID = "RPG/11555212114/0",

    -- ESP
    EnemyESPEnabled = true,
    ESPDistanceLimit = 500,
    ESP_Box = true,
    ESP_Tracer = true,
    ESP_Label = true,
    ESP_ColorCycle = true,

    -- Anti-Lag
    AntiLagEnabled = true,
    TargetScanInterval = 0.15,
    ESPUpdateInterval = 0.08,
    MaxActiveGrenades = 10,

    -- 車両設定
    VehicleFlySpeed = 50,
}

-- ============================================================
-- ★★★ リモートイベント取得 ★★★
-- ============================================================
local ClientRunner = ReplicatedStorage:FindFirstChild("FlowClient") and ReplicatedStorage.FlowClient:FindFirstChild("ClientRunner")
local Event = ClientRunner and ClientRunner:FindFirstChild("Event")
if not Event then
    warn("FlowClient.ClientRunner.Event が見つかりません")
    return
end

-- ============================================================
-- ★★★ FlowClientモジュール取得（本物グレネード用） ★★★
-- ============================================================
local FlowClientModule = nil
local function getFlowClient()
    local success, result = pcall(function()
        return require(ReplicatedStorage:WaitForChild("FlowClient"))
    end)
    if success and result then
        FlowClientModule = result
    end
end
task.spawn(getFlowClient)

-- ============================================================
-- ★★★ キャッシュ変数 ★★★
-- ============================================================
local lastAttackTime = 0
local lastGunShot = 0
local lastGrenadeTime = 0
local lastRPGTime = 0
local lastTargetScan = 0
local lastESPUpdate = 0
local LocalCharacter = LocalPlayer.Character
local LocalRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")
local activeGrenades = {}
local selectedPlayerIndex = 1
local cachedTargets = {}
local vehicleTargetObjectName = ""
local carFlightState = nil

LocalPlayer.CharacterAdded:Connect(function(char)
    LocalCharacter = char
    LocalRoot = char:WaitForChild("HumanoidRootPart")
    for _, g in ipairs(activeGrenades) do
        if g.dummy and g.dummy.Parent then
            g.dummy:Destroy()
        end
    end
    activeGrenades = {}
    cachedTargets = {}
    if carFlightState then
        cancelCarFly()
    end
end)

-- ============================================================
-- ★★★ ユーティリティ ★★★
-- ============================================================
local function isTeammate(player)
    if LocalPlayer.Team and player.Team then
        return LocalPlayer.Team == player.Team
    end
    return false
end

local function getCyclingColor()
    local t = tick() % 6
    local pink = Color3.fromRGB(255, 105, 180)
    local lightPink = Color3.fromRGB(255, 182, 193)
    local lightPurple = Color3.fromRGB(200, 162, 200)
    if t < 2 then
        return pink:Lerp(lightPink, t / 2)
    elseif t < 4 then
        return lightPink:Lerp(lightPurple, (t - 2) / 2)
    else
        return lightPurple:Lerp(pink, (t - 4) / 2)
    end
end

-- ============================================================
-- ★★★ ターゲット検出（範囲指定対応、敵のみ、Anti-Lag対応） ★★★
-- ============================================================
local function findAllTargets(range)
    if not LocalRoot then return {} end
    if SETTINGS.AntiLagEnabled and tick() - lastTargetScan < SETTINGS.TargetScanInterval then
        return cachedTargets
    end
    lastTargetScan = tick()

    local targets = {}
    local myPos = LocalRoot.Position
    local maxDist = range or SETTINGS.AttackRange

    if SETTINGS.TargetNPCs then
        local npcFolder = Workspace:FindFirstChild("NPCs")
        if npcFolder then
            for _, npc in ipairs(npcFolder:GetChildren()) do
                if npc:IsA("Model") then
                    local humanoid = npc:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        local rootPart = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Torso")
                        if rootPart then
                            local dist = (rootPart.Position - myPos).Magnitude
                            if dist <= maxDist then
                                table.insert(targets, {
                                    Character = npc,
                                    Humanoid = humanoid,
                                    RootPart = rootPart,
                                    IsPlayer = false,
                                    Distance = dist,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if SETTINGS.TargetPlayers then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and not isTeammate(player) then
                local char = player.Character
                if char then
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        local rootPart = char:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local dist = (rootPart.Position - myPos).Magnitude
                            if dist <= maxDist then
                                table.insert(targets, {
                                    Character = char,
                                    Humanoid = humanoid,
                                    RootPart = rootPart,
                                    IsPlayer = true,
                                    Distance = dist,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(targets, function(a, b) return a.Distance < b.Distance end)
    cachedTargets = targets
    return targets
end

-- ============================================================
-- ★★★ 近接自動攻撃実行 ★★★
-- ============================================================
local function attackTarget(target)
    if not target or not target.Humanoid or target.Humanoid.Health <= 0 then return end
    if LocalCharacter then
        local hrp = LocalCharacter:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                Event:FireServer("Punches", "ReplicateSound", hrp, "Swoosh")
            end)
        end
    end
    pcall(function()
        Event:FireServer("NPCs", "Damage", target.Humanoid, SETTINGS.Damage)
    end)
end

-- ============================================================
-- ★★★ 銃自動射撃（直接ダメージ） ★★★
-- ============================================================
local function findGunTarget()
    if not SETTINGS.GunEnabled or not LocalRoot then return nil end
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local bestTarget = nil
    local bestScore = math.huge

    local targets = cachedTargets
    if #targets == 0 then
        targets = findAllTargets(SETTINGS.GunMaxRange)
    end

    for _, targetData in ipairs(targets) do
        local npc = targetData.Character
        local humanoid = targetData.Humanoid
        if humanoid and humanoid.Health > 0 then
            local part
            if SETTINGS.GunAimPart == "Head" then
                part = npc:FindFirstChild("Head")
            elseif SETTINGS.GunAimPart == "Torso" then
                part = npc:FindFirstChild("Torso") or npc:FindFirstChild("UpperTorso")
            else
                part = targetData.RootPart
            end
            if part then
                local targetPos = part.Position
                local dist = (targetPos - LocalRoot.Position).Magnitude
                if dist <= SETTINGS.GunMaxRange then
                    if SETTINGS.GunWallCheck then
                        local rayParams = RaycastParams.new()
                        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                        rayParams.FilterDescendantsInstances = {LocalCharacter}
                        rayParams.IgnoreWater = true
                        local ray = Workspace:Raycast(LocalRoot.Position, (targetPos - LocalRoot.Position).Unit * SETTINGS.GunMaxRange, rayParams)
                        if ray and ray.Instance and ray.Instance:FindFirstAncestorOfClass("Model") ~= npc then
                            continue
                        end
                    end
                    local screenPos, onScreen = cam:WorldToViewportPoint(targetPos)
                    if onScreen then
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if screenDist <= SETTINGS.GunFOV then
                            local score = screenDist + dist * 0.1
                            if score < bestScore then
                                bestScore = score
                                bestTarget = {
                                    Character = npc,
                                    Humanoid = humanoid,
                                    Part = part,
                                    Position = targetPos,
                                    Distance = dist,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return bestTarget
end

local function gunShoot()
    if not SETTINGS.GunEnabled then return end
    if tick() - lastGunShot < SETTINGS.GunInterval then return end
    local target = findGunTarget()
    if target then
        pcall(function()
            Event:FireServer("NPCs", "Damage", target.Humanoid, SETTINGS.GunDamage)
        end)
        pcall(function()
            Event:FireServer("NPCs", "GunFired", LocalRoot.Position, target.Position)
        end)
        lastGunShot = tick()
    end
end

-- ============================================================
-- ★★★ RPG7自動発射（ミニガン対応） ★★★
-- ============================================================
local function findRPGTarget()
    if not SETTINGS.RPGEnabled or not LocalRoot then return nil end
    local targets = findAllTargets(SETTINGS.RPGRange)
    if #targets == 0 then return nil end
    local target = targets[1]
    local part = target.RootPart
    if SETTINGS.RPGAimPart == "Head" then
        part = target.Character:FindFirstChild("Head") or part
    elseif SETTINGS.RPGAimPart == "Torso" then
        part = target.Character:FindFirstChild("Torso") or target.Character:FindFirstChild("UpperTorso") or part
    end
    return {target = target, part = part}
end

local function fireRPG()
    if not SETTINGS.RPGEnabled then return end
    local interval = SETTINGS.RPGMinigun and SETTINGS.RPGMinigunInterval or SETTINGS.RPGInterval
    if tick() - lastRPGTime < interval then return end
    local rpgTarget = findRPGTarget()
    if not rpgTarget then return end

    local target = rpgTarget.target
    local aimPart = rpgTarget.part
    local targetPos = aimPart.Position
    local origin = LocalRoot.Position + Vector3.new(0, 1.5, 0)

    local rpgTool = LocalCharacter and LocalCharacter:FindFirstChild("RPG7")
    if not rpgTool then
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            rpgTool = backpack:FindFirstChild("RPG7")
        end
    end
    if not rpgTool then return end

    local projectileID = SETTINGS.RPGProjectileID
    local ignoreList = { LocalCharacter, Workspace:FindFirstChild("Effects") }

    pcall(function()
        Event:FireServer("RPG7", "Missile", rpgTool, targetPos, projectileID, ignoreList)
    end)

    lastRPGTime = tick()
end

-- ============================================================
-- ★★★ グレネード投擲（複数同時対応・ミニガン対応・Anti-Lag） ★★★
-- ============================================================
local function findGrenadeTool()
    if not LocalPlayer then return nil end
    local function search(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                local name = child.Name:lower()
                if name:find("grenade") or name:find("molotov") or name:find("throwable") then
                    return child
                end
            end
        end
        return nil
    end

    if LocalCharacter then
        local found = search(LocalCharacter)
        if found then return found end
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        local found = search(backpack)
        if found then return found end
    end
    local starterGear = LocalPlayer:FindFirstChild("StarterGear")
    if starterGear then
        local found = search(starterGear)
        if found then return found end
    end
    return nil
end

local function explodeGrenade(dummy, target)
    if not dummy then return end
    local pos = dummy.Position
    pcall(function()
        Event:FireServer("Explosions", "Exploded", pos)
    end)
    if FlowClientModule and FlowClientModule.GetThrowable then
        pcall(function()
            FlowClientModule.GetThrowable.explode(dummy)
        end)
    end
    pcall(function()
        Event:FireServer("GetThrowable", "explode", dummy)
    end)
    if target and target.Humanoid and target.Humanoid.Health > 0 then
        pcall(function()
            Event:FireServer("NPCs", "Damage", target.Humanoid, SETTINGS.GrenadeDamage)
        end)
    end
    pcall(function()
        Event:FireServer("NPCs", "Disturb", pos, 20)
    end)
end

local function throwAuthenticGrenade(target)
    if not FlowClientModule or not FlowClientModule.GetThrowable then
        return false
    end
    if SETTINGS.AntiLagEnabled and #activeGrenades >= SETTINGS.MaxActiveGrenades then
        return false
    end
    local tool = findGrenadeTool()
    if not tool then return false end
    if not LocalCharacter then return false end

    if tool.Parent ~= LocalCharacter then
        LocalCharacter:FindFirstChildOfClass("Humanoid"):EquipTool(tool)
        task.wait(0.2)
    end

    local dummy = tool:FindFirstChild("Dummy")
    local weld = dummy and dummy:FindFirstChild("Weld")
    if not dummy or not weld then
        return false
    end

    local startPos = LocalRoot.Position + Vector3.new(0, 1.5, 0)
    local targetPos = target.RootPart.Position + Vector3.new(0, 1, 0)
    local direction = (targetPos - startPos).Unit
    local speed = 100
    local initialVelocity = direction * speed

    pcall(function()
        dummy.AssemblyLinearVelocity = initialVelocity
        FlowClientModule.GetThrowable.throw(dummy)
        Event:FireServer("GetThrowable", "throw", dummy)
    end)

    local grenadeData = {
        dummy = dummy,
        target = target,
        startTime = tick(),
    }
    table.insert(activeGrenades, grenadeData)

    task.spawn(function()
        while grenadeData.dummy and grenadeData.dummy.Parent do
            local dt = task.wait()
            local currentTarget = grenadeData.target
            if currentTarget and currentTarget.RootPart and currentTarget.RootPart.Parent then
                local currentPos = grenadeData.dummy.Position
                local desiredDirection = (currentTarget.RootPart.Position + Vector3.new(0,1,0) - currentPos).Unit
                local currentVel = grenadeData.dummy.AssemblyLinearVelocity
                local newVel = currentVel:Lerp(desiredDirection * currentVel.Magnitude, SETTINGS.HomingStrength)
                grenadeData.dummy.AssemblyLinearVelocity = newVel
            end
            local dist = (grenadeData.dummy.Position - (currentTarget.RootPart.Position + Vector3.new(0,1,0))).Magnitude
            if dist < 5 or tick() - grenadeData.startTime > 2.5 then
                explodeGrenade(grenadeData.dummy, currentTarget)
                if grenadeData.dummy and grenadeData.dummy.Parent then
                    grenadeData.dummy:Destroy()
                end
                for i, g in ipairs(activeGrenades) do
                    if g == grenadeData then
                        table.remove(activeGrenades, i)
                        break
                    end
                end
                break
            end
        end
    end)

    return true
end

local function createVisualGrenade(target)
    if SETTINGS.AntiLagEnabled and #activeGrenades >= SETTINGS.MaxActiveGrenades then
        return
    end
    local startPos = LocalRoot.Position + Vector3.new(0, 1.5, 0)
    local targetPos = target.RootPart.Position + Vector3.new(0, 1, 0)

    local visual = Instance.new("Part")
    visual.Shape = Enum.PartType.Ball
    visual.Size = Vector3.new(1.5, 1.5, 1.5)
    visual.Material = Enum.Material.Neon
    visual.Color = Color3.fromRGB(255, 0, 0)
    visual.Anchored = true
    visual.CanCollide = false
    visual.Position = startPos
    visual.Parent = Workspace

    local grenadeData = {
        dummy = visual,
        target = target,
        startTime = tick(),
    }
    table.insert(activeGrenades, grenadeData)

    local tweenInfo = TweenInfo.new(SETTINGS.GrenadeFlightTime, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(visual, tweenInfo, {Position = targetPos})
    tween.Completed:Connect(function()
        pcall(function()
            Event:FireServer("Explosions", "Exploded", visual.Position)
        end)
        pcall(function()
            Event:FireServer("NPCs", "Damage", target.Humanoid, SETTINGS.GrenadeDamage)
        end)
        pcall(function()
            Event:FireServer("NPCs", "Disturb", visual.Position, 20)
        end)
        visual:Destroy()
        for i, g in ipairs(activeGrenades) do
            if g == grenadeData then
                table.remove(activeGrenades, i)
                break
            end
        end
    end)
    tween:Play()
end

local function throwGrenadeAt(target)
    if SETTINGS.UseAuthenticGrenade and FlowClientModule and FlowClientModule.GetThrowable then
        local success = throwAuthenticGrenade(target)
        if success then return end
    end
    createVisualGrenade(target)
end

-- ============================================================
-- ★★★ 車両滑空（Chunkmover・オブジェクト指定・プレイヤー選択・キャンセル・座標指定・全パーツ移動） ★★★
-- ============================================================
local function findChunkmoverVehicle()
    -- 直接パスを最優先
    local vehiclesFolder = Workspace:FindFirstChild("Vehicles")
    if vehiclesFolder then
        local chunkmover = vehiclesFolder:FindFirstChild("Chunkmover")
        if chunkmover then
            if chunkmover:IsA("Model") then
                if chunkmover.PrimaryPart then
                    return chunkmover, chunkmover.PrimaryPart
                end
                for _, child in ipairs(chunkmover:GetDescendants()) do
                    if child:IsA("BasePart") then
                        return chunkmover, child
                    end
                end
                return chunkmover, nil
            elseif chunkmover:IsA("BasePart") then
                return chunkmover, chunkmover
            end
        end
    end
    -- フォールバック
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name == "Chunkmover" then
            if obj.PrimaryPart then
                return obj, obj.PrimaryPart
            end
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("BasePart") then
                    return obj, child
                end
            end
            return obj, nil
        end
        if obj:IsA("VehicleSeat") and obj.Name == "Chunkmover" then
            local model = obj.Parent or obj
            if model:IsA("Model") then
                if model.PrimaryPart then
                    return model, model.PrimaryPart
                end
                for _, child in ipairs(model:GetDescendants()) do
                    if child:IsA("BasePart") then
                        return model, child
                    end
                end
            end
            return model, (model:IsA("BasePart") and model or nil)
        end
    end
    return nil, nil
end

local function teleportSelfToChunkmover()
    if not LocalRoot then return end
    local vehicle, targetPart = findChunkmoverVehicle()
    if not vehicle or not targetPart then
        warn("Chunkmover車両または移動用パーツが見つかりません")
        return
    end
    LocalRoot.CFrame = CFrame.new(targetPart.Position + Vector3.new(0, 3, 0))
end

local function findObjectByName(name)
    if not name or name == "" then
        warn("オブジェクト名が空です")
        return nil
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == name then
            if obj:IsA("BasePart") then
                return obj
            elseif obj:IsA("Model") and obj.PrimaryPart then
                return obj.PrimaryPart
            elseif obj:IsA("Model") then
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("BasePart") then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

local function flyChunkmoverToPosition(targetPosition)
    -- 既存の飛行中なら一旦キャンセル
    if carFlightState then
        cancelCarFly()
    end

    local vehicle, targetPart = findChunkmoverVehicle()
    if not vehicle or not targetPart then
        warn("Chunkmover車両または移動用パーツが見つかりません")
        return
    end

    -- モデル内のすべてのBasePartを取得
    local parts = {}
    if vehicle:IsA("Model") then
        for _, child in ipairs(vehicle:GetDescendants()) do
            if child:IsA("BasePart") then
                table.insert(parts, child)
            end
        end
    else
        table.insert(parts, vehicle)
    end

    if #parts == 0 then
        warn("移動するパーツがありません")
        return
    end

    -- ルートパーツの現在位置を基準
    local rootPart = targetPart or parts[1]
    local startCFrame = rootPart.CFrame
    local distance = (startCFrame.Position - targetPosition).Magnitude
    local duration = math.clamp(distance / SETTINGS.VehicleFlySpeed, 0.1, 30)
    local startTime = tick()

    -- 全パーツの元の状態を保存
    local originalStates = {}
    local offsets = {}
    for _, part in ipairs(parts) do
        originalStates[part] = {
            Anchored = part.Anchored,
            CanCollide = part.CanCollide,
            AssemblyLinearVelocity = part.AssemblyLinearVelocity,
            AssemblyAngularVelocity = part.AssemblyAngularVelocity,
        }
        offsets[part] = part.Position - startCFrame.Position
        -- 飛行中はアンカーして物理を無効化
        part.Anchored = true
        part.CanCollide = false
        part.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local alpha = math.clamp(elapsed / duration, 0, 1)
        local newRootPos = startCFrame.Position:Lerp(targetPosition, alpha)

        for part, offset in pairs(offsets) do
            part.Position = newRootPos + offset
        end

        if alpha >= 1 then
            -- 到着、元の状態に戻す
            for part, state in pairs(originalStates) do
                part.Anchored = state.Anchored
                part.CanCollide = state.CanCollide
                part.AssemblyLinearVelocity = state.AssemblyLinearVelocity
                part.AssemblyAngularVelocity = state.AssemblyAngularVelocity
            end
            connection:Disconnect()
            carFlightState = nil
        end
    end)

    -- 飛行状態を保存
    carFlightState = {
        connection = connection,
        parts = parts,
        originalStates = originalStates,
        offsets = offsets,
    }
end

local function cancelCarFly()
    if not carFlightState then return end

    if carFlightState.connection then
        carFlightState.connection:Disconnect()
    end

    for part, state in pairs(carFlightState.originalStates) do
        part.Anchored = state.Anchored
        part.CanCollide = state.CanCollide
        part.AssemblyLinearVelocity = state.AssemblyLinearVelocity
        part.AssemblyAngularVelocity = state.AssemblyAngularVelocity
    end

    carFlightState = nil
    print("車の飛行をキャンセルしました")
end

local function flyChunkmoverToObject(objectName)
    if not objectName or objectName == "" then
        warn("オブジェクト名を入力してください")
        return
    end
    local targetPart = findObjectByName(objectName)
    if not targetPart then
        warn("オブジェクトが見つかりません: " .. objectName)
        return
    end
    flyChunkmoverToPosition(targetPart.Position + Vector3.new(0, 5, 0))
end

local function flyChunkmoverToPlayer(player)
    if not player or not player.Character then return end
    local targetHRP = player.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end
    flyChunkmoverToPosition(targetHRP.Position + Vector3.new(0, 5, 0))
end

-- ============================================================
-- ★★★ ESPシステム（敵のみ、Anti-Lag対応） ★★★
-- ============================================================
local function getParent()
    if gethui then return gethui() end
    local success, result = pcall(function() return game:GetService("CoreGui") end)
    if success and result then return result end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local espGui = Instance.new("ScreenGui")
espGui.Name = "CAT_ESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.Parent = getParent()

local enemyESPObjects = {}

local function createEnemyESP(model)
    if enemyESPObjects[model] then return end
    local obj = {}
    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.Parent = espGui
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = box
    obj.Box = box
    obj.Stroke = stroke

    local tracer = Instance.new("Frame")
    tracer.BackgroundColor3 = Color3.fromRGB(255, 182, 193)
    tracer.BorderSizePixel = 0
    tracer.AnchorPoint = Vector2.new(0.5, 0.5)
    tracer.Visible = false
    tracer.Parent = espGui
    obj.Tracer = tracer

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextSize = 14
    label.Font = Enum.Font.SourceSansBold
    label.Visible = false
    label.Parent = espGui
    obj.Label = label

    enemyESPObjects[model] = obj
end

RunService.RenderStepped:Connect(function()
    if not SETTINGS.EnemyESPEnabled then
        for _, obj in pairs(enemyESPObjects) do
            obj.Box.Visible = false
            obj.Tracer.Visible = false
            obj.Label.Visible = false
        end
        return
    end

    if SETTINGS.AntiLagEnabled then
        if tick() - lastESPUpdate < SETTINGS.ESPUpdateInterval then return end
    end
    lastESPUpdate = tick()

    local cam = Workspace.CurrentCamera
    local enemyColor = SETTINGS.ESP_ColorCycle and getCyclingColor() or Color3.fromRGB(255, 105, 180)
    local myPos = LocalRoot and LocalRoot.Position or Vector3.new()

    local npcFolder = Workspace:FindFirstChild("NPCs")
    if npcFolder then
        for _, npc in ipairs(npcFolder:GetChildren()) do
            if npc:IsA("Model") then
                local humanoid = npc:FindFirstChildOfClass("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if humanoid and humanoid.Health > 0 and hrp then
                    local distFromPlayer = (hrp.Position - myPos).Magnitude
                    if distFromPlayer > SETTINGS.ESPDistanceLimit then
                        if enemyESPObjects[npc] then
                            enemyESPObjects[npc].Box.Visible = false
                            enemyESPObjects[npc].Tracer.Visible = false
                            enemyESPObjects[npc].Label.Visible = false
                        end
                        continue
                    end

                    if not enemyESPObjects[npc] then
                        createEnemyESP(npc)
                    end
                    local obj = enemyESPObjects[npc]
                    local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                    if onScreen then
                        if SETTINGS.ESP_Box then
                            local headPos = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                            local legPos = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.5, 0))
                            local height = math.abs(headPos.Y - legPos.Y)
                            local width = height / 1.5
                            obj.Stroke.Color = enemyColor
                            obj.Box.Size = UDim2.new(0, width, 0, height)
                            obj.Box.Position = UDim2.new(0, pos.X - width/2, 0, pos.Y - height/2)
                            obj.Box.Visible = true
                        else
                            obj.Box.Visible = false
                        end
                        if SETTINGS.ESP_Label then
                            local dist = math.floor(distFromPlayer)
                            obj.Label.Text = string.format("NPC %s\n%dHP | %dm", npc.Name, humanoid.Health, dist)
                            obj.Label.TextColor3 = enemyColor
                            obj.Label.Size = UDim2.new(0, 100, 0, 30)
                            obj.Label.Position = UDim2.new(0, pos.X - 50, 0, pos.Y - (math.abs(cam:WorldToViewportPoint(hrp.Position + Vector3.new(0,3,0)).Y - pos.Y)/2) - 35)
                            obj.Label.Visible = true
                        else
                            obj.Label.Visible = false
                        end
                        if SETTINGS.ESP_Tracer then
                            local screenX, screenY = cam.ViewportSize.X, cam.ViewportSize.Y
                            local startPos = Vector2.new(screenX / 2, screenY)
                            local endPos = Vector2.new(pos.X, pos.Y)
                            local distance = (endPos - startPos).Magnitude
                            local center = (startPos + endPos) / 2
                            local angle = math.atan2(endPos.Y - startPos.Y, endPos.X - startPos.X)
                            obj.Tracer.BackgroundColor3 = enemyColor
                            obj.Tracer.Size = UDim2.new(0, distance, 0, 1.5)
                            obj.Tracer.Position = UDim2.new(0, center.X, 0, center.Y)
                            obj.Tracer.Rotation = math.deg(angle)
                            obj.Tracer.Visible = true
                        else
                            obj.Tracer.Visible = false
                        end
                    else
                        obj.Box.Visible = false
                        obj.Tracer.Visible = false
                        obj.Label.Visible = false
                    end
                else
                    if enemyESPObjects[npc] then
                        enemyESPObjects[npc].Box.Visible = false
                        enemyESPObjects[npc].Tracer.Visible = false
                        enemyESPObjects[npc].Label.Visible = false
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- ★★★ モバイル最適化UI（4メニュー：戦闘・グレ・ESP・車） ★★★
-- ============================================================
local function createSettingsUI()
    local parent = getParent()
    local ui = Instance.new("ScreenGui")
    ui.Name = "CAT_Settings_UI"
    ui.ResetOnSpawn = false
    ui.IgnoreGuiInset = true
    ui.Parent = parent

    local settingsButton = Instance.new("TextButton")
    settingsButton.Size = UDim2.new(0, 140, 0, 50)
    settingsButton.Position = UDim2.new(1, -150, 0, 10)
    settingsButton.BackgroundColor3 = Color3.fromRGB(255, 105, 180)
    settingsButton.Text = "⚙️ 設定"
    settingsButton.TextColor3 = Color3.new(1,1,1)
    settingsButton.TextSize = 18
    settingsButton.Font = Enum.Font.SourceSansBold
    settingsButton.Parent = ui

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 320, 0, 420)
    panel.Position = UDim2.new(1, -330, 0, 70)
    panel.BackgroundColor3 = Color3.fromRGB(30,30,30)
    panel.BorderSizePixel = 0
    panel.Visible = false
    panel.Parent = ui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundColor3 = Color3.fromRGB(255, 105, 180)
    title.Text = "CAT 設定"
    title.TextColor3 = Color3.new(1,1,1)
    title.TextSize = 20
    title.Font = Enum.Font.SourceSansBold
    title.Parent = panel

    local menuFrame = Instance.new("Frame")
    menuFrame.Size = UDim2.new(1, 0, 0, 35)
    menuFrame.Position = UDim2.new(0, 0, 0, 40)
    menuFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
    menuFrame.Parent = panel

    local menuButtons = {}
    local menuNames = {"戦闘", "グレ", "ESP", "車"}
    local menuKeys = {"combat", "grenade", "esp", "vehicle"}
    for i, name in ipairs(menuNames) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 80, 1, 0)
        btn.Position = UDim2.new(0, (i-1)*80, 0, 0)
        btn.BackgroundColor3 = (i == 1) and Color3.fromRGB(255,105,180) or Color3.fromRGB(60,60,60)
        btn.Text = name
        btn.TextColor3 = Color3.new(1,1,1)
        btn.TextSize = 16
        btn.Font = Enum.Font.SourceSansBold
        btn.Parent = menuFrame
        menuButtons[menuKeys[i]] = btn
    end

    local function createScrollFrame()
        local sf = Instance.new("ScrollingFrame")
        sf.Size = UDim2.new(1, 0, 1, -75)
        sf.Position = UDim2.new(0, 0, 0, 75)
        sf.BackgroundTransparency = 1
        sf.CanvasSize = UDim2.new(0, 0, 0, 800)
        sf.ScrollBarThickness = 6
        sf.Visible = false
        sf.Parent = panel
        return sf
    end

    local combatFrame = createScrollFrame()
    local grenadeFrame = createScrollFrame()
    local espFrame = createScrollFrame()
    local vehicleFrame = createScrollFrame()

    local function addToggleToFrame(frame, label, key, yPos)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -20, 0, 36)
        btn.Position = UDim2.new(0, 10, 0, yPos)
        btn.BackgroundColor3 = SETTINGS[key] and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0)
        btn.Text = label .. ": " .. (SETTINGS[key] and "ON" or "OFF")
        btn.TextColor3 = Color3.new(1,1,1)
        btn.TextSize = 16
        btn.Font = Enum.Font.SourceSansBold
        btn.Parent = frame
        btn.Activated:Connect(function()
            SETTINGS[key] = not SETTINGS[key]
            btn.BackgroundColor3 = SETTINGS[key] and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0)
            btn.Text = label .. ": " .. (SETTINGS[key] and "ON" or "OFF")
        end)
        return yPos + 40
    end

    local function addNumericUnrestricted(frame, label, key, yPos)
        local labelText = Instance.new("TextLabel")
        labelText.Size = UDim2.new(0, 120, 0, 30)
        labelText.Position = UDim2.new(0, 10, 0, yPos)
        labelText.BackgroundTransparency = 1
        labelText.Text = label .. ":"
        labelText.TextColor3 = Color3.new(1,1,1)
        labelText.TextSize = 16
        labelText.Parent = frame

        local valueText = Instance.new("TextBox")
        valueText.Size = UDim2.new(0, 150, 0, 30)
        valueText.Position = UDim2.new(0, 130, 0, yPos)
        valueText.BackgroundColor3 = Color3.fromRGB(60,60,60)
        valueText.TextColor3 = Color3.new(1,1,1)
        valueText.Text = tostring(SETTINGS[key])
        valueText.TextSize = 16
        valueText.Font = Enum.Font.SourceSans
        valueText.Parent = frame
        valueText.FocusLost:Connect(function(enterPressed)
            local num = tonumber(valueText.Text)
            if num then
                SETTINGS[key] = num
                valueText.Text = tostring(SETTINGS[key])
            else
                valueText.Text = tostring(SETTINGS[key])
            end
        end)

        return yPos + 35
    end

    local function addButtonToFrame(frame, label, yPos, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -20, 0, 40)
        btn.Position = UDim2.new(0, 10, 0, yPos)
        btn.BackgroundColor3 = Color3.fromRGB(100,100,100)
        btn.Text = label
        btn.TextColor3 = Color3.new(1,1,1)
        btn.TextSize = 16
        btn.Font = Enum.Font.SourceSansBold
        btn.Parent = frame
        btn.Activated:Connect(callback)
        return yPos + 45
    end

    -- 戦闘フレーム
    local y = 10
    y = addToggleToFrame(combatFrame, "近接自動攻撃", "AutoAttackEnabled", y)
    y = addNumericUnrestricted(combatFrame, "近接ダメージ", "Damage", y)
    y = addNumericUnrestricted(combatFrame, "近接間隔", "AttackInterval", y)
    y = addNumericUnrestricted(combatFrame, "近接範囲", "AttackRange", y)
    y = addToggleToFrame(combatFrame, "銃自動射撃", "GunEnabled", y)
    y = addNumericUnrestricted(combatFrame, "銃ダメージ", "GunDamage", y)
    y = addNumericUnrestricted(combatFrame, "銃間隔", "GunInterval", y)
    y = addNumericUnrestricted(combatFrame, "銃FOV", "GunFOV", y)
    y = addNumericUnrestricted(combatFrame, "銃射程", "GunMaxRange", y)
    y = addToggleToFrame(combatFrame, "RPG自動発射", "RPGEnabled", y)
    y = addNumericUnrestricted(combatFrame, "RPG通常間隔", "RPGInterval", y)
    y = addNumericUnrestricted(combatFrame, "RPG射程", "RPGRange", y)
    y = addToggleToFrame(combatFrame, "RPGミニガン", "RPGMinigun", y)
    y = addNumericUnrestricted(combatFrame, "RPGミニガン間隔", "RPGMinigunInterval", y)
    combatFrame.CanvasSize = UDim2.new(0, 0, 0, y + 20)

    -- グレネードフレーム
    y = 10
    y = addToggleToFrame(grenadeFrame, "グレネード有効", "GrenadeEnabled", y)
    y = addToggleToFrame(grenadeFrame, "本物グレネード", "UseAuthenticGrenade", y)
    y = addNumericUnrestricted(grenadeFrame, "通常間隔", "GrenadeInterval", y)
    y = addNumericUnrestricted(grenadeFrame, "射程", "GrenadeRange", y)
    y = addNumericUnrestricted(grenadeFrame, "ダメージ", "GrenadeDamage", y)
    y = addNumericUnrestricted(grenadeFrame, "誘導強度", "HomingStrength", y)
    y = addToggleToFrame(grenadeFrame, "ミニガンモード", "GrenadeMinigun", y)
    y = addNumericUnrestricted(grenadeFrame, "ミニガン間隔", "GrenadeMinigunInterval", y)
    y = addNumericUnrestricted(grenadeFrame, "最大同時数", "MaxActiveGrenades", y)
    grenadeFrame.CanvasSize = UDim2.new(0, 0, 0, y + 20)

    -- ESPフレーム
    y = 10
    y = addToggleToFrame(espFrame, "敵ESP", "EnemyESPEnabled", y)
    y = addToggleToFrame(espFrame, "ESPボックス", "ESP_Box", y)
    y = addToggleToFrame(espFrame, "ESPトレーサー", "ESP_Tracer", y)
    y = addToggleToFrame(espFrame, "ESPラベル", "ESP_Label", y)
    y = addToggleToFrame(espFrame, "色循環", "ESP_ColorCycle", y)
    y = addNumericUnrestricted(espFrame, "距離制限", "ESPDistanceLimit", y)
    y = addNumericUnrestricted(espFrame, "更新間隔", "ESPUpdateInterval", y)
    espFrame.CanvasSize = UDim2.new(0, 0, 0, y + 20)

    -- 車フレーム（Chunkmover・オブジェクト名・プレイヤー選択・キャンセル・座標指定）
    y = 10
    y = addButtonToFrame(vehicleFrame, "自分をChunkmoverにテレポート", y, function()
        teleportSelfToChunkmover()
    end)

    -- オブジェクト名入力
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0, 120, 0, 30)
    nameLabel.Position = UDim2.new(0, 10, 0, y)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "オブジェクト名:"
    nameLabel.TextColor3 = Color3.new(1,1,1)
    nameLabel.TextSize = 16
    nameLabel.Parent = vehicleFrame

    local nameInput = Instance.new("TextBox")
    nameInput.Size = UDim2.new(0, 150, 0, 30)
    nameInput.Position = UDim2.new(0, 130, 0, y)
    nameInput.BackgroundColor3 = Color3.fromRGB(60,60,60)
    nameInput.TextColor3 = Color3.new(1,1,1)
    nameInput.PlaceholderText = "Command"
    nameInput.Text = ""
    nameInput.TextSize = 16
    nameInput.Font = Enum.Font.SourceSans
    nameInput.Parent = vehicleFrame
    nameInput.FocusLost:Connect(function(enterPressed)
        vehicleTargetObjectName = nameInput.Text
    end)
    y = y + 35

    y = addButtonToFrame(vehicleFrame, "Chunkmoverを指定オブジェクトに飛ばす", y, function()
        flyChunkmoverToObject(vehicleTargetObjectName)
    end)

    -- プレイヤー選択サイクル
    local playerLabel = Instance.new("TextLabel")
    playerLabel.Size = UDim2.new(1, -20, 0, 30)
    playerLabel.Position = UDim2.new(0, 10, 0, y)
    playerLabel.BackgroundTransparency = 1
    playerLabel.Text = "選択プレイヤー: " .. (Players:GetPlayers()[selectedPlayerIndex] and Players:GetPlayers()[selectedPlayerIndex].Name or "なし")
    playerLabel.TextColor3 = Color3.new(1,1,1)
    playerLabel.TextSize = 16
    playerLabel.Font = Enum.Font.SourceSansBold
    playerLabel.Parent = vehicleFrame
    y = y + 35

    y = addButtonToFrame(vehicleFrame, "次のプレイヤー", y, function()
        local players = Players:GetPlayers()
        if #players == 0 then
            playerLabel.Text = "選択プレイヤー: なし"
            return
        end
        selectedPlayerIndex = selectedPlayerIndex % #players + 1
        local selected = players[selectedPlayerIndex]
        playerLabel.Text = "選択プレイヤー: " .. selected.Name
    end)

    y = addButtonToFrame(vehicleFrame, "Chunkmoverを選択プレイヤーに飛ばす", y, function()
        local players = Players:GetPlayers()
        if #players == 0 then return end
        local selected = players[selectedPlayerIndex]
        if selected and selected ~= LocalPlayer then
            flyChunkmoverToPlayer(selected)
        end
    end)

    -- 指定座標へ飛ばす
    y = addButtonToFrame(vehicleFrame, "指定座標に飛ばす", y, function()
        flyChunkmoverToPosition(Vector3.new(-795.02, 2516.95, 83579.28))
    end)

    -- キャンセル
    y = addButtonToFrame(vehicleFrame, "車の飛行をキャンセル", y, function()
        cancelCarFly()
    end)

    y = addNumericUnrestricted(vehicleFrame, "飛行速度 (studs/s)", "VehicleFlySpeed", y)

    y = addToggleToFrame(vehicleFrame, "Anti-Lag", "AntiLagEnabled", y)
    y = addNumericUnrestricted(vehicleFrame, "スキャン間隔", "TargetScanInterval", y)

    vehicleFrame.CanvasSize = UDim2.new(0, 0, 0, y + 20)

    -- メニュー切替
    local function showFrame(frameKey)
        combatFrame.Visible = false
        grenadeFrame.Visible = false
        espFrame.Visible = false
        vehicleFrame.Visible = false
        if frameKey == "combat" then combatFrame.Visible = true
        elseif frameKey == "grenade" then grenadeFrame.Visible = true
        elseif frameKey == "esp" then espFrame.Visible = true
        elseif frameKey == "vehicle" then vehicleFrame.Visible = true
        end
        for key, btn in pairs(menuButtons) do
            btn.BackgroundColor3 = (key == frameKey) and Color3.fromRGB(255,105,180) or Color3.fromRGB(60,60,60)
        end
    end

    menuButtons.combat.Activated:Connect(function() showFrame("combat") end)
    menuButtons.grenade.Activated:Connect(function() showFrame("grenade") end)
    menuButtons.esp.Activated:Connect(function() showFrame("esp") end)
    menuButtons.vehicle.Activated:Connect(function() showFrame("vehicle") end)

    showFrame("combat")

    settingsButton.Activated:Connect(function()
        panel.Visible = not panel.Visible
    end)
end

task.spawn(createSettingsUI)

-- ============================================================
-- ★★★ ロード通知（チャット） ★★★
-- ============================================================
local function sendChatMessage(msg)
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local channels = TextChatService:FindFirstChild("TextChannels")
        if channels then
            local general = channels:FindFirstChild("RBXGeneral")
            if general and general:IsA("TextChannel") then
                general:SendAsync(msg)
                return
            end
        end
    end)
    pcall(function()
        game:GetService("Players"):Chat(msg)
    end)
end

task.spawn(function()
    task.wait(1)
    sendChatMessage("キャットハブロード")
end)

-- ============================================================
-- ★★★ メインループ ★★★
-- ============================================================
RunService.Heartbeat:Connect(function()
    local now = tick()

    if SETTINGS.AutoAttackEnabled and now - lastAttackTime >= SETTINGS.AttackInterval then
        local targets = findAllTargets(SETTINGS.AttackRange)
        for _, target in ipairs(targets) do
            if target.Humanoid and target.Humanoid.Health > 0 then
                attackTarget(target)
                lastAttackTime = now
                break
            end
        end
    end

    gunShoot()
    fireRPG()

    if SETTINGS.GrenadeEnabled then
        local interval = SETTINGS.GrenadeMinigun and SETTINGS.GrenadeMinigunInterval or SETTINGS.GrenadeInterval
        if now - lastGrenadeTime >= interval then
            local targets = findAllTargets(SETTINGS.GrenadeRange)
            if #targets > 0 then
                lastGrenadeTime = now
                throwGrenadeAt(targets[1])
            end
        end
    end
end)

print("✅ オート攻撃 + 銃 + グレネードミニガン + RPGミニガン + 敵ESP + Chunkmover滑空（キャンセル・座標指定） + Anti-Lag + 制限解除UI + ロード通知 起動完了")
print("📌 Chunkmoverを自由に操り、指定座標への飛行・途中キャンセルが可能")
