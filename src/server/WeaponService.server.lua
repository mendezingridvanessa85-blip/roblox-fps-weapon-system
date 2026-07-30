local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local weaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local remotes = weaponSystem:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon")
local reloadWeapon = remotes:WaitForChild("ReloadWeapon")
local setAiming = remotes:WaitForChild("SetAiming")
local weaponEffects = remotes:WaitForChild("WeaponEffects")

local giveWeaponEvent = remotes:FindFirstChild("GiveWeaponEvent")
if not giveWeaponEvent then
	giveWeaponEvent = Instance.new("RemoteEvent")
	giveWeaponEvent.Name = "GiveWeaponEvent"
	giveWeaponEvent.Parent = remotes
end

local configs = weaponSystem:WaitForChild("Configs")
local rifleConfig = require(configs:WaitForChild("RifleConfig"))

local weaponTemplates = ReplicatedStorage:FindFirstChild("WeaponTemplates")

local rifleTemplate = weaponTemplates and weaponTemplates:FindFirstChild("Rifle")

local lastShotTimes = {}
local sprayStates = {}
local reloadVersions = {}
local aimStates = {}
local characterHistory = {}
local lastSnapshotTime = 0

local function isFiniteNumber(value)
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector)
	return isFiniteNumber(vector.X)
		and isFiniteNumber(vector.Y)
		and isFiniteNumber(vector.Z)
end

local function getEquippedRifle(player)
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChild("Rifle")

	if not tool then
		local backpack = player:FindFirstChild("Backpack")
		tool = backpack and backpack:FindFirstChild("Rifle")
	end

	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local weaponId = tool:FindFirstChild("WeaponId")
	if not weaponId then
		weaponId = Instance.new("StringValue")
		weaponId.Name = "WeaponId"
		weaponId.Value = rifleConfig.Id
		weaponId.Parent = tool
	end

	if weaponId.Value ~= rifleConfig.Id then
		return nil
	end

	return tool
end

local function setWeaponState(tool, state)
	if tool and tool.Parent then
		tool:SetAttribute("WeaponState", state)
	end
end

local function giveRifle(player)
	local backpack = player:WaitForChild("Backpack")
	local character = player.Character

	if backpack:FindFirstChild("Rifle") 
		or (character and character:FindFirstChild("Rifle")) then
		return
	end

	local template = rifleTemplate or (ReplicatedStorage:FindFirstChild("WeaponTemplates") and ReplicatedStorage.WeaponTemplates:FindFirstChild("Rifle"))
	if not template then
		return
	end

	local rifle = template:Clone()

	local weaponId = rifle:FindFirstChild("WeaponId")
	if not weaponId then
		weaponId = Instance.new("StringValue")
		weaponId.Name = "WeaponId"
		weaponId.Parent = rifle
	end
	weaponId.Value = rifleConfig.Id

	rifle:SetAttribute("Ammo", rifleConfig.MagazineSize)
	rifle:SetAttribute("ReserveAmmo", rifleConfig.ReserveAmmo)
	rifle:SetAttribute("Reloading", false)
	rifle:SetAttribute("Aiming", false)
	rifle:SetAttribute("WeaponState", "Idle")
	rifle:SetAttribute("ShotCounter", 0)

	rifle.Parent = backpack

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	task.wait(0.2)

	humanoid:EquipTool(rifle)
	
	task.wait(0.1)

end

local function cancelReload(player, tool)
	reloadVersions[player] = (reloadVersions[player] or 0) + 1
	if tool and tool.Parent then
		tool:SetAttribute("Reloading", false)
		setWeaponState(tool, "Idle")
	end
end
giveWeaponEvent.OnServerEvent:Connect(function(player)
	giveRifle(player)
end)

local function beginReload(player)
	local character = player.Character
	local tool = getEquippedRifle(player)
	if not character or not tool or tool:GetAttribute("Reloading") then
		return false
	end

	local ammo = tool:GetAttribute("Ammo") or 0
	local reserve = tool:GetAttribute("ReserveAmmo") or 0
	if ammo >= rifleConfig.MagazineSize or reserve <= 0 then
		return false
	end

	local version = (reloadVersions[player] or 0) + 1
	reloadVersions[player] = version
	tool:SetAttribute("Reloading", true)
	aimStates[player] = false
	tool:SetAttribute("Aiming", false)
	setWeaponState(tool, "Reloading")

	local ancestryConnection
	ancestryConnection = tool.AncestryChanged:Connect(function()
		if tool.Parent ~= character then
			if ancestryConnection then
				ancestryConnection:Disconnect()
				ancestryConnection = nil
			end
			if reloadVersions[player] == version then
				cancelReload(player, tool)
			end
		end
	end)

	task.delay(rifleConfig.ReloadTime, function()
		if ancestryConnection then
			ancestryConnection:Disconnect()
			ancestryConnection = nil
		end

		if reloadVersions[player] ~= version or tool.Parent ~= character then
			return
		end

		local currentAmmo = tool:GetAttribute("Ammo") or 0
		local currentReserve = tool:GetAttribute("ReserveAmmo") or 0
		local loaded = math.min(
			math.max(0, rifleConfig.MagazineSize - currentAmmo),
			currentReserve
		)

		tool:SetAttribute("Ammo", currentAmmo + loaded)
		tool:SetAttribute("ReserveAmmo", currentReserve - loaded)
		tool:SetAttribute("Reloading", false)
		setWeaponState(tool, "Idle")
	end)

	return true
end

local function getSpreadDirection(player, humanoid, root, direction, requestId, now)
	local spreadConfig = rifleConfig.Spread
	local state = sprayStates[player]
	if not state or now - state.LastShot > spreadConfig.ResetTime then
		state = {Index = 1, LastShot = now}
	else
		state.Index += 1
		state.LastShot = now
	end
	sprayStates[player] = state

	local horizontalVelocity = Vector3.new(
		root.AssemblyLinearVelocity.X,
		0,
		root.AssemblyLinearVelocity.Z
	).Magnitude
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local crouching = humanoid.WalkSpeed <= 10
	local moving = horizontalVelocity > 2 or humanoid.MoveDirection.Magnitude > 0.05

	local spreadDegrees = spreadConfig.Standing
	if airborne then
		spreadDegrees = spreadConfig.Airborne
	elseif crouching then
		spreadDegrees = spreadConfig.Crouching
	elseif moving then
		spreadDegrees = spreadConfig.Moving
	end

	spreadDegrees = math.min(
		spreadConfig.Maximum,
		spreadDegrees + spreadConfig.PerShot * math.max(0, state.Index - 1)
	)
	if aimStates[player] then
		spreadDegrees *= rifleConfig.Aim.SpreadMultiplier
	end

	local seed = math.floor((
		player.UserId * 104729
			+ requestId * 15485863
			+ state.Index * 32452843
		) % 2147483647)
	local random = Random.new(seed)
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(random:NextNumber()) * math.tan(math.rad(spreadDegrees))

	local right = direction:Cross(Vector3.yAxis)
	if right.Magnitude < 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	local up = right:Cross(direction).Unit

	return (direction + right * math.cos(angle) * radius + up * math.sin(angle) * radius).Unit,
		spreadDegrees
end

local function getDamageMultiplier(part)
	local name = string.lower(part.Name)
	if string.find(name, "head", 1, true) then
		return rifleConfig.HeadMultiplier, "Head"
	elseif string.find(name, "torso", 1, true) or name == "humanoidrootpart" then
		return rifleConfig.TorsoMultiplier, "Torso"
	elseif string.find(name, "arm", 1, true) or string.find(name, "hand", 1, true) then
		return rifleConfig.ArmMultiplier, "Arm"
	elseif string.find(name, "leg", 1, true) or string.find(name, "foot", 1, true) then
		return rifleConfig.LegMultiplier, "Leg"
	end
	return rifleConfig.TorsoMultiplier, "Body"
end

local function canDamagePlayer(shooter, targetPlayer)
	if rifleConfig.FriendlyFire or not targetPlayer then
		return true
	end
	if shooter.Team ~= nil and targetPlayer.Team == shooter.Team then
		return false
	end
	return true
end

local function tagHumanoid(targetHumanoid, player)
	local oldTag = targetHumanoid:FindFirstChild("creator")
	if oldTag then
		oldTag:Destroy()
	end

	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = player
	tag.Parent = targetHumanoid
	Debris:AddItem(tag, 5)
end

local function rejectShot(player, requestId, reason)
	weaponEffects:FireClient(player, "ShotRejected", requestId, reason)
end

local function isHitboxPart(part)
	local name = string.lower(part.Name)
	return name == "humanoidrootpart"
		or string.find(name, "head", 1, true)
		or string.find(name, "torso", 1, true)
		or string.find(name, "arm", 1, true)
		or string.find(name, "hand", 1, true)
		or string.find(name, "leg", 1, true)
		or string.find(name, "foot", 1, true)
end

local function captureCharacterHistory(serverTime)
	local lagConfig = rifleConfig.LagCompensation
	if not lagConfig.Enabled or serverTime - lastSnapshotTime < lagConfig.SnapshotInterval then
		return
	end
	lastSnapshotTime = serverTime

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local snapshot = {Time = serverTime, Parts = {}}
			for _, item in ipairs(character:GetChildren()) do
				if item:IsA("BasePart") and isHitboxPart(item) then
					snapshot.Parts[item.Name] = {
						CFrame = item.CFrame,
						Size = item.Size,
					}
				end
			end

			local history = characterHistory[player] or {}
			table.insert(history, snapshot)
			characterHistory[player] = history

			while #history > 0 and serverTime - history[1].Time > lagConfig.HistorySeconds do
				table.remove(history, 1)
			end
		end
	end
end

local function getClosestSnapshot(targetPlayer, shotTime)
	local history = characterHistory[targetPlayer]
	if not history then
		return nil
	end

	local closest
	local smallestDelta = math.huge
	for _, snapshot in ipairs(history) do
		local delta = math.abs(snapshot.Time - shotTime)
		if delta < smallestDelta then
			closest = snapshot
			smallestDelta = delta
		end
	end
	return closest
end

local function rayIntersectsBox(origin, direction, maxDistance, boxCFrame, boxSize)
	local localOrigin = boxCFrame:PointToObjectSpace(origin)
	local localDirection = boxCFrame:VectorToObjectSpace(direction)
	local minCorner = -boxSize * 0.5
	local maxCorner = boxSize * 0.5
	local nearDistance = 0
	local farDistance = maxDistance

	for _, axis in ipairs({"X", "Y", "Z"}) do
		local originAxis = localOrigin[axis]
		local directionAxis = localDirection[axis]
		local minAxis = minCorner[axis]
		local maxAxis = maxCorner[axis]

		if math.abs(directionAxis) < 0.00001 then
			if originAxis < minAxis or originAxis > maxAxis then
				return nil
			end
		else
			local first = (minAxis - originAxis) / directionAxis
			local second = (maxAxis - originAxis) / directionAxis
			if first > second then
				first, second = second, first
			end
			nearDistance = math.max(nearDistance, first)
			farDistance = math.min(farDistance, second)
			if nearDistance > farDistance then
				return nil
			end
		end
	end

	if farDistance < 0 or nearDistance > maxDistance then
		return nil
	end
	return math.max(0, nearDistance)
end

local function getLagCompensatedHit(shooter, origin, direction, shotTime)
	if not rifleConfig.LagCompensation.Enabled then
		return nil
	end

	local closestHit
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= shooter then
			local targetCharacter = targetPlayer.Character
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local snapshot = targetHumanoid and targetHumanoid.Health > 0
				and getClosestSnapshot(targetPlayer, shotTime)

			if snapshot then
				for partName, partData in pairs(snapshot.Parts) do
					local distance = rayIntersectsBox(
						origin,
						direction,
						rifleConfig.Range,
						partData.CFrame,
						partData.Size
					)
					if distance and (not closestHit or distance < closestHit.Distance) then
						closestHit = {
							Character = targetCharacter,
							Humanoid = targetHumanoid,
							Player = targetPlayer,
							PartName = partName,
							Distance = distance,
							Position = origin + direction * distance,
						}
					end
				end
			end
		end
	end
	return closestHit
end

RunService.Heartbeat:Connect(function()
	captureCharacterHistory(workspace:GetServerTimeNow())
end)

local function setupPlayer(player)
	player.CharacterAdded:Connect(function()
		lastShotTimes[player] = nil
		sprayStates[player] = nil
		aimStates[player] = false
		characterHistory[player] = nil
		reloadVersions[player] = (reloadVersions[player] or 0) + 1
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end


setAiming.OnServerEvent:Connect(function(player, isAiming)
	if typeof(isAiming) ~= "boolean" then
		return
	end

	local tool = getEquippedRifle(player)
	local allowed = tool ~= nil and not tool:GetAttribute("Reloading") and isAiming
	aimStates[player] = allowed

	if tool then
		tool:SetAttribute("Aiming", allowed)
	end
end)

reloadWeapon.OnServerEvent:Connect(function(player)
	beginReload(player)
end)

fireWeapon.OnServerEvent:Connect(function(player, requestId, origin, direction, shotTimestamp)


	if typeof(requestId) ~= "number"
		or typeof(origin) ~= "Vector3"
		or typeof(direction) ~= "Vector3"
		or not isFiniteNumber(requestId)
		or not isFiniteVector(origin)
		or not isFiniteVector(direction)
		or (shotTimestamp ~= nil and (typeof(shotTimestamp) ~= "number" or not isFiniteNumber(shotTimestamp))) then
		return
	end

	requestId = math.floor(requestId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local tool = getEquippedRifle(player)

	if not character or not humanoid or humanoid.Health <= 0 or not root or not head or not tool then


		rejectShot(player, requestId, "InvalidState")
		return
	end

	if tool:GetAttribute("Reloading") then
		rejectShot(player, requestId, "Reloading")
		return
	end

	if direction.Magnitude < rifleConfig.MinimumDirectionMagnitude then
		rejectShot(player, requestId, "InvalidDirection")
		return
	end

	if (origin - head.Position).Magnitude > rifleConfig.MaxOriginDistance then
		rejectShot(player, requestId, "InvalidOrigin")
		return
	end

	local directionUnit = direction.Unit

	if directionUnit:Dot(root.CFrame.LookVector) < rifleConfig.MaximumBackwardDot then
		rejectShot(player, requestId, "InvalidAngle")
		return
	end

	local now = os.clock()
	local serverTime = workspace:GetServerTimeNow()
	local lagConfig = rifleConfig.LagCompensation
	local compensatedShotTime = serverTime
	if typeof(shotTimestamp) == "number" then
		compensatedShotTime = math.clamp(
			shotTimestamp,
			serverTime - lagConfig.MaxRewindSeconds,
			serverTime + 0.05
		)
	end
	local minimumShotDelay = 60 / rifleConfig.RPM
	local lastShot = lastShotTimes[player] or 0
	if now - lastShot < minimumShotDelay * 0.92 then
		rejectShot(player, requestId, "FireRate")
		return
	end

	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		rejectShot(player, requestId, "Empty")
		if rifleConfig.AutoReload then
			beginReload(player)
		end
		return
	end

	lastShotTimes[player] = now
	local shotCounter = (tool:GetAttribute("ShotCounter") or 0) + 1
	tool:SetAttribute("ShotCounter", shotCounter)
	tool:SetAttribute("Ammo", ammo - 1)
	setWeaponState(tool, "Firing")

	task.delay(minimumShotDelay, function()
		if tool.Parent and lastShotTimes[player] == now and not tool:GetAttribute("Reloading") then
			setWeaponState(tool, "Idle")
		end
	end)

	local spreadDirection, spreadDegrees = getSpreadDirection(
		player,
		humanoid,
		root,
		directionUnit,
		requestId,
		now
	)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoredInstances = {character}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			table.insert(ignoredInstances, otherPlayer.Character)
		end
	end
	raycastParams.FilterDescendantsInstances = ignoredInstances
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = false

	local result = workspace:Raycast(origin, spreadDirection * rifleConfig.Range, raycastParams)
	local staticDistance = result and (result.Position - origin).Magnitude or rifleConfig.Range
	local lagHit = getLagCompensatedHit(
		player,
		origin,
		spreadDirection,
		compensatedShotTime
	)

	local hitPosition = origin + spreadDirection * rifleConfig.Range
	local hitNormal = -spreadDirection
	local hitZone = "None"
	local damageDealt = 0

	local function damageTarget(targetHumanoid, targetPlayer, hitPart, distance)
		if not canDamagePlayer(player, targetPlayer) then
			return "Friendly", 0
		end

		local zoneMultiplier, zoneName = getDamageMultiplier(hitPart)
		local distanceAlpha = math.clamp(
			(distance - rifleConfig.FalloffStart)
				/ math.max(1, rifleConfig.Range - rifleConfig.FalloffStart),
			0,
			1
		)
		local distanceMultiplier = 1 - distanceAlpha * (1 - rifleConfig.MinimumDamageMultiplier)
		local damage = math.max(
			1,
			math.floor(rifleConfig.Damage * zoneMultiplier * distanceMultiplier + 0.5)
		)

		tagHumanoid(targetHumanoid, player)
		targetHumanoid:TakeDamage(damage)
		return zoneName, damage
	end

	if lagHit and lagHit.Distance < staticDistance then
		hitPosition = lagHit.Position
		hitZone, damageDealt = damageTarget(
			lagHit.Humanoid,
			lagHit.Player,
			{Name = lagHit.PartName},
			lagHit.Distance
		)
	elseif result then
		hitPosition = result.Position
		hitNormal = result.Normal

		local targetModel = result.Instance:FindFirstAncestorOfClass("Model")
		local targetHumanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
		if targetHumanoid and targetHumanoid ~= humanoid and targetHumanoid.Health > 0 then
			local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
			hitZone, damageDealt = damageTarget(
				targetHumanoid,
				targetPlayer,
				result.Instance,
				staticDistance
			)
		end
	end

	weaponEffects:FireClient(
		player,
		"ShotAccepted",
		requestId,
		hitPosition,
		hitNormal,
		hitZone,
		damageDealt,
		spreadDegrees
	)

	if tool:GetAttribute("Ammo") <= 0 and rifleConfig.AutoReload then
		task.delay(0.15, function()
			if tool.Parent == character and not tool:GetAttribute("Reloading") then
				beginReload(player)
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastShotTimes[player] = nil
	sprayStates[player] = nil
	aimStates[player] = nil
	characterHistory[player] = nil
	reloadVersions[player] = nil
end)