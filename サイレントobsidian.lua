-- 殺人決闘 常時引き寄せ + オートサイレントエイム + ESP
-- Obsidian UI版 / CAT HUB

local cloneref = cloneref or function(i) return i end
local RunService = cloneref(game:GetService("RunService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))

-- ============================================================
-- Obsidian UI 読み込み（失敗時 Wind UI フォールバック）
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
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local TweenService = game:GetService("TweenService")

-- ============================================================
-- ★★★ 設定 ★★★
-- ============================================================
local SETTINGS = {
    FOV_RADIUS = 650,
    MAX_DISTANCE = 300,
    TARGET_NOOB = true,
    TEAM_CHECK = true,
    PULL_ENABLED = false,
    PULL_DISTANCE = 5,
    PULL_HEIGHT = 0,
    SMOOTH_PULL = true,
    SMOOTH_SPEED = 0.2,
    AUTO_SHOOT = false,
    SHOOT_INTERVAL = 0.06,
    USE_BURST = false,
    BURST_COUNT = 5,
    BURST_DELAY = 0.02,
    ESP_ENABLED = true,
}

-- ============================================================
-- ★★★ 味方判定 ★★★
-- ============================================================
local function isTeammate(char)
    if not char then return false end
    local player = Players:GetPlayerFromCharacter(char)
    if player then
        if SETTINGS.TEAM_CHECK then
            if LocalPlayer.Team and player.Team == LocalPlayer.Team then return true end
            local mySide = LocalPlayer:GetAttribute("MatchSide")
            local theirSide = player:GetAttribute("MatchSide")
            if mySide and theirSide and mySide == theirSide then return true end
        end
        return false
    end
    local mySide = LocalPlayer:GetAttribute("MatchSide")
    local theirSide = char:GetAttribute("MatchSide")
    if mySide and theirSide and mySide == theirSide then
        if char:GetAttribute("BotMatchBot") == true or char:GetAttribute("Decoy") == true then
            return false
        end
        return true
    end
    return false
end

-- ============================================================
-- ★★★ ターゲット検出（0.1秒間隔） ★★★
-- ============================================================
local currentTarget = nil
local currentTargetRoot = nil
local currentTargetPart = nil
local lastTargetScan = 0

local function scanTarget()
    if tick() - lastTargetScan < 0.1 then return end
    lastTargetScan = tick()

    local closestTarget = nil
    local shortestDistance = SETTINGS.FOV_RADIUS
    local mousePos = UserInputService:GetMouseLocation()
    local character = LocalPlayer.Character
    if not character then return end
    local myRoot = character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local charsFolder = Workspace:FindFirstChild("Characters")
    local characters = charsFolder and charsFolder:GetChildren() or Workspace:GetChildren()

    for _, char in ipairs(characters) do
        if char:IsA("Model") and char ~= LocalPlayer.Character then
            if isTeammate(char) then continue end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local rootPart = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                if rootPart then
                    local dist = (rootPart.Position - myRoot.Position).Magnitude
                    if dist > SETTINGS.MAX_DISTANCE then continue end
                end
                local head = char:FindFirstChild("Head")
                local aimPart = head or rootPart
                if aimPart then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
                    if onScreen then
                        local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if distance < shortestDistance then
                            shortestDistance = distance
                            closestTarget = {
                                Part = aimPart,
                                Root = rootPart,
                                Model = char,
                                Humanoid = humanoid,
                            }
                        end
                    end
                end
            end
        end
    end

    if not closestTarget and SETTINGS.TARGET_NOOB then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj ~= character then
                if not string.find(obj.Name, "Noob") then continue end
                if isTeammate(obj) then continue end
                local humanoid = obj:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local rootPart = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
                    if rootPart then
                        local dist = (rootPart.Position - myRoot.Position).Magnitude
                        if dist > SETTINGS.MAX_DISTANCE then continue end
                    end
                    local head = obj:FindFirstChild("Head")
                    local aimPart = head or rootPart
                    if aimPart then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
                        if onScreen then
                            local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if distance < shortestDistance then
                                shortestDistance = distance
                                closestTarget = {
                                    Part = aimPart,
                                    Root = rootPart,
                                    Model = obj,
                                    Humanoid = humanoid,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    currentTarget = closestTarget
    if closestTarget then
        currentTargetRoot = closestTarget.Root
        currentTargetPart = closestTarget.Part
    else
        currentTargetRoot = nil
        currentTargetPart = nil
    end
end

RunService.RenderStepped:Connect(scanTarget)

-- ============================================================
-- ★★★ 常時引き寄せ ★★★
-- ============================================================
RunService.RenderStepped:Connect(function()
    if not SETTINGS.PULL_ENABLED then return end
    if not currentTargetRoot or not currentTargetRoot.Parent then return end

    local character = LocalPlayer.Character
    if not character then return end
    local myRoot = character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local lookVector = myRoot.CFrame.LookVector
    local targetPos = myRoot.Position + lookVector * SETTINGS.PULL_DISTANCE + Vector3.new(0, SETTINGS.PULL_HEIGHT, 0)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { character, currentTarget.Model }
    rayParams.IgnoreWater = true
    local groundHit = Workspace:Raycast(targetPos, Vector3.new(0, -10, 0), rayParams)
    if groundHit then
        targetPos = Vector3.new(targetPos.X, groundHit.Position.Y + 1, targetPos.Z)
    end

    if SETTINGS.SMOOTH_PULL then
        local tweenInfo = TweenInfo.new(SETTINGS.SMOOTH_SPEED, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local tween = TweenService:Create(currentTargetRoot, tweenInfo, { CFrame = CFrame.new(targetPos) })
        tween:Play()
    else
        currentTargetRoot.CFrame = CFrame.new(targetPos)
    end
end)

-- ============================================================
-- ★★★ オート射撃関数 ★★★
-- ============================================================
local shotCount = 0

local function fireSilent()
    if not currentTargetPart or not currentTargetPart.Parent then return end
    local targetPos = currentTargetPart.Position
    local character = LocalPlayer.Character
    if not character then return end
    local tool = character:FindFirstChild("Revolver") or character:FindFirstChildOfClass("Tool")
    if not tool then return end

    local origin = character:FindFirstChild("HumanoidRootPart")
    if not origin then return end
    local originPos = origin.Position + Vector3.new(0, 1.5, 0)

    shotCount = shotCount + 1

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    local shootRemote = remotes:FindFirstChild("ShootReplicate")
    if not shootRemote then return end

    local data = {
        hitPos = targetPos,
        to = targetPos,
        origin = originPos,
        id = shotCount,
        hitNormal = Vector3.new(0, 1, 0),
        effects = { Frost = 0, Ricochet = 0, Barrage = 0 },
        hitInstance = currentTargetPart,
        kind = "bullet",
        isCharacterHit = true,
        mode = "single",
        ownerUserId = LocalPlayer.UserId,
        isADS = false,
    }

    pcall(function() shootRemote:FireServer(data) end)
end

-- ============================================================
-- ★★★ オート射撃ループ ★★★
-- ============================================================
local lastShootTime = 0
local burstIndex = 0

RunService.RenderStepped:Connect(function()
    if not SETTINGS.AUTO_SHOOT then return end
    if not currentTarget then return end

    local now = tick()
    if SETTINGS.USE_BURST then
        if burstIndex < SETTINGS.BURST_COUNT then
            if now - lastShootTime >= SETTINGS.BURST_DELAY then
                fireSilent()
                burstIndex = burstIndex + 1
                lastShootTime = now
            end
        else
            if now - lastShootTime >= SETTINGS.SHOOT_INTERVAL then
                burstIndex = 0
                lastShootTime = now
            end
        end
    else
        if now - lastShootTime >= SETTINGS.SHOOT_INTERVAL then
            fireSilent()
            lastShootTime = now
        end
    end
end)

-- ============================================================
-- ★★★ リモートフック ★★★
-- ============================================================
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}

    if currentTarget then
        local targetPart = currentTarget.Part or currentTarget.Root
        if method == "FireServer" then
            if self.Name == "ThrowReplicate" and type(args[1]) == "table" then
                args[1].target = targetPart.Position
                return oldNamecall(self, unpack(args))
            elseif self.Name == "ShootReplicate" and type(args[1]) == "table" then
                args[1].hitInstance = targetPart
                args[1].hitPos = targetPart.Position
                args[1].to = targetPart.Position
                args[1].isCharacterHit = true
                if args[1].segments and type(args[1].segments) == "table" and #args[1].segments > 0 then
                    local lastSegment = args[1].segments[#args[1].segments]
                    lastSegment.hitInstance = targetPart
                    lastSegment.hitPos = targetPart.Position
                    lastSegment.isCharacterHit = true
                end
                return oldNamecall(self, unpack(args))
            end
        elseif method == "Fire" then
            if self.Name == "SpawnKnife" and type(args[1]) == "table" then
                args[1].target = targetPart.Position
                return oldNamecall(self, unpack(args))
            elseif self.Name == "SpawnBullet" and type(args[1]) == "table" then
                args[1].hitInstance = targetPart
                args[1].hitPos = targetPart.Position
                args[1].to = targetPart.Position
                args[1].isCharacterHit = true
                if args[1].segments and type(args[1].segments) == "table" and #args[1].segments > 0 then
                    local lastSegment = args[1].segments[#args[1].segments]
                    lastSegment.hitInstance = targetPart
                    lastSegment.hitPos = targetPart.Position
                    lastSegment.isCharacterHit = true
                end
                return oldNamecall(self, unpack(args))
            end
        end
    end

    return oldNamecall(self, ...)
end)

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
    objects.Box = box
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = box
    objects.BoxStroke = stroke 

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextStrokeTransparency = 0
    label.TextSize = 14
    label.Font = Enum.Font.SourceSansBold
    label.Visible = false
    label.Parent = espGui
    objects.Label = label

    local tracer = Instance.new("Frame")
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

-- 色循環のキャッシュ
local cachedColor = Color3.fromRGB(0,0,255)
local lastColorUpdate = 0
local function getCycleColor()
    if tick() - lastColorUpdate < 0.1 then
        return cachedColor
    end
    lastColorUpdate = tick()
    local progress = tick() % 3 / 3 
    local blue = Color3.fromRGB(0, 0, 255)       
    local white = Color3.fromRGB(255, 255, 255)  
    local lightBlue = Color3.fromRGB(0, 255, 255)
    
    if progress < 0.333 then
        cachedColor = blue:Lerp(white, progress / 0.333)
    elseif progress < 0.666 then
        cachedColor = white:Lerp(lightBlue, (progress - 0.333) / 0.333)
    else
        cachedColor = lightBlue:Lerp(blue, (progress - 0.666) / 0.334)
    end
    return cachedColor
end

-- ESP更新（0.1秒間隔）
local lastESPUpdate = 0
RunService.RenderStepped:Connect(function()
    if tick() - lastESPUpdate < 0.1 then return end
    lastESPUpdate = tick()

    if not SETTINGS.ESP_ENABLED then
        for _, objects in pairs(espObjects) do
            objects.Box.Visible = false
            objects.Label.Visible = false
            objects.Tracer.Visible = false
        end
        return
    end

    local currentColor = getCycleColor()

    for player, objects in pairs(espObjects) do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        
        if character and humanoid and humanoid.Health > 0 and hrp then
            local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            
            if onScreen then
                objects.BoxStroke.Color = currentColor
                objects.Label.TextColor3 = currentColor
                objects.Tracer.BackgroundColor3 = currentColor

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
-- ★★★ Obsidian UI 構築 ★★★
-- ============================================================
if UIMode == "obsidian" then
    -- ===== Obsidian 版 =====
    local Window = Library:CreateWindow({
        Title = "CAT HUB - 殺人決闘",
        Footer = "CAT HUB",
        AutoShow = true,
        NotifySide = "Right",
    })

    local Tabs = {
        Combat = Window:AddTab("戦闘"),
        Pull = Window:AddTab("引き寄せ"),
        Visual = Window:AddTab("視覚"),
    }

    -- --- 戦闘タブ ---
    local AimGroup = Tabs.Combat:AddLeftGroupbox("エイム")

    AimGroup:AddToggle("AutoShoot", {
        Text = "オート射撃",
        Default = SETTINGS.AUTO_SHOOT,
        Callback = function(v) SETTINGS.AUTO_SHOOT = v end,
    })

    AimGroup:AddToggle("UseBurst", {
        Text = "バーストモード",
        Default = SETTINGS.USE_BURST,
        Callback = function(v) SETTINGS.USE_BURST = v end,
    })

    AimGroup:AddToggle("TeamCheck", {
        Text = "味方を無視",
        Default = SETTINGS.TEAM_CHECK,
        Callback = function(v) SETTINGS.TEAM_CHECK = v end,
    })

    AimGroup:AddToggle("TargetNoob", {
        Text = "Noobを狙う",
        Default = SETTINGS.TARGET_NOOB,
        Callback = function(v) SETTINGS.TARGET_NOOB = v end,
    })

    local AimGroupR = Tabs.Combat:AddRightGroupbox("数値設定")

    AimGroupR:AddSlider("ShootInterval", {
        Text = "射撃間隔 (秒)",
        Default = SETTINGS.SHOOT_INTERVAL,
        Min = 0.01,
        Max = 0.5,
        Rounding = 2,
        Callback = function(v) SETTINGS.SHOOT_INTERVAL = v end,
    })

    AimGroupR:AddSlider("BurstCount", {
        Text = "バースト発射数",
        Default = SETTINGS.BURST_COUNT,
        Min = 1,
        Max = 20,
        Rounding = 0,
        Callback = function(v) SETTINGS.BURST_COUNT = v end,
    })

    AimGroupR:AddSlider("FOVRadius", {
        Text = "FOV範囲 (px)",
        Default = SETTINGS.FOV_RADIUS,
        Min = 0,
        Max = 1500,
        Rounding = 0,
        Callback = function(v) SETTINGS.FOV_RADIUS = v end,
    })

    AimGroupR:AddSlider("MaxDistance", {
        Text = "最大距離 (m)",
        Default = SETTINGS.MAX_DISTANCE,
        Min = 0,
        Max = 1000,
        Rounding = 0,
        Callback = function(v) SETTINGS.MAX_DISTANCE = v end,
    })

    -- --- 引き寄せタブ ---
    local PullGroup = Tabs.Pull:AddLeftGroupbox("引き寄せ設定")

    PullGroup:AddToggle("PullEnabled", {
        Text = "常時引き寄せ",
        Default = SETTINGS.PULL_ENABLED,
        Callback = function(v) SETTINGS.PULL_ENABLED = v end,
    })

    PullGroup:AddToggle("SmoothPull", {
        Text = "スムース",
        Default = SETTINGS.SMOOTH_PULL,
        Callback = function(v) SETTINGS.SMOOTH_PULL = v end,
    })

    local PullGroupR = Tabs.Pull:AddRightGroupbox("パラメータ")

    PullGroupR:AddSlider("PullDistance", {
        Text = "引き寄せ距離",
        Default = SETTINGS.PULL_DISTANCE,
        Min = 0,
        Max = 50,
        Rounding = 0,
        Callback = function(v) SETTINGS.PULL_DISTANCE = v end,
    })

    PullGroupR:AddSlider("PullHeight", {
        Text = "引き寄せ高さ",
        Default = SETTINGS.PULL_HEIGHT,
        Min = -10,
        Max = 50,
        Rounding = 0,
        Callback = function(v) SETTINGS.PULL_HEIGHT = v end,
    })

    -- --- 視覚タブ ---
    local VisualGroup = Tabs.Visual:AddLeftGroupbox("ESP")

    VisualGroup:AddToggle("ESPEnabled", {
        Text = "ESP表示",
        Default = SETTINGS.ESP_ENABLED,
        Callback = function(v) SETTINGS.ESP_ENABLED = v end,
    })

    print("✅ Obsidian UI 読み込み完了（CAT HUB / 殺人決闘）")

else
    -- ===== Wind UI フォールバック =====
    local WindUI = Library
    local Window = WindUI:CreateWindow({
        Title = "CAT HUB - 殺人決闘",
        Icon = "solar:sword-bold",
        NewElements = true,
        HideSearchBar = true,
        OpenButton = {
            Title = "CAT HUB",
            CornerRadius = UDim.new(1,0),
            StrokeThickness = 2,
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.6,
            Color = ColorSequence.new(Color3.fromHex("#FF69B4"), Color3.fromHex("#FFB6C1"))
        },
        Topbar = { Height = 44, ButtonsType = "Mac" }
    })

    local CombatTab = Window:Tab({ Title = "戦闘", Icon = "solar:gamepad-bold" })
    local PullTab = Window:Tab({ Title = "引き寄せ", Icon = "solar:magnet-bold" })
    local VisualTab = Window:Tab({ Title = "視覚", Icon = "solar:eye-bold" })

    CombatTab:Section({ Title = "エイム" })
    CombatTab:Toggle({ Title = "オート射撃", Value = SETTINGS.AUTO_SHOOT, Callback = function(v) SETTINGS.AUTO_SHOOT = v end })
    CombatTab:Toggle({ Title = "バーストモード", Value = SETTINGS.USE_BURST, Callback = function(v) SETTINGS.USE_BURST = v end })
    CombatTab:Toggle({ Title = "味方を無視", Value = SETTINGS.TEAM_CHECK, Callback = function(v) SETTINGS.TEAM_CHECK = v end })
    CombatTab:Toggle({ Title = "Noobを狙う", Value = SETTINGS.TARGET_NOOB, Callback = function(v) SETTINGS.TARGET_NOOB = v end })
    CombatTab:Slider({ Title = "射撃間隔 (秒)", Step = 0.01, Value = { Min = 0.01, Max = 0.5, Default = SETTINGS.SHOOT_INTERVAL }, Callback = function(v) SETTINGS.SHOOT_INTERVAL = v end })
    CombatTab:Slider({ Title = "バースト発射数", Step = 1, Value = { Min = 1, Max = 20, Default = SETTINGS.BURST_COUNT }, Callback = function(v) SETTINGS.BURST_COUNT = v end })
    CombatTab:Slider({ Title = "FOV範囲 (px)", Step = 10, Value = { Min = 0, Max = 1500, Default = SETTINGS.FOV_RADIUS }, Callback = function(v) SETTINGS.FOV_RADIUS = v end })
    CombatTab:Slider({ Title = "最大距離 (m)", Step = 10, Value = { Min = 0, Max = 1000, Default = SETTINGS.MAX_DISTANCE }, Callback = function(v) SETTINGS.MAX_DISTANCE = v end })

    PullTab:Section({ Title = "引き寄せ" })
    PullTab:Toggle({ Title = "常時引き寄せ", Value = SETTINGS.PULL_ENABLED, Callback = function(v) SETTINGS.PULL_ENABLED = v end })
    PullTab:Toggle({ Title = "スムース", Value = SETTINGS.SMOOTH_PULL, Callback = function(v) SETTINGS.SMOOTH_PULL = v end })
    PullTab:Slider({ Title = "引き寄せ距離", Step = 1, Value = { Min = 0, Max = 50, Default = SETTINGS.PULL_DISTANCE }, Callback = function(v) SETTINGS.PULL_DISTANCE = v end })
    PullTab:Slider({ Title = "引き寄せ高さ", Step = 1, Value = { Min = -10, Max = 50, Default = SETTINGS.PULL_HEIGHT }, Callback = function(v) SETTINGS.PULL_HEIGHT = v end })

    VisualTab:Section({ Title = "ESP" })
    VisualTab:Toggle({ Title = "ESP表示", Value = SETTINGS.ESP_ENABLED, Callback = function(v) SETTINGS.ESP_ENABLED = v end })

    print("✅ Wind UI 読み込み完了（フォールバック）")
end
