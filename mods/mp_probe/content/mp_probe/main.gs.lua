-- Game script registration (TF3 resource file; the engine reads the table returned by data()).
-- v24: the GUI script keeps the shared game speed; it also runs while the game is paused.
-- v33: guiHandleEvent sees TF3's build tools before they execute (hold.lua).
function data()
	return {
		updateScript = {
			fileName = "main.script@update",
		},
		handleEventScript = {
			fileName = "main.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "main.script@guiUpdate",
		},
		guiHandleEventScript = {
			fileName = "main.script@guiHandleEvent",
		},
	}
end
