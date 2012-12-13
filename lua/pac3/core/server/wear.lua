local function decimal_hack_unpack(tbl)
	for key, val in pairs(tbl) do
		local t = type(val)
		if t == "table" then 
			if val.__type then
				t = val.__type 
				
				if t == "Vector" then
					tbl[key] = Vector()
					tbl[key].x = tostring(val.x)
					tbl[key].y = tonumber(val.y)
					tbl[key].z = tonumber(val.z)
				elseif t == "number" then
					tbl[key] = tonumber(val.val)
				end
			else
				decimal_hack_unpack(val)
			end
		end
	end
	
	return tbl
end

local function decimal_hack_pack(tbl)
	for key, val in pairs(tbl) do
		local t = type(val)
		if t == "Vector" then
			tbl[key] = {}
			tbl[key].x = tostring(val.x)
			tbl[key].y = tostring(val.y)
			tbl[key].z = tostring(val.z)
			tbl[key].__type = "Vector"
		elseif t == "number" then
			tbl[key] = {__type = "number", val = tostring(val)}
		elseif t == "table" then
			decimal_hack_pack(val)
		end
	end
	
	return tbl
end

function pac.SubmitPart(data, filter)

	-- last arg "true" is pac3 only in case you need to do your checking differnetly from pac2
	local allowed, reason = hook.Call("PrePACConfigApply", GAMEMODE, data.owner, data, true)

	if type(data.part) == "table" then	
		local ent = Entity(tonumber(data.part.self.OwnerName))
		if ent:IsValid()then
			if ent.CPPICanTool and (ent:CPPIGetOwner() ~= data.owner and not ent:CPPICanTool(data.owner)) then
				allowed = false
				reason = "you are not allowed to modify this entity: " .. tostring(ent) .. " owned by: " .. tostring(ent:CPPIGetOwner())
			else
				duplicator.StoreEntityModifier(ent, "pac_config", data)
			end
		end
	end
	
	if data.uid ~= false then
		if allowed == false then return allowed, reason end
		if pac.IsBanned(data.owner) then return false, "you are banned from using pac" end
	end

	local uid = data.uid
	pac.Parts[uid] = pac.Parts[uid] or {}
	
	if type(data.part) == "table" then
		pac.Parts[uid][data.part.self.Name] = data
		
		pac.HandleServerModifiers(data)		
	else
		if data.part == "__ALL__" then
			pac.Parts[uid] = {}
		else
			pac.Parts[uid][data.part] = nil
		end
		
		pac.HandleServerModifiers(data.owner, true)
	end
	
	if filter == false then
		filter = data.owner
	elseif filter == true then
		local tbl = {}
		for k,v in pairs(player.GetAll()) do
			if v ~= data.owner then
				table.insert(tbl, v)
			end
		end
		filter = tbl
	end
	
	if not data.server_only then
		if pac.netstream then
			pac.netstream.Start(filter or player.GetAll(), data)
		else
			net.Start("pac_submit")
				net.WriteTable(decimal_hack_pack(table.Copy(data)))
			net.Send(filter or player.GetAll())	
		end
	end
	
	return true
end

function pac.SubmitPartNotify(data)
	pac.dprint("submitted outfit %q from %s with %i number of children to set on %s", data.part.self.Name or "", data.owner:GetName(), table.Count(data.part.children), data.part.self.OwnerName or "")
	
	local allowed, reason = pac.SubmitPart(data)
	
	if data.owner:IsPlayer() then
		umsg.Start("pac_submit_acknowledged", data.owner)
			umsg.Bool(allowed)
			umsg.String(reason or "")
			umsg.String(data.part.self.Name)
		umsg.End()
	end
end

function pac.RemovePart(data)
	pac.dprint("%s is removed %q", data.owner:GetName(), data.part)
	
	pac.SubmitPart(data, data.filter)
end

local function handle_data(owner, data)
	data.owner = owner
	data.uid = owner:UniqueID()
	
	if type(data.part) == "table" then
		pac.SubmitPartNotify(data)
	elseif type(data.part) == "string" then
		pac.RemovePart(data)
	end
end

util.AddNetworkString("pac_submit")
util.AddNetworkString("pac_effect_precached")
util.AddNetworkString("pac_precache_effect")

if pac.netstream then
	pac.netstream.Hook("pac_submit", function(ply, data)
		handle_data(ply, data)
	end)
else
	net.Receive("pac_submit", function(_, ply)
		local data = net.ReadTable()
		decimal_hack_unpack(data)
		handle_data(ply, data)
	end)
end

function pac.RequestOutfits(ply)
	if ply:IsValid() and not ply.pac_requested_outfits then
		for id, outfits in pairs(pac.Parts) do
			local owner = (player.GetByUniqueID(id) or NULL)
			if id == false or owner:IsValid() and owner:IsPlayer() and owner.GetPos and id ~= ply:UniqueID() then
				for key, outfit in pairs(outfits) do
					pac.SubmitPart(outfit, ply)
				end
			end
		end
		ply.pac_requested_outfits = true
	end
end

concommand.Add("pac_request_outfits", pac.RequestOutfits)