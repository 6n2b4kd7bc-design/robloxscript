-- language: Lua, target: Roblox
-- Movement Suite 完全版 — Obsidian UI
-- Movement / Attack / UnHook / Veil / Parry / Bring / ESP / Aim / Mobile Hold

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
-- 設定
-- ============================================================
local config = {
    speedEnabled = false, speedMode = "Smooth", speedValue = 80,
    flyEnabled = false, flySpeed = 60,
    noclip = false, infJump = false, antiFling = false, lowGravity = false,
    dashKey = Enum.KeyCode.V, dashRange = 30,

    atkEnabled = false, atkMode = "Always", atkKey = Enum.KeyCode.E,
    atkArgMode = "None", atkCps = 15, atkMaxBurst = 5, atkFireCount = 0,

    unhookEnabled = false, unhookMode = "Always", unhookKey = Enum.KeyCode.Q,
    unhookCps = 15, unhookMaxBurst = 5, unhookFireCount = 0,

    veilVfxSpam = false, veilVfxInterval = 0.1, veilVfxFireCount = 0,
    veilSpearEnabled = false, veilSpearMode = "SilentAim", veilSpearCps = 3,
    veilSpearDamage = 165, veilSpearTeamCheck = true, veilSpearMaxDist = 1000,
    veilSpearFireCount = 0,

    parryEnabled = false,
    parryAutoDetect = true,
    parrySpam = false,
    parrySpamCps = 20,
    parryTeamCheck = true,
    parryMaxDist = 15,
    parryFacingCheck = true,
    parryFacingAngle = 120,
    parryCooldown = 0.15,
    parryBurst = 2,
    parryFireCount = 0,

    bringLoop = false, bringLayout = "Stack", bringDistance = 5,
    bringSpacing = 6, bringInterval = 0.15, bringTeamCheck = true,
    bringStealOwnership = true, bringCount = 0,

    espEnabled = false, espTeamCheck = true, espTeamColor = true,
    espEnemyColor = Color3.fromRGB(255, 60, 60),
    espAllyColor = Color3.fromRGB(80, 200, 255),
    espSelfColor = Color3.fromRGB(80, 255, 120),
    espFill = true, espDepthMode = "AlwaysOnTop",
    espMaxDist = 2000, espShowSelf = false,

    aimEnabled = false, aimTeamCheck = true, aimWallCheck = true,
    aimFov = 80, aimMaxDist = 500, aimStrength = 8,
    aimHitbox = "Head", aimTargets = 0,
}

local flyVel, flyAlign
local savedGravity = workspace.Gravity

-- ============================================================
-- チーム判定
-- ============================================================
local function isTeammate(plr)
    if plr == LocalPlayer then return true end
    if plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then return true end
    if plr.TeamColor and LocalPlayer.TeamColor
       and plr.TeamColor == LocalPlayer.TeamColor
       and plr.TeamColor.Name ~= "White" then return true end
    local pT = plr:GetAttribute("Team")
    local lT = LocalPlayer:GetAttribute("Team")
    if pT and lT and pT == lT then return true end
    return false
end

local function getTeamColor(plr)
    if plr.TeamColor then return plr.TeamColor.Color end
    if plr.Team then return plr.Team.TeamColor.Color end
    return config.espAllyColor
end

-- ============================================================
-- Raycast
-- ============================================================
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function hasLineOfSight(targetPart)
    local origin = Camera.CFrame.Position
    local dir = targetPart.Position - origin
    if dir.Magnitude < 0.1 then return true end
    local filter = { LocalPlayer.Character }
    if targetPart.Parent then table.insert(filter, targetPart.Parent) end
    raycastParams.FilterDescendantsInstances = filter
    return workspace:Raycast(origin, dir, raycastParams) == nil
end

-- ============================================================
-- リモート解決
-- ============================================================
local attackRemote, unhookRemote, parryRemote
local veilUpdateWep, veilVfx, veilSpear

do
    local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
    if Remotes then
        local Attacks = Remotes:FindFirstChild("Attacks")
        if Attacks then attackRemote = Attacks:FindFirstChild("BasicAttack") end
        local Carry = Remotes:FindFirstChild("Carry")
        if Carry then unhookRemote = Carry:FindFirstChild("SelfUnHookEvent") end
        local Items = Remotes:FindFirstChild("Items")
        if Items then
            local PD = Items:FindFirstChild("Parrying Dagger")
            if PD then parryRemote = PD:FindFirstChild("parry") end
        end
        local Killers = Remotes:FindFirstChild("Killers")
        if Killers then
            local Veil = Killers:FindFirstChild("Veil")
            if Veil then
                veilUpdateWep = Veil:FindFirstChild("updatewep")
                veilVfx       = Veil:FindFirstChild("vfx")
                veilSpear     = Veil:FindFirstChild("Spearthrow")
            end
        end
    end
    print("[Suite] BasicAttack      =", attackRemote and "OK" or "MISSING")
    print("[Suite] SelfUnHookEvent  =", unhookRemote and "OK" or "MISSING")
    print("[Suite] Parry            =", parryRemote and "OK" or "MISSING")
    print("[Suite] Veil.updatewep   =", veilUpdateWep and "OK" or "MISSING")
    print("[Suite] Veil.vfx         =", veilVfx and "OK" or "MISSING")
    print("[Suite] Veil.Spearthrow  =", veilSpear and "OK" or "MISSING")
end

local function fireAttack()
    if not attackRemote then return false end
    local ok
    if config.atkArgMode == "True" then
        ok = pcall(function() attackRemote:FireServer(true) end)
    elseif config.atkArgMode == "False" then
        ok = pcall(function() attackRemote:FireServer(false) end)
    else
        ok = pcall(function() attackRemote:FireServer() end)
    end
    if ok then config.atkFireCount = config.atkFireCount + 1 end
    return ok
end

local function fireUnhook()
    if not unhookRemote then return false end
    local ok = pcall(function() unhookRemote:FireServer() end)
    if ok then config.unhookFireCount = config.unhookFireCount + 1 end
    return ok
end

local function fireParry()
    if not parryRemote then return false end
    local ok = pcall(function() parryRemote:FireServer() end)
    if ok then config.parryFireCount = config.parryFireCount + 1 end
    return ok
end

local function fireVeilUpdateWep()
    if not veilUpdateWep then return false end
    return (pcall(function() veilUpdateWep:FireServer(true) end))
end

local function fireVeilVfx()
    if not veilVfx then return false end
    local ok = pcall(function() veilVfx:FireServer(2, true, true) end)
    if ok then config.veilVfxFireCount = config.veilVfxFireCount + 1 end
    return ok
end

-- ============================================================
-- 仮想ホールド
-- ============================================================
local virtualHold = { attack = false, unhook = false, parry = false }

-- ============================================================
-- モバイル ホールドボタン
-- ============================================================
local pguiRoot = CoreGui or LocalPlayer:WaitForChild("PlayerGui")
if pguiRoot:FindFirstChild("MobileHoldUI") then pguiRoot.MobileHoldUI:Destroy() end

local holdGui = Instance.new("ScreenGui")
holdGui.Name = "MobileHoldUI"
holdGui.ResetOnSpawn = false
holdGui.IgnoreGuiInset = true
holdGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
holdGui.Parent = pguiRoot

local holdButtons = {}

local function makeHoldButton(action, label, color, order)
    local btn = Instance.new("TextButton")
    btn.Name = "Hold_" .. action
    btn.Size = UDim2.new(0, 90, 0, 90)
    btn.Position = UDim2.new(1, -110 - (order - 1) * 105, 1, -140)
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.15
    btn.Text = label
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.Visible = false
    btn.ZIndex = 20
    btn.Parent = holdGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = 2
    stroke.Transparency = 0.4

    local pressed = false
    local function press()
        if pressed then return end
        pressed = true
        virtualHold[action] = true
        btn.BackgroundTransparency = 0.35
        stroke.Transparency = 0.1
    end
    local function release()
        if not pressed then return end
        pressed = false
        virtualHold[action] = false
        btn.BackgroundTransparency = 0.15
        stroke.Transparency = 0.4
    end

    local dragging, dragStart, startPos, moved = false, nil, nil, false
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; moved = false
            dragStart = input.Position; startPos = btn.Position
            press()
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false; release()
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if math.abs(delta.X) + math.abs(delta.Y) > 6 then moved = true end
            if moved then
                btn.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    holdButtons[action] = btn
    return btn
end

makeHoldButton("attack", "ATTACK\nHOLD", Color3.fromRGB(220, 60, 60), 1)
makeHoldButton("unhook", "UNHOOK\nHOLD", Color3.fromRGB(220, 140, 40), 2)
makeHoldButton("parry",  "PARRY\nHOLD",  Color3.fromRGB(60, 160, 220), 3)

local function refreshHoldButtons()
    if holdButtons.attack then holdButtons.attack.Visible = (config.atkMode == "Hold") end
    if holdButtons.unhook then holdButtons.unhook.Visible = (config.unhookMode == "Hold") end
    if holdButtons.parry  then holdButtons.parry.Visible  = (config.parryMode == "Hold") end
end

-- ============================================================
-- Speed / Fly / Noclip / InfJump / Anti-Fling / LowGrav / Dash
-- ============================================================
local function getMoveDir(hum)
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude < 0.01 then return nil end
    local cam = Camera.CFrame
    local fl = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
    local fr = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z)
    if fl.Magnitude > 0 then fl = fl.Unit end
    if fr.Magnitude > 0 then fr = fr.Unit end
    local v = fl * moveDir:Dot(fl) + fr * moveDir:Dot(fr)
    if v.Magnitude > 0 then v = v.Unit end
    return v
end

local speedVel
local function ensureSpeedVel(root)
    if speedVel and speedVel.Parent == root then return end
    if speedVel then speedVel:Destroy() end
    speedVel = Instance.new("BodyVelocity")
    speedVel.MaxForce = Vector3.new(1e5, 0, 1e5)
    speedVel.P = 1250
    speedVel.Velocity = Vector3.zero
    speedVel.Parent = root
end
local function destroySpeedVel()
    if speedVel then speedVel:Destroy(); speedVel = nil end
end

RunService.RenderStepped:Connect(function(dt)
    if not config.speedEnabled then
        if speedVel then speedVel.Velocity = Vector3.zero end
        return
    end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if not (root and hum) then return end
    local dir = getMoveDir(hum)
    if config.speedMode == "Smooth" then
        ensureSpeedVel(root)
        speedVel.Velocity = dir and (dir * config.speedValue) or Vector3.zero
    elseif config.speedMode == "Direct" then
        destroySpeedVel()
        if dir then
            local step = dir * config.speedValue * dt
            if step.Magnitude > 4 then step = step.Unit * 4 end
            root.CFrame = root.CFrame + step
            root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
        end
    elseif config.speedMode == "Hybrid" then
        ensureSpeedVel(root)
        speedVel.Velocity = dir and (dir * config.speedValue) or Vector3.zero
        if dir then
            local step = dir * config.speedValue * dt * 0.5
            if step.Magnitude > 2 then step = step.Unit * 2 end
            root.CFrame = root.CFrame + step
        end
    end
end)

local function startFly()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if flyVel then flyVel:Destroy() end
    if flyAlign then flyAlign:Destroy() end
    flyVel = Instance.new("LinearVelocity")
    flyVel.MaxForce = math.huge
    flyVel.VectorVelocity = Vector3.zero
    flyVel.RelativeTo = Enum.ActuatorRelativeTo.World
    flyVel.Attachment0 = Instance.new("Attachment", root)
    flyVel.Parent = root
    flyAlign = Instance.new("AlignOrientation")
    flyAlign.MaxTorque = math.huge
    flyAlign.Responsiveness = 200
    flyAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
    flyAlign.Attachment0 = flyVel.Attachment0
    flyAlign.Parent = root
end
local function stopFly()
    if flyVel then
        if flyVel.Attachment0 then flyVel.Attachment0:Destroy() end
        flyVel:Destroy(); flyVel = nil
    end
    if flyAlign then flyAlign:Destroy(); flyAlign = nil end
end

RunService.RenderStepped:Connect(function()
    if not config.flyEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if not (root and hum) then return end
    if not flyVel then startFly() end
    if not flyVel then return end
    local moveDir = hum.MoveDirection
    local cam = Camera.CFrame
    local dir3D = Vector3.zero
    if moveDir.Magnitude > 0 then
        local fl = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z).Unit
        local fr = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z).Unit
        dir3D = cam.LookVector * moveDir:Dot(fl) + cam.RightVector * moveDir:Dot(fr)
        if dir3D.Magnitude > 0 then dir3D = dir3D.Unit end
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        dir3D = dir3D + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
       or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
        dir3D = dir3D + Vector3.new(0, -1, 0)
    end
    flyVel.VectorVelocity = dir3D * config.flySpeed
    flyAlign.CFrame = CFrame.new(root.Position, root.Position + cam.LookVector)
    root.AssemblyAngularVelocity = Vector3.zero
end)

task.spawn(function()
    while task.wait(0.2) do
        if config.noclip and LocalPlayer.Character then
            for _, p in ipairs(LocalPlayer.Character:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if not config.infJump then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if hum:GetState() == Enum.HumanoidStateType.Freefall
       or hum:GetState() == Enum.HumanoidStateType.Jumping then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

task.spawn(function()
    while task.wait(0.2) do
        if config.antiFling then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    for _, part in ipairs(p.Character:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        if config.lowGravity then
            workspace.Gravity = savedGravity * 0.3
        elseif not config.lowGravity and workspace.Gravity ~= savedGravity then
            workspace.Gravity = savedGravity
        end
    end
end)

local function doDash()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local cam = Camera.CFrame
    local flat = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z).Unit
    task.spawn(function()
        local remaining = config.dashRange
        while remaining > 0 do
            local step = math.min(remaining, 3)
            root.CFrame = root.CFrame + flat * step
            remaining = remaining - step
            RunService.RenderStepped:Wait()
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == config.dashKey then doDash() end
end)

-- ============================================================
-- Auto Attack / UnHook / Veil loops
-- ============================================================
local atkAccum = 0
RunService.Heartbeat:Connect(function(dt)
    if not config.atkEnabled then atkAccum = 0 return end
    if not attackRemote then return end
    local shouldFire = false
    if config.atkMode == "Always" then shouldFire = true
    elseif config.atkMode == "Hold" then
        shouldFire = UserInputService:IsKeyDown(config.atkKey) or virtualHold.attack
    elseif config.atkMode == "Keybind" then shouldFire = true end
    if not shouldFire then atkAccum = 0 return end
    atkAccum = atkAccum + dt
    local interval = 1 / math.max(config.atkCps, 0.1)
    local burst = 0
    while atkAccum >= interval and burst < config.atkMaxBurst do
        atkAccum = atkAccum - interval
        fireAttack()
        burst = burst + 1
    end
    if burst >= config.atkMaxBurst then atkAccum = 0 end
end)

local unhookAccum = 0
RunService.Heartbeat:Connect(function(dt)
    if not config.unhookEnabled then unhookAccum = 0 return end
    if not unhookRemote then return end
    local shouldFire = false
    if config.unhookMode == "Always" then shouldFire = true
    elseif config.unhookMode == "Hold" then
        shouldFire = UserInputService:IsKeyDown(config.unhookKey) or virtualHold.unhook
    end
    if not shouldFire then unhookAccum = 0 return end
    unhookAccum = unhookAccum + dt
    local interval = 1 / math.max(config.unhookCps, 0.1)
    local burst = 0
    while unhookAccum >= interval and burst < config.unhookMaxBurst do
        unhookAccum = unhookAccum - interval
        fireUnhook()
        burst = burst + 1
    end
    if burst >= config.unhookMaxBurst then unhookAccum = 0 end
end)

local function selectVeilTarget()
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local myPos = myRoot.Position
    local best, bestDist = nil, config.veilSpearMaxDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local skip = false
            if config.veilSpearTeamCheck and isTeammate(plr) then skip = true end
            if not skip then
                local head = plr.Character:FindFirstChild("Head")
                local hum  = plr.Character:FindFirstChildOfClass("Humanoid")
                if head and hum and hum.Health > 0 then
                    local d = (myPos - head.Position).Magnitude
                    if d < bestDist then best = head; bestDist = d end
                end
            end
        end
    end
    return best
end

local function fireVeilSpear()
    if not veilSpear then return false end
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false end
    local targetPos, targetDir
    if config.veilSpearMode == "SilentAim" then
        local target = selectVeilTarget()
        if target then
            targetPos = target.Position
            targetDir = (target.Position - myRoot.Position).Unit
        else
            local cam = Camera.CFrame
            targetPos = myRoot.Position + cam.LookVector * 500
            targetDir = cam.LookVector
        end
    else
        local cam = Camera.CFrame
        targetPos = myRoot.Position + cam.LookVector * 500
        targetDir = cam.LookVector
    end
    local ok = pcall(function()
        veilSpear:FireServer(targetDir, config.veilSpearDamage, targetPos)
    end)
    if ok then config.veilSpearFireCount = config.veilSpearFireCount + 1 end
    return ok
end

local veilSpearAccum = 0
RunService.Heartbeat:Connect(function(dt)
    if not config.veilSpearEnabled then veilSpearAccum = 0 return end
    if not veilSpear then return end
    veilSpearAccum = veilSpearAccum + dt
    local interval = 1 / math.max(config.veilSpearCps, 0.1)
    local burst = 0
    while veilSpearAccum >= interval and burst < 3 do
        veilSpearAccum = veilSpearAccum - interval
        fireVeilSpear()
        burst = burst + 1
    end
    if burst >= 3 then veilSpearAccum = 0 end
end)

task.spawn(function()
    while true do
        if config.veilVfxSpam and veilVfx then
            pcall(fireVeilVfx)
            task.wait(math.max(config.veilVfxInterval, 0.05))
        else
            task.wait(0.2)
        end
    end
end)

-- ============================================================
-- Auto Parry
-- ============================================================
local ATTACK_ANIM_PATTERNS = {
    "attack", "swing", "slash", "punch", "stab",
    "hit", "combat", "sword", "melee", "weapon",
}

local function isAttackAnim(name)
    if not name or name == "" then return false end
    local l = name:lower()
    for _, p in ipairs(ATTACK_ANIM_PATTERNS) do
        if l:find(p, 1, true) then return true end
    end
    return false
end

local parryLastByPlayer = {}

local function tryParry()
    if not config.parryEnabled then return end
    if not parryRemote then return end
    task.spawn(function()
        fireParry()
        for i = 2, math.max(config.parryBurst, 1) do
            task.wait(0.02)
            if not config.parryEnabled then break end
            fireParry()
        end
    end)
end

local function hookParryChar(plr, char)
    if not char then return end
    task.spawn(function()
        local animator = char:WaitForChild("Animator", 8)
        if not animator then return end
        animator.AnimationPlayed:Connect(function(track)
            if not config.parryEnabled then return end
            if not config.parryAutoDetect then return end

            local aName = track.Animation and track.Animation.Name or ""
            local tName = track.Name or ""
            if not (isAttackAnim(aName) or isAttackAnim(tName)) then return end

            if config.parryTeamCheck and isTeammate(plr) then return end

            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local theirRoot = char:FindFirstChild("HumanoidRootPart")
            if not (myRoot and theirRoot) then return end

            local dist = (myRoot.Position - theirRoot.Position).Magnitude
            if dist > config.parryMaxDist then return end

            if config.parryFacingCheck then
                local myLook = myRoot.CFrame.LookVector
                local toThem = (theirRoot.Position - myRoot.Position)
                if toThem.Magnitude > 0.1 then
                    toThem = toThem.Unit
                    local dot = myLook:Dot(toThem)
                    if dot < math.cos(math.rad(config.parryFacingAngle / 2)) then return end
                end
            end

            local now = tick()
            local last = parryLastByPlayer[plr]
            if last and now - last < config.parryCooldown then return end
            parryLastByPlayer[plr] = now

            tryParry()
        end)
    end)
end

local function hookParryPlayer(plr)
    if plr == LocalPlayer then return end
    if plr.Character then hookParryChar(plr, plr.Character) end
    plr.CharacterAdded:Connect(function(char) hookParryChar(plr, char) end)
end

for _, plr in ipairs(Players:GetPlayers()) do hookParryPlayer(plr) end
Players.PlayerAdded:Connect(hookParryPlayer)

-- Proactive spam loop
task.spawn(function()
    while true do
        if config.parryEnabled and config.parrySpam and parryRemote then
            fireParry()
            task.wait(1 / math.max(config.parrySpamCps, 1))
        else
            task.wait(0.05)
        end
    end
end)

-- Hold-loop (virtual button / keyboard)
task.spawn(function()
    while true do
        if config.parryEnabled and config.parryMode == "Hold" then
            local held = UserInputService:IsKeyDown(config.parryKey) or virtualHold.parry
            if held then
                fireParry()
                task.wait(0.02)
            else
                task.wait(0.02)
            end
        else
            task.wait(0.1)
        end
    end
end)

-- ============================================================
-- Bring
-- ============================================================
local function bringPlayers()
    local char = LocalPlayer.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return 0 end
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            if not (config.bringTeamCheck and isTeammate(plr)) then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    table.insert(list, hrp)
                end
            end
        end
    end
    if #list == 0 then return 0 end

    local myCF = myRoot.CFrame
    local forward = myCF.LookVector
    local right = myCF.RightVector
    local basePos = myRoot.Position + forward * config.bringDistance
    local placed = 0
    for i, hrp in ipairs(list) do
        local targetPos
        if config.bringLayout == "Stack" then targetPos = basePos
        elseif config.bringLayout == "Row" then
            local offset = (i - (#list + 1) / 2) * config.bringSpacing
            targetPos = basePos + right * offset
        elseif config.bringLayout == "Circle" then
            local angle = ((i - 1) / #list) * math.pi * 2
            targetPos = basePos + Vector3.new(
                math.cos(angle) * config.bringSpacing, 0,
                math.sin(angle) * config.bringSpacing)
        else targetPos = basePos end
        if config.bringStealOwnership then
            pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
        end
        local ok = pcall(function()
            local rot = (hrp.CFrame - hrp.CFrame.Position)
            hrp.CFrame = CFrame.new(targetPos) * rot
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        if ok then placed = placed + 1 end
    end
    config.bringCount = placed
    return placed
end

task.spawn(function()
    while true do
        if config.bringLoop then
            pcall(bringPlayers)
            task.wait(math.max(config.bringInterval, 0.05))
        else
            task.wait(0.1)
        end
    end
end)

-- ============================================================
-- ESP
-- ============================================================
local ESP_HIGHLIGHTS = {}

local function createHighlight(char)
    local h = Instance.new("Highlight")
    h.Name = "TrollESP"
    h.Adornee = char
    h.FillTransparency = config.espFill and 0.6 or 1
    h.OutlineTransparency = 0
    h.DepthMode = config.espDepthMode == "AlwaysOnTop"
        and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded
    h.Parent = char
    return h
end

local function updateHighlightColor(h, plr)
    if plr == LocalPlayer then
        h.FillColor = config.espSelfColor
        h.OutlineColor = config.espSelfColor
        return
    end
    if config.espTeamColor and isTeammate(plr) then
        local c = getTeamColor(plr)
        h.FillColor = c; h.OutlineColor = c
    elseif not config.espTeamCheck and isTeammate(plr) then
        h.FillColor = config.espEnemyColor
        h.OutlineColor = config.espEnemyColor
    else
        h.FillColor = config.espEnemyColor
        h.OutlineColor = config.espEnemyColor
    end
end

local function updateESP()
    if not config.espEnabled then
        for plr, h in pairs(ESP_HIGHLIGHTS) do
            if h and h.Parent then h:Destroy() end
        end
        ESP_HIGHLIGHTS = {}
        return
    end

    local myPos = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        and LocalPlayer.Character.HumanoidRootPart.Position

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then
            if config.espShowSelf and plr.Character then
                local h = ESP_HIGHLIGHTS[plr]
                if not h or not h.Parent then
                    h = createHighlight(plr.Character)
                    ESP_HIGHLIGHTS[plr] = h
                end
                h.Adornee = plr.Character
                h.Enabled = true
                updateHighlightColor(h, plr)
            else
                local h = ESP_HIGHLIGHTS[plr]
                if h then h.Enabled = false end
            end
        else
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local shouldShow = char and hum and hum.Health > 0 and hrp
            if shouldShow and myPos then
                local d = (myPos - hrp.Position).Magnitude
                if d > config.espMaxDist then shouldShow = false end
            end
            if shouldShow then
                local h = ESP_HIGHLIGHTS[plr]
                if not h or not h.Parent then
                    h = createHighlight(char)
                    ESP_HIGHLIGHTS[plr] = h
                end
                h.Adornee = char
                h.Enabled = true
                h.FillTransparency = config.espFill and 0.6 or 1
                h.DepthMode = config.espDepthMode == "AlwaysOnTop"
                    and Enum.HighlightDepthMode.AlwaysOnTop
                    or Enum.HighlightDepthMode.Occluded
                updateHighlightColor(h, plr)
            else
                local h = ESP_HIGHLIGHTS[plr]
                if h then h.Enabled = false end
            end
        end
    end
    for plr, h in pairs(ESP_HIGHLIGHTS) do
        if not plr.Parent then
            if h and h.Parent then h:Destroy() end
            ESP_HIGHLIGHTS[plr] = nil
        end
    end
end

task.spawn(function()
    while task.wait(1 / 15) do pcall(updateESP) end
end)

-- ============================================================
-- Aim Assist
-- ============================================================
local aimBound = false

local function aimAssistStep(dt)
    if not config.aimEnabled then return end
    local camCF = Camera.CFrame
    local camPos = camCF.Position
    local camLook = camCF.LookVector
    local candidates = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local skip = false
            if config.aimTeamCheck and isTeammate(plr) then skip = true end
            if not skip then
                local char = plr.Character
                local hum = char:FindFirstChildOfClass("Humanoid")
                local part
                if config.aimHitbox == "Head" then part = char:FindFirstChild("Head")
                else part = char:FindFirstChild("HumanoidRootPart") end
                if part and hum and hum.Health > 0 then
                    local dist = (camPos - part.Position).Magnitude
                    if dist <= config.aimMaxDist then
                        local toTarget = part.Position - camPos
                        if toTarget.Magnitude > 0.1 then
                            local dot = camLook:Dot(toTarget.Unit)
                            local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
                            if angle <= config.aimFov then
                                table.insert(candidates, { part = part, angle = angle, dist = dist })
                            end
                        end
                    end
                end
            end
        end
    end
    if #candidates == 0 then config.aimTargets = 0 return end
    table.sort(candidates, function(a, b) return a.angle < b.angle end)
    local target = nil
    for _, c in ipairs(candidates) do
        if not config.aimWallCheck or hasLineOfSight(c.part) then
            target = c.part; break
        end
    end
    if not target then config.aimTargets = 0 return end
    config.aimTargets = #candidates
    local targetCF = CFrame.new(camPos, target.Position)
    local alpha = 1 - math.exp(-config.aimStrength * dt)
    Camera.CFrame = camCF:Lerp(targetCF, math.clamp(alpha, 0, 1))
end

if not aimBound then
    RunService:BindToRenderStep("TrollAimAssist",
        Enum.RenderPriority.Camera.Value + 1, aimAssistStep)
    aimBound = true
end

-- ============================================================
-- Obsidian UI
-- ============================================================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Movement Suite", Footer = "Obsidian | Full",
    NotifySide = "Right", ShowCustomCursor = true, Resizable = true,
})

local MainTab    = Window:AddTab("Main", "footprints")
local AttackTab  = Window:AddTab("Attacks", "sword")
local ParryTab   = Window:AddTab("Parry", "shield")
local AimTab     = Window:AddTab("Aim Assist", "crosshair")
local BringTab   = Window:AddTab("Bring", "users")
local EspTab     = Window:AddTab("ESP", "eye")
local ExtraTab   = Window:AddTab("Extra", "zap")
local ConfigTab  = Window:AddTab("Config", "settings")

-- Main
local SpeedGB = MainTab:AddLeftGroupbox("Speed", "rabbit")
SpeedGB:AddToggle("SpeedEnabled", {
    Text = "Speed 有効", Default = config.speedEnabled,
    Callback = function(v)
        config.speedEnabled = v
        if not v then destroySpeedVel() end
    end,
})
SpeedGB:AddDropdown("SpeedMode", {
    Values = { "Smooth", "Direct", "Hybrid" }, Default = "Smooth",
    Text = "モード", Callback = function(v) config.speedMode = v end,
})
SpeedGB:AddSlider("SpeedValue", {
    Text = "速度", Default = config.speedValue,
    Min = 20, Max = 400, Rounding = 0, Compact = false, Suffix = " studs/s",
    Callback = function(v) config.speedValue = v end,
})

local FlyGB = MainTab:AddRightGroupbox("Fly", "plane")
FlyGB:AddToggle("FlyEnabled", {
    Text = "Fly 有効", Default = config.flyEnabled,
    Tooltip = "Space = 上昇 / Shift = 下降",
    Callback = function(v)
        config.flyEnabled = v
        if v then startFly() else stopFly() end
    end,
})
FlyGB:AddSlider("FlySpeed", {
    Text = "Fly 速度", Default = config.flySpeed,
    Min = 10, Max = 300, Rounding = 0, Compact = false, Suffix = " studs/s",
    Callback = function(v) config.flySpeed = v end,
})

-- Attacks
local AtkGB = AttackTab:AddLeftGroupbox("Auto Attack", "sword")
AtkGB:AddToggle("AtkEnabled", {
    Text = "Auto Attack", Default = config.atkEnabled,
    Callback = function(v) config.atkEnabled = v end,
})
AtkGB:AddDropdown("AtkMode", {
    Values = { "Always", "Hold", "Keybind" }, Default = "Always",
    Text = "発火モード", Tooltip = "Hold でモバイルボタン出現",
    Callback = function(v) config.atkMode = v; refreshHoldButtons() end,
})
AtkGB:AddDropdown("AtkArgMode", {
    Values = { "None", "True", "False" }, Default = "None",
    Text = "引数", Tooltip = "None = FireServer() / True = FireServer(true)",
    Callback = function(v) config.atkArgMode = v end,
})
AtkGB:AddSlider("AtkCps", {
    Text = "CPS", Default = config.atkCps,
    Min = 1, Max = 60, Rounding = 0, Compact = false, Suffix = " /s",
    Callback = function(v) config.atkCps = v end,
})
AtkGB:AddSlider("AtkMaxBurst", {
    Text = "Max Burst", Default = config.atkMaxBurst,
    Min = 1, Max = 20, Rounding = 0, Compact = false,
    Callback = function(v) config.atkMaxBurst = v end,
})
AtkGB:AddButton({
    Text = "Manual Fire (1発)",
    Func = function()
        fireAttack()
        Library:Notify({ Title = "Manual Fire",
            Description = "Fire Count: " .. config.atkFireCount, Time = 2 })
    end, DoubleClick = false,
})
AtkGB:AddLabel("Fire Count: 0", true, "AtkStatusLabel")

task.spawn(function()
    while task.wait(0.5) do
        if Options.AtkStatusLabel then pcall(function()
            Options.AtkStatusLabel:SetText(
                ("Fire Count: %d\nRemote: %s | Arg: %s"):format(
                    config.atkFireCount,
                    attackRemote and "Found" or "Missing",
                    config.atkArgMode))
        end) end
    end
end)

local UnhookGB = AttackTab:AddRightGroupbox("Carry / UnHook", "unlock")
UnhookGB:AddToggle("UnhookEnabled", {
    Text = "SelfUnHook 連投", Default = config.unhookEnabled,
    Callback = function(v) config.unhookEnabled = v end,
})
UnhookGB:AddDropdown("UnhookMode", {
    Values = { "Always", "Hold" }, Default = "Always",
    Text = "発火モード", Callback = function(v) config.unhookMode = v; refreshHoldButtons() end,
})
UnhookGB:AddSlider("UnhookCps", {
    Text = "CPS", Default = config.unhookCps,
    Min = 1, Max = 60, Rounding = 0, Compact = false, Suffix = " /s",
    Callback = function(v) config.unhookCps = v end,
})
UnhookGB:AddSlider("UnhookMaxBurst", {
    Text = "Max Burst", Default = config.unhookMaxBurst,
    Min = 1, Max = 20, Rounding = 0, Compact = false,
    Callback = function(v) config.unhookMaxBurst = v end,
})
UnhookGB:AddButton({
    Text = "Manual UnHook",
    Func = function()
        local ok = fireUnhook()
        Library:Notify({ Title = "UnHook",
            Description = ok and ("Fires: " .. config.unhookFireCount) or "Missing", Time = 2 })
    end, DoubleClick = false,
})

-- Veil
local VeilGB = AttackTab:AddLeftGroupbox("Veil / Killers", "swords")
VeilGB:AddButton({
    Text = "Auto Equip (updatewep)",
    Func = function()
        local ok = fireVeilUpdateWep()
        Library:Notify({ Title = "Veil",
            Description = ok and "updatewep(true) sent" or "Missing", Time = 2 })
    end, DoubleClick = false,
})
VeilGB:AddToggle("VeilVfxSpam", {
    Text = "VFX Spam", Default = config.veilVfxSpam,
    Callback = function(v) config.veilVfxSpam = v end,
})
VeilGB:AddSlider("VeilVfxInterval", {
    Text = "VFX 間隔", Default = config.veilVfxInterval,
    Min = 0.05, Max = 2, Rounding = 2, Compact = false, Suffix = " s",
    Callback = function(v) config.veilVfxInterval = v end,
})
VeilGB:AddDivider()
VeilGB:AddToggle("VeilSpearEnabled", {
    Text = "Spearthrow 連投", Default = config.veilSpearEnabled,
    Callback = function(v) config.veilSpearEnabled = v end,
})
VeilGB:AddDropdown("VeilSpearMode", {
    Values = { "SilentAim", "Camera" }, Default = "SilentAim",
    Text = "発射モード", Callback = function(v) config.veilSpearMode = v end,
})
VeilGB:AddSlider("VeilSpearCps", {
    Text = "CPS", Default = config.veilSpearCps,
    Min = 1, Max = 30, Rounding = 0, Compact = false, Suffix = " /s",
    Callback = function(v) config.veilSpearCps = v end,
})
VeilGB:AddSlider("VeilSpearDamage", {
    Text = "Arg2 (元コード = 165)", Default = config.veilSpearDamage,
    Min = 1, Max = 1000, Rounding = 0, Compact = false,
    Callback = function(v) config.veilSpearDamage = v end,
})
VeilGB:AddSlider("VeilSpearMaxDist", {
    Text = "最大距離", Default = config.veilSpearMaxDist,
    Min = 50, Max = 5000, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.veilSpearMaxDist = v end,
})

-- Parry
local ParryGB = ParryTab:AddLeftGroupbox("Auto Parry", "shield")
ParryGB:AddToggle("ParryEnabled", {
    Text = "Auto Parry 有効", Default = config.parryEnabled,
    Tooltip = "敵の攻撃を検知して parry を発火",
    Callback = function(v) config.parryEnabled = v end,
})
ParryGB:AddToggle("ParryAutoDetect", {
    Text = "自動検知 (Animation)", Default = config.parryAutoDetect,
    Tooltip = "敵の攻撃アニメを検知して発火",
    Callback = function(v) config.parryAutoDetect = v end,
})
ParryGB:AddToggle("ParryTeamCheck", {
    Text = "チームチェック", Default = config.parryTeamCheck,
    Callback = function(v) config.parryTeamCheck = v end,
})
ParryGB:AddDropdown("ParryMode", {
    Values = { "Auto", "Hold", "Off" }, Default = "Auto",
    Text = "手動モード", Tooltip = "Hold でモバイルボタン出現",
    Callback = function(v)
        config.parryMode = v
        refreshHoldButtons()
    end,
})
ParryGB:AddLabel("Parry Key (Hold)")
    :AddKeyPicker("ParryKeyPicker", {
        Default = "F", Mode = "Press", Text = "Parry Key",
        Callback = function() fireParry() end,
    })

local ParryTuneGB = ParryTab:AddRightGroupbox("Detection Tuning", "sliders-horizontal")
ParryTuneGB:AddToggle("ParryFacingCheck", {
    Text = "向きチェック", Default = config.parryFacingCheck,
    Tooltip = "敵が自分に正面を向いている時のみ発火",
    Callback = function(v) config.parryFacingCheck = v end,
})
ParryTuneGB:AddSlider("ParryFacingAngle", {
    Text = "許容角度 (度)", Default = config.parryFacingAngle,
    Min = 20, Max = 360, Rounding = 0, Compact = false, Suffix = "°",
    Callback = function(v) config.parryFacingAngle = v end,
})
ParryTuneGB:AddSlider("ParryMaxDist", {
    Text = "最大距離", Default = config.parryMaxDist,
    Min = 3, Max = 100, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.parryMaxDist = v end,
})
ParryTuneGB:AddSlider("ParryCooldown", {
    Text = "クールダウン", Default = config.parryCooldown,
    Min = 0.02, Max = 1, Rounding = 2, Compact = false, Suffix = " s",
    Callback = function(v) config.parryCooldown = v end,
})
ParryTuneGB:AddSlider("ParryBurst", {
    Text = "Burst (1検知あたり)", Default = config.parryBurst,
    Min = 1, Max = 5, Rounding = 0, Compact = false,
    Tooltip = "1回の検知で parry を何連打するか",
    Callback = function(v) config.parryBurst = v end,
})
ParryTuneGB:AddDivider()
ParryTuneGB:AddToggle("ParrySpam", {
    Text = "Proactive Spam", Default = config.parrySpam,
    Risky = true,
    Tooltip = "常時 parry を連打 — 検知ログに残りやすい",
    Callback = function(v) config.parrySpam = v end,
})
ParryTuneGB:AddSlider("ParrySpamCps", {
    Text = "Spam CPS", Default = config.parrySpamCps,
    Min = 1, Max = 60, Rounding = 0, Compact = false, Suffix = " /s",
    Callback = function(v) config.parrySpamCps = v end,
})
ParryTuneGB:AddLabel("Parry Fires: 0", true, "ParryStatusLabel")

task.spawn(function()
    while task.wait(0.5) do
        if Options.ParryStatusLabel then pcall(function()
            Options.ParryStatusLabel:SetText(
                ("Parry Fires: %d\nRemote: %s"):format(
                    config.parryFireCount,
                    parryRemote and "Found" or "Missing"))
        end) end
    end
end)

-- Aim
local AimMainGB = AimTab:AddLeftGroupbox("Aim Assist", "crosshair")
AimMainGB:AddToggle("AimEnabled", {
    Text = "Aim Assist 有効", Default = config.aimEnabled,
    Callback = function(v) config.aimEnabled = v end,
})
AimMainGB:AddToggle("AimTeamCheck", {
    Text = "チームチェック", Default = config.aimTeamCheck,
    Callback = function(v) config.aimTeamCheck = v end,
})
AimMainGB:AddToggle("AimWallCheck", {
    Text = "壁チェック (Raycast)", Default = config.aimWallCheck,
    Callback = function(v) config.aimWallCheck = v end,
})
AimMainGB:AddDropdown("AimHitbox", {
    Values = { "Head", "HumanoidRootPart" }, Default = "Head",
    Text = "ターゲット部位", Callback = function(v) config.aimHitbox = v end,
})

local AimTuneGB = AimTab:AddRightGroupbox("Tuning", "sliders-horizontal")
AimTuneGB:AddSlider("AimFov", {
    Text = "FOV (半角°)", Default = config.aimFov,
    Min = 5, Max = 180, Rounding = 0, Compact = false, Suffix = "°",
    Tooltip = "80 = 実質 160° の円錐",
    Callback = function(v) config.aimFov = v end,
})
AimTuneGB:AddSlider("AimMaxDist", {
    Text = "最大距離", Default = config.aimMaxDist,
    Min = 20, Max = 3000, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.aimMaxDist = v end,
})
AimTuneGB:AddSlider("AimStrength", {
    Text = "吸着強度", Default = config.aimStrength,
    Min = 1, Max = 30, Rounding = 0, Compact = false,
    Callback = function(v) config.aimStrength = v end,
})
AimTuneGB:AddLabel("Targets in FOV: 0", true, "AimStatusLabel")

task.spawn(function()
    while task.wait(0.5) do
        if Options.AimStatusLabel then pcall(function()
            Options.AimStatusLabel:SetText(
                ("Targets in FOV: %d"):format(config.aimTargets))
        end) end
    end
end)

-- Bring
local BringGB = BringTab:AddLeftGroupbox("Bring Players", "users")
BringGB:AddButton({
    Text = "Bring All (one-shot)",
    Func = function()
        local n = bringPlayers()
        Library:Notify({ Title = "Bring",
            Description = n .. " players brought", Time = 2 })
    end, DoubleClick = false,
})
BringGB:AddToggle("BringLoop", {
    Text = "Bring Loop", Default = config.bringLoop,
    Callback = function(v) config.bringLoop = v end,
})
BringGB:AddToggle("BringTeamCheck", {
    Text = "チームチェック", Default = config.bringTeamCheck,
    Callback = function(v) config.bringTeamCheck = v end,
})
BringGB:AddToggle("BringStealOwnership", {
    Text = "Network Ownership 奪取", Default = config.bringStealOwnership,
    Callback = function(v) config.bringStealOwnership = v end,
})

local LayoutGB = BringTab:AddRightGroupbox("Layout / Tuning", "layout-grid")
LayoutGB:AddDropdown("BringLayout", {
    Values = { "Stack", "Row", "Circle" }, Default = "Stack",
    Text = "配置", Callback = function(v) config.bringLayout = v end,
})
LayoutGB:AddSlider("BringDistance", {
    Text = "前方距離", Default = config.bringDistance,
    Min = 2, Max = 50, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.bringDistance = v end,
})
LayoutGB:AddSlider("BringSpacing", {
    Text = "間隔", Default = config.bringSpacing,
    Min = 2, Max = 30, Rounding = 1, Compact = false, Suffix = " studs",
    Callback = function(v) config.bringSpacing = v end,
})
LayoutGB:AddSlider("BringInterval", {
    Text = "Loop 間隔", Default = config.bringInterval,
    Min = 0.05, Max = 2, Rounding = 2, Compact = false, Suffix = " s",
    Callback = function(v) config.bringInterval = v end,
})
LayoutGB:AddLabel("Brought: 0", true, "BringStatusLabel")

task.spawn(function()
    while task.wait(0.5) do
        if Options.BringStatusLabel then pcall(function()
            Options.BringStatusLabel:SetText(
                ("Brought: %d | Layout: %s"):format(config.bringCount, config.bringLayout))
        end) end
    end
end)

-- ESP
local EspGB = EspTab:AddLeftGroupbox("ESP", "eye")
EspGB:AddToggle("EspEnabled", {
    Text = "ESP 有効", Default = config.espEnabled,
    Callback = function(v) config.espEnabled = v end,
})
EspGB:AddToggle("EspTeamCheck", {
    Text = "チームチェック", Default = config.espTeamCheck,
    Callback = function(v) config.espTeamCheck = v end,
})
EspGB:AddToggle("EspTeamColor", {
    Text = "チーム色を自動適用", Default = config.espTeamColor,
    Callback = function(v) config.espTeamColor = v end,
})
EspGB:AddToggle("EspShowSelf", {
    Text = "自分も表示", Default = config.espShowSelf,
    Callback = function(v) config.espShowSelf = v end,
})
EspGB:AddToggle("EspFill", {
    Text = "塗りつぶし", Default = config.espFill,
    Callback = function(v) config.espFill = v end,
})
EspGB:AddSlider("EspMaxDist", {
    Text = "最大距離", Default = config.espMaxDist,
    Min = 100, Max = 5000, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.espMaxDist = v end,
})

local EspStyleGB = EspTab:AddRightGroupbox("Style / Colors", "palette")
EspStyleGB:AddDropdown("EspDepthMode", {
    Values = { "AlwaysOnTop", "Occluded" }, Default = "AlwaysOnTop",
    Text = "描画深度", Callback = function(v) config.espDepthMode = v end,
})
EspStyleGB:AddLabel("敵の色"):AddColorPicker("EspEnemyColor", {
    Default = config.espEnemyColor, Title = "Enemy Color",
    Callback = function(v) config.espEnemyColor = v end,
})
EspStyleGB:AddLabel("味方の色"):AddColorPicker("EspAllyColor", {
    Default = config.espAllyColor, Title = "Ally Color",
    Callback = function(v) config.espAllyColor = v end,
})
EspStyleGB:AddLabel("自分の色"):AddColorPicker("EspSelfColor", {
    Default = config.espSelfColor, Title = "Self Color",
    Callback = function(v) config.espSelfColor = v end,
})

-- Extra
local MoveGB = ExtraTab:AddLeftGroupbox("Movement", "move")
MoveGB:AddToggle("Noclip", {
    Text = "Noclip", Default = config.noclip,
    Callback = function(v) config.noclip = v end,
})
MoveGB:AddToggle("InfJump", {
    Text = "Infinite Jump", Default = config.infJump,
    Callback = function(v) config.infJump = v end,
})
MoveGB:AddToggle("AntiFling", {
    Text = "Anti-Fling", Default = config.antiFling,
    Callback = function(v) config.antiFling = v end,
})
MoveGB:AddToggle("LowGravity", {
    Text = "Low Gravity", Default = config.lowGravity,
    Callback = function(v) config.lowGravity = v end,
})

local DashGB = ExtraTab:AddRightGroupbox("Dash", "zap")
DashGB:AddSlider("DashRange", {
    Text = "距離", Default = config.dashRange,
    Min = 5, Max = 200, Rounding = 0, Compact = false, Suffix = " studs",
    Callback = function(v) config.dashRange = v end,
})
DashGB:AddLabel("Dash keybind")
    :AddKeyPicker("DashKey", {
        Default = "V", Mode = "Press", Text = "Dash",
        Callback = function() doDash() end,
    })

-- Config
local InfoGB = ConfigTab:AddLeftGroupbox("Info", "info")
InfoGB:AddLabel("Auto Parry: Animation 検知 + Raycast 距離")
InfoGB:AddLabel("Spam モードは検知ログに残りやすい")

-- Addons
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("MovementSuite")
SaveManager:SetFolder("MovementSuite/default")
SaveManager:BuildConfigSection(ConfigTab)
ThemeManager:ApplyToTab(ConfigTab)
SaveManager:LoadAutoloadConfig()

Library:Notify({
    Title = "Movement Suite",
    Description = "Loaded. Parry タブで Auto Parry。",
    Time = 3,
})

Library:OnUnload(function()
    destroySpeedVel(); stopFly()
    workspace.Gravity = savedGravity
    config.atkEnabled = false
    config.unhookEnabled = false
    config.parryEnabled = false
    config.parrySpam = false
    config.veilSpearEnabled = false
    config.veilVfxSpam = false
    config.bringLoop = false
    config.espEnabled = false
    config.aimEnabled = false
    for plr, h in pairs(ESP_HIGHLIGHTS) do
        if h and h.Parent then h:Destroy() end
    end
    ESP_HIGHLIGHTS = {}
    if holdGui then holdGui:Destroy() end
    if aimBound then
        pcall(function() RunService:UnbindFromRenderStep("TrollAimAssist") end)
        aimBound = false
    end
    print("[Suite] Unloaded",
        "| Atk=", config.atkFireCount,
        "| UnHook=", config.unhookFireCount,
        "| Parry=", config.parryFireCount,
        "| Spear=", config.veilSpearFireCount,
        "| VFX=", config.veilVfxFireCount)
end)
