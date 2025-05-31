local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local parentFrame = script.Parent.Frame
local getJSON = script:WaitForChild("getJSON")

local playPauseBtn = parentFrame:WaitForChild("PlayPauseButton")
local backBtn = parentFrame:WaitForChild("BackButton")
local forwardBtn = parentFrame:WaitForChild("ForwardButton")
local label = parentFrame:FindFirstChild("FrameLabel")
local bar = parentFrame:WaitForChild("ProgressBar")
local fill = bar:WaitForChild("ProgressFill")
local thumb = bar:WaitForChild("ProgressThumb")
local frameContainer = parentFrame:WaitForChild("Frames")
local urlBox = parentFrame:WaitForChild("URLBox") -- TextBox для ввода URL
local loadBtn = parentFrame:WaitForChild("LoadButton") -- Кнопка загрузки

local jsonData = nil
local palette = {}
local symbolMap = {}
local frameStrings = {}
local frameRate = 15
local frameCount = 1
local width, height = 1, 1
local pixelSize = 3
local playing = true
local dragging = false
local frameIndex = 1
local pixelCache = {}
local colorCache = {}

local function hexToColor3(hex)
	if colorCache[hex] then return colorCache[hex] end
	local r = tonumber(hex:sub(1, 2), 16) or 0
	local g = tonumber(hex:sub(3, 4), 16) or 0
	local b = tonumber(hex:sub(5, 6), 16) or 0
	local color = Color3.fromRGB(r, g, b)
	colorCache[hex] = color
	return color
end

local function decodeCompressedFrame(frameStr)
	local rows = string.split(frameStr, "|")
	local decoded = table.create(#rows)

	for rowIndex, row in ipairs(rows) do
		local pixels = table.create(width)
		local chars = {}

		for _, cp in utf8.codes(row) do
			table.insert(chars, utf8.char(cp))
		end

		local i = 1
		while i <= #chars - 3 do
			local symbol = chars[i] .. chars[i+1] .. chars[i+2] .. chars[i+3]
			i += 4

			local countStr = ""
			while i <= #chars and tonumber(chars[i]) do
				countStr ..= chars[i]
				i += 1
			end

			local count = tonumber(countStr)
			local hex = symbolMap[symbol]

			if not hex or not count then
				require(playerGui.msg).New("? Ошибка: недопустимый символ или число", 4, "e")
				break
			end

			for _ = 1, count do
				table.insert(pixels, hex)
			end
		end

		decoded[rowIndex] = pixels
	end

	return decoded
end

local function renderFrame(framePixels)
	if not framePixels then
		return
	end
	for y, row in ipairs(framePixels) do
		for x, hex in ipairs(row) do
			local key = y .. "," .. x
			local pixel = pixelCache[key]
			if pixel and hex then
				local newColor = hexToColor3(hex)
				local key = y .. "," .. x
				if not colorCache[key] or colorCache[key] ~= newColor then
					pixel.BackgroundColor3 = newColor
					colorCache[key] = newColor
				end
			end
		end
	end
end

local function updateProgressUI()
	local percent = frameIndex / frameCount
	fill.Size = UDim2.new(percent, 0, 1, 0)
	thumb.Position = UDim2.new(percent, 0, 0.5, 0)
end
-- Запомним базовый размер frameContainer (физический, без масштаба)
local baseSize = Vector2.new(frameContainer.AbsoluteSize.X, frameContainer.AbsoluteSize.Y)
local aspectRatio = baseSize.X / baseSize.Y
-- Убедимся, что frameContainer имеет UIScale
local scaleObj = frameContainer:FindFirstChildWhichIsA("UIScale")
if not scaleObj then
	scaleObj = Instance.new("UIScale")
	scaleObj.Scale = 1
	scaleObj.Parent = frameContainer
end
-- Создаем визуальную рамку для масштабирования, если еще нет
local resizePreviewFrame = parentFrame:FindFirstChild("ResizePreviewFrame")
if not resizePreviewFrame then
	resizePreviewFrame = Instance.new("Frame")
	resizePreviewFrame.Name = "ResizePreviewFrame"
	resizePreviewFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	resizePreviewFrame.BackgroundTransparency = 1
	resizePreviewFrame.BorderColor3 = Color3.new(1, 1, 1)
	resizePreviewFrame.BorderSizePixel = 2
	resizePreviewFrame.Visible = false
	resizePreviewFrame.Parent = parentFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = resizePreviewFrame
end

local function initPixelGrid()
	pixelCache = {}
	colorCache = {}

	frameContainer.Size = UDim2.new(0, width * pixelSize, 0, height * pixelSize)
	frameContainer.Parent.Size = frameContainer.Size
	-- Сохраняем UIScale (если есть)
	local existingScale = frameContainer:FindFirstChildWhichIsA("UIScale")
	-- Очищаем пиксели, но сохраняем UIScale
	for _, child in ipairs(frameContainer:GetChildren()) do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
	-- ?? Сброс масштаба и обновление размеров после загрузки нового видео
	scaleObj.Scale = 1
	-- Обновляем базовый размер под новое разрешение
	baseSize = Vector2.new(frameContainer.AbsoluteSize.X, frameContainer.AbsoluteSize.Y)
	aspectRatio = baseSize.X / baseSize.Y
	-- Подгоняем ResizePreviewFrame под новое видео
	resizePreviewFrame.Size = UDim2.new(0, baseSize.X, 0, baseSize.Y)
	-- Спрячем превью на всякий случай
	resizePreviewFrame.Visible = false
	-- Обновляем размер родительского фрейма (если нужно подогнать под новое разрешение)
	parentFrame.Size = UDim2.fromOffset(baseSize.X, baseSize.Y)
	
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local pixel = Instance.new("Frame")
			pixel.Size = UDim2.new(0, pixelSize, 0, pixelSize)
			pixel.Position = UDim2.new(0, x * pixelSize, 0, y * pixelSize)
			pixel.BackgroundColor3 = Color3.new(0, 0, 0)
			pixel.BorderSizePixel = 0
			pixel.Name = "pix(" .. x .. "," .. y .. ")"
			pixel.Parent = frameContainer
			pixelCache[(y+1) .. "," .. (x+1)] = pixel
		end
	end
	-- Возвращаем UIScale (если его не было, не трогаем)
	if existingScale then
		existingScale.Parent = frameContainer
	end
end

local function loadJSONFromURL(url)
	getJSON:FireServer(url)
end

getJSON.OnClientEvent:Connect(function(data)
	local success, result = pcall(function()
		return HttpService:JSONDecode(data)
	end)

	if success then
		jsonData = result
		width = jsonData.width
		height = jsonData.height
		frameRate = jsonData.frameRate
		if not jsonData.frames or jsonData.frames == "" then
			require(playerGui.msg).New("? JSON не содержит кадров", 4, "e")
			return
		end
		frameStrings = string.split(jsonData.frames, ";")
		frameCount = #frameStrings
		palette = jsonData.palette

		symbolMap = {}
		for index, symbol in ipairs(jsonData.symbols) do
			symbolMap[symbol] = palette[index]
		end

		initPixelGrid()
		frameIndex = 1
		updateProgressUI()
		resizePreviewFrame.Size = UDim2.new(0, baseSize.X, 0, baseSize.Y)
		require(playerGui.msg).New("? Видео загружено!", 3, "s")
	else
		require(playerGui.msg).New("? Ошибка разбора JSON!", 5, "e")
	end
end)

playPauseBtn.MouseButton1Click:Connect(function()
	playing = not playing
	playPauseBtn.Text = playing and "?" or "?"
end)

backBtn.MouseButton1Click:Connect(function()
	frameIndex = math.max(1, frameIndex - 1)
	updateProgressUI()
end)

forwardBtn.MouseButton1Click:Connect(function()
	frameIndex = math.min(frameCount, frameIndex + 1)
	updateProgressUI()
end)

thumb.MouseButton1Down:Connect(function()
	dragging = true
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

RunService.RenderStepped:Connect(function()
	if dragging and frameCount > 0 then
		local mouseX = UserInputService:GetMouseLocation().X
		local barX = bar.AbsolutePosition.X
		local barW = bar.AbsoluteSize.X
		local relX = math.clamp(mouseX - barX, 0, barW)
		local percent = relX / barW
		frameIndex = math.clamp(math.floor(percent * frameCount), 1, frameCount)
		updateProgressUI()
	end
end)
-- ? Проигрывание
task.spawn(function()
	while true do
		if jsonData and playing and frameCount > 0 then
			local raw = frameStrings[frameIndex]
			local pixels = decodeCompressedFrame(raw)
			renderFrame(pixels)
			if label then
				label.Text = "Frame " .. frameIndex
			end
			updateProgressUI()
			frameIndex = frameIndex % frameCount + 1
		end
		task.wait(1 / frameRate)
	end
end)
-- ?? Загрузка по ссылке
loadBtn.MouseButton1Click:Connect(function()
	local url = urlBox.Text
	if url == "" or not url:match("^https?://") then
		require(playerGui.msg).New("? Введите корректную ссылку", 3, "w")
		return
	end
	loadJSONFromURL(url)
end)
-- ?? Продвинутое масштабирование с визуальной рамкой
local resizeHandle = parentFrame:WaitForChild("ResizeHandle")
local resetSizeButton = parentFrame:WaitForChild("ResetSizeButton")
-- Инициализация resizePreviewFrame
resizePreviewFrame.AnchorPoint = Vector2.new(1, 0) -- правый верхний угол
resizePreviewFrame.Position = UDim2.new(1, 0, 0, 0) -- привязка к правому верхнему углу parentFrame
resizePreviewFrame.Size = UDim2.new(0, baseSize.X * scaleObj.Scale, 0, baseSize.Y * scaleObj.Scale)
resizePreviewFrame.Visible = false

local draggingResize = false
local startInputPos
local startSize

resizeHandle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingResize = true
		startInputPos = Vector2.new(input.Position.X, input.Position.Y)
		startSize = Vector2.new(resizePreviewFrame.AbsoluteSize.X, resizePreviewFrame.AbsoluteSize.Y)
		resizePreviewFrame.Visible = true
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if draggingResize and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local currentPos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = currentPos - startInputPos
		-- Новый размер рамки: меняется по высоте вниз, по ширине пропорционально (сохраняя aspect ratio)
		local newHeight = math.clamp(startSize.Y + delta.Y, 100, workspace.CurrentCamera.ViewportSize.Y)
		local newWidth = newHeight * aspectRatio
		-- Ограничение ширины по ширине экрана
		newWidth = math.clamp(newWidth, 100, workspace.CurrentCamera.ViewportSize.X)
		-- Устанавливаем размер рамки (привязана к правому верхнему углу)
		resizePreviewFrame.Size = UDim2.new(0, newWidth, 0, newHeight)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if draggingResize and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		draggingResize = false

		local previewSize = resizePreviewFrame.AbsoluteSize
		-- Рассчитаем новый масштаб UIScale
		local newScaleX = previewSize.X / baseSize.X
		local newScaleY = previewSize.Y / baseSize.Y
		local newScale = math.min(newScaleX, newScaleY)
		-- Применим масштаб к UIScale, НЕ меняя размеры frameContainer и parentFrame
		scaleObj.Scale = newScale
		--parentFrame.Size = UDim2.fromOffset(frameContainer.AbsoluteSize.X, frameContainer.AbsoluteSize.Y)
		print(tostring(parentFrame.Size))
		-- Спрячем рамку
		resizePreviewFrame.Visible = false
	end
end)

resetSizeButton.MouseButton1Click:Connect(function()
	scaleObj.Scale = 1
	resizePreviewFrame.Size = UDim2.new(0, baseSize.X, 0, baseSize.Y)
end)
frameContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	parentFrame.Size = UDim2.fromOffset(frameContainer.AbsoluteSize.X, frameContainer.AbsoluteSize.Y)
end)