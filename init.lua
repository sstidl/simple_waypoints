-------------- INIT VARIABLES ------------------
local modstorage = minetest.get_mod_storage()
local world_path = minetest.get_worldpath()
local world_name = world_path:match( "([^/]+)$" )
local waypoints = minetest.deserialize(modstorage:get_string(world_name)) or {}

-- Read persisted toggles from modstorage first, then fall back to settings
local function read_bool_from_storage(key, settings_key, default)
	local v = modstorage:get_string(key)
	if v ~= "" then
		return v == "true"
	end
	-- try settings (support both names used historically)
	if settings_key then
		local s = minetest.settings:get_bool(settings_key, nil)
		if s ~= nil then return s end
	end
	return default
end

local show_waypoint_hud = read_bool_from_storage("show_waypoint_hud", "simple_waypoints.show_hud", true)
local beacons_enabled = read_bool_from_storage("beacons_enabled", "simple_waypoints.beacons_enable", minetest.settings:get_bool("beacons.enable", false))

-- Track HUD IDs per player: player_huds[player_name][waypoint_index] = hud_id
local player_huds = {}

--------------- HELPER FUNCTIONS ---------------
local function save() -- dumps table to modstorage
	-- Clean up any hudId fields that shouldn't be persisted
	local clean_waypoints = {}
	for i, wp in ipairs(waypoints) do
		clean_waypoints[i] = {name = wp.name, pos = wp.pos}
	end
	modstorage:set_string(world_name, minetest.serialize(clean_waypoints))
end

local function set_persisted_toggle(key, value)
	modstorage:set_string(key, tostring(value and true or false))
end

local function getIndexByName(tbl, n)
	for k,v in pairs(tbl) do
		if v.name == n then
			return k
		end
	end
	return nil --Index not found
end

local function getPosByName(tbl, n)
	for k,v in pairs(tbl) do
		if v.name == n then
			return v.pos
		end
	end
	return nil -- Position not found
end

local function waypointExists(tbl, n)
	for k,v in pairs(tbl) do
	  if v.name == n then
		return "Waypoint exists." 
	  end
	end
	return nil --Waypoint doesn't exist
end

-- HUD helper: add HUD marker for the last entry in tbl (called after adding)
local function addWaypointHud(tbl, player)
	if not show_waypoint_hud then return end
	if not player or type(tbl) ~= "table" then return end

	local idx = #tbl
	if idx < 1 then return end
	local entry = tbl[idx]
	if not entry or not entry.pos then return end

	local wayPos = minetest.string_to_pos(entry.pos)
	if not wayPos then return end

	local pname = player:get_player_name()
	if not player_huds[pname] then
		player_huds[pname] = {}
	end

	-- add hud and store hudId in player-specific table
	local hud_id = player:hud_add({
		hud_elem_type = "waypoint",
		name = entry.name,
		text = "m",
		number = 0xFFFFFF,
		world_pos = wayPos,
	})
	player_huds[pname][idx] = hud_id
end

-- HUD helper: refresh HUD for a given index in tbl
local function refreshWaypointHud(tbl, player, idx)
	if not show_waypoint_hud then return end
	if not player or type(tbl) ~= "table" or type(idx) ~= "number" then return end
	local entry = tbl[idx]
	if not entry or not entry.pos then return end

	local pname = player:get_player_name()
	if not player_huds[pname] then
		player_huds[pname] = {}
	end

	-- remove existing hud if present
	if player_huds[pname][idx] then
		pcall(function() player:hud_remove(player_huds[pname][idx]) end)
		player_huds[pname][idx] = nil
	end

	local wayPos = minetest.string_to_pos(entry.pos)
	if not wayPos then return end

	local hud_id = player:hud_add({
		hud_elem_type = "waypoint",
		name = entry.name,
		text = "m",
		number = 0xFFFFFF,
		world_pos = wayPos,
	})
	player_huds[pname][idx] = hud_id
end

-- HUD helper: load all waypoints into player's HUD
local function loadWaypointsHud(tbl, player)
	if not show_waypoint_hud then return end
	if not player or type(tbl) ~= "table" then return end

	local pname = player:get_player_name()
	if not player_huds[pname] then
		player_huds[pname] = {}
	end

	for i, v in ipairs(tbl) do
		if v and v.pos then
			-- don't add again if already present for this player
			if not player_huds[pname][i] then
				local pos = minetest.string_to_pos(v.pos)
				if pos then
					local hid = player:hud_add({
						hud_elem_type = "waypoint",
						name = v.name,
						text = "m",
						number = 0xFFFFFF,
						world_pos = pos,
					})
					player_huds[pname][i] = hid
				end
			end
		end
	end
end

-- Remove HUD markers for a given player (used when disabling HUDs)
local function removeAllWaypointsHudForPlayer(player)
	if not player then return end
	local pname = player:get_player_name()
	if player_huds[pname] then
		for idx, hud_id in pairs(player_huds[pname]) do
			pcall(function() player:hud_remove(hud_id) end)
		end
		player_huds[pname] = {}
	end
end

--------------- ON JOIN / LEAVE ------------------
minetest.register_on_joinplayer(function(player)
	minetest.after(.5, function()
		loadWaypointsHud(waypoints, player)
	end)
end)

minetest.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	-- Clean up player HUD tracking when they leave
	player_huds[pname] = nil
end)

-------------- NODE DEFINITIONS -----------------
local palette = {"blue", "green", "orange", "pink", "purple", "red", "white", "yellow"}

-- BEACON DEFINITION
for _, color in ipairs(palette) do
	minetest.register_node("simple_waypoints:"..color.."_beacon", {
		visual_scale = 1.0,
		drawtype = "plantlike",
		tiles = {"beacon_"..color..".png"},
		paramtype = "light",
		walkable = false,
		diggable = false,
		light_source = 13,
		groups = {not_in_creative_inventory=1}
	})
end

-- BEACON FUNCTIONS
local function placeBeacon(pos, color)
	local random = math.random(1,#palette)
	for i=0,50 do
		local target_node = minetest.get_node({x=pos.x, y=pos.y+i, z=pos.z})
		if target_node.name == "air" then
			if color == nil then
				minetest.add_node({x=pos.x, y=pos.y+i, z=pos.z},
				{name="simple_waypoints:"..palette[random].."_beacon"})
			else
				minetest.add_node({x=pos.x, y=pos.y+i, z=pos.z},
				{name="simple_waypoints:"..color.."_beacon"})
			end
			-- stop after placing one beacon
			break
		end
	end
end

local function removeBeacon(pos)
	for _,v in ipairs(palette) do
		for i=0,50 do
			local target_node = minetest.get_node({x=pos.x, y=pos.y+i, z=pos.z})
			if target_node.name == "simple_waypoints:"..v.."_beacon" then
				minetest.add_node({x=pos.x, y=pos.y+i, z=pos.z}, {name="air"})
				-- continue scanning to ensure all variants removed in column
			end
		end
	end
end

--------------- CHAT COMMANDS -------------------

-- CREATE WAYPOINT
minetest.register_chatcommand("wc", {
	params = "<waypoint_name>",
	description = "create a waypoint at current position using a unique name",
	privs = {teleport = true},
	func = function (name, params)
		local player = minetest.get_player_by_name(name)
		local p_pos = player:get_pos()
		local round_pos = vector.round(p_pos)

		-- Check if the waypoint name is at least 1 character long
		if string.len(params) < 1 then
			return nil, "Waypoint name must be at least 1 character long"
		end

		-- Check if a waypoint with the given name already exists
		if not waypointExists(waypoints, params) == true then
			-- Add the new waypoint to the table
			waypoints[#waypoints+1] = { name = params,
			pos = minetest.pos_to_string(round_pos) }

			-- Add the waypoint to all players' HUDs (if enabled)
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					addWaypointHud(waypoints, p)
				end
			end

			-- Check if beacons are enabled before placing a beacon
			if beacons_enabled then
				placeBeacon(round_pos)
			end

			-- Save the waypoints to modstorage
			save()

			-- Return success message
			return true, "Waypoint "..params.." created!"
		else
			return nil, "Waypoint with that name already exists"
		end
	end
})


-- DELETE WAYPOINT
minetest.register_chatcommand("wd", {
	params = "<waypoint_name>",
	description = "Delete a waypoint using its name.",
	privs = {teleport = true},
	func = function(name,params)
		local player = minetest.get_player_by_name(name)
		local targetIndex = getIndexByName(waypoints, params)
		local beaconPos = getPosByName(waypoints, params)
		if (type(targetIndex) == "number") then
			if beaconPos then
				local bp = minetest.string_to_pos(beaconPos)
				if bp then removeBeacon(bp) end
			end

			-- Remove HUD for all players
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					local pname = p:get_player_name()
					if player_huds[pname] and player_huds[pname][targetIndex] then
						pcall(function() p:hud_remove(player_huds[pname][targetIndex]) end)
						player_huds[pname][targetIndex] = nil
					end
				end
			end

			-- Remove the waypoint from the table
			table.remove(waypoints, targetIndex)

			-- Reindex HUD entries for all players (indices shift down after removal)
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					local pname = p:get_player_name()
					if player_huds[pname] then
						local new_huds = {}
						for idx, hud_id in pairs(player_huds[pname]) do
							if idx > targetIndex then
								new_huds[idx - 1] = hud_id
							elseif idx < targetIndex then
								new_huds[idx] = hud_id
							end
						end
						player_huds[pname] = new_huds
					end
				end
			end

			save()
			return true, "Waypoint deleted."
		else
			return false, "Waypoint "..params.." is invalid or inexistent."
		end
	end
})


-- LIST WAYPOINTS
minetest.register_chatcommand("wl", {
	params = "",
	description = "Lists your waypoints.",
	privs = {teleport = true},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		local p_name = player:get_player_name()

		-- Iterate through the waypoints table and send each waypoint's details to the player
		for k,v in pairs(waypoints) do
			minetest.chat_send_player(p_name, tostring(k.." "..v.name.." "..v.pos))
		end
	end
})

-- TELEPORT TO WAYPOINT
minetest.register_chatcommand("wt", {
	params = "<waypoint_name>",
	description = "Teleports you to a specified waypoint.",
	privs = {teleport = true},
	func = function(name, params)
		local player = minetest.get_player_by_name(name)
		local p_name = player:get_player_name()
		local targetPos = getPosByName(waypoints, params)

		-- Check if the waypoint exists and has a valid position
		if (type(targetPos) == "string") then
			-- Teleport the player to the waypoint position
			player:set_pos(minetest.string_to_pos(targetPos))
			return true, tostring("Teleported "..p_name.." to "..params..".")
		else
			return false, tostring("Waypoint "..params.." is invalid or inexistent.")
		end
	end
})

-- SHOW WAYPOINTS FORMSPEC
minetest.register_chatcommand("wf", {
	description = "Brings up the GUI.",
	privs = {teleport = true},
	func = function(name)
		-- Show the waypoints formspec to the player
		minetest.show_formspec(name, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_main())
	end,
})

-- NEW: Toggle HUD display at runtime
minetest.register_chatcommand("sw_hud", {
	params = "<on|off|toggle|status>",
	description = "Toggle waypoint HUD display (runtime). Use 'status' to view current value.",
	privs = {teleport = true},
	func = function(name, params)
		local cmd = params:lower():gsub("^%s*(.-)%s*$","%1")
		if cmd == "" or cmd == "status" then
			return true, "Waypoint HUDs currently: " .. (show_waypoint_hud and "ON" or "OFF")
		end
		if cmd == "on" or cmd == "true" then
			if show_waypoint_hud then
				return true, "Waypoint HUDs are already ON"
			end
			show_waypoint_hud = true
			set_persisted_toggle("show_waypoint_hud", true)
			-- add HUDs for all connected players
			for _, player in ipairs(minetest.get_connected_players()) do
				loadWaypointsHud(waypoints, player)
			end
			return true, "Waypoint HUDs enabled"
		elseif cmd == "off" or cmd == "false" then
			if not show_waypoint_hud then
				return true, "Waypoint HUDs are already OFF"
			end
			show_waypoint_hud = false
			set_persisted_toggle("show_waypoint_hud", false)
			-- remove HUDs for all connected players
			for _, player in ipairs(minetest.get_connected_players()) do
				removeAllWaypointsHudForPlayer(player)
			end
			return true, "Waypoint HUDs disabled"
		elseif cmd == "toggle" then
			-- toggle and reuse the on/off behavior
			if show_waypoint_hud then
				return minetest.registered_chatcommands["sw_hud"].func(name, "off")
			else
				return minetest.registered_chatcommands["sw_hud"].func(name, "on")
			end
		else
			return false, "Invalid parameter. Use on/off/toggle/status"
		end
	end
})

-- NEW: Toggle beacons at runtime
minetest.register_chatcommand("sw_beacons", {
	params = "<on|off|toggle|status>",
	description = "Toggle waypoint beacons (world nodes). Use 'status' to view current value.",
	privs = {teleport = true},
	func = function(name, params)
		local cmd = params:lower():gsub("^%s*(.-)%s*$","%1")
		if cmd == "" or cmd == "status" then
			return true, "Waypoints beacons currently: " .. (beacons_enabled and "ON" or "OFF")
		end
		if cmd == "on" or cmd == "true" then
			if beacons_enabled then
				return true, "Waypoints beacons are already ON"
			end
			beacons_enabled = true
			set_persisted_toggle("beacons_enabled", true)
			-- place beacons at all waypoints
			for _, v in ipairs(waypoints) do
				if v and v.pos then
					local p = minetest.string_to_pos(v.pos)
					if p then placeBeacon(p) end
				end
			end
			return true, "Waypoints beacons enabled (beacons placed)"
		elseif cmd == "off" or cmd == "false" then
			if not beacons_enabled then
				return true, "Waypoints beacons are already OFF"
			end
			beacons_enabled = false
			set_persisted_toggle("beacons_enabled", false)
			-- remove beacons at all waypoints
			for _, v in ipairs(waypoints) do
				if v and v.pos then
					local p = minetest.string_to_pos(v.pos)
					if p then removeBeacon(p) end
				end
			end
			return true, "Waypoints beacons disabled (beacons removed)"
		elseif cmd == "toggle" then
			if beacons_enabled then
				return minetest.registered_chatcommands["sw_beacons"].func(name, "off")
			else
				return minetest.registered_chatcommands["sw_beacons"].func(name, "on")
			end
		else
			return false, "Invalid parameter. Use on/off/toggle/status"
		end
	end
})

--------------- FORMSPEC -----------------------
waypoints_formspec = {}

-- MAIN PAGE
function waypoints_formspec.get_main()
	local text = "Waypoints list."
	formspec = {
		"size[11,14]",
		"real_coordinates[true]",
		"label[0.375,0.5;", minetest.formspec_escape(text), "]",
		"button_exit[8.7,0.75;2,1;teleport;Teleport]",
		"button[8.7,1.75;2,1;add;Add]",
		"button[8.7,2.75;2,1;delete;Delete]",
		"button[8.7,3.75;2,1;rename;Rename]",
	}

local f = ""
	f = f..
	"textlist[0.375,0.75;8,13;waylist;"
	for i = 1, #waypoints do
		f = f..i.."  "..minetest.formspec_escape(waypoints[i].name.." "..waypoints[i].pos)..","
	end
	formspec[#formspec+1] = f.."]"
	return table.concat(formspec, " ")
end

function waypoints_formspec.get_add()
	local text = "Add waypoint at current position. Random color if unselected."
	local text2 = "Color:"
	formspec = {
		"size[10,5]",
		"real_coordinates[true]",
		"label[0.375,0.5;", text, "]",
		"label[5.375,1.80;", text2, "]",
		"field[0.375,2;4,0.6;name;Name:;]",
		"dropdown[5.375,2;4,0.6;color;blue,green,orange,pink,purple,red,white,yellow;0]",
		"button[4,3.5;2,1;create;Create]"
	}
	return table.concat(formspec, " ")
end
-- RENAME PAGE
function waypoints_formspec.get_rename()
	local text = "Enter a new name:"
	formspec = {
		"size[4,2.5]",
		"real_coordinates[true]",
		"label[0.58,0.5;", text, "]",
		"field[0.25,0.9;3.5,0.6;new_name;;]",
		"button[1.5,1.75;1,0.5;ok;OK]"
	}
	return table.concat(formspec, " ")
end

function waypoints_formspec.get_exists()
	local text = "A waypoint with that name already exists!"
	local text2 = "Please choose a unique name."
	formspec = {
		"size[7,3]",
		"real_coordinates[true]",
		"label[0.375,0.5;", text, "]",
		"label[1.15,1;"; text2, "]",
		"button[2.5,1.5;2,1;back;Back]"
	}
	return table.concat(formspec, " ")
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname ~= "simple_waypoints:waypoints_formspec" then return
	elseif fields.waylist then
		local event = minetest.explode_textlist_event(fields.waylist)
		if(event.type == "CHG") then
			selected_idx = event.index
		end
	elseif fields.teleport then
		if waypoints[selected_idx] ~= nil then
			player:set_pos(minetest.string_to_pos(waypoints[selected_idx].pos))
			minetest.chat_send_all(pname .. " Teleported to " .. waypoints[selected_idx].name)
			selected_idx = nil   -- "Teleport" button remembers the last location when you don't select a valid item. This is a reset.
		end
	elseif fields.add then
		minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_add())
	elseif fields.create or fields.key_enter_field then
		if fields.name ~= nil and string.len(fields.name) ~= 0 then
			local player = minetest.get_player_by_name(pname)
			local p_pos = player:get_pos()
			local round_pos = vector.round(p_pos)
			if not waypointExists(waypoints, fields.name) then
				waypoints[#waypoints+1] = { name = fields.name, pos = minetest.pos_to_string(round_pos) }
				
				-- Add HUD for all connected players
				if show_waypoint_hud then
					for _, p in ipairs(minetest.get_connected_players()) do
						addWaypointHud(waypoints, p)
					end
				end
				
				if beacons_enabled then
					placeBeacon(round_pos, fields.color)
				end
				save()
				minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_main())
			else minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_exists())
			end
		end
	elseif fields.back then
		minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_add())
	elseif fields.delete then
		if waypoints[selected_idx] ~= nil then
			local beaconPos = getPosByName(waypoints, waypoints[selected_idx].name)
			if beaconPos then
				local bp = minetest.string_to_pos(beaconPos)
				if bp then removeBeacon(bp) end
			end
			
			-- Remove HUD for all players
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					local pn = p:get_player_name()
					if player_huds[pn] and player_huds[pn][selected_idx] then
						pcall(function() p:hud_remove(player_huds[pn][selected_idx]) end)
						player_huds[pn][selected_idx] = nil
					end
				end
			end
			
			table.remove(waypoints, selected_idx)
			
			-- Reindex HUD entries for all players
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					local pn = p:get_player_name()
					if player_huds[pn] then
						local new_huds = {}
						for idx, hud_id in pairs(player_huds[pn]) do
							if idx > selected_idx then
								new_huds[idx - 1] = hud_id
							elseif idx < selected_idx then
								new_huds[idx] = hud_id
							end
						end
						player_huds[pn] = new_huds
					end
				end
			end
			
			save()
			minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_main())
		end
	elseif fields.rename then
		if waypoints[selected_idx] ~= nil then
			minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_rename())
		end
	elseif fields.ok or fields.key_enter_field then
		if fields.new_name ~= nil and string.len(fields.new_name) ~= 0 and selected_idx then
			waypoints[selected_idx].name = fields.new_name
			-- update HUD for renamed waypoint for all players
			if show_waypoint_hud then
				for _, p in ipairs(minetest.get_connected_players()) do
					refreshWaypointHud(waypoints, p, selected_idx)
				end
			end
			save()
			minetest.show_formspec(pname, "simple_waypoints:waypoints_formspec", waypoints_formspec.get_main())
		end
	end
end)
