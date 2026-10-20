--// NovaUI v3 - horizontal GUI library for Roblox
--// v3 changes:
--//   - Multiple background effect modes (particles, starfield, grid, bubbles, snow, waves)
--//   - Stand indicator ball (green/red/count) + stand picker overlay
--//   - 3-row button grid layout with descriptions under each button
--//   - Working command textbox (accepts "summon" or ".summon")
--//   - Extended color palette
--//   - More pages support

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------------ CONFIG
local Config = {
	SFX = true,
	VFX = true,
	BGMode = 1,  -- 1=particles, 2=starfield, 3=grid, 4=bubbles, 5=snow, 6=waves, 7=off
}

local SOUND_ID = "rbxassetid://6895079853"
local SoundPresets = {
	Click  = { Volume = 0.5, Speed = 1.0 },
	Hover  = { Volume = 0.12, Speed = 1.9 },
	Toggle = { Volume = 0.5,  Speed = 1.35 },
	Select = { Volume = 0.5,  Speed = 1.6 },
	Open   = { Volume = 0.5,  Speed = 0.8 },
	Close  = { Volume = 0.5,  Speed = 0.65 },
}

local Theme = {
	Accent = Color3.fromRGB(125, 95, 255),
	Accent2 = Color3.fromRGB(255, 95, 180),
	Background = Color3.fromRGB(16, 16, 22),
	Panel = Color3.fromRGB(24, 24, 33),
	Element = Color3.fromRGB(33, 33, 45),
	ElementHover = Color3.fromRGB(43, 43, 59),
	Track = Color3.fromRGB(54, 54, 72),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(150, 150, 172),
	Danger = Color3.fromRGB(240, 80, 95),
	Success = Color3.fromRGB(80, 220, 130),
	Warning = Color3.fromRGB(240, 200, 70),
	Info = Color3.fromRGB(80, 170, 255),
}

local BG_MODES = {"Particles", "Starfield", "Grid", "Bubbles", "Snow", "Waves", "Off"}

------------------------------------------------------------------ HELPERS
local accentBound = {}
local function bindAccent(obj, prop)
	table.insert(accentBound, { obj, prop })
	obj[prop] = Theme.Accent
end

local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function text(parent, str, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = str, Font = Enum.Font.Gotham, TextSize = 14,
		TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
	})
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

local function safeParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	ok, ui = pcall(function() return game:GetService("CoreGui") end)
	if ok and ui then
		local fine = pcall(function() return ui.Name end)
		if fine then return ui end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local State = { Sounds = {} }

local function sfx(name)
	if not Config.SFX then return end
	local s = State.Sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

local function ripple(frame)
	if not Config.VFX then return end
	local m = UIS:GetMouseLocation()
	local ap, as = frame.AbsolutePosition, frame.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then return end
	local c = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.clamp((m.X - ap.X) / as.X, 0, 1), math.clamp((m.Y - ap.Y) / as.Y, 0, 1)),
		Size = UDim2.fromScale(0, 0), SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75, BorderSizePixel = 0,
		Parent = frame,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	tween(c, 0.5, { Size = UDim2.fromScale(1.8, 1.8), BackgroundTransparency = 1 })
	Debris:AddItem(c, 0.55)
end

local thumbCache = {}
local function loadAvatar(img, userId)
	task.spawn(function()
		local url = thumbCache[userId]
		if not url then
			local ok, res = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok then url = res; thumbCache[userId] = res end
		end
		if url and img.Parent then img.Image = url end
	end)
end

------------------------------------------------------------------ LIBRARY
local Library = {}
local Window = {}
Window.__index = Window

function Library.SetAccent(color)
	Theme.Accent = color
	for i = #accentBound, 1, -1 do
		local b = accentBound[i]
		if b[1] and b[1].Parent then
			tween(b[1], 0.25, { [b[2]] = color })
		else
			table.remove(accentBound, i)
		end
	end
end

function Library.SetBGMode(mode)
	Config.BGMode = mode
end

function Window:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

------------------------------------------------------------------ BACKGROUND EFFECTS
local BGEffects = {}

function BGEffects.Particles(fx)
	local dots = {}
	for _ = 1, 22 do
		local size = math.random(2, 5)
		local dot = new("Frame", {
			Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(math.random(), math.random()),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = math.random(75, 93) / 100,
			BorderSizePixel = 0, Parent = fx,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		table.insert(dots, dot)
		task.spawn(function()
			while dot.Parent do
				local dur = math.random(8, 16)
				if Config.VFX then
					tween(dot, dur, { Position = UDim2.fromScale(math.random(), math.random()) }, Enum.EasingStyle.Linear)
				end
				task.wait(dur)
			end
		end)
	end
	return dots
end

function BGEffects.Starfield(fx)
	local stars = {}
	for _ = 1, 60 do
		local s = new("Frame", {
			Size = UDim2.fromOffset(math.random(1, 3), math.random(1, 3)),
			Position = UDim2.fromScale(math.random(), math.random()),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = math.random(50, 90) / 100,
			BorderSizePixel = 0, Parent = fx,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		table.insert(stars, s)
		task.spawn(function()
			while s.Parent do
				if Config.VFX then
					tween(s, math.random(1, 3), { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
					task.wait(math.random(1, 3))
					tween(s, math.random(1, 3), { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
				end
				task.wait(math.random(1, 4))
			end
		end)
	end
	return stars
end

function BGEffects.Grid(fx)
	local grid = new("Frame", {
		Size = UDim2.fromScale(2, 2), Position = UDim2.fromScale(-0.5, -0.5),
		BackgroundTransparency = 1, Parent = fx,
	})
	local gridGradient = new("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1)
		}),
		Parent = grid,
	})
	-- Draw grid lines using frames
	for i = 0, 20 do
		new("Frame", {
			Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 20),
			BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = grid,
		})
		new("Frame", {
			Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(i / 20, 0),
			BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = grid,
		})
	end
	task.spawn(function()
		while grid.Parent do
			if Config.VFX then
				tween(grid, 8, { Position = UDim2.fromScale(-0.3, -0.3) }, Enum.EasingStyle.Linear)
				task.wait(8)
				tween(grid, 8, { Position = UDim2.fromScale(-0.5, -0.5) }, Enum.EasingStyle.Linear)
				task.wait(8)
			else task.wait(1) end
		end
	end)
	return {grid}
end

function BGEffects.Bubbles(fx)
	local bubbles = {}
	for _ = 1, 15 do
		local size = math.random(8, 24)
		local b = new("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(math.random(), 1.2),
			BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.85,
			BorderSizePixel = 0, Parent = fx,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		table.insert(bubbles, b)
		task.spawn(function()
			while b.Parent do
				if Config.VFX then
					b.Position = UDim2.fromScale(math.random(), 1.2)
					tween(b, math.random(6, 12), { Position = UDim2.fromScale(math.random(), -0.2), BackgroundTransparency = 1 }, Enum.EasingStyle.Linear)
				end
				task.wait(math.random(6, 12))
			end
		end)
	end
	return bubbles
end

function BGEffects.Snow(fx)
	local flakes = {}
	for _ = 1, 40 do
		local size = math.random(2, 4)
		local f = new("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(math.random(), -0.1),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = math.random(20, 60) / 100,
			BorderSizePixel = 0, Parent = fx,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		table.insert(flakes, f)
		task.spawn(function()
			while f.Parent do
				if Config.VFX then
					f.Position = UDim2.fromScale(math.random(), -0.1)
					local dur = math.random(4, 9)
					tween(f, dur, { Position = UDim2.fromScale(math.random(), 1.1) }, Enum.EasingStyle.Linear)
				end
				task.wait(math.random(4, 9))
			end
		end)
	end
	return flakes
end

function BGEffects.Waves(fx)
	local wave1 = new("Frame", {
		Size = UDim2.fromScale(2, 0.5), Position = UDim2.fromScale(-0.5, 0.3),
		BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.88, BorderSizePixel = 0, Parent = fx,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local wave2 = new("Frame", {
		Size = UDim2.fromScale(2, 0.4), Position = UDim2.fromScale(-0.5, 0.6),
		BackgroundColor3 = Theme.Accent2, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = fx,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	task.spawn(function()
		while wave1.Parent do
			if Config.VFX then
				tween(wave1, 4, { Position = UDim2.fromScale(-0.3, 0.3), Rotation = 5 }, Enum.EasingStyle.Sine)
				tween(wave2, 4, { Position = UDim2.fromScale(-0.4, 0.6), Rotation = -5 }, Enum.EasingStyle.Sine)
				task.wait(4)
				tween(wave1, 4, { Position = UDim2.fromScale(-0.5, 0.3), Rotation = -5 }, Enum.EasingStyle.Sine)
				tween(wave2, 4, { Position = UDim2.fromScale(-0.6, 0.6), Rotation = 5 }, Enum.EasingStyle.Sine)
				task.wait(4)
			else task.wait(1) end
		end
	end)
	return {wave1, wave2}
end

local function applyBGEffect(self)
	if self.FX then
		for _, c in ipairs(self.FX:GetChildren()) do c:Destroy() end
		self.BGObjects = {}
	end
	local mode = Config.BGMode
	if mode == 7 then return end  -- Off
	local fn = ({BGEffects.Particles, BGEffects.Starfield, BGEffects.Grid, BGEffects.Bubbles, BGEffects.Snow, BGEffects.Waves})[mode]
	if fn then self.BGObjects = fn(self.FX) end
end

------------------------------------------------------------------ WINDOW
function Library:CreateWindow(title)
	local self = setmetatable({ Tabs = {}, Active = nil, Connections = {}, Visible = true,
		Listening = false, ToggleKey = Enum.KeyCode.RightShift, UserScale = 1, Minimized = false,
		StandProvider = nil, CommandHandler = nil, SelectedStands = {}, StandPickerOpen = false }, Window)

	local parent = safeParent()
	local old = parent:FindFirstChild("NovaUI")
	if old then old:Destroy() end

	local gui = new("ScreenGui", {
		Name = "NovaUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui.Parent = parent
	self.Gui = gui

	State.Sounds = {}
	for name, p in pairs(SoundPresets) do
		State.Sounds[name] = new("Sound", { SoundId = SOUND_ID, Volume = p.Volume, PlaybackSpeed = p.Speed, Parent = gui })
	end

	local main = new("CanvasGroup", {
		Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 480), BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
		GroupTransparency = 1, Parent = gui,
	}, { corner(14) })
	local scale = new("UIScale", { Scale = 0.85, Parent = main })
	local stroke = new("UIStroke", { Thickness = 1.5, Transparency = 0.45, Parent = main })
	bindAccent(stroke, "Color")
	self.Main, self.Scale = main, scale

	-- FX layer
	local fx = new("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = main })
	self.FX = fx
	self.BGObjects = {}
	applyBGEffect(self)

	-- top bar
	local top = new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0, ZIndex = 3, Parent = main })
	self.Top = top

	local line = new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = top })
	bindAccent(line, "BackgroundColor3")
	local shimmer = new("UIGradient", {
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.8) }),
		Parent = line,
	})
	local shimmerTween = TweenService:Create(shimmer, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Offset = Vector2.new(1, 0) })
	local pulseTween = TweenService:Create(stroke, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.85 })

	function self:ApplyVFX()
		fx.Visible = Config.VFX
		if Config.VFX then
			shimmerTween:Play(); pulseTween:Play()
		else
			shimmerTween:Cancel(); pulseTween:Cancel()
			shimmer.Offset = Vector2.new(0, 0)
			stroke.Transparency = 0.45
		end
	end
	self:ApplyVFX()

	local titleLbl = text(top, string.upper(title or "NovaUI"), {
		Size = UDim2.new(0, 150, 1, -2), Position = UDim2.fromOffset(18, 0),
		Font = Enum.Font.GothamBlack, TextSize = 19,
	})
	bindAccent(titleLbl, "TextColor3")

	local tabBar = new("ScrollingFrame", {
		Size = UDim2.new(1, -400, 1, -4), Position = UDim2.fromOffset(170, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, Parent = top,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }) })
	self.TabBar = tabBar

	local indicator = new("Frame", { Size = UDim2.new(0, 0, 0, 3), Position = UDim2.new(0, 0, 1, -4), BorderSizePixel = 0,
		Visible = false, ZIndex = 4, Parent = top }, { corner(2) })
	bindAccent(indicator, "BackgroundColor3")

	function self:MoveIndicator(btn, instant)
		task.spawn(function()
			RunService.Heartbeat:Wait()
			if not btn.Parent or top.AbsoluteSize.X <= 0 then return end
			local x = (btn.AbsolutePosition.X - top.AbsolutePosition.X) / top.AbsoluteSize.X
			local w = btn.AbsoluteSize.X / top.AbsoluteSize.X
			indicator.Visible = true
			if instant then
				indicator.Position = UDim2.new(x, 0, 1, -4)
				indicator.Size = UDim2.new(w, 0, 0, 3)
			else
				tween(indicator, 0.3, { Position = UDim2.new(x, 0, 1, -4), Size = UDim2.new(w, 0, 0, 3) },
					Enum.EasingStyle.Quart)
			end
		end)
	end

	-- STAND INDICATOR BALL (next to minimize/close)
	local standBall = new("TextButton", {
		Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -112, 0.5, -10),
		BackgroundColor3 = Theme.Danger, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = top,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	self.StandBall = standBall
	local standCountLbl = text(standBall, "", {
		Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0),
		Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	})
	self.StandCountLbl = standCountLbl

	standBall.MouseEnter:Connect(function() sfx("Hover"); tween(standBall, 0.15, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -114, 0.5, -12) }) end)
	standBall.MouseLeave:Connect(function() tween(standBall, 0.15, { Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -112, 0.5, -10) }) end)
	standBall.MouseButton1Click:Connect(function()
		sfx("Click")
		self:OpenStandPicker()
	end)

	-- Update stand ball state every 0.5s
	task.spawn(function()
		while main.Parent do
			self:UpdateStandBall()
			task.wait(0.5)
		end
	end)

	local function topButton(symbol, xOff, color, cb)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, xOff, 0.5, -15), BackgroundColor3 = color,
			Text = symbol, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false, Parent = top,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		b.MouseEnter:Connect(function() sfx("Hover"); tween(b, 0.15, { Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, xOff - 2, 0.5, -17) }) end)
		b.MouseLeave:Connect(function() tween(b, 0.15, { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, xOff, 0.5, -15) }) end)
		b.MouseButton1Click:Connect(function() sfx("Click"); cb() end)
	end
	topButton("-", -76, Color3.fromRGB(235, 170, 50), function()
		self.Minimized = not self.Minimized
		tween(main, 0.3, { Size = UDim2.fromOffset(820, self.Minimized and 48 or 480) }, Enum.EasingStyle.Quart)
	end)
	topButton("x", -42, Theme.Danger, function() self:Destroy() end)

	local pages = new("Frame", { Name = "Pages", Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48),
		BackgroundTransparency = 1, ZIndex = 2, ClipsDescendants = true, Parent = main })
	self.Pages = pages

	-- dragging
	local dragging, dragStart, startPos
	top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, main.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	self:_connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)

	self:_connect(UIS.InputBegan, function(i, gp)
		if gp or self.Listening then return end
		if i.KeyCode == self.ToggleKey then self:Toggle() end
	end)

	self.Toasts = new("Frame", { Size = UDim2.fromOffset(290, 400), AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1, Parent = gui },
		{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom }) })

	return self
end

------------------------------------------------------------------ STAND BALL + PICKER
function Window:SetStandProvider(fn)
	self.StandProvider = fn
end

function Window:SetCommandHandler(fn)
	self.CommandHandler = fn
end

function Window:UpdateStandBall()
	local stands = {}
	if self.StandProvider then
		local ok, result = pcall(self.StandProvider)
		if ok and type(result) == "table" then stands = result end
	end
	self.Stands = stands
	local count = #stands
	if count == 0 then
		self.StandBall.BackgroundColor3 = Theme.Danger
		self.StandCountLbl.Text = ""
	elseif count == 1 then
		self.StandBall.BackgroundColor3 = Theme.Success
		self.StandCountLbl.Text = ""
	else
		self.StandBall.BackgroundColor3 = Theme.Success
		local selectedCount = 0
		for _, s in ipairs(stands) do
			if s.selected then selectedCount += 1 end
		end
		if selectedCount > 0 then
			self.StandCountLbl.Text = tostring(count) .. "/" .. tostring(selectedCount)
		else
			self.StandCountLbl.Text = tostring(count)
		end
	end
end

function Window:OpenStandPicker()
	if self.StandPickerOpen then return end
	self.StandPickerOpen = true
	sfx("Open")

	local main = self.Main
	local conns = {}

	local overlay = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20, Parent = main })
	tween(overlay, 0.25, { BackgroundTransparency = 0.45 })

	local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 400), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = overlay },
		{ corner(14), new("UIScale", { Scale = 0.85 }) })
	local pstroke = new("UIStroke", { Thickness = 1.5, Transparency = 0.3, Parent = panel })
	bindAccent(pstroke, "Color")
	tween(panel.UIScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	text(panel, "Connected Stands", { Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(18, 8),
		Font = Enum.Font.GothamBold, TextSize = 17 })

	local list = new("ScrollingFrame", { Size = UDim2.new(1, -36, 1, -120), Position = UDim2.fromOffset(18, 48),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel },
		{ new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name }),
		  new("UIPadding", { PaddingRight = UDim.new(0, 6) }) })

	local function close()
		for _, c in ipairs(conns) do c:Disconnect() end
		sfx("Close")
		tween(panel.UIScale, 0.2, { Scale = 0.9 })
		tween(overlay, 0.2, { BackgroundTransparency = 1 })
		Debris:AddItem(overlay, 0.22)
		self.StandPickerOpen = false
	end

	local function addRow(stand)
		local plr = stand.player
		local r = new("TextButton", { Name = string.lower(plr.DisplayName) .. plr.UserId, Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ClipsDescendants = true, Parent = list },
			{ corner(10) })
		local rstroke = new("UIStroke", { Thickness = 1.5, Transparency = 1, Parent = r })
		bindAccent(rstroke, "Color")
		local avatar = new("ImageLabel", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Theme.Background, Image = "", Parent = r }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		loadAvatar(avatar, plr.UserId)
		text(r, plr.DisplayName, { Size = UDim2.new(1, -130, 0, 22), Position = UDim2.fromOffset(66, 8), Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd })
		text(r, "@" .. plr.Name, { Size = UDim2.new(1, -130, 0, 18), Position = UDim2.fromOffset(66, 28), TextSize = 12,
			TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
		text(r, stand.status or "—", { Size = UDim2.new(1, -130, 0, 18), Position = UDim2.fromOffset(66, 44), TextSize = 11,
			TextColor3 = stand.statusColor or Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
		-- selection orb
		local orb = new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, -24, 0.5, -8),
			BackgroundColor3 = stand.selected and Theme.Success or Theme.Danger, BorderSizePixel = 0, Parent = r },
			{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		r.MouseEnter:Connect(function() sfx("Hover"); tween(r, 0.15, { BackgroundColor3 = Theme.ElementHover }) end)
		r.MouseLeave:Connect(function() tween(r, 0.15, { BackgroundColor3 = Theme.Element }) end)
		r.MouseButton1Click:Connect(function()
			sfx("Select"); ripple(r)
			stand.selected = not stand.selected
			orb.BackgroundColor3 = stand.selected and Theme.Success or Theme.Danger
			if stand.onToggle then stand.onToggle(stand.selected) end
			self:UpdateStandBall()
		end)
		return r
	end

	-- populate
	local stands = self.Stands or {}
	for _, s in ipairs(stands) do addRow(s) end

	-- close button
	local closeBtn = new("TextButton", { Size = UDim2.new(1, -36, 0, 36), Position = UDim2.fromOffset(18, 1, -48),
		BackgroundColor3 = Theme.Element, Text = "Close", Font = Enum.Font.GothamBold, TextSize = 14,
		TextColor3 = Theme.Text, AutoButtonColor = false, Parent = panel }, { corner(9) })
	closeBtn.Position = UDim2.new(0, 18, 1, -48)
	closeBtn.MouseEnter:Connect(function() sfx("Hover"); tween(closeBtn, 0.15, { BackgroundColor3 = Theme.ElementHover }) end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, 0.15, { BackgroundColor3 = Theme.Element }) end)
	table.insert(conns, closeBtn.MouseButton1Click:Connect(function() sfx("Click"); close() end))
end

------------------------------------------------------------------ WINDOW METHODS
function Window:Show()
	self.Visible = true
	self.Gui.Enabled = true
	self.Main.GroupTransparency = 1
	self.Scale.Scale = self.UserScale * 0.88
	tween(self.Main, 0.35, { GroupTransparency = 0 })
	tween(self.Scale, 0.45, { Scale = self.UserScale }, Enum.EasingStyle.Back)
	sfx("Open")
end

function Window:Hide()
	self.Visible = false
	sfx("Close")
	tween(self.Main, 0.25, { GroupTransparency = 1 })
	tween(self.Scale, 0.25, { Scale = self.UserScale * 0.9 })
	task.delay(0.27, function()
		if not self.Visible and self.Gui.Parent then self.Gui.Enabled = false end
	end)
end

function Window:Toggle()
	if self.Visible then self:Hide() else self:Show() end
end

function Window:SetScale(s)
	self.UserScale = s
	tween(self.Scale, 0.2, { Scale = s })
end

function Window:Destroy()
	for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
	if self.Gui then self.Gui:Destroy() end
end

function Window:Notify(title, body, duration)
	sfx("Select")
	local t = new("CanvasGroup", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		GroupTransparency = 1, Parent = self.Toasts }, { corner(10), new("UIStroke", { Color = Theme.Track, Thickness = 1 }) })
	local bar = new("Frame", { Size = UDim2.new(0, 4, 1, 0), BorderSizePixel = 0, Parent = t })
	bindAccent(bar, "BackgroundColor3")
	text(t, title, { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(16, 8), Font = Enum.Font.GothamBold })
	text(t, body, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(16, 29), TextSize = 12, TextColor3 = Theme.SubText })
	tween(t, 0.3, { GroupTransparency = 0 })
	task.delay(duration or 3, function()
		if t.Parent then
			tween(t, 0.3, { GroupTransparency = 1 })
			Debris:AddItem(t, 0.35)
		end
	end)
end

------------------------------------------------------------------ PLAYER PICKER (UI only)
function Window:OpenPlayerPicker(title, callback)
	local main = self.Main
	local selected, rows, conns = nil, {}, {}

	local overlay = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20, Parent = main })
	tween(overlay, 0.25, { BackgroundTransparency = 0.45 })

	local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 350), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = overlay },
		{ corner(14), new("UIScale", { Scale = 0.85 }) })
	local pstroke = new("UIStroke", { Thickness = 1.5, Transparency = 0.3, Parent = panel })
	bindAccent(pstroke, "Color")
	tween(panel.UIScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	sfx("Open")

	text(panel, title or "Select a player", { Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(18, 8),
		Font = Enum.Font.GothamBold, TextSize = 17 })

	local search = new("TextBox", { Size = UDim2.new(1, -36, 0, 30), Position = UDim2.fromOffset(18, 48),
		BackgroundColor3 = Theme.Element, Text = "", PlaceholderText = "Search players...", PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text, Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = panel },
		{ corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })

	local list = new("ScrollingFrame", { Size = UDim2.new(1, -36, 1, -150), Position = UDim2.fromOffset(18, 88),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel },
		{ new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name }),
		  new("UIPadding", { PaddingRight = UDim.new(0, 6) }) })

	local function close()
		for _, c in ipairs(conns) do c:Disconnect() end
		sfx("Close")
		tween(panel.UIScale, 0.2, { Scale = 0.9 })
		tween(overlay, 0.2, { BackgroundTransparency = 1 })
		Debris:AddItem(overlay, 0.22)
	end

	local confirm
	local function setSelected(plr)
		selected = plr
		for p, r in pairs(rows) do
			local on = (p == plr)
			tween(r.stroke, 0.2, { Transparency = on and 0 or 1 })
			tween(r.check, 0.2, { TextTransparency = on and 0 or 1 })
			tween(r.frame, 0.2, { BackgroundColor3 = on and Theme.ElementHover or Theme.Element })
		end
		confirm.BackgroundTransparency = plr and 0 or 0.6
		confirm.Text = plr and ("Confirm: " .. plr.DisplayName) or "Confirm"
	end

	local function addRow(plr)
		if rows[plr] then return end
		local r = new("TextButton", { Name = string.lower(plr.DisplayName) .. plr.UserId, Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = Theme.Element, Text = "", AutoButtonColor = false, ClipsDescendants = true, Parent = list },
			{ corner(10) })
		local rstroke = new("UIStroke", { Thickness = 1.5, Transparency = 1, Parent = r })
		bindAccent(rstroke, "Color")
		local avatar = new("ImageLabel", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 7),
			BackgroundColor3 = Theme.Background, Image = "", Parent = r }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		loadAvatar(avatar, plr.UserId)
		local nm = plr.DisplayName .. ((plr == LocalPlayer) and "  (you)" or "")
		text(r, nm, { Size = UDim2.new(1, -110, 0, 22), Position = UDim2.fromOffset(58, 8), Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd })
		text(r, "@" .. plr.Name, { Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(58, 28), TextSize = 12,
			TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd })
		local check = text(r, "OK", { Size = UDim2.fromOffset(40, 54), Position = UDim2.new(1, -46, 0, 0), Font = Enum.Font.GothamBlack,
			TextSize = 14, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center })
		bindAccent(check, "TextColor3")
		rows[plr] = { frame = r, stroke = rstroke, check = check,
			search = string.lower(plr.DisplayName .. " " .. plr.Name) }
		r.MouseEnter:Connect(function() sfx("Hover") end)
		r.MouseButton1Click:Connect(function() sfx("Select"); ripple(r); setSelected(plr) end)
	end

	local function footerButton(label, xScale, xOff, color)
		return new("TextButton", { Size = UDim2.new(0.5, -24, 0, 36), Position = UDim2.new(xScale, xOff, 1, -48),
			BackgroundColor3 = color, Text = label, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false, ClipsDescendants = true, Parent = panel }, { corner(9) })
	end
	local cancel = footerButton("Cancel", 0, 18, Theme.Element)
	confirm = footerButton("Confirm", 0.5, 6, Theme.Accent)
	bindAccent(confirm, "BackgroundColor3")
	confirm.BackgroundTransparency = 0.6
	cancel.MouseButton1Click:Connect(function() sfx("Click"); ripple(cancel); close() end)
	confirm.MouseButton1Click:Connect(function()
		if not selected then return end
		sfx("Click"); ripple(confirm)
		local plr = selected
		close()
		if callback then task.spawn(callback, plr) end
	end)

	for _, p in ipairs(Players:GetPlayers()) do addRow(p) end
	table.insert(conns, Players.PlayerAdded:Connect(addRow))
	table.insert(conns, Players.PlayerRemoving:Connect(function(p)
		local r = rows[p]
		if r then
			r.frame:Destroy(); rows[p] = nil
			if selected == p then setSelected(nil) end
		end
	end))
	search:GetPropertyChangedSignal("Text"):Connect(function()
		local q = string.lower(search.Text)
		for _, r in pairs(rows) do
			r.frame.Visible = (q == "") or (string.find(r.search, q, 1, true) ~= nil)
		end
	end)
end

------------------------------------------------------------------ TABS
function Window:CreateTab(name)
	local window = self
	local tab = { Name = name }
	local order = 0
	local function nextOrder() order += 1; return order end

	local button = new("TextButton", {
		Name = name, LayoutOrder = #window.Tabs + 1, Size = UDim2.new(0, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Element, BackgroundTransparency = 1, Text = name, Font = Enum.Font.GothamMedium,
		TextSize = 14, TextColor3 = Theme.SubText, AutoButtonColor = false, Parent = window.TabBar,
	}, { corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }) })

	local holder = new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false,
		Parent = window.Pages })
	local scroll = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = holder },
		{ new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		  new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	tab.Button, tab.Holder, tab.Scroll = button, holder, scroll

	function tab:Select()
		if window.Active == tab then return end
		for _, t in ipairs(window.Tabs) do
			t.Holder.Visible = false
			tween(t.Button, 0.2, { BackgroundTransparency = 1, TextColor3 = Theme.SubText })
		end
		window.Active = tab
		holder.Visible = true
		tween(button, 0.2, { BackgroundTransparency = 0, TextColor3 = Theme.Text })
		if Config.VFX then
			holder.GroupTransparency = 1
			holder.Position = UDim2.fromOffset(0, 18)
			tween(holder, 0.3, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quart)
		else
			holder.GroupTransparency = 0
			holder.Position = UDim2.fromOffset(0, 0)
		end
		window:MoveIndicator(button, #window.Tabs == 1 and window.FirstSelect == nil)
		window.FirstSelect = true
	end

	button.MouseEnter:Connect(function()
		sfx("Hover")
		if window.Active ~= tab then tween(button, 0.15, { TextColor3 = Theme.Text }) end
	end)
	button.MouseLeave:Connect(function()
		if window.Active ~= tab then tween(button, 0.15, { TextColor3 = Theme.SubText }) end
	end)
	button.MouseButton1Click:Connect(function()
		if window.Active ~= tab then sfx("Click"); tab:Select() end
	end)

	---------------------------------------------------------- element builders
	local function row(height)
		return new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, height or 42),
			BackgroundColor3 = Theme.Element, BorderSizePixel = 0, ClipsDescendants = true, Parent = scroll }, { corner(9) })
	end

	local function interactive(frame, onClick)
		local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = frame })
		hit.MouseEnter:Connect(function() sfx("Hover"); tween(frame, 0.15, { BackgroundColor3 = Theme.ElementHover }) end)
		hit.MouseLeave:Connect(function() tween(frame, 0.15, { BackgroundColor3 = Theme.Element }) end)
		hit.MouseButton1Click:Connect(function() ripple(frame); onClick() end)
		return hit
	end

	function tab:AddSection(str)
		local l = text(scroll, string.upper(str), { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 20),
			Font = Enum.Font.GothamBold, TextSize = 12 })
		bindAccent(l, "TextColor3")
		return l
	end

	function tab:AddLabel(str)
		local f = row(36)
		local l = text(f, str, { Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0), TextColor3 = Theme.SubText })
		return { Set = function(_, s) l.Text = s end }
	end

	-- 3-column button grid with descriptions
	-- buttons = { {label="Summon", desc="Summon the stand", callback=fn}, ... }
	function tab:AddButtonGrid(buttons)
		local n = #buttons
		local rows = math.ceil(n / 3)
		local gridHeight = rows * 70 + (rows - 1) * 8
		local grid = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, gridHeight), BackgroundTransparency = 1, Parent = scroll },
			{ new("UIGridLayout", { SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(8, 8),
				CellSize = UDim2.new(1/3, -8/3, 0, 70) }) })
		for idx, b in ipairs(buttons) do
			local f = new("TextButton", { LayoutOrder = idx, BackgroundColor3 = Theme.Element, Text = "",
				AutoButtonColor = false, ClipsDescendants = true, Parent = grid }, { corner(9) })
			local bar = new("Frame", { Size = UDim2.new(0, 3, 1, 0), Position = UDim2.fromScale(0, 0), BorderSizePixel = 0, Parent = f })
			if b.color then bar.BackgroundColor3 = b.color else bindAccent(bar, "BackgroundColor3") end
			text(f, b.label, { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(12, 10), Font = Enum.Font.GothamBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
			text(f, b.desc or "", { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(12, 34), Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = true })
			f.MouseEnter:Connect(function() sfx("Hover"); tween(f, 0.15, { BackgroundColor3 = Theme.ElementHover }) end)
			f.MouseLeave:Connect(function() tween(f, 0.15, { BackgroundColor3 = Theme.Element }) end)
			f.MouseButton1Click:Connect(function()
				sfx("Click"); ripple(f)
				if b.callback then task.spawn(b.callback) end
			end)
		end
		return grid
	end

	local function buttonRow(label, color)
		local f = row(42)
		text(f, label, { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(16, 0), Font = Enum.Font.GothamMedium })
		local arrow = text(f, ">", { Size = UDim2.fromOffset(30, 42), Position = UDim2.new(1, -40, 0, 0),
			Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center })
		if color then arrow.TextColor3 = color else bindAccent(arrow, "TextColor3") end
		local bar = new("Frame", { Size = UDim2.new(0, 3, 0.5, 0), Position = UDim2.fromScale(0, 0.25), BorderSizePixel = 0, Parent = f })
		if color then bar.BackgroundColor3 = color else bindAccent(bar, "BackgroundColor3") end
		return f
	end

	function tab:AddButton(label, desc, callback)
		local f = row(56)
		text(f, label, { Size = UDim2.new(1, -60, 0, 24), Position = UDim2.fromOffset(16, 6), Font = Enum.Font.GothamBold, TextSize = 14 })
		text(f, desc or "", { Size = UDim2.new(1, -60, 0, 18), Position = UDim2.fromOffset(16, 30), Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.SubText })
		local arrow = text(f, ">", { Size = UDim2.fromOffset(30, 56), Position = UDim2.new(1, -40, 0, 0),
			Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center })
		bindAccent(arrow, "TextColor3")
		local bar = new("Frame", { Size = UDim2.new(0, 3, 1, 0), Position = UDim2.fromScale(0, 0), BorderSizePixel = 0, Parent = f })
		bindAccent(bar, "BackgroundColor3")
		interactive(f, function() sfx("Click"); if callback then task.spawn(callback) end end)
	end

	function tab:AddPlayerPickerButton(label, pickerTitle, callback)
		local f = buttonRow(label, Theme.Danger)
		interactive(f, function() sfx("Click"); window:OpenPlayerPicker(pickerTitle, callback) end)
	end

	function tab:AddToggle(label, default, callback)
		local state = default or false
		local f = row(42)
		text(f, label, { Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(16, 0) })
		local track = new("Frame", { Size = UDim2.fromOffset(42, 22), Position = UDim2.new(1, -58, 0.5, -11),
			BackgroundColor3 = Theme.Track, Parent = f }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local knob = new("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(2, 2),
			BackgroundColor3 = Color3.new(1, 1, 1), Parent = track }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local function render()
			tween(track, 0.2, { BackgroundColor3 = state and Theme.Accent or Theme.Track })
			tween(knob, 0.25, { Position = state and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2) }, Enum.EasingStyle.Back)
		end
		render()
		interactive(f, function()
			state = not state
			sfx("Toggle")
			render()
			if callback then task.spawn(callback, state) end
		end)
		return { Set = function(_, v) state = v; render() end }
	end

	function tab:AddSlider(label, min, max, default, callback)
		local value = default or min
		local f = row(58)
		text(f, label, { Size = UDim2.new(1, -28, 0, 24), Position = UDim2.fromOffset(16, 6) })
		local val = text(f, tostring(value), { Size = UDim2.new(1, -32, 0, 24), Position = UDim2.fromOffset(16, 6),
			Font = Enum.Font.GothamBold, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right })
		local bar = new("Frame", { Size = UDim2.new(1, -32, 0, 6), Position = UDim2.new(0, 16, 1, -18),
			BackgroundColor3 = Theme.Track, Parent = f }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local fill = new("Frame", { Size = UDim2.fromScale((value - min) / (max - min), 1), BorderSizePixel = 0, Parent = bar },
			{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		bindAccent(fill, "BackgroundColor3")
		local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), Parent = fill },
			{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

		local sliding = false
		local function set(x)
			local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			local v = math.floor(min + (max - min) * a + 0.5)
			fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
			if v ~= value then
				value = v
				val.Text = tostring(v)
				if callback then task.spawn(callback, v) end
			end
		end
		local hit = new("TextButton", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -30),
			BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = f })
		hit.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				sliding = true; sfx("Click"); set(i.Position.X)
				tween(knob, 0.15, { Size = UDim2.fromOffset(18, 18) })
			end
		end)
		window:_connect(UIS.InputEnded, function(i)
			if sliding and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
				sliding = false
				tween(knob, 0.15, { Size = UDim2.fromOffset(14, 14) })
			end
		end)
		window:_connect(UIS.InputChanged, function(i)
			if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				set(i.Position.X)
			end
		end)
	end

	-- Command textbox — accepts "summon" or ".summon"
	function tab:AddCommandBox(label, placeholder, callback)
		local f = row(46)
		text(f, label, { Size = UDim2.new(0.35, 0, 1, 0), Position = UDim2.fromOffset(16, 0) })
		local box = new("TextBox", { Size = UDim2.new(0.65, -30, 0, 28), Position = UDim2.new(0.35, 0, 0.5, -14),
			BackgroundColor3 = Theme.Background, Text = "", PlaceholderText = placeholder or "Type a command...",
			PlaceholderColor3 = Theme.SubText, TextColor3 = Theme.Text, Font = Enum.Font.Gotham, TextSize = 13,
			ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = f },
			{ corner(7), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
		local bs = new("UIStroke", { Color = Theme.Track, Thickness = 1, Parent = box })
		box.Focused:Connect(function() sfx("Click"); tween(bs, 0.2, { Color = Theme.Accent }) end)
		box.FocusLost:Connect(function(enter)
			tween(bs, 0.2, { Color = Theme.Track })
			if enter and box.Text ~= "" then
				local cmd = box.Text
				-- Add dot prefix if missing
				if string.sub(cmd, 1, 1) ~= "." then
					cmd = "." .. cmd
				end
				sfx("Select")
				if callback then task.spawn(callback, cmd) end
				box.Text = ""
			end
		end)
		return box
	end

	function tab:AddTextbox(label, placeholder, callback)
		local f = row(46)
		text(f, label, { Size = UDim2.new(0.35, 0, 1, 0), Position = UDim2.fromOffset(16, 0) })
		local box = new("TextBox", { Size = UDim2.new(0.65, -30, 0, 28), Position = UDim2.new(0.35, 0, 0.5, -14),
			BackgroundColor3 = Theme.Background, Text = "", PlaceholderText = placeholder or "Type here...",
			PlaceholderColor3 = Theme.SubText, TextColor3 = Theme.Text, Font = Enum.Font.Gotham, TextSize = 13,
			ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = f },
			{ corner(7), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
		local bs = new("UIStroke", { Color = Theme.Track, Thickness = 1, Parent = box })
		box.Focused:Connect(function() sfx("Click"); tween(bs, 0.2, { Color = Theme.Accent }) end)
		box.FocusLost:Connect(function(enter)
			tween(bs, 0.2, { Color = Theme.Track })
			if callback then task.spawn(callback, box.Text, enter) end
		end)
		return box
	end

	function tab:AddColorRow(label, colors, callback)
		local f = row(46)
		text(f, label, { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(16, 0) })
		local holderF = new("Frame", { Size = UDim2.new(0.6, -20, 1, 0), Position = UDim2.fromScale(0.4, 0),
			BackgroundTransparency = 1, Parent = f },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center }) })
		for idx, c in ipairs(colors) do
			local s = new("TextButton", { LayoutOrder = idx, Size = UDim2.fromOffset(24, 24), BackgroundColor3 = c, Text = "",
				AutoButtonColor = false, Parent = holderF }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			s.MouseEnter:Connect(function() sfx("Hover"); tween(s, 0.15, { Size = UDim2.fromOffset(28, 28) }) end)
			s.MouseLeave:Connect(function() tween(s, 0.15, { Size = UDim2.fromOffset(24, 24) }) end)
			s.MouseButton1Click:Connect(function() sfx("Select"); if callback then callback(c) end end)
		end
	end

	function tab:AddKeybind(label, default, callback)
		local f = row(42)
		text(f, label, { Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(16, 0) })
		local b = new("TextButton", { Size = UDim2.fromOffset(100, 26), Position = UDim2.new(1, -116, 0.5, -13),
			BackgroundColor3 = Theme.Background, Text = default.Name, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = Theme.SubText, AutoButtonColor = false, Parent = f }, { corner(7) })
		b.MouseEnter:Connect(function() sfx("Hover") end)
		b.MouseButton1Click:Connect(function()
			if window.Listening then return end
			sfx("Click")
			window.Listening = true
			b.Text = "press a key..."
			local conn
			conn = UIS.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.Keyboard then
					conn:Disconnect()
					if i.KeyCode ~= Enum.KeyCode.Escape then
						b.Text = i.KeyCode.Name
						if callback then callback(i.KeyCode) end
					else
						b.Text = default.Name
					end
					task.delay(0.1, function() window.Listening = false end)
				end
			end)
		end)
	end

	function tab:AddProfileBanner()
		local f = row(80)
		local avatar = new("ImageLabel", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(14, 12),
			BackgroundColor3 = Theme.Background, Image = "", Parent = f }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local ring = new("UIStroke", { Thickness = 2, Parent = avatar })
		bindAccent(ring, "Color")
		loadAvatar(avatar, LocalPlayer.UserId)
		text(f, "Welcome back, " .. LocalPlayer.DisplayName, { Size = UDim2.new(1, -240, 0, 26), Position = UDim2.fromOffset(82, 14),
			Font = Enum.Font.GothamBold, TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd })
		text(f, "@" .. LocalPlayer.Name .. "  |  ID " .. LocalPlayer.UserId, { Size = UDim2.new(1, -240, 0, 20),
			Position = UDim2.fromOffset(82, 42), TextSize = 12, TextColor3 = Theme.SubText })
		local timer = text(f, "00:00", { Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -124, 0, 14),
			Font = Enum.Font.GothamBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right })
		bindAccent(timer, "TextColor3")
		text(f, "SESSION", { Size = UDim2.fromOffset(110, 16), Position = UDim2.new(1, -124, 0, 50), TextSize = 10,
			Font = Enum.Font.GothamBold, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right })
		local start = os.clock()
		task.spawn(function()
			while timer.Parent do
				local s = math.floor(os.clock() - start)
				timer.Text = string.format("%02d:%02d", math.floor(s / 60), s % 60)
				task.wait(1)
			end
		end)
	end

	function tab:AddInfoGrid(items)
		local n = #items
		local grid = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 78), BackgroundTransparency = 1, Parent = scroll },
			{ new("UIGridLayout", { SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(8, 8),
				CellSize = UDim2.new(1 / n, -(8 * (n - 1)) / n, 1, 0) }) })
		local labels = {}
		for idx, it in ipairs(items) do
			local c = new("Frame", { LayoutOrder = idx, BackgroundColor3 = Theme.Element, BorderSizePixel = 0, Parent = grid }, { corner(10) })
			text(c, it[1], { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(12, 10), TextSize = 11,
				Font = Enum.Font.GothamBold, TextColor3 = Theme.SubText })
			local v = text(c, it[2], { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 34),
				Font = Enum.Font.GothamBold, TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd })
			if it[3] then v.TextColor3 = Theme.Text else bindAccent(v, "TextColor3") end
			labels[idx] = v
		end
		return labels
	end

	table.insert(window.Tabs, tab)
	if #window.Tabs == 1 then tab:Select() end
	return tab
end

-- expose BG modes for settings UI
Library.BG_MODES = BG_MODES
Library.Theme = Theme

return Library
