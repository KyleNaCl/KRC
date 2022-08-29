
-- Original: Smart Render > https://steamcommunity.com/sharedfiles/filedetails/?id=2354971452
-- This is a modified, more configurable version with better dynamic fov checks
-- By Kyle

print("[KRC] \tLoaded cl_render_distance.lua")

local ClassList = { -- Classes to Cull
	"prop_",
	'bw_',
	'item_', 
	'gmod_', 
	'ent', 
	'weapon_',
	'sent_', 
	'base_', 
	'func_'
}
RenderEntities = {}

local cvar_enable = CreateClientConVar("cl_render_enable", "1", true, false, "enable custom render culling", 0, 1)
local cvar_distance = CreateClientConVar("cl_render_distance", "8000", true, false, "max distance to render objects", 4000, 35000)
local cvar_distance_always = CreateClientConVar("cl_render_distance_always", "1500", true, false, "max distance to always render objects", 50, 4000)
local cvar_refresh = CreateClientConVar("cl_render_refresh", "10", true, false, "Refresh rate of culling", 5, 60)

local crash_count = 0
local dotfov = 65
local enabled = cvar_enable:GetBool()
local distance, distance_always = cvar_distance:GetInt() ^ 2, cvar_distance_always:GetInt() ^ 2
local last_enabled = enabled
local last_refresh = cvar_refresh:GetInt()
local context_open = false

local function addRender(ent)
	if not ent then return end
	local class = ent:GetClass()

	local push = false
	for _, a in ipairs(ClassList) do
		if string.StartWith(class, a) and not push then push = true end
	end
	if not push then return end

	timer.Simple(0.1, function() -- Delay to wait for addons set metadata
		if IsValid(ent) then
			table.insert(RenderEntities, ent)
			ent.custom_render = ent:GetNoDraw()
		end
	end)
end

local function setState(e, state)
	if e:GetNoDraw() != e.custom_render then -- Check if another addon changed state
		--e.custom_render = nil
		--print("[KRC] \tInfo: " .. tostring(e) .. " detected 3rd party change")
		e.custom_render = e:GetNoDraw()
	else
		e:SetNoDraw(state)
		e.custom_render = state
	end
end

local function checkRender(e)
	local e_pos = e:GetPos()
	local dist = pos:DistToSqr(e_pos) -- Bypass expensive sqrt

	if dist > distance then -- Entity is further than max distance
		setState(e,true)
		return
	end

	if dist < distance_always then -- Entity is within always draw range
		setState(e,false)
		return
	end

	if e:IsWeapon() or e:IsVehicle() then -- Can't cull Weapons & Vehicles
		setState(e,false)
		return
	end
	local normalized = e_pos - pos
	local dot = aim:Dot(normalized) / normalized:Length()

	setState(e,dot < dotfov)
end

local function updateRender()
	local LP = LocalPlayer()
	if not IsValid(LP) then return end
	if LP:InVehicle() then return end -- Vehicles can have dynamic camera positions not reletive to player's location

	local rate = cvar_refresh:GetInt()
	if last_refresh != rate then
		print("[KRC] \tInfo: Refresh Rate Changed, Updating...")
		timer.Adjust("Custom_Render_Update", 1 / rate)
	end
	last_refresh = rate

	enabled = cvar_enable:GetBool()

	if last_enabled != enabled then -- Reset all Entities if convar changed
		for _, e in ipairs(RenderEntities) do
			if IsValid(e) then
				setState(e,false)
			else
				table.remove(RenderEntities, _)
			end
		end
	end
	last_enabled = enabled
	if not enabled or context_open then return end

	dotfov = math.abs(1 - (math.pi / (360 / (LP:GetFOV()))))

	distance = cvar_distance:GetInt() ^ 2 -- Calculate squared to not use sprt in distance check
	distance_always = cvar_distance_always:GetInt() ^ 2

	for _, e in ipairs(RenderEntities) do
		if IsValid(e) then
			if e.custom_render == nil then -- If marked for Remove
				table.remove(RenderEntities, _)
			else
				checkRender(e)
			end
		else
			table.remove(RenderEntities, _)
		end
	end
end

local function checkTimer() -- Check if Render timer crashed
	if not timer.Exists("Custom_Render_Update") then
		crash_count = crash_count + 1
		if crash_count > 5 then
			cvar_enable:SetBool(false)
			print("[KRC] \tError: Think Crashed 5 times, use cl_render_enable 1 to re-enable")
			print("[KRC] \tError: Please Report Errors to github: https://github.com/KyleNaCl/KRC")
		else
			for _, e in ipairs(RenderEntities) do
				if IsValid(e) then
					setState(e,false)
				else
					table.remove(RenderEntities, _)
				end
			end
			print("[KRC] \tError: Think Crashed, Restarting...")
		end
		timer.Create("Custom_Render_Update", 0.1, 0, updateRender)
	end
end

if timer.Exists("Custom_Render_Update") and IsValid(LocalPlayer()) then -- Check if file was refreshed and reset hooks
	print("[KRC] \tInfo: Refresh Detected")

	timer.Remove("Custom_Render_Update")
	timer.Remove("Custom_Render_Valid")
	hook.Remove("OnEntityCreated","Custom_Render_Create")
	hook.Remove("OnContextMenuOpen","Custom_Render_Context_Open")
	hook.Remove("OnContextMenuClose","Custom_Render_Context_Close")

	local ent_list = ents.GetAll()
	for _,ent in ipairs(ent_list) do
		addRender(ent)
	end
end

timer.Simple(0.1, function() -- Delay for old timers to be removed
	timer.Create("Custom_Render_Update",0.1,0, updateRender)
	timer.Create("Custom_Render_Valid",1,0, checkTimer)
	hook.Add("OnEntityCreated","Custom_Render_Create", addRender)
	hook.Add("OnContextMenuOpen","Custom_Render_Context_Open", function() context_open = true end) -- Context Menu breaks aim vector
	hook.Add("OnContextMenuClose","Custom_Render_Context_Close", function() context_open = false end)
end)

hook.Add("SetupWorldFog","Custom_Render_Fog", function() -- Fog For World
	if enabled then
		render.FogMode(1)
		render.FogColor(130,130,150)
		render.FogStart(cvar_distance:GetInt() - (cvar_distance:GetInt() / 2))
		render.FogEnd(cvar_distance:GetInt())
		render.FogMaxDensity(0.98)
		return true
	end
end)

hook.Add("SetupSkyboxFog","Custom_Render_Fog", function(scale) -- Fog For 3D Skybox
	if enabled then
		render.FogMode(1)
		render.FogColor(130,130,150)
		render.FogStart((cvar_distance:GetInt() - (cvar_distance:GetInt() / 2)) * scale)
		render.FogEnd(cvar_distance:GetInt() * scale)
		render.FogMaxDensity(0.98)
		return true
	end
end)

hook.Add("CalcView","Custom_Render_View", function(ply, origin, angles, fov)
	aim = angles:Forward()
	pos = origin
end)
