-- 殺人決闘 常時引き寄せ + オートサイレントエイム（ミニガンモード対応） + ESP
-- スマホ対応 (Rayfield UI Version)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- ★★★ UI制御用設定 ★★★
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
-- ★★★ 味方判定関数 ★★★
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
-- ★★★ ターゲット検出 ★★★
-- ============================================================
local currentTarget = nil
local currentTargetRoot = nil
local currentTargetPart = nil

RunService.RenderStepped:Connect(function()
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
end)

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

local function getCycleColor()
    local progress = tick() % 3 / 3 
    local blue = Color3.fromRGB(0, 0, 255)       
    local white = Color3.fromRGB(255, 255, 255)  
    local lightBlue = Color3.fromRGB(0, 255, 255)
    
    if progress < 0.333 then
        return blue:Lerp(white, progress / 0.333)
    elseif progress < 0.666 then
        return white:Lerp(lightBlue, (progress - 0.333) / 0.333)
    else
        return lightBlue:Lerp(blue, (progress - 0.666) / 0.334)
    end
end

RunService.RenderStepped:Connect(function()
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
-- ★★★ Rayfield Library ダッシュボードUI (スマホ対応版) ★★★
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "殺人決闘 ダッシュボード",
   LoadingTitle = "スクリプトを読み込み中...",
   LoadingSubtitle = "スマホ最適化版",
   ConfigurationSaving = {
      Enabled = false, 
   },
   KeySystem = false
})

-- タブの作成
local CombatTab = Window:CreateTab("戦闘 (Combat)", 4483345998)
local PullTab = Window:CreateTab("引き寄せ (Pull)", 4483345998)
local VisualTab = Window:CreateTab("視覚 (Visual)", 4483345998)

-- 【戦闘タブ】
CombatTab:CreateToggle({
   Name = "オート射撃 (AUTO_SHOOT)",
   CurrentValue = SETTINGS.AUTO_SHOOT,
   Flag = "ToggleAutoShoot",
   Callback = function(Value) SETTINGS.AUTO_SHOOT = Value end
})

CombatTab:CreateToggle({
   Name = "バーストモード (USE_BURST)",
   CurrentValue = SETTINGS.USE_BURST,
   Flag = "ToggleBurst",
   Callback = function(Value) SETTINGS.USE_BURST = Value end
})

CombatTab:CreateToggle({
   Name = "味方を無視 (TEAM_CHECK)",
   CurrentValue = SETTINGS.TEAM_CHECK,
   Flag = "ToggleTeam",
   Callback = function(Value) SETTINGS.TEAM_CHECK = Value end
})

CombatTab:CreateToggle({
   Name = "Noobを狙う (TARGET_NOOB)",
   CurrentValue = SETTINGS.TARGET_NOOB,
   Flag = "ToggleNoob",
   Callback = function(Value) SETTINGS.TARGET_NOOB = Value end
})

CombatTab:CreateInput({
   Name = "射撃間隔 (秒) 例:0.06",
   PlaceholderText = tostring(SETTINGS.SHOOT_INTERVAL),
   RemoveTextAfterFocusLost = false,
   Callback = function(Text)
       local num = tonumber(Text)
       if num then SETTINGS.SHOOT_INTERVAL = num end
   end
})

CombatTab:CreateSlider({
   Name = "バースト発射数",
   Range = {1, 20},
   Increment = 1,
   Suffix = "発",
   CurrentValue = SETTINGS.BURST_COUNT,
   Flag = "SliderBurstCount",
   Callback = function(Value) SETTINGS.BURST_COUNT = Value end
})

CombatTab:CreateSlider({
   Name = "エイム視野範囲 (FOV)",
   Range = {0, 1500},
   Increment = 10,
   Suffix = "px",
   CurrentValue = SETTINGS.FOV_RADIUS,
   Flag = "SliderFov",
   Callback = function(Value) SETTINGS.FOV_RADIUS = Value end
})

CombatTab:CreateSlider({
   Name = "ターゲット最大距離",
   Range = {0, 1000},
   Increment = 10,
   Suffix = "m",
   CurrentValue = SETTINGS.MAX_DISTANCE,
   Flag = "SliderMaxDist",
   Callback = function(Value) SETTINGS.MAX_DISTANCE = Value end
})

-- 【引き寄せタブ】
PullTab:CreateToggle({
   Name = "常時引き寄せ (PULL_ENABLED)",
   CurrentValue = SETTINGS.PULL_ENABLED,
   Flag = "TogglePull",
   Callback = function(Value) SETTINGS.PULL_ENABLED = Value end
})

PullTab:CreateToggle({
   Name = "スムース引き寄せ (SMOOTH)",
   CurrentValue = SETTINGS.SMOOTH_PULL,
   Flag = "ToggleSmooth",
   Callback = function(Value) SETTINGS.SMOOTH_PULL = Value end
})

PullTab:CreateSlider({
   Name = "引き寄せ距離",
   Range = {0, 50},
   Increment = 1,
   Suffix = "m",
   CurrentValue = SETTINGS.PULL_DISTANCE,
   Flag = "SliderPullDist",
   Callback = function(Value) SETTINGS.PULL_DISTANCE = Value end
})

PullTab:CreateSlider({
   Name = "引き寄せ高さ",
   Range = {-10, 50},
   Increment = 1,
   Suffix = "m",
   CurrentValue = SETTINGS.PULL_HEIGHT,
   Flag = "SliderPullHeight",
   Callback = function(Value) SETTINGS.PULL_HEIGHT = Value end
})

-- 【視覚タブ】
VisualTab:CreateToggle({
   Name = "ESP表示 (ESP_ENABLED)",
   CurrentValue = SETTINGS.ESP_ENABLED,
   Flag = "ToggleESP",
   Callback = function(Value) SETTINGS.ESP_ENABLED = Value end
})

Rayfield:LoadConfiguration()
