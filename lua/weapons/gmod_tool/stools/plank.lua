--[[
	plank.lua: Plank SWEP for GMod
]]

--------------------------------------------------------------------------------
-- Tool Metadata & Configuration
--------------------------------------------------------------------------------

TOOL.Category = "Construction"
TOOL.Name = "#tool.plank.name"
TOOL.Information = {
	{ name = "left", stage = 0 },
	{ name = "left_1", stage = 1 }
}

local CONVAR_WELD = "weld"			 -- Weld planks at their endpoints?
local CONVAR_FREEZE = "freeze"		 -- Freeze created planks?
local CONVAR_NOCOLLIDE = "nocollide" -- Nocollide planks with their endpoints?
local CONVAR_THICKNESS = "thickness" -- How thick should planks be?
local CONVAR_PLANK_MODEL = "model"	 -- What model should be used for planks?

if (CLIENT) then
	TOOL.ClientConVar[CONVAR_WELD] = "1"
	TOOL.ClientConVar[CONVAR_FREEZE] = "1"
	TOOL.ClientConVar[CONVAR_NOCOLLIDE] = "0"
	TOOL.ClientConVar[CONVAR_THICKNESS] = "4"
	TOOL.ClientConVar[CONVAR_PLANK_MODEL] = "models/props/plank_swep/plank.mdl"
end

local ConVarsDefault = TOOL:BuildConVarList()

--------------------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------------------

if (CLIENT) then
	language.Add("tool.plank.name", "Plank")
	language.Add("tool.plank.desc", "Create a wooden plank between two points")
	language.Add("tool.plank.left", "Select the first point")
	language.Add("tool.plank.left_1", "Select the second point")

	language.Add("tool.plank." .. CONVAR_WELD, "Weld")
	language.Add(
		"tool.plank." .. CONVAR_WELD .. ".help",
		"If selected, plank will be welded at both ends"
	)

	language.Add("tool.plank." .. CONVAR_FREEZE, "Freeze")
	language.Add(
		"tool.plank." .. CONVAR_FREEZE .. ".help",
		"If selected, plank will be frozen when placed"
	)

	language.Add("tool.plank." .. CONVAR_NOCOLLIDE, "No Collide")
	language.Add(
		"tool.plank." .. CONVAR_NOCOLLIDE .. ".help",
		"If selected, collisions with connected props will be disabled"
	)

	language.Add("tool.plank." .. CONVAR_THICKNESS, "Thickness:")
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

--[[
	UPDATE_VISUAL_MSG is sent when a plank has been created and its client-side
	visuals (namely scale) need to be updated.
]]
local UPDATE_VISUAL_MSG = "plank_stool_update_visual"

if (SERVER) then
	util.AddNetworkString(UPDATE_VISUAL_MSG)
end

if (CLIENT) then
	function UpdatePlankVisuals(ent, length, thickness)
		local m = Matrix()
		m:Scale(Vector(length/2, thickness, 1))
		ent:EnableMatrix("RenderMultiply", m)

		local rbMin, rbMax = ent:GetModelRenderBounds()
		ent:SetRenderBounds(length * rbMin, length * rbMax)
	end

	net.Receive(
		UPDATE_VISUAL_MSG,
		function(len)
			local ent = net.ReadEntity()
			if (not IsValid(ent)) then return end

			local length = net.ReadFloat()
			if (length < 0) then return end

			local thickness = net.ReadFloat()
			if (thickness < 0) then return end

			ent:EnableCustomCollisions(true)
			UpdatePlankVisuals(ent, length, thickness)
		end
	)
end

--------------------------------------------------------------------------------
-- Tool Implementation
--------------------------------------------------------------------------------

util.PrecacheModel("models/props/plank_swep/plank.mdl")

--[[
	ScalePhysicsMesh scales the physics mesh of a given entity. The new mesh is
	immediately applied, discarding the previous physics object.

	ScalePhysicsMesh assumes the entity has physics and a single convex mesh
	(all that is needed for our planks). It returns the new physics object upon
	success and nil on failure.
]]
function ScalePhysicsMesh(ent, factor)
	if (CLIENT) then return end

	ent:PhysicsInit(SOLID_VPHYSICS)
	local physObj = ent:GetPhysicsObject()
	if (not IsValid(physObj)) then return nil end

	local physMesh = physObj:GetMesh()

	for key, vertex in ipairs(physMesh) do
		-- Save on a table allocation by overwriting vertices in physMesh with
		-- vectors
		physMesh[key] = vertex.pos * factor
	end

	ent:PhysicsInitConvex(physMesh)
	ent:SetMoveType(MOVETYPE_VPHYSICS)
	ent:SetSolid(SOLID_VPHYSICS)
	ent:EnableCustomCollisions(true)
	return ent:GetPhysicsObject()
end

local ENT_MODIFIER_PLANK = "plank_params"

--[[
	SpawnPlank spawns a plank with `model` between `startPos` and `endPos`. The
	plank is `thickness` units thick and has a flat side facing `normal`. It
	returns the entity and physics object on success and two nils on failure.

	SpawnPlank does not handle cleanups or undos.
]]

if (SERVER) then
	function SpawnPlank(model, startPos, endPos, thickness, normal)
		local ent = ents.Create("prop_physics")
		if (not IsValid(ent)) then return nil, nil end

		-- Raise the plank slightly above the surface to prevent weird physics
		local offset = 0.75 * normal
		startPos = startPos + offset
		endPos = endPos + offset

		ent:SetModel(model)
		ent:SetPos(startPos)

		local ang = (startPos - endPos):AngleEx(normal)
		ent:SetAngles(ang)
		ent:Spawn()

		local length = (startPos:Distance(endPos))

		physObj = ScalePhysicsMesh(ent, Vector(length/2, thickness, 1))
		if not (IsValid(physObj)) then return nil, nil end
		physObj:SetMass(60)

		ent:GetPhysicsObject():Wake()

		if (game.SinglePlayer()) then
			UpdateClientPlank(ent, length, thickness)
		else
			-- TODO: I have no idea how this is actually supposed to be done. How do we get a newly-created entity
			-- on the client? net.ReadEntity always fails...
			timer.Simple(0, function() UpdateClientPlank(ent, length, thickness) end)
		end

		duplicator.StoreEntityModifier(ent, ENT_MODIFIER_PLANK, { 
			length = length,
			thickness = thickness
		})
		
		return ent, physObj
	end

	function RestorePlank(owner, ent, data)
		local startPos = ent:GetPos()
		local length = data.length
		physObj = ScalePhysicsMesh(ent, Vector(length/2, data.thickness, 1))
		if not (IsValid(physObj)) then return nil, nil end
		physObj:SetMass(60)

		ent:GetPhysicsObject():Wake()
		UpdateClientPlank(ent, length, data.thickness)
	end

	function UpdateClientPlank(ent, length, thickness)
		net.Start(UPDATE_VISUAL_MSG)
		net.WriteEntity(ent)
		net.WriteFloat(length)
		net.WriteFloat(thickness)
		net.Broadcast()
	end
end

duplicator.RegisterEntityModifier(ENT_MODIFIER_PLANK, RestorePlank)

function TOOL:LeftClick(trace)
	if (IsValid(trace.Entity) and trace.Entity:IsPlayer()) then return false end

	local owner = self:GetOwner()
	local model = self:GetClientInfo(CONVAR_PLANK_MODEL, "models/props/plank_swep/plank.mdl")

	if (self:GetStage() == 0) then
		local physObj = trace.Entity:GetPhysicsObjectNum(trace.PhysicsBone)

		self:MakeGhostEntity(model, trace.HitPos, owner:EyeAngles())
		self:SetObject(2, trace.Entity, trace.HitPos, physObj, trace.PhysicsBone, trace.HitNormal)
		self:SetStage(1)
	else
		self:ReleaseGhostEntity()
		self:SetStage(0)

		if (CLIENT) then
			return true
		end

		local thickness = math.max(1, self:GetClientNumber(CONVAR_THICKNESS))
		local ent, physObj = SpawnPlank(model, self:GetPos(2), trace.HitPos, thickness, trace.HitNormal)
		local startEnt = self:GetEnt(2)
		local startBone = self:GetBone(2)
		local endEnt = trace.Entity
		local endBone = trace.PhysicsBone

		undo.Create("Plank")
		undo.AddEntity(ent)
		cleanup.Add(owner, "props", ent)

		if (self:GetClientNumber(CONVAR_WELD) == 1) then
			local startWeld = constraint.Weld(ent, startEnt, 0, startBone, 0, false, false)
			if (not IsValid(startWeld)) then return false end
			undo.AddEntity(startWeld)
			cleanup.Add(owner, "props", startWeld)

			if (endEnt ~= startEnt) then
				local endWeld = constraint.Weld(ent, endEnt, 0, endBone, 0, false, false)
				if (not IsValid(endWeld)) then return false end
				undo.AddEntity(endWeld)
				cleanup.Add(owner, "props", endWeld)
			end
		end

		if (self:GetClientNumber(CONVAR_FREEZE) == 1) then
			physObj:EnableMotion(false)
			owner:AddFrozenPhysicsObject(ent, physObj)
		end

		if (self:GetClientNumber(CONVAR_NOCOLLIDE) == 1) then
			local startNc = constraint.NoCollide(ent, startEnt, 0, startBone)
			if (not IsValid(startNc)) then return false end
			undo.AddEntity(startNc)
			cleanup.Add(owner, "props", startNc)

			if (endEnt ~= startEnt) then
				local endNc = constraint.NoCollide(ent, endEnt, 0, endBone)
				if (not IsValid(endNc)) then return false end
				undo.AddEntity(endNc)
				cleanup.Add(owner, "props", endNc)
			end
		end

		undo.SetPlayer(owner)
		undo.Finish()

		self:ClearObjects()
	end

	return true
end

function TOOL:Think()
	if (self:GetStage() ~= 1 or not IsValid(self.GhostEntity)) then return end
	self:UpdateGhostPlank(self.GhostEntity, self:GetOwner():GetEyeTrace(), self:GetOwner())
end

function TOOL:UpdateGhostPlank(ent, trace, owner)
	-- Ghost is updated on SERVER in singleplayer and CLIENT in multiplayer (?)
	if ((SERVER and not game.SinglePlayer()) or not IsValid(ent)) then return end

	local startPos = self:GetPos(2)
	local endPos = trace.HitPos

	ent:SetAngles((startPos - endPos):AngleEx(trace.HitNormal))

	if (game.SinglePlayer()) then
		UpdateClientPlank(ent, startPos:Distance(endPos), math.max(1, self:GetClientNumber(CONVAR_THICKNESS)))
	else
		UpdatePlankVisuals(ent, startPos:Distance(endPos), math.max(1, self:GetClientNumber(CONVAR_THICKNESS)))
	end
end

function TOOL.BuildCPanel( CPanel )
	CPanel:AddControl("Header", { Description = "#tool.plank.desc" })
	CPanel:AddControl("ComboBox", { MenuButton = 1, Folder = "plank", Options = { [ "#preset.default" ] = ConVarsDefault }, CVars = table.GetKeys( ConVarsDefault ) })

	CPanel:AddControl("Slider", {
		Label = "#tool.plank." .. CONVAR_THICKNESS,
		Command = "plank_" .. CONVAR_THICKNESS,
		Type = "Float",
		Min = 1,
		Max = 32
	})

	CPanel:AddControl("Checkbox", {
		Label = "#tool.plank." .. CONVAR_WELD,
		Command = "plank_" .. CONVAR_WELD,
		Help = true
	})

	CPanel:AddControl("Checkbox", {
		Label = "#tool.plank." .. CONVAR_NOCOLLIDE,
		Command = "plank_" .. CONVAR_NOCOLLIDE,
		Help = true
	})

	CPanel:AddControl("Checkbox", {
		Label = "#tool.plank." .. CONVAR_FREEZE,
		Command = "plank_" .. CONVAR_FREEZE,
		Help = true
	})
end
