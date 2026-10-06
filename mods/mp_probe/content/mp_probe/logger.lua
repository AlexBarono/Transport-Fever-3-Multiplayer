--- Tagged logging to the game log (stdout.txt).
-- @module mp_probe.logger
local logger = {}

local TAG = "[mp_probe]"

function logger.info(...)
	debugPrint(TAG, ...)
end

return logger
