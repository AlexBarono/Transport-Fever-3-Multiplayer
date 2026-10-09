--- Installed in the main GUI, before a subsidy decision or company rename executes.
local hooks = { SOURCE = "mp_probe_economy" }

function hooks.watch(env, m, options)
	m.options = options
	if m.installed then return end
	m.installed, m.marked = true, setmetatable({}, { __mode = "k" })
	local cmd, count = env.api.cmd, 0
	local function install(name, mark)
		local ok, why = pcall(function()
			local original = assert(cmd[name], name .. " missing")
			local hook = function(...)
				local c = original(...); local args, data = mark(...)
				if c and args then m.marked[c] = { args = args, data = data } end
				return c
			end
			cmd[name] = hook; assert(cmd[name] == hook, "economy hook not retained")
		end)
		if ok then count = count + 1 else options.log("economy hook unavailable: " .. tostring(why):sub(1, 160)) end
	end
	install("makeScriptingSendEventCmd", function(src, id, name, param)
		if src ~= hooks.SOURCE and id == "Subvention" and (name == "onAccept" or name == "onDecline") then
			return { kind = "subvention", name = name, uid = param and param.uid }, { src = src, id = id, name = name, param = param }
		end
	end)
	install("makeEntitySetNameCmd", function(id, name)
		local ok, player = pcall(function() return env.api.engine.util.getPlayer() end)
		if ok and id == player then return { kind = "company", name = name }, { entity = id, name = name } end
	end)
	local ok, why = pcall(function()
		local send = assert(cmd.sendCommand); m.send = send
		local hook = function(command, callback, ...)
			local marked = command and m.marked[command]
			if marked then m.marked[command] = nil end
			if not marked or not m.options.timed() then return send(command, callback, ...) end
			local sent, err = pcall(function()
				local event = assert(cmd.makeScriptingSendEventCmd(hooks.SOURCE, hooks.SOURCE, hooks.SOURCE, marked.args), "economy event missing")
				send(event)
			end)
			if not sent then
				local label = marked.args.kind == "company" and ("Unternehmen umbenennen: " .. tostring(marked.args.name)) or
					("Subvention " .. (marked.args.name == "onAccept" and "annehmen" or "ablehnen") .. " (Kennung " .. tostring(marked.args.uid) .. ")")
				local reason = "economy scheduling failed: GUI handover unavailable (" .. tostring(err):sub(1, 160) .. ")"
				m.options.log(reason)
				pcall(m.options.issue, label, reason)
				-- Never pay only the clicking PC when the shared handover failed.
				if callback then pcall(callback, marked.data, false, {}) end
				return
			end
			if callback then
				local completed, err_cb = pcall(callback, marked.data, true, {})
				if not completed then m.options.log("economy window callback failed: " .. tostring(err_cb):sub(1, 160)) end
			end
		end
		cmd.sendCommand = hook; assert(cmd.sendCommand == hook, "economy send hook not retained")
	end)
	if ok then count = count + 1 else options.log("economy send hook unavailable: " .. tostring(why):sub(1, 160)) end
	options.log("economy hooks: " .. count .. " of 3 installed")
end

return hooks
