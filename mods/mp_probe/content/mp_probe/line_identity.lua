--- Compare captured line settings without treating engine bookkeeping as a UI change.
-- The wire record remains untouched: tolerance applies only to the comparison of
-- street-stop positions, never to waypoints, tracks or construction geometry.
local identity = { STREET_POSITION_EPSILON = 0.01 }

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function spend(context)
	context.remaining = context.remaining - 1
	return context.remaining >= 0
end

local function exact(a, b, context, depth)
	if not spend(context) or depth > 32 or type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b and (type(a) ~= "number" or finite(a)) end
	for key, value in pairs(a) do
		if not exact(value, b[key], context, depth + 1) then return false end
	end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function fields(a, b, excluded, context)
	if type(a) ~= "table" or type(b) ~= "table" or not spend(context) then return false end
	for key, value in pairs(a) do
		if not excluded[key] and not exact(value, b[key], context, 0) then return false end
	end
	for key in pairs(b) do if not excluded[key] and a[key] == nil then return false end end
	return true
end

local function array_size(value)
	if type(value) ~= "table" then return nil end
	local n, count = #value, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n then return nil end
		count = count + 1
	end
	if count ~= n then return nil end
	return n
end

local POSITION = { position = true }
local XYZ = { x = true, y = true, z = true }
local function station_same(a, b, context)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if a.kind ~= "street_station" or b.kind ~= "street_station" then return exact(a, b, context, 0) end
	if not fields(a, b, POSITION, context) or not fields(a.position, b.position, XYZ, context) then return false end
	for _, axis in ipairs({ "x", "y", "z" }) do
		local left, right = a.position[axis], b.position[axis]
		if not finite(left) or not finite(right) or math.abs(left - right) > identity.STREET_POSITION_EPSILON then return false end
	end
	return true
end

--- Engine station-group order may change. Every reference must have exactly one
-- counterpart; choosing the nearest of several candidates would hide a side change.
local function station_map(a, b, context)
	local n, m = array_size(a), array_size(b)
	if not n or n ~= m then return nil end
	local mapping, used = {}, {}
	for i = 1, n do
		local found
		for j = 1, n do
			if not spend(context) then return nil end
			if station_same(a[i], b[j], context) then
				if found then return nil end
				found = j
			end
		end
		if not found or used[found] then return nil end
		mapping[i], used[found] = found, true
	end
	return mapping
end

local function mapped_index(a, b, mapping)
	if a == -1 then return b == -1 end -- Deleted/unassigned stop.
	return type(a) == "number" and a % 1 == 0 and a >= 0
		and type(b) == "number" and b % 1 == 0 and b >= 0 and mapping[a + 1] == b + 1
end

local TARGET = { stations = true, station = true }
local function target_same(a, b, context)
	if not fields(a, b, TARGET, context) then return nil end
	local mapping = station_map(a.stations, b.stations, context)
	if not mapping or not mapped_index(a.station, b.station, mapping) then return nil end
	return mapping
end

local STOP = { target = true, alternativeTerminals = true, terminalTag = true }
local ALTERNATIVE = { station = true, terminalTag = true }
local function terminal_tag_same(a, b, a_ref, b_ref, context)
	-- A source-verified one-terminal street stop always selects index zero. Its
	-- lane-derived tag is not a terminal choice; modular/multi-terminal tags are.
	if a.singleStreetTerminal == true and b.singleStreetTerminal == true and a.terminal == 0 and b.terminal == 0
		and a_ref and b_ref and a_ref.kind == "street_station" and b_ref.kind == "street_station" then return true end
	return exact(a.terminalTag, b.terminalTag, context, 0)
end

local function stop_same(a, b, context)
	if not fields(a, b, STOP, context) then return false end
	local mapping = target_same(a.target, b.target, context)
	if not mapping then return false end
	local left, right = a.target.stations, b.target.stations
	if not terminal_tag_same(a, b, left[a.target.station + 1], right[b.target.station + 1], context) then return false end
	local n, m = array_size(a.alternativeTerminals), array_size(b.alternativeTerminals)
	if not n or n ~= m then return false end
	for i = 1, n do
		local x, y = a.alternativeTerminals[i], b.alternativeTerminals[i]
		if not fields(x, y, ALTERNATIVE, context) or not mapped_index(x.station, y.station, mapping)
			or not terminal_tag_same(x, y, left[x.station + 1], right[y.station + 1], context) then return false end
	end
	return true
end

local RECORD = { data = true }
local DATA = { vehicleInfo = true, stops = true }
function identity.same(a, b)
	local context = { remaining = 262144 }
	if not fields(a, b, RECORD, context) or not fields(a.data, b.data, DATA, context) then return false end
	local n, m = array_size(a.data.stops), array_size(b.data.stops)
	if not n or n ~= m then return false end
	for i = 1, n do if not stop_same(a.data.stops[i], b.data.stops[i], context) then return false end end
	return true
end

return identity
