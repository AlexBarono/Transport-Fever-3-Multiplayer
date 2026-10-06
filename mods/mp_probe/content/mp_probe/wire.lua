--- Bounded data-only codec. No load()/eval of text received from another game.
-- Strings are hex encoded so names/params cannot inject a stdout line or protocol marker.
local wire = { MAX_BYTES = 16383, MAX_DEPTH = 24, MAX_ITEMS = 4096 }

function wire.encode(value)
	local seen, items = {}, 0
	local function put(v, depth)
		assert(depth <= wire.MAX_DEPTH, "wire nesting limit")
		items = items + 1
		assert(items <= wire.MAX_ITEMS, "wire item limit")
		local t = type(v)
		if t == "boolean" then return v and "y" or "n" end
		if t == "number" then
			assert(v == v and math.abs(v) < math.huge, "non-finite number")
			return "d" .. string.format("%.17g", v) .. ";"
		end
		if t == "string" then
			local hex = v:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)
			return "s" .. #hex .. ":" .. hex
		end
		assert(t == "table", "unsupported wire value: " .. t)
		assert(not seen[v], "cyclic wire table")
		seen[v] = true
		local keys = {}
		for k in pairs(v) do
			assert(type(k) == "string" or type(k) == "number", "unsupported wire key")
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		local parts = { "t" .. #keys .. ":" }
		for _, k in ipairs(keys) do
			parts[#parts + 1] = put(k, depth + 1)
			parts[#parts + 1] = put(v[k], depth + 1)
		end
		seen[v] = nil
		return table.concat(parts)
	end
	local text = put(value, 0)
	assert(#text + 3 <= wire.MAX_BYTES, "action exceeds DLL line limit")
	return text
end

function wire.decode(text)
	local ok, result = pcall(function()
		assert(type(text) == "string" and #text + 3 <= wire.MAX_BYTES, "invalid wire length")
		local pos, items = 1, 0
		local function count()
			local stop = text:find(":", pos, true)
			assert(stop, "missing wire length")
			local digits = text:sub(pos, stop - 1)
			assert(digits:match("^%d+$"), "invalid wire length")
			pos = stop + 1
			return tonumber(digits)
		end
		local function get(depth)
			assert(depth <= wire.MAX_DEPTH, "wire nesting limit")
			items = items + 1
			assert(items <= wire.MAX_ITEMS, "wire item limit")
			local tag = text:sub(pos, pos)
			pos = pos + 1
			if tag == "y" then return true elseif tag == "n" then return false end
			if tag == "d" then
				local stop = text:find(";", pos, true)
				assert(stop, "missing number end")
				local v = tonumber(text:sub(pos, stop - 1))
				assert(v and v == v and math.abs(v) < math.huge, "invalid number")
				pos = stop + 1
				return v
			elseif tag == "s" then
				local n = count()
				assert(n % 2 == 0 and n <= #text - pos + 1, "invalid string length")
				local hex = text:sub(pos, pos + n - 1)
				assert(not hex:find("[^0-9a-f]"), "invalid hex string")
				pos = pos + n
				return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
			elseif tag == "t" then
				local n, t = count(), {}
				assert(n <= wire.MAX_ITEMS, "wire item limit")
				for _ = 1, n do
					local k = get(depth + 1)
					assert(type(k) == "string" or type(k) == "number", "invalid wire key")
					assert(t[k] == nil, "duplicate wire key")
					t[k] = get(depth + 1)
				end
				return t
			end
			error("unknown wire tag")
		end
		local v = get(0)
		assert(pos == #text + 1, "trailing wire data")
		return v
	end)
	if ok then return result end
	return nil, tostring(result)
end

function wire.copy(value)
	local result, err = wire.decode(wire.encode(value))
	assert(err == nil, err)
	return result
end

return wire
