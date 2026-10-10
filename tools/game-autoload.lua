-- TF3MP_AUTOLOAD_V53
-- Called from the original MainMenu recipe, after its ready/mod-management guards.
-- Use the game's own progress page, including startReadyGame after loading finishes.
return function(react, app, api, log, setPage)
    local tf3mpLaunchOnce = react.useRef(false)
    local tf3mpLaunchQuery = react.useRef(nil)
    react.onStep(function()
        if tf3mpLaunchOnce:get() then return end
        local ok, err = pcall(function()
        local hex = os.getenv("TF3MP_AUTOLOAD") or ""
        if hex == "" or #hex > 1440 or #hex % 2 ~= 0 or hex:find("[^0-9a-f]") then return end
        local name = hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)
        local saveId = api.type.SavegameId.new()
        saveId.saveGameNamespace = app.SaveGameNamespace.getSavegame()
        saveId.saveGameName = name
        saveId.path = ""
        if not tf3mpLaunchQuery:get() then
            for _, save in pairs(app.findAllSavegames(saveId.saveGameNamespace)) do
                if save.saveName == name then saveId.path = save.path or ""; break end
            end
            tf3mpLaunchQuery:set({ id = saveId, query = app.getSavegameInfo(saveId) })
            return
        end
        local pending = tf3mpLaunchQuery:get()
        if not pending.query:isCompleted() then return end
        tf3mpLaunchOnce:set(true)
        local data = pending.query:get()
        if not data or not data.info or (data.errorMsg and data.errorMsg ~= "") then
            log.warning("[mp_probe]autoload failed: save metadata unavailable")
            return
        end
        local info = api.type.SaveGameData.SaveGameDetails.new(data.info)
        local enabled = false
        for _, mod in pairs(info.mods) do if mod.name == "mp_probe_1" then enabled = true end end
        if not enabled then
            local mod = api.type.mod.ModId.new()
            mod.name = "mp_probe_1"
            local mods = info.mods
            table.insert(mods, mod)
            info.mods = mods
        end
        log.warning("[mp_probe]autoload requested: " .. name)
        setPage("ProgressPage", {
            saveGameId = pending.id,
            mission = info.mission or "",
            onMount = function()
                app.setWaitForStartReadyGame()
                app.loadGame(pending.id, false, info)
            end,
        })
        end)
        if not ok then
            tf3mpLaunchOnce:set(true)
            log.warning("[mp_probe]autoload failed: " .. tostring(err))
        end
    end)
end
