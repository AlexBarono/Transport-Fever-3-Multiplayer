-- Game script registration (TF3 resource file; the engine reads the table returned by data()).
function data()
	return {
		updateScript = {
			fileName = "main.script@update",
		},
		handleEventScript = {
			fileName = "main.script@handleEvent",
		},
	}
end
