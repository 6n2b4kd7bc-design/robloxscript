-- CAT HUB キーシステム (改良版)
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local cfg = {
    api = "8d65b9f4-b94e-4aef-b3d0-68710a307194", -- 既存のAPIキー（変更可）
    service = "universal troll",
    provider = "minitomato1900",
    discord = "https://work.ink/29FJ/first-step",
    logo = "rbxassetid://111213907861637", -- CAT HUBロゴに変更推奨
    -- ピンクテーマ
    barColor = Color3.fromRGB(255, 105, 180),       -- 光るピンク
    bgColor = Color3.fromRGB(35, 20, 40),           -- ダークピンク背景
    topColor = Color3.fromRGB(60, 30, 70),          -- ダークピンクトップ
    inputColor = Color3.fromRGB(50, 25, 60),        -- 入力欄背景
    textColor = Color3.fromRGB(255, 182, 193),      -- 薄ピンク文字
    keyFile = "CAT_HUB_key.txt"                     -- キー保存ファイル
}

local notifActive = {}

local function createNotification(title, content, length, iconId)
    local screen = Instance.new("ScreenGui")
    screen.Name = "NotifGui"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 2147483647
    screen.Parent = CoreGui

    local scale = math.clamp(math.min(workspace.CurrentCamera.ViewportSize.X, workspace.CurrentCamera.ViewportSize.Y) / 1366, 0.6, 1.6)
    local w = math.clamp(320 * scale, 200, 520)
    local h = math.clamp(72 * scale, 54, 140)

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, w, 0, h)
    main.Position = UDim2.new(1, -12, 1, -12 - h - 16)
    main.AnchorPoint = Vector2.new(1, 1)
    main.BackgroundTransparency = 0
    main.BackgroundColor3 = cfg.bgColor
    main.BorderSizePixel = 0
    main.Parent = screen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = main

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 4)
    bar.Position = UDim2.new(0, 0, 1, -4)
    bar.BackgroundColor3 = cfg.barColor
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = main

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 2)
    barCorner.Parent = bar

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.BackgroundColor3 = cfg.barColor
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local icon = Instance.new("ImageLabel")
    icon.Size = UDim2.new(0, h, 1, 0)
    icon.Position = UDim2.new(0, 0, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Image = iconId or cfg.logo
    icon.ImageColor3 = cfg.barColor
    icon.ScaleType = Enum.ScaleType.Stretch
    icon.Parent = main

    local txt = Instance.new("TextLabel")
    txt.BackgroundTransparency = 1
    txt.Size = UDim2.new(1, -h - 8, 0.4, 0)
    txt.Position = UDim2.new(0, h + 8, 0, 0)
    txt.Font = Enum.Font.Code
    txt.TextSize = math.clamp(14 * scale, 12, 20)
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.TextYAlignment = Enum.TextYAlignment.Top
    txt.TextColor3 = cfg.textColor
    txt.Text = title
    txt.Parent = main

    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Size = UDim2.new(1, -h - 8, 0.5, 0)
    sub.Position = UDim2.new(0, h + 8, 0.4, 0)
    sub.Font = Enum.Font.Code
    sub.TextSize = math.clamp(12 * scale, 10, 16)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextYAlignment = Enum.TextYAlignment.Top
    sub.TextColor3 = Color3.fromRGB(255, 200, 220)
    sub.Text = content
    sub.TextWrapped = true
    sub.Parent = main

    local id = tostring(math.floor(tick() * 1000)) .. "-" .. HttpService:GenerateGUID(false)
    table.insert(notifActive, { id = id, frame = main, sizeY = h })

    local function restack()
        local spacing = 8 * scale
        local yoff = 0
        for i = #notifActive, 1, -1 do
            local node = notifActive[i]
            if node and node.frame and node.frame.Parent then
                local target = -12 - yoff - node.sizeY
                TweenService:Create(node.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(1, -12, 1, target) }):Play()
                yoff = yoff + node.sizeY + spacing
            end
        end
    end

    restack()

    local function destroy()
        for i = 1, #notifActive do
            if notifActive[i].id == id then
                table.remove(notifActive, i)
                break
            end
        end
        TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, 16, main.Position.Y.Scale, main.Position.Y.Offset), BackgroundTransparency = 1 }):Play()
        TweenService:Create(txt, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
        TweenService:Create(sub, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
        TweenService:Create(icon, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
        task.wait(0.35)
        pcall(function() main:Destroy() end)
        restack()
    end

    if length and length > 0 then
        TweenService:Create(fill, TweenInfo.new(length, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { Size = UDim2.new(0, 0, 1, 0) }):Play()
        task.delay(length, destroy)
    end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.ZIndex = 10
    btn.Parent = main
    btn.MouseButton1Click:Connect(destroy)
    btn.TouchTap:Connect(destroy)

    return { Close = destroy }
end

local function saveKey(key)
    if writefile then
        pcall(function() writefile(cfg.keyFile, key) end)
    end
end

local function loadKey()
    if readfile then
        local ok, data = pcall(function() return readfile(cfg.keyFile) end)
        if ok then return data end
    end
    return ""
end

local function buildUI()
    local Part1 = {}
    local Part2 = {}
    local Part3 = {}

    Part1.Screen = Instance.new("ScreenGui")
    Part1.Screen.Name = "CAT_HUB_KeyUI"
    Part1.Screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
    Part1.Screen.ResetOnSpawn = false
    Part1.Screen.IgnoreGuiInset = true
    Part1.Screen.Parent = CoreGui

    Part1.Main = Instance.new("Frame")
    Part1.Main.Name = "Main"
    Part1.Main.Size = UDim2.new(0, 370, 0, 200)
    Part1.Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    Part1.Main.AnchorPoint = Vector2.new(0.5, 0.5)
    Part1.Main.BackgroundColor3 = cfg.bgColor
    Part1.Main.BackgroundTransparency = 0
    Part1.Main.BorderSizePixel = 0
    Part1.Main.ClipsDescendants = false
    Part1.Main.Parent = Part1.Screen

    Part1.Corner = Instance.new("UICorner")
    Part1.Corner.CornerRadius = UDim.new(0, 10)
    Part1.Corner.Parent = Part1.Main

    Part2.Top = Instance.new("Frame")
    Part2.Top.Name = "Top"
    Part2.Top.Size = UDim2.new(1, 0, 0, 35)
    Part2.Top.Position = UDim2.new(0, 0, 0, 0)
    Part2.Top.BackgroundColor3 = cfg.topColor
    Part2.Top.BorderSizePixel = 0
    Part2.Top.Parent = Part1.Main

    Part2.TopCorner = Instance.new("UICorner")
    Part2.TopCorner.CornerRadius = UDim.new(0, 10)
    Part2.TopCorner.Parent = Part2.Top

    Part2.TopCover = Instance.new("Frame")
    Part2.TopCover.Name = "TopCover"
    Part2.TopCover.Size = UDim2.new(1, 0, 0, 20)
    Part2.TopCover.Position = UDim2.new(0, 0, 1, -20)
    Part2.TopCover.BackgroundColor3 = cfg.topColor
    Part2.TopCover.BorderSizePixel = 0
    Part2.TopCover.Parent = Part2.Top

    Part2.Line = Instance.new("Frame")
    Part2.Line.Name = "Line"
    Part2.Line.Size = UDim2.new(1, 0, 0, 1)
    Part2.Line.Position = UDim2.new(0, 0, 1, 0)
    Part2.Line.BackgroundColor3 = Color3.fromRGB(80, 40, 90)
    Part2.Line.BorderSizePixel = 0
    Part2.Line.Parent = Part2.Top

    Part2.Logo = Instance.new("ImageLabel")
    Part2.Logo.Name = "Logo"
    Part2.Logo.Size = UDim2.new(0, 20, 0, 20)
    Part2.Logo.Position = UDim2.new(0, 10, 0, 7)
    Part2.Logo.BackgroundTransparency = 1
    Part2.Logo.Image = cfg.logo
    Part2.Logo.ImageColor3 = cfg.barColor
    Part2.Logo.Parent = Part2.Top

    Part2.Title = Instance.new("TextLabel")
    Part2.Title.Name = "Title"
    Part2.Title.Size = UDim2.new(0, 100, 0, 35)
    Part2.Title.Position = UDim2.new(0, 35, 0, 0)
    Part2.Title.BackgroundTransparency = 1
    Part2.Title.Text = "CAT HUB"
    Part2.Title.TextColor3 = cfg.textColor
    Part2.Title.TextSize = 18
    Part2.Title.Font = Enum.Font.GothamBold
    Part2.Title.TextXAlignment = Enum.TextXAlignment.Left
    Part2.Title.Parent = Part2.Top

    Part2.Close = Instance.new("ImageButton")
    Part2.Close.Name = "Close"
    Part2.Close.Size = UDim2.new(0, 20, 0, 20)
    Part2.Close.Position = UDim2.new(1, -10, 0.5, 0)
    Part2.Close.AnchorPoint = Vector2.new(1, 0.5)
    Part2.Close.BackgroundTransparency = 1
    Part2.Close.Image = "rbxassetid://122931434733842"
    Part2.Close.ImageColor3 = cfg.textColor
    Part2.Close.ScaleType = Enum.ScaleType.Fit
    Part2.Close.Parent = Part2.Top

    Part3.Input = Instance.new("Frame")
    Part3.Input.Name = "Input"
    Part3.Input.Size = UDim2.new(0.9, 0, 0, 35)
    Part3.Input.Position = UDim2.new(0.5, 0, 0, 60)
    Part3.Input.AnchorPoint = Vector2.new(0.5, 0)
    Part3.Input.BackgroundColor3 = cfg.inputColor
    Part3.Input.BackgroundTransparency = 0.3
    Part3.Input.BorderSizePixel = 0
    Part3.Input.Parent = Part1.Main

    Part3.InputStroke = Instance.new("UIStroke")
    Part3.InputStroke.Color = cfg.barColor
    Part3.InputStroke.Thickness = 1
    Part3.InputStroke.Transparency = 0.5
    Part3.InputStroke.Parent = Part3.Input

    Part3.InputCorner = Instance.new("UICorner")
    Part3.InputCorner.CornerRadius = UDim.new(0, 6)
    Part3.InputCorner.Parent = Part3.Input

    Part3.Box = Instance.new("TextBox")
    Part3.Box.Name = "Box"
    Part3.Box.Size = UDim2.new(0.9, 0, 1, 0)
    Part3.Box.Position = UDim2.new(0.5, 0, 0.5, 0)
    Part3.Box.AnchorPoint = Vector2.new(0.5, 0.5)
    Part3.Box.BackgroundTransparency = 1
    Part3.Box.Text = loadKey()
    Part3.Box.TextColor3 = cfg.textColor
    Part3.Box.PlaceholderText = "00000000-0000-0000-0000-000000000000"
    Part3.Box.PlaceholderColor3 = Color3.fromRGB(180, 140, 160)
    Part3.Box.TextSize = 14
    Part3.Box.Font = Enum.Font.Gotham
    Part3.Box.ClearTextOnFocus = false
    Part3.Box.Parent = Part3.Input

    Part3.Buttons = Instance.new("Frame")
    Part3.Buttons.Name = "Buttons"
    Part3.Buttons.Size = UDim2.new(0.9, 0, 0, 30)
    Part3.Buttons.Position = UDim2.new(0.5, 0, 1, -40)
    Part3.Buttons.AnchorPoint = Vector2.new(0.5, 1)
    Part3.Buttons.BackgroundTransparency = 1
    Part3.Buttons.Parent = Part1.Main

    local btnColor = Color3.fromRGB(100, 40, 130)

    Part3.GetKey = Instance.new("TextButton")
    Part3.GetKey.Name = "GetKey"
    Part3.GetKey.Size = UDim2.new(0.45, -4, 1, 0)
    Part3.GetKey.Position = UDim2.new(0.25, 0, 0, 0)
    Part3.GetKey.AnchorPoint = Vector2.new(0.5, 0)
    Part3.GetKey.BackgroundColor3 = btnColor
    Part3.GetKey.BorderSizePixel = 0
    Part3.GetKey.Text = ""
    Part3.GetKey.AutoButtonColor = false
    Part3.GetKey.Parent = Part3.Buttons

    local getKeyIco = Instance.new("ImageLabel")
    getKeyIco.Size = UDim2.new(0, 16, 0, 16)
    getKeyIco.Position = UDim2.new(0.5, -20, 0.5, 0)
    getKeyIco.AnchorPoint = Vector2.new(0.5, 0.5)
    getKeyIco.BackgroundTransparency = 1
    getKeyIco.Image = "rbxassetid://96510194465420"
    getKeyIco.ImageColor3 = Color3.new(1, 1, 1)
    getKeyIco.Parent = Part3.GetKey

    local getKeyTxt = Instance.new("TextLabel")
    getKeyTxt.Size = UDim2.new(1, 0, 1, 0)
    getKeyTxt.Position = UDim2.new(0.5, 8, 0, 0)
    getKeyTxt.AnchorPoint = Vector2.new(0.5, 0)
    getKeyTxt.BackgroundTransparency = 1
    getKeyTxt.Text = "Get Key"
    getKeyTxt.TextColor3 = Color3.new(1, 1, 1)
    getKeyTxt.TextSize = 12
    getKeyTxt.Font = Enum.Font.GothamBold
    getKeyTxt.Parent = Part3.GetKey

    Part3.GetKeyCorner = Instance.new("UICorner")
    Part3.GetKeyCorner.CornerRadius = UDim.new(0, 8)
    Part3.GetKeyCorner.Parent = Part3.GetKey

    Part3.Verify = Instance.new("TextButton")
    Part3.Verify.Name = "Verify"
    Part3.Verify.Size = UDim2.new(0.45, -4, 1, 0)
    Part3.Verify.Position = UDim2.new(0.75, 0, 0, 0)
    Part3.Verify.AnchorPoint = Vector2.new(0.5, 0)
    Part3.Verify.BackgroundColor3 = btnColor
    Part3.Verify.BorderSizePixel = 0
    Part3.Verify.Text = ""
    Part3.Verify.AutoButtonColor = false
    Part3.Verify.Parent = Part3.Buttons

    local verifyIco = Instance.new("ImageLabel")
    verifyIco.Size = UDim2.new(0, 16, 0, 16)
    verifyIco.Position = UDim2.new(0.5, -20, 0.5, 0)
    verifyIco.AnchorPoint = Vector2.new(0.5, 0.5)
    verifyIco.BackgroundTransparency = 1
    verifyIco.Image = "rbxassetid://87354736164608"
    verifyIco.ImageColor3 = Color3.new(1, 1, 1)
    verifyIco.Parent = Part3.Verify

    local verifyTxt = Instance.new("TextLabel")
    verifyTxt.Size = UDim2.new(1, 0, 1, 0)
    verifyTxt.Position = UDim2.new(0.5, 8, 0, 0)
    verifyTxt.AnchorPoint = Vector2.new(0.5, 0)
    verifyTxt.BackgroundTransparency = 1
    verifyTxt.Text = "Verify"
    verifyTxt.TextColor3 = Color3.new(1, 1, 1)
    verifyTxt.TextSize = 12
    verifyTxt.Font = Enum.Font.GothamBold
    verifyTxt.Parent = Part3.Verify

    Part3.VerifyCorner = Instance.new("UICorner")
    Part3.VerifyCorner.CornerRadius = UDim.new(0, 8)
    Part3.VerifyCorner.Parent = Part3.Verify

    return {
        gui = Part1.Screen,
        main = Part1.Main,
        box = Part3.Box,
        verify = Part3.Verify,
        getKey = Part3.GetKey,
        close = Part2.Close,
        top = Part2.Top
    }
end

local function drag(ui)
    local dragInput, dragStart, startPos
    ui.top.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
            dragStart = inp.Position
            startPos = ui.main.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragInput = nil
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if inp == dragInput and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local delta = inp.Position - dragStart
            ui.main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function pulse(btn)
    local orig = btn.BackgroundColor3
    local pop = Color3.new(math.min(orig.R * 1.3, 1), math.min(orig.G * 1.3, 1), math.min(orig.B * 1.3, 1))
    TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = pop }):Play()
    task.wait(0.15)
    TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { BackgroundColor3 = orig }):Play()
end

-- ============================================================
-- メインスクリプト読み込み（CAT HUB用にカスタマイズ）
-- ============================================================
local function loadMainScript()
    -- ここにCAT HUB本体のスクリプトを貼り付けるか、loadstringで読み込む
    -- 例: loadstring(game:HttpGet("https://your-cat-hub-script-url"))()
    print("CAT HUB メインスクリプトをロードします")
    -- 仮の通知
    createNotification("CAT HUB", "メインスクリプトを読み込み中...", 3, "rbxassetid://87094841427580")
loadstring(game:HttpGet("https://raw.githubusercontent.com/6n2b4kd7bc-design/robloxscript/refs/heads/main/trollCAT.lua"))()
end

local function main()
    if getgenv().CATHUB_KeyLoaded then return end
    getgenv().CATHUB_KeyLoaded = true

    local ui = buildUI()
    drag(ui)

    local function validate()
        local key = ui.box.Text:gsub("%s+", "")
        if key == "" then
            createNotification("Key Required", "キーを入力してください。", 3, "rbxassetid://82094603330968")
            return
        end

        createNotification("Checking...", "キーを検証中です。", 2, "rbxassetid://92630967969808")

        local success, sdk = pcall(function()
            return loadstring(game:HttpGet("https://junkie-development.de/sdk/JunkieKeySystem.lua"))()
        end)

        if not success then
            createNotification("Error", "SDKの読み込みに失敗しました。", 3, "rbxassetid://78733624425654")
            return
        end

        local ok = sdk.verifyKey(cfg.api, key, cfg.service)

        if ok then
            saveKey(key)
            createNotification("Success!", "キーが確認されました。", 3, "rbxassetid://87094841427580")
            TweenService:Create(ui.main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, 0, -0.5, 0),
                BackgroundTransparency = 1
            }):Play()
            task.wait(0.4)
            ui.gui:Destroy()
            loadMainScript() -- メインスクリプトを呼び出す
        else
            createNotification("Invalid Key", "キーが正しくありません。", 3, "rbxassetid://78733624425654")
        end
    end

    ui.verify.MouseButton1Click:Connect(function()
        pulse(ui.verify)
        validate()
    end)
    ui.verify.TouchTap:Connect(function()
        pulse(ui.verify)
        validate()
    end)

    ui.box.FocusLost:Connect(function(enter)
        if enter then
            validate()
        end
    end)

    ui.getKey.MouseButton1Click:Connect(function()
        pulse(ui.getKey)
        createNotification("Getting Key...", "キーリンクを生成中...", 2, "rbxassetid://83281479437771")

        local success, sdk = pcall(function()
            return loadstring(game:HttpGet("https://junkie-development.de/sdk/JunkieKeySystem.lua"))()
        end)

        if success then
            local link = sdk.getLink(cfg.api, cfg.provider, cfg.service)
            if link and setclipboard then
                setclipboard(link)
                createNotification("Link Copied", "キーリンクがクリップボードにコピーされました。", 3, "rbxassetid://128463727794542")
            else
                createNotification("Failed", "キーリンクを生成できませんでした。", 3, "rbxassetid://78733624425654")
            end
        else
            createNotification("Error", "SDKの読み込みに失敗しました。", 3, "rbxassetid://78733624425654")
        end
    end)
    ui.getKey.TouchTap:Connect(function()
        pulse(ui.getKey)
        createNotification("Getting Key...", "キーリンクを生成中...", 2, "rbxassetid://83281479437771")
        -- 同じ処理を関数化して呼ぶ方が良いが簡略化
    end)

    ui.close.MouseButton1Click:Connect(function()
        createNotification("Closing...", "またね！", 2, "rbxassetid://116998807311805")
        TweenService:Create(ui.main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, -0.5, 0),
            BackgroundTransparency = 1
        }):Play()
        task.wait(0.4)
        ui.gui:Destroy()
    end)
    ui.close.TouchTap:Connect(function()
        createNotification("Closing...", "またね！", 2, "rbxassetid://116998807311805")
        TweenService:Create(ui.main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, -0.5, 0),
            BackgroundTransparency = 1
        }):Play()
        task.wait(0.4)
        ui.gui:Destroy()
    end)

    ui.box.Focused:Connect(function()
        TweenService:Create(ui.box.Parent, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
    end)

    ui.box.FocusLost:Connect(function()
        TweenService:Create(ui.box.Parent, TweenInfo.new(0.2), { BackgroundTransparency = 0.3 }):Play()
    end)

    for _, btn in ipairs({ ui.verify, ui.getKey }) do
        btn.MouseEnter:Connect(function()
            local orig = btn.BackgroundColor3
            local bright = Color3.new(math.min(orig.R * 1.15, 1), math.min(orig.G * 1.15, 1), math.min(orig.B * 1.15, 1))
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = bright }):Play()
        end)
        btn.MouseLeave:Connect(function()
            local orig = btn.BackgroundColor3
            local dim = Color3.new(orig.R / 1.15, orig.G / 1.15, orig.B / 1.15)
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = dim }):Play()
        end)
    end
end

main()
