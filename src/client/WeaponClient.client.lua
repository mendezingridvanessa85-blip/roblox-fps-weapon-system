local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local weaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local remotes = weaponSystem:WaitForChild("Remotes")

local fireWeapon = remotes:WaitForChild("FireWeapon")
local reloadWeapon = remotes:WaitForChild("ReloadWeapon")
local setAiming = remotes:WaitForChild("SetAiming")
local weaponEffects = remotes:WaitForChild("WeaponEffects")
local rifleConfig = require(
	weaponSystem:WaitForChild("Configs"):WaitForChild("RifleConfig")
)

local firing = false
local recoilIndex = 1
local requestCounter = 0
local lastAcceptedShot = 0
local aiming = false
local adsAlpha = 0
local hipFieldOfView = 70

local function getEquippedRifle()
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChild("Rifle")

	if tool and tool:IsA("Tool") then
		return tool
	end

	return nil
end

local function setLocalToolVisibility(tool, hidden)
	if not tool then
		return
	end

	local transparency = hidden and 1 or 0
	for _, item in ipairs(tool:GetDescendants()) do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = transparency
		end
	end
end

local recoilTarget = Vector2.new(0, 0)
local recoilCurrent = Vector2.new(0, 0)
local recoilLastFrame = Vector2.new(0, 0)
local weaponKickPosition = Vector3.zero
local weaponKickRotation = Vector2.zero

local viewModelEditor = workspace:WaitForChild("ViewModelEditor")
local viewModelTemplate = viewModelEditor:WaitForChild("RifleViewModel")
local activeViewModels = {}
local cameraPartLocalCFrame = nil
local aimAttachmentLocalCFrame = nil
local sway = Vector2.new(0, 0)
local bobTime = 0

local function hideEditorSource()
	for _, item in ipairs(viewModelTemplate:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 1
		elseif item:IsA("BillboardGui") then
			item.Enabled = false
		end
	end
end

local function clearViewModel()
	for _, model in ipairs(activeViewModels) do
		model:Destroy()
	end
	table.clear(activeViewModels)
	cameraPartLocalCFrame = nil
	aimAttachmentLocalCFrame = nil
end

local function cloneViewModel(template)
	if not template or not template:IsA("Model") then
		return
	end

	local clone = template:Clone()
	for _, item in ipairs(clone:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = false
			item.LocalTransparencyModifier = 0
		elseif item:IsA("BillboardGui") then
			item:Destroy()
		end
	end

	local cameraPart = clone:FindFirstChild("CameraBone", true) or clone:FindFirstChild("CameraPart", true)
	if not cameraPart or not cameraPart:IsA("BasePart") then
		clone:Destroy()
		return
	end

	cameraPart.Transparency = 1
	cameraPartLocalCFrame = clone:GetPivot():ToObjectSpace(cameraPart.CFrame)

	local aimAttachment = clone:FindFirstChild("AimAttachment", true)
	if aimAttachment and aimAttachment:IsA("Attachment") then
		aimAttachmentLocalCFrame = clone:GetPivot():ToObjectSpace(aimAttachment.WorldCFrame)
	end

	clone.Name = "ActiveRifleViewModel"
	clone.Parent = workspace.CurrentCamera
	table.insert(activeViewModels, clone)
end

local function refreshViewModel()
	clearViewModel()

	local tool = getEquippedRifle()
	if not tool then
		return
	end

	hideEditorSource()
	cloneViewModel(viewModelTemplate)
end

local lastViewModelSync = 0
RunService.Heartbeat:Connect(function()
	if os.clock() - lastViewModelSync < 0.2 then
		return
	end
	lastViewModelSync = os.clock()
	hideEditorSource()

	local equippedRifle = getEquippedRifle()
	local hasRifle = equippedRifle ~= nil
	setLocalToolVisibility(equippedRifle, hasRifle)

	if hasRifle and #activeViewModels == 0 then
		refreshViewModel()
	elseif not hasRifle and #activeViewModels > 0 then
		clearViewModel()
	end
end)

local function getRecoilMultiplier()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return 1
	end

	local multiplier = 1
	if humanoid.FloorMaterial == Enum.Material.Air then
		multiplier = rifleConfig.AirborneRecoilMultiplier
	elseif humanoid.WalkSpeed <= 10 then
		multiplier = rifleConfig.CrouchingRecoilMultiplier
	else
		local horizontalVelocity = Vector3.new(
			root.AssemblyLinearVelocity.X,
			0,
			root.AssemblyLinearVelocity.Z
		).Magnitude
		if horizontalVelocity > 2 or humanoid.MoveDirection.Magnitude > 0.05 then
			multiplier = rifleConfig.MovingRecoilMultiplier
		end
	end

	if aiming then
		multiplier *= rifleConfig.Aim.RecoilMultiplier
	end
	return multiplier
end

local function applyAcceptedRecoil()
	local now = os.clock()
	if now - lastAcceptedShot > rifleConfig.RecoilResetTime then
		recoilIndex = 1
	end
	lastAcceptedShot = now

	local pattern = rifleConfig.RecoilPattern
	local recoil = pattern[recoilIndex] or pattern[#pattern]
	local multiplier = getRecoilMultiplier()
	recoil *= multiplier
	recoilIndex += 1

	recoilTarget += recoil
	weaponKickPosition += Vector3.new(
		recoil.X * 0.012,
		recoil.Y * 0.009,
		rifleConfig.ViewModelKick * multiplier
	)
	weaponKickRotation += Vector2.new(recoil.X * 1.15, recoil.Y * 1.5)
end

local function createTracer(hitPosition)
	if typeof(hitPosition) ~= "Vector3" then
		return
	end

	local muzzleAttachment
	for _, viewModel in ipairs(activeViewModels) do
		muzzleAttachment = viewModel:FindFirstChild("MuzzleAttachment", true)
		if muzzleAttachment and muzzleAttachment:IsA("Attachment") then
			break
		end
		muzzleAttachment = nil
	end

	local startPosition = muzzleAttachment and muzzleAttachment.WorldPosition
		or (camera.CFrame.Position + camera.CFrame.LookVector * 1.2)
	local distance = (hitPosition - startPosition).Magnitude
	if distance < 0.05 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "LocalBulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanTouch = false
	tracer.CanQuery = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 217, 92)
	tracer.Transparency = 0.1
	tracer.Size = Vector3.new(0.045, 0.045, distance)
	tracer.CFrame = CFrame.lookAt(startPosition, hitPosition) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace.CurrentCamera

	Debris:AddItem(tracer, 0.055)
end

weaponEffects.OnClientEvent:Connect(function(eventType, requestId, extra1, extra2)
	if eventType == "ShotAccepted" and typeof(requestId) == "number" then
		local hitPosition = extra1
		createTracer(hitPosition)
		applyAcceptedRecoil()
	end
end)

RunService:BindToRenderStep("WeaponPresentation", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera = workspace.CurrentCamera

	local equippedTool = getEquippedRifle()
	if not equippedTool or equippedTool:GetAttribute("Reloading") then
		aiming = false
	end
	adsAlpha += ((aiming and 1 or 0) - adsAlpha)
		* math.clamp(dt * rifleConfig.Aim.TransitionSpeed, 0, 1)
	local targetFov = aiming and rifleConfig.Aim.Fov or hipFieldOfView
	camera.FieldOfView += (targetFov - camera.FieldOfView)
		* math.clamp(dt * rifleConfig.Aim.TransitionSpeed, 0, 1)

	recoilCurrent = recoilCurrent:Lerp(
		recoilTarget,
		math.clamp(dt * rifleConfig.RecoilKickSpeed, 0, 1)
	)

	recoilTarget = recoilTarget:Lerp(
		Vector2.new(0, 0),
		math.clamp(dt * rifleConfig.RecoilRecoverySpeed, 0, 1)
	)

	local delta = recoilCurrent - recoilLastFrame
	recoilLastFrame = recoilCurrent

	camera.CFrame *= CFrame.Angles(
		math.rad(delta.Y),
		math.rad(-delta.X),
		0
	)

	weaponKickPosition = weaponKickPosition:Lerp(Vector3.zero, math.clamp(dt * 12, 0, 1))
	weaponKickRotation = weaponKickRotation:Lerp(Vector2.zero, math.clamp(dt * 14, 0, 1))

	if #activeViewModels > 0 then
		local mouseDelta = UserInputService:GetMouseDelta()
		sway = sway:Lerp(
			Vector2.new(-mouseDelta.X, -mouseDelta.Y) * 0.012,
			math.clamp(dt * 12, 0, 1)
		)

		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local moving = humanoid and humanoid.MoveDirection.Magnitude > 0
		if moving then
			bobTime += dt * 9
		end

		local bob = moving and math.sin(bobTime) * 0.025 or 0
		local presentationCFrame = camera.CFrame
			* CFrame.new(0, bob, 0)
			* CFrame.Angles(math.rad(sway.Y), math.rad(sway.X), 0)
			* CFrame.new(weaponKickPosition)
			* CFrame.Angles(
				math.rad(-weaponKickRotation.Y),
				math.rad(weaponKickRotation.X),
				math.rad(weaponKickRotation.X * 0.25)
			)

		for index = #activeViewModels, 1, -1 do
			if not activeViewModels[index].Parent then
				table.remove(activeViewModels, index)
			end
		end

		if cameraPartLocalCFrame then
			local hipPivot = presentationCFrame * cameraPartLocalCFrame:Inverse()
			local aimPivot = aimAttachmentLocalCFrame
				and presentationCFrame * aimAttachmentLocalCFrame:Inverse()
				or hipPivot

			for _, model in ipairs(activeViewModels) do
				model:PivotTo(hipPivot:Lerp(aimPivot, adsAlpha))
			end
		end
	end
end)

local function shootOnce()
	local tool = getEquippedRifle()
	if not tool or tool:GetAttribute("Reloading") then
		return false
	end

	if tool:GetAttribute("Ammo") == nil then
		tool:SetAttribute("Ammo", rifleConfig.MagazineSize)
	end

	if (tool:GetAttribute("Ammo") or 0) <= 0 then
		firing = false
		if rifleConfig.AutoReload then
			reloadWeapon:FireServer()
		end
		return false
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)

	requestCounter = (requestCounter % 1000000000) + 1
	fireWeapon:FireServer(
		requestCounter,
		ray.Origin,
		ray.Direction,
		workspace:GetServerTimeNow()
	)
	return true
end

local function setAimingState(value)
	local tool = getEquippedRifle()
	local shouldAim = value and tool and not tool:GetAttribute("Reloading") or false
	if aiming == shouldAim then
		return
	end

	aiming = shouldAim
	setAiming:FireServer(aiming)
end

local function startFiring()
	if firing then
		return
	end

	local tool = getEquippedRifle()

	if not tool then
		return
	end

	if tool:GetAttribute("Reloading") then
		return
	end

	firing = true
	if not rifleConfig.Automatic then
		shootOnce()
		firing = false
		return
	end

	task.spawn(function()
		local secondsPerShot = 60 / rifleConfig.RPM
		while firing do
			if not shootOnce() then
				break
			end
			task.wait(secondsPerShot)
		end
		firing = false
	end)
end

local function stopFiring()
	firing = false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		startFiring()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAimingState(true)
	elseif input.KeyCode == Enum.KeyCode.R then
		local tool = getEquippedRifle()
		if tool and not tool:GetAttribute("Reloading") then
			stopFiring()
			setAimingState(false)
			reloadWeapon:FireServer()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		stopFiring()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAimingState(false)
	end
end)

local function monitorCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(refreshViewModel)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			setAimingState(false)
			task.defer(refreshViewModel)
		end
	end)

	task.defer(refreshViewModel)
end

if player.Character then
	monitorCharacter(player.Character)
end

player.CharacterAdded:Connect(function(character)
	stopFiring()
	aiming = false
	adsAlpha = 0
	recoilIndex = 1
	lastAcceptedShot = 0
	recoilTarget = Vector2.new(0, 0)
	recoilCurrent = Vector2.new(0, 0)
	recoilLastFrame = Vector2.new(0, 0)
	weaponKickPosition = Vector3.zero
	weaponKickRotation = Vector2.zero
	monitorCharacter(character)
end)
