--------------------------------------------------------------------------------
-- Tool Information
--------------------------------------------------------------------------------

TOOL.Category = "Construction"
TOOL.Name = "#tool.plank.name"
TOOL.Information = {
	{ name = "left", stage = 0 },
	{ name = "left_1", stage = 1 }
}

if (CLIENT) then
	language.Add("tool.plank.name", "Plank")
	language.Add("tool.plank.desc", "Create a wooden plank between two points")
	language.Add("tool.plank.left", "Select the first point")
	language.Add("tool.plank.left_1", "Select the second point")
end

--------------------------------------------------------------------------------
-- ConVars
--------------------------------------------------------------------------------

local CONVAR_WELD = "weld"				-- Weld the plank at its endpoints?
local CONVAR_FREEZE = "freeze"			-- Freeze the created plank?
local CONVAR_NOCOLLIDE = "nocollide"	-- Disable collisions between plank and endpoints?
local CONVAR_THICKNESS = "thickness"	-- How thick should the plank be?

if (CLIENT) then
	TOOL.ClientConVar[CONVAR_WELD] = "1"
	TOOL.ClientConVar[CONVAR_FREEZE] = "0"
	TOOL.ClientConVar[CONVAR_NOCOLLIDE] = "0"
	TOOL.ClientConVar[CONVAR_THICKNESS] = "4"
end

-- UPDATE_VISUAL_MSG is the message sent when a plank has been created and its
-- client-side visuals need to be updated.
local UPDATE_VISUAL_MSG = "plank_stool_update_visual"

if (SERVER) then
	util.AddNetworkString(UPDATE_VISUAL_MSG)
end

if (CLIENT) then
	net.Receive(
		"plank_stool_update_visual",
		function(len)
			local ent = net.ReadEntity()
			if (not IsValid(ent)) then return end

			local length = net.ReadFloat()
			if (length < 0) then return end

			local thickness = net.ReadFloat()
			if (thickness < 0) then return end

			local m = Matrix()
			m:Scale(Vector(length/2, thickness, 1))
			ent:EnableMatrix("RenderMultiply", m)

			local rbMin, rbMax = ent:GetModelRenderBounds()
			ent:SetRenderBounds(length * rbMin, length * rbMax)
		end
	)
end

-- PLANK_MODEL should be one unit long and one unit wide.
local PLANK_MODEL = "models/props/plank_swep/plank.mdl"

-- MakePlank creates a plank between a starting and ending position.
function MakePlank(owner, startPos, endPos, startEnt, endEnt, startBone, endBone, normal, thickness, doWeld, doFreeze, doNoCollide)
	if (CLIENT) then return end

	local ent = ents.Create("prop_physics")
	if (not IsValid(ent)) then return end

	ent:SetModel(PLANK_MODEL)
	ent:SetPos(startPos)

	local ang = (startPos - endPos):AngleEx(normal)
	ent:SetAngles(ang)
	ent:Spawn()

	local length = (startPos:Distance(endPos))
	ent:PhysicsInit(SOLID_VPHYSICS)

	-- Scale physics mesh and replace it
	local physObj = ent:GetPhysicsObject()
	local physMesh = physObj:GetMesh()

	for key, vertex in ipairs(physMesh) do
		physMesh[key] = vertex.pos * Vector(length/2, thickness, 1)
	end

	ent:PhysicsInitConvex(physMesh)
	ent:EnableCustomCollisions(true)

	physObj = ent:GetPhysicsObject()
	physObj:SetMass(60)

	if (doWeld) then
		local startWeld = constraint.Weld(ent, startEnt, 0, startBone, 0, false, false)
		if (not IsValid(startWeld)) then return end

		local separateEndWeld = endEnt ~= startEnt
		if (separateEndWeld) then
			local endWeld = constraint.Weld(ent, endEnt, 0, endBone, 0, false, false)
			if (not IsValid(endWeld)) then return end
		end
	end

	if (doFreeze) then
		physObj:EnableMotion(false)
	end

	ent:GetPhysicsObject():Wake()

	net.Start("plank_stool_update_visual")
	net.WriteEntity(ent)
	net.WriteFloat(length)
	net.WriteFloat(thickness)
	net.Broadcast()

	cleanup.Add(owner, "props", ent)
	undo.Create("plank")
		undo.AddEntity(ent)

		if (doWeld) then
			undo.AddEntity(startWeld)
			if (separateEndWeld) then undo.AddEntity(endWeld) end
		end

		undo.SetPlayer(owner)
	undo.Finish()
end


function TOOL:LeftClick(trace)
	if (IsValid(trace.Entity) and trace.Entity:IsPlayer()) then return false end
	if (CLIENT) then return true end

	local owner = self:GetOwner()

	if (self:GetStage() == 0) then
		local physObj = trace.Entity:GetPhysicsObjectNum(trace.PhysicsBone)

		self:ReleaseGhostEntity()
		self:MakeGhostEntity(PLANK_MODEL, trace.HitPos, owner:EyeAngles())
		self:SetObject(2, trace.Entity, trace.HitPos, physObj, trace.PhysicsBone, trace.HitNormal)
		self:SetStage(1)
	else
		MakePlank(
			owner,
			self:GetPos(2), trace.HitPos,
			self:GetEnt(2), trace.Entity,
			self:GetBone(2), trace.PhysicsBone,
			trace.HitNormal,
			math.max(1, self:GetClientNumber(CONVAR_THICKNESS)),
			self:GetClientNumber(CONVAR_WELD) == 1,
			self:GetClientNumber(CONVAR_FREEZE) == 1,
			self:GetClientNumber(CONVAR_NOCOLLIDE) == 1
		)

		self:ClearObjects()
		self:ReleaseGhostEntity()
		self:SetStage(0)
	end

	return true
end

function TOOL:Think()
	if (CLIENT) then return end
	if (self:GetStage() ~= 1 or not IsValid(self.GhostEntity)) then return end

	self:UpdateGhostPlank(self.GhostEntity, self:GetOwner():GetEyeTrace())
end

function TOOL:UpdateGhostPlank(ent, trace)
	self.GhostEntity:SetAngles((self:GetPos(2) - trace.HitPos):AngleEx(trace.Normal))

	net.Start(UPDATE_VISUAL_MSG, true)
	net.WriteEntity(ent)
	net.WriteFloat(self:GetPos(2):Distance(trace.HitPos))
	net.WriteFloat(self:GetClientNumber(CONVAR_THICKNESS))
	net.Broadcast()
end
