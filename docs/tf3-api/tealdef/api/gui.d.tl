recordDef = true

--- Contains all GUI functionality apart from react.

--- Nine-patch image description.
global record NinePatch
	new : function() : NinePatch

	fileName : string
	horizontal : {integer}
	vertical : {integer}
	flipHorizontally : boolean
	repeatHorizontally : boolean
	repeatVertically : boolean
	--- Repeat factor (must be positive).
	repeatFactor : number
end

--- Stylesheet used by GUI components.
global record StyleSheet
	new : function() : StyleSheet

	backgroundColor : Vec4f
	backgroundColor1 : Vec4f
	backgroundColor2 : Vec4f

	backgroundImage1 : NinePatch
	backgroundImage2 : NinePatch

	borderWidth : Vec4f
	borderColor : Vec4f
	color : Vec4f

	size : Vec2f
	padding : Vec4f

	fontSize : integer
	borderImage : NinePatch

	anchorPoint : Vec2f
end

--- Main GUI interface
--- @category main
global record Gui
	--- Fire a react event (same as react.fireEvent() but from outside of react)
	---- @param name the event name
	---- @param param the event parameter
	fireReactEvent : function(name : string, param : any)
	--- Fire a game gui script event.
	--- This event is meant to be handled by game scripts (guiHandleEvent), not by react.onEvent().
	--- It differs from react.fireEvent in that it allows to return a value (like an error string to prevent the operation)
	--- @param id the component id
	--- @param name the event name
	--- @param param event-specific parameters
	-- @return the result from the event handler
	fireGuiScriptEvent : function(id : string, name : string, param : any) : any

	record HighlightStyle
		Square : HighlightStyle
		Circle : HighlightStyle
		Mask : HighlightStyle
	end


	record SpawnHudImageParams
		--- Mandatory path to the icon
		iconPath : FilePath

		--- Optional color. If set, the icon is expected to be grayscale.
		color : Vec4f

		--- Optional entity (if not used, specify position)
		entity : Engine.Entity

		--- Optional position (if not used, position of the entity is used)
		position : Vec3f		
	end

	--- Spawn a short-lived floating image as a hud-icon
	--- @param iconPath The icon to be used
	--- @param entity Optional entity (if not used, you must specify position instead)
	--- @param color Optional color (if not used, the icon is expected to have color channels)
	--- @param position Optional position (if not used, position is obtained from the entity)
	--- @param overrideDuration Optional duration in seconds
	--- @param fadeIn Optional: Start invisible and fade in (default: false)
	--- @param fadeOut Optional: Slowly fade out at the end (default: true)
	--- @param rev0 Optional revision0 (if not used, defaults to api.engine.getRevision(entity).num[1])
	spawnEphemeralHudImage : function(iconPath : FilePath, entity : Engine.Entity, color? : Vec4f, position? : Vec3f, overrideDuration? : number, fadeIn? : boolean, fadeOut? : boolean, rev0? : integer)

	--- Spawns a short icon that follows a path
	--- @param iconPath The icon to be used
	--- @param pos0 The starting position of the icon
	--- @param pos1 The end position of the icon
	--- @param pos0 The starting tangent of the icon
	--- @param pos1 The end tangent of the icon
	--- @param speed The speed (in m/s) of the icon
	--- @param scale A scaling factor for the size of the icon
	--- @param maxDistance The maximal distance at which the icon will be rendered
	spawnEphemeralHudImageOnPath : function(iconPath : FilePath, pos0 : Vec3f, pos1 : Vec3f, tan0 : Vec3f, tan1 : Vec3f, 
		speed : number, scale : number, maxDistance : number)

	--- Close all windows
	closeAllWindows : function()

	--- Carries details about selection event
	record SelectionDetails
		userdata
		new : function() : SelectionDetails
		new : function(copy : SelectionDetails) : SelectionDetails

		record Type
			None : Type
			Line : Type
			Station : Type
			Signal : Type
			Stop : Type
			Waypoint : Type
			TransportNetworkEdge : Type
			World : Type
			Marker : Type
			Town : Type
		end

		interface DataType
			is userdata
			kind : Type
		end

		--- Carries details about selection event for a Line.
		record Line is DataType
			--- The line entity
			line : Engine.Entity
			--- Stop index where the selected line segment starts
			stop : integer
			--- Waypoint index identifying the selected subsegment (-1: no waypoints, 0 = begins at stop, numWaypoints = ends at next stop)
			waypoint : integer
		end

		--- Carries details about selection event for a Station, StationGroup or Terminal
		record Station is DataType
			new : function() : Station

			--- The station group entity
			stationGroup : Engine.Entity

			--- Index in the the StationGroup's flattened list of station/terminals
			flatStationTerminalIndex : integer
			stationTerminal : StationTerminal
		end

		--- Carries details about selection event for a Signal
		record Signal is DataType
			--- The signalList entity
			signalList : Engine.Entity
			--- Index of the actual signal in the the SignalList
			signalIndex : integer
		end

		--- Carries details about selection event for a Stop (terminal) inside a line
		record Stop is DataType
			new : function() : Stop

			--- The station / terminal
			station : SelectionDetails.Station
			--- The line entity
			line : Engine.Entity
			--- Index of the stop in the line
			stopIndex : integer
		end

		--- Carries details about selection event for a waypoint inside a line
		record Waypoint is DataType
			--- The line entity
			line : Engine.Entity
			--- Index of the stop in the line
			stopIndex : integer
			--- Index of the waypoint in the line (index in stop.waypoints)
			waypointIndex : integer

			tag : integer
		end

		--- Carries details about selection event for a Transport Network Edge
		record TransportNetworkEdge is DataType
			new : function() : TransportNetworkEdge

			snap : EdgePos
		end

		--- Carries details about the cursor location in the world.
		record World is DataType
			new : function() : World

			pos : Vec3f
			water : boolean
		end

		--- Carries details about selection event for a Marker.
		record Marker is DataType
			new : function() : Marker

			marker : string
			--- If true, select the underlying entity of the marker (default = true)
			fireSelectEntity : boolean
			--- Get the marker position (if it is a position marker)
			pos : Vec3f
			--- Get the marked entity (if it is an entity marker)
			entity : Engine.Entity
		end

		--- Carries details about selection event for a Town.
		record Town is DataType
			new : function() : Town

			townEntity : Engine.Entity
			districtType : LandUseType
			districtCenter : Vec3f
		end

		data : DataType -- variant: nil|Line|Station|Signal|Stop|Waypoint|TransportNetworkEdge|World|Marker|Town
	end

	record WorldEvent
		pos : { number, number, number }
		water : boolean
	end

	record Mouse
		--- Represents a mouse event
		record Event
			record Type
				Pressed : Type
				Released : Type
				Clicked : Type
				Entered : Type
				Exited : Type
				Moved : Type
				Wheel : Type
				DoubleClicked : Type
				PressedOutside : Type
			end

			--- Event type.
			type : Type
			--- Mouse button: 0 = left, 1 = middle, 2 = right.
			button : integer
			--- Horizontal position of the mouse when event was triggered
			x : integer
			--- Vertical position of the mouse when event was triggered
			y : integer
			--- Relative horizontal movement.
			xrel : integer
			--- Relative vertical movement.
			yrel : integer
			--- Whether the event was already handled by a child component.
			handled : boolean
		end

		--- Gets the last valid terrain position pointed by the mouse.
		--- @return coordinates of the terrain position 
		getTerrainPosition : function() : Vec3f
		--- Returns whether a valid terrain position is currently available.
		--- @return boolean true if the mouse is pointing at the terrain
		hasTerrainPosition : function() : boolean
	end

	record Key
		record State
			Up : State
			Pressed : State
		end

		record InputEvent
			dir : State
			repeated : boolean
			--- Returns whether this is a gamepad event.
			isGamepadEvent : function(InputEvent) : boolean
			--- Returns whether this is a keyboard event.
			isKeyboardEvent : function(InputEvent) : boolean
			--- Returns the key code.
			getKey : function(InputEvent) : integer
			--- Returns key modifiers.
			getKeyMod : function(InputEvent) : integer
		end

		--- Represents a key press event.
		record Event
			data  : InputEvent
			--- Returns whether the key is pressed.
			isPressed : function(Event) : boolean
		end
	end

	record DataTransferItem
		new : function(ResName, any) : DataTransferItem

		type : ResName

		-- type-specific data. Note that this needs to be serializable.
		data : any
	end
	record DnD
		--- Represents drag & drop event
		record Event
			record Type
				Drop : Type
				DragStarted : Type
				DragEntered : Type
				DragExited : Type
			end

			--- Event type.
			type : Type
		end

		--- Set cursor while dragging (will get reset when a new drag starts).
		--- @param cursor the cursor id
		setCursor : function(cursor : integer)

		--- Add transfer data to the current drag & drop operation.
		--- @param dragStartEvent drag start event (must be Event.Type.DragStarted)
		--- @param item transferable item
		addTransferData : function(dragStartEvent : Event, item : DataTransferItem)

		--- Get current drag & drop data.
		--- @return current transfer data list
		getAllTransferData : function() : {DataTransferItem}
	end

	record InputAction
		record InputActionState
			Disabled : InputActionState -- disabled, action will not be triggered and no hints or prompts are shown, leaving the keys for other actions
			Inactive : InputActionState -- action will not be triggered, but hints and button prompts are generated
			Enabled  : InputActionState -- fully enabled, hints and prompts shown (except if disabled/invisible due to hierarchy)
		end

		--- Additional info about the invocation of an input action event
		record InvokeData
			userdata

			--- Status type of the InputActionInvokeData
			record Status
				Triggered : Status   -- Start event: when an event key combo first is fully pressed, or when axis values change
				Repeat : Status      -- When the system reports a repeated key press for this action
				PressedStep : Status -- Invoked every game step, as long as the active is active = pressed
				EndReleased : Status -- "Good" end event: due to a key/button release there no longer is a action combo active
				EndAborted : Status	 -- Component/action became disabled, or another action with higher priority has started
			end

			--- status of the action.
			status : Status
		end

		--- Checks if a modifier-only action is currently active.
		--- @param inputActionId the input action identifier
		-- @return True if active.
		modifierOnlyActionIsActive : function(inputActionId : string) : boolean
		--- Resets all modifier-only action states to `false`
		resetModifierOnlyActionStates : function()
		--- Checks for key binding conflicts.
		--- @param keyCmdDefinitions Key command definitions.
		--- @param inputActionId Input action id.
		--- @param keyComboDef Key combo definition.
		-- @return Conflict description (empty if no conflict).
		hasConflicts : function(keyCmdDefinitions : {string : {KeyComboDef}}, inputActionId : string, keyComboDef : KeyComboDef) : string
		--- Recursively find list of all IAs that should are duplicates of this one (i.e. duplicateOf == inputActionId and duplicatedKeybindings == true)
		--- @param inputActionId Input action id.
		-- @return Duplications of the IA
		findDuplicatesOf : function(inputActionId : string) : {string}
		--- Resolves key binding conflicts and returns updated key command definitions.
		--- @param keyCmdDefinitions Key command definitions.
		--- @param inputActionId Input action id.
		--- @param keyComboDef Key combo definition.
		-- @return Fixed key command definitions  or empty table if change not allowed.
		getFixedKeyCmdDefs : function(keyCmdDefinitions : {string : {KeyComboDef}}, inputActionId : string, keyComboDef : KeyComboDef) : {string : {KeyComboDef}}
	end

	record ById
		--- Shows or hides a component.
		--- @param idOrTag the component identifier or a tag
		--- @param visible whether visible or not (nil to reset the rule
		--- @param idOnly idOnly -> do not consider tags
		setVisibilityByClass : function(idOrTag : string, visible : boolean, idOnly?: boolean) -- visible: nil removes visibility override
		--- Enables or disables a component.
		--- @param idOrTag the component identifier or a tag
		--- @param enabled whether enabled or not (nil sets to enabled and removes the rule)
		--- @param idOnly idOnly -> do not consider tags
		setEnabled : function(idOrTag : string, enabled : boolean, idOnly?: boolean) -- enable: nil re-enables it (and removes the rule)
		---  Sets the highlighted state of a component.
		--- @param idOrTag the component identifier or a tag
		--- @param highlighted whether highlighted or not (nil sets to not highlighted and removes the rule)
		--- @param style defaults to HighlightStyle::Circle
		--- @param color the color of the highlight, defaults to yellow
		--- @param idOnly idOnly -> do not consider tags
		setHighlighted : function(
			idOrTag : string,
			highlighted? : boolean,
			style? : HighlightStyle,
			color? : Vec3f,
			idOnly?: boolean
		)

		--- Checks if a UI component is visible by its id.
		--- @param id the component identifier
		--- @return true if the component is visible
		isVisible : function(id : string) : boolean
		--- Checks if a UI component and all its parents are visible by id.
		--- @param id the component identifier
		--- @return true if the component and all parents are visible
		isVisibleRecursive : function(id : string) : boolean
		--- Sets the visibility of a UI component by its ID.
		--- @param id the component identifier
		--- @param visible if the component should be visible
		setVisible : function(id : string, visible : boolean)

		--- Resets a window to its original position if it was moved by the user.
		--- @param id string id the window identifier
		resetMovedWindowPosition : function(id : string)
		--- Get width and height of UI component
		--- @param id string id the window identifier
		--- @return width and height
		getSize : function(id : string) : Vec2f
	end

	record Camera
		--- Sets camera to a given position/orientation.
		--- @param center position on the map where the camera should point to
		--- @param distance the distance from the position
		setManualCamera : function(center : Vec2f, distance : number)

		--- Obtains the current camera data.
		--- @return the current camera data as a Vec5f {center.x, center.y, distance, angle, pitch}
		getCameraData: function() : Vec5f

		--- Set the camera data.
		--- @param Vec5f set the camera data as a Vec5f {center.x, center.y, distance, angle, pitch}
		setCameraData: function(Vec5f)

		--- Obtains the current height above terrain.
		--- @return the height of the camera above the terrain
		getHeightAboveTerrain : function() : number

		--- Focuses the camera on an entity.
		--- @param entity the id of the entity that should be focused on
		focusEntity : function(entity : Engine.Entity)

		--- Focuses the camera on a position.
		--- @param position the position that should be focused
		--- @param distance the distance of the camera from the target
		focusPosition : function(position : Vec3f, distance : number)

		--- Takes a screenshot and stores it in userdata folder
		--- @param scale image resolution
		takeScreenshot : function(scale : integer)

		--- Gets the entity currently being followed.
		--- @return the entity being followed (and the entity revision)
		getFollowEntity : function() : { Engine.Entity, Engine.Revision }

		--- Sets camera to follow an Entity.
		--- @param entity the id of the entity that should be followed
		--- @param jump true if the camera should directly jump to the entity and not slide there
		followEntity : function(entity : Engine.Entity, jump : boolean)

		--- Enters the cockpit of an entity.
		--- @param entity entity of the object to enter
		enterFollowCameraCockpit : function(entity : Engine.Entity)

		--- Leave the cockpit of an entity.
		leaveFollowCameraCockpit : function()

		--- Tells if mouse is attached to free cam or not
		--- @return if mouse is attached (true) or not (false)
		isFreeCameraMouseAttached : function() : boolean

		--- Toggles mouse attachment
		toggleFreeCameraMouseAttachment : function()

		--- Toggles free camera
		toggleFreeCamera : function()

		--- Convert a 3D World position into a position on screen (in pixels)
		world2Screen : function(Vec3f) : Vec2i

		--- Convert a position on the screen (in pixels) (with depth [0, 1]) into a 3D World position
		screen2World : function(Vec3f) : Vec3f

		--- Get camera origin in world coordinates
		getEye : function() : Vec3f

		--- Get camera center ("look-at" pos) in world coordinates
		getCenter : function() : Vec3f

		--- Get near and far distances of camera in x and y coordinates repsectively
		getNearFar : function() : Vec2f

		--- Width and height of the viewport, in pixels
		getSize : function() : Vec2i

		--- Trace a ray from worldPos to farPos, and find the intersection (if any) with the terrain, offsetted at zOffset
		--- @param worldPos world position of starting point of ray
		--- @param farPos world position of end point of ray
		--- @param zOffset offset to shift the terrain for intersection
		--- @param numSteps number of steps to perform for finding an intersection. more steps are more precise but cost more, 30 is a good compromise
		traceToTerrain : function(worldPos : Vec3f, farPos : Vec3f, zOffset : number, numSteps : integer) : Vec3f | nil
	end

	record Sound
		--- Sounds the vehicle horn.
		--- @param vehicleEntity the vehicle to sound the horn
		letVehicleHorn : function(vehicleEntity : Engine.Entity)

		--- Plays a single sound effect randomly selected of the provided selection.
		--- @param paths vector of strings paths of sound effects
		playRandomSoundEffect : function(paths : {FilePath})
	end

	record MusicPlayer
		--- Goes back to the previous track in the music player.
		goBack : function()

		--- Goes forward to the next track in the music player.
		goForward : function()

		--- Toggles pause/play state of the music player.
		togglePause : function()

		--- Gets the title of the currently playing track.
		--- @return the track title
		getTitle : function() : string

		--- Gets the artist of the currently playing track.
		--- @return the track artist
		getArtist : function() : string

		--- Checks if the music player has tracks loaded.
		--- @return true if the music player has tracks
		hasPlaylist : function() : boolean

		--- Gets the current track index (1-based).
		--- @return the current track index
		getPlaylistIndex : function() : integer

		--- Sets the current playlist. 
		--- The current track will only start after the current track ends. To trigger the new playlist immediately, call `goForward()` right after this call.
		--- @param playlist the playlist resource name
		--- @param startPaused if set, does not play the playlist, just prepares it
		--- @param offset playback offset in seconds (optional)
		setTrackListFromPlayList : function(playlist : string, startPaused : boolean, offset? : number)

		--- Sets the current playlist. Only available while in-game.
		--- The current track will only start after the current track ends. To trigger the new playlist immediately, call `goForward()` right after this call.
		--- @param playlist the playlist resource name
		setPlaylist : function(playlist : string)

		--- Gets the current playlist. Only available while in-game.
		--- @return the resource name of the current playlist
		getPlaylist : function() : string

		--- Checks if the music player is currently playing.
		--- @return true if music is playing
		isPlaying : function() : boolean

		--- Plays a track by name.
		--- @param trackName the name of the track to play
		--- @param offset playback offset in seconds (optional)
		playTrack : function(trackName : string, offset? : number)

		--- Plays a specific file that might not be part of the current track list
		--- @param filePath the path to the track file
		--- @param offset playback offset in seconds (optional)
		playTrackFile : function(filePath : string, offset? : number)

		--- Gets the length (duration) of the current track
		--- @return the track duration in second
		getTrackLength : function() : number

		--- Gets the time of the current track
		--- @return the current time of the current track
		getTrackElapsedTime : function() : number

		--- Gets the current gain (volume) of the music player.
		--- @return the gain value
		getGain : function() : number

		--- Sets the gain (volume) of the music player.
		--- @param gain the gain value
		setGain : function(gain : number)

		--- Sets the track list for the music player, replaces the current track list.
		--- @param trackList array of tuples containing track name, file path, and repeat flag
		--- @param enableRepeat true to enable repeat for the entire list
		setTrackList : function(trackList : {{string, string, boolean}}, enableRepeat : boolean)

		--- Adds a track list to the music player. This doesn't replace the existing tracks
		---	and once the added tracks are finish, the track previously playing will resume
		--- @param trackList array of tuples containing track name, file path, and repeat flag
		--- @param enableRepeat true to enable repeat for the entire list
		addTrackList : function(trackList : {{string, string, boolean}}, enableRepeat : boolean)

		--- Sets the context tag for the music player. 
		--- The context tag can be used to change the variant of a playing track.
		--- @param contextTag the context tag to set
		setContextTag : function(contextTag : string)
	end

	record VoiceOverManager
		--- Stops the current voice over playing
		stop : function()

		--- Plays a new voice over
		--- @param voiceOverRes the file path to the voice over to play
		--- @param delayInSeconds delay before the voice over starts
		play : function(voiceOverRes : string, delayInSeconds? : number)

		--- Checks whether a specific voice over is playing
		--- @param voiceOverRes the voice over file to check
		--- @return true if the voice over file is playing
		isPlaying : function(voiceOverRes : string) : boolean

		--- Checks whether any voice over is current playing
		--- @return true if any voice over is playing
		isPlayingAny : function() : boolean

		--- Checks whether any voice over is current playing and returns the file path if one is playing
		--- @return file path if any voice over is playing
		getPlaying : function() : ResName
	end

	record ByEntity
		--- Checks if line is empty or visible
		--- @param Engine.Entity the line entity to check
		--- @return true if the line is empty or visible
		isLineEmptyOrVisible : function(Engine.Entity) : boolean

		--- Checks if an entity is visible
		--- @param Engine.Entity the entity to check
		--- @return true if the entity is visible
		isVisible : function(Engine.Entity) : boolean

		--- Checks if vehicle is visible
		--- @param Engine.Entity the vehicle entity to check
		--- @return true if the vehicle is visible
		isVehicleVisible : function(Engine.Entity) : boolean
	end

	record ContextHelper
		record SubjectState
			Visible : SubjectState
			Focused : SubjectState
		end

		--- Collects subject states for given ids
		--- @param idsOfInterest ids to collect states for
		collectSubjectStates : function(idsOfInterest : {string}) : {string : SubjectState}
		getIdsOfActiveTool : function() : {string}
	end

	record Construction
		--- Sets the default construction angle for constructions.
		--- @param angle the default construction angle
		setAngle : function(angle : number)

		--- Modifies a construction
		--- @param construction the construction entity
		modify : function(construction : Engine.Entity)

		--- Returns brush icons for construction menu
		--- @return paths to brush icons for the construction menu
		getBrushIcons : function() : {string}

		--- Provides dust effects for proposal
		--- @param proposal the proposal
		--- @param proposalData the proposal data
		provideDustWheneverPossible : function(proposal : Proposal, proposalData : ProposalData)

		getRefundableEntities : function() : {{Engine.Entity, integer}, {Engine.Revision, integer}}
		--- Updates refundable entities
		--- @param resultEntities result entities
		--- @param proposal the street proposal
		updateRefundableEntities : function(resultEntities : {Engine.Entity}, proposal : Proposal.StreetProposal)
	end

	record Mission
		--- Get the current mission
		--- @return the mission name
		getMission : function() : string

		--- Get the current campaign
		--- @return the campaign name
		getCampaign : function() : string

		--- Adds a zone
		--- @param key the key (name) of the zone
		--- @param polygon the shape of the zone as a list of 2d position
		--- @param draw if the zone should be drawn
		--- @param drawColor the color of the zone
		--- @param prohibitBuilding if prevented or not to build inside the zone
		--- @param playAnimation if player zone animation (optional), default to true
		--- @param zOffset (optional), default to terrain level
		setZone : function(key : string, polygon: {Vec2f}, draw : boolean, drawColor : Vec4f, prohibitBuilding : boolean, playAnimation? : boolean, zOffset? : number)
		
		--- Adds a zone as a cylinder
		--- @param key the key (name) of the zone
		--- @param center the center of the zone
		--- @param radius the radius of the zone
		--- @param draw if the zone should be drawn
		--- @param drawColor the color of the zone
		--- @param prohibitBuilding if prevented or not to build inside the zone
		--- @param playAnimation if player zone animation (optional), default to true
		--- @param zOffset (optional), default to terrain level
		setZoneCircle : function(key : string, center: Vec2f, radius : number, draw : boolean, drawColor : Vec4f, prohibitBuilding : boolean, playAnimation? : boolean, zOffset? : number)
		
		--- Removes a zone
		--- @param key the key of the zone
		removeZone : function(key : string)

		--- Sets marker at the given position
		--- @param key the key of the marker
		--- @param pos the position of the marker
		--- @param type type of marker (optional)
		--- @param scaling scaling of marker (optional)
		--- @param isSelectable whether marker is selectable
		--- @param fireSelectEntity whether selecting the marker also selects the underlying entity (default is true)
		setMarkerAtPosition : function(key : string, pos : Vec3f, type : string, scaling : number, isSelectable? : boolean, fireSelectEntity? : boolean)

		--- Sets marker at the given entity
		--- @param key the key of the marker
		--- @param entity the entity
		--- @param type optional type
		--- @param scaling optional scaling
		--- @param isSelectable whether marker is selectable
		--- @param fireSelectEntity whether selecting the marker also selects the underlying entity (default is true)
		setMarkerAtEntity : function(key : string, entity : Engine.Entity, type : string, scaling : number, isSelectable? : boolean, fireSelectEntity? : boolean)
		
		--- Removes a marker
		--- @param key the key of the marker
		removeMarker : function(key : string)
		--- Renderes the move path of an entity dynamically
		--- ATTENTION: at the moment, only ships are supported.
		--- @param key unique key
		--- @param entity entity
		--- @param color optional color
		setMovePathVisualizationAtEntity : function(key : string, entity : Engine.Entity, color? : Vec3f)
		--- Removes the move path of an entity dynamically
		--- @param key unique key
		removeMovePathVisualization : function(key : string)

		--- Plays a cutscene.
		--- @param filePath the filepath to the cutscene keyframe definition that should be played
		--- @param resolveLanguageFolder automatically resolve the selected keyframe file by language
		--- @param entityToEntityMap maps entities from the keyframe file to possible runtime entities
		playCutscene : function(filePath : string, resolveLanguageFolder? : boolean, entityToEntityMap? : {Engine.Entity : Engine.Entity})

		--- Checks if a cutscene is currently playing.
		isCutscenePlaying : function() : boolean

		--- Return the current cutscene time for syncing mission related systems to the cutscene
		--- @return the actual simulated cutscene time
		getCutsceneElapsedTime : function() : number
	end

	record Game
		--- Returns if the UI is blocked by a savegame in progress
		--- @return true if the ui is blocked by a savegame
		isSavegameUIBlocked : function() : boolean

		--- Sets if the game pause menu is open
		--- @param pause true if the user is in the pause menu
		setInGameMenuPause : function(pause : boolean)

		--- Returns the GUI SaveData
		--- @param modId the mod to get the user data for
		--- @return the userData as a lua table
		getGuiSaveData : function(modId : string) : table

		--- Sets the GUI SaveData
		--- @param modId the mod to set the user data for
		--- @param data the user data
		setGuiSaveData : function(modId : string, data : table)

		--- Returns the (estimated) maximum possible game speed based on actual simulation timings. 
		--- Only available in GUI thread.
		--- @return maximum game speed (or 0 if not enough data available)
		getEstimatedMaximumGameSpeed : function() : integer

		--- Returns if the game is currently in the map editor
		--- @return true if in the map editor
		isMapEditor : function() : boolean

		--- Returns the default savegame id
		--- @return the default savegame id
		getDefaultSavegameId : function() : string

		--- Sets an environment. This value is saved in the GUI SaveData and will be restored on next load.
		---	Changing it will not change the current environment, for that `api.gui.rendering.setEnvironment` needs to be as well called.
		--- @param environment the resource name for the environment
		setEnvironment : function(environment : ResName)

		--- Returns the resource name of the current environment
		--- @return the environment resource name
		getEnvironment : function() : ResName
	end

	record Guide
		--- Gui positioning of the guide "bookmark" with respect to target component
		record GuidePosition
			Left : GuidePosition
			Right : GuidePosition
			Above : GuidePosition
			Below : GuidePosition
		end

		--- Gui positioning of the guide "bookmark" with respect to the entire screen
		record FreeGuidePosition
			High : FreeGuidePosition
			Low: FreeGuidePosition
		end

		--- A target component for the guide system
		record GuideTarget
			userdata
			new : function(idOrTag : string, position? : GuidePosition) : GuideTarget
			idOrTag : string
			position : GuidePosition -- default is above
		end

		-- Tries to attach a guide system button to the first visible target component
		-- @param targets prioritized list of target components
		-- @param tooltip text
		-- @param caption optional caption text
		trySpawnGuideById : function(targets : {GuideTarget}, tooltip : string, caption : string) : boolean

		-- Tries to spawn a free floating guide system button
		-- @param tooltip text
		-- @param caption optional caption text
		trySpawnGuideFree : function(position : FreeGuidePosition, tooltip : string, caption : string) : boolean

		-- Completes a guide corresponding to a specific id
		completeGuideById : function(targets : {GuideTarget}) : boolean

		-- Resets the current active guide
		resetGuide : function()
	end

	record Rendering
		--- Sets an environment. This will change the current environment, but will not persist the environment resource name.
		---	It might be necessary to as well call `api.gui.game.setEnvironment` if a different environment resource is set.
		--- @param environment the description for the environment
		setEnvironment : function(environment : Environment)

		--- Returns the current environment data
		--- @return the current environment data
		getEnvironment : function() : Environment

		--- Makes a dust cloud appear
		--- @param bbMin bounding box min
		--- @param bbMax bounding box max
		--- @param transf transformation matrix
		spawnDust : function(bbMin : Vec3f, bbMax : Vec3f, transf : Mat4f)
		getFrameTime01 : function() : number
	end

	record Map
		--- Sets seed for the map. Only available in GUI thread.
		--- @param seed the seed
		setMapSeedText : function(seed : string)
		--- Reloads the material index manager pipeline.
		reloadMaterialIndexManagerPipeline : function()
		openTerrainEditor : function()
		closeTerrainEditor : function()
	end

	record BenchMark
		--- Simulation time frame along with game time at moment of capture
		record SimTime
			frameTime : integer
			gameTime : integer
		end

		--- Returns the rendering preparation time
		getBeginFrameTimes : function() : {integer}

		--- Returns the events processing time
		getEventTimes : function() : {integer}

		--- Returns the gui update time
		getCoreStepTimes : function() : {integer}

		--- Returns the rendering time
		getRenderTimes : function() : {integer}

		--- Returns the rendering finish time
		getSwapTimes : function() : {integer}

		--- Returns the sync time between gui and simulation. Only available in GUI thread.
		getReplicateTimes : function() : {SimTime}

		--- Returns commands processing time. Only available in GUI thread.
		getCommandTimes : function() : {SimTime}

		--- Returns the simulation update time. Only available in GUI thread.
		getGameStepTimes : function() : {SimTime}
	end

	record Debug
		--- Set the current debug entity
		--- @param entity the entity
		selectEntity : function(entity : Engine.Entity)
	end

	record Achievements
		--- Checkes whether player stats are disabled
		--- @return true if player stats are disabled
		areStatsDisabled : function() : boolean

		--- Unlocks an achievement based on its string id
		--- @param achievement achievement to unlock
		unlockAchievement : function(achievement : string)

		--- Checks whether an achievement can be unlocked
		--- @param achievement achievement to check
		--- @return true if the achievement can be unlocked
		isAchievementUnlockable : function(achievement : string) : boolean

		--- Checks whether an achievement is unlocked (completed)
		--- @param achievement achievement to check
		--- @return true if the achievement is unlocked
		isAchievementUnlocked : function(achievement : string) : boolean

		--- Increments a player stat value by the provided value
		--- @param playerStat the stat id to update
		--- @param value the value to add to the stat
		updateStat : function(playerStat : string, value : number)

		--- Sets a player stat value, replacing the current value by the provided one
		--- @param playerStat the stat id to update
		--- @param value the value to add to the stat
		setStat : function(playerStat : string, value : number)

		--- Gets a player stat value
		--- @param playerStat the stat id to get
		--- @return the current value of the stat
		getStatValue : function(playerStat : string) : number

		--- Sets extra data associated with a stat.
		--- Extra data are stored locally in the player profile and allow tracking of more informations if necessary.
		--- @param playerStat the stat id to set the extra data for
		--- @param data the extra data to set
		setStatExtraData : function(playerStat : string, data : table)

		--- Gets extra data associated with a stat.
		--- Extra data are stored locally in the player profile and allow tracking of more informations if necessary.
		--- @param playerStat the stat id to get the extra data for
		--- @return the extra data
		getStatExtraData : function(playerStat : string) : table

		--- Set sound effect(s) to be played when an achievement is earned.
		--- @param sfx vector of filepaths pointing to .wav files with according sound effect(s)
		setEarnedSFX : function(sfx : {FilePath})
	end

	record GenericRep is ResTypeRep<integer,GenericGameRes>
		--- Gets all the Genereic Resource Type of a given type name
		--- Only allows typeName in { "gui_res_overwrite", "gui_res" }, for other types, use `api.res.genericRep`
		--- @param typeName the type name
		--- @param includeInvisible whether to include invisible resources
		getAllOfType : function(typeName : string, includeInvisible? : boolean) : {integer}
	end

	record Backend
		record LegalDocument
			title : string
			text : string
		end

		isInitialized : function() : boolean
		
		hasLegalDocuments : function()

		getLegalDocuments : function() : {string}

		markLegalDocumentViewed : function(string)

		isAccountLoggedIn : function() : boolean

		loginAccount : function(username : string, password : string) : PdxFuture<PdxLoginResult>

		logoutAccount : function() : PdxFuture<PdxResult>

		getAccountInfo : function() : PdxFuture<PdxAccountInfo>

		getProfile : function(social : boolean) : PdxFuture<PdxProfileResult>

		createProfile : function(name : string, social : boolean) : PdxFuture<PdxResult>

		renameProfile : function(name : string, social : boolean) : PdxFuture<PdxResult>

		getCountries : function() : {PdxCountry}
		
		getLegalDocument : function(type : string) : PdxFuture<PdxLegalDocument>
		
		createAccount : function(email : string, password : string, dateOfBirth : string, countryCode : integer, marketingPermission : boolean) : PdxFuture<PdxResult>

		supportsAccountLinking : function() : boolean

		getThirdPartyLinkState : function() : PdxFuture<PdxThirdPartyLinkState>

		getThirdPartyAutoLoginPromptState : function() : PdxThirdPartyAutoLoginPromptState

		setThirdPartyAutoLoginPromptState : function(state : PdxThirdPartyAutoLoginPromptState)

		linkThirdPartyAccount : function() : PdxFuture<PdxResult>
		
		unlinkThirdPartyAccount : function() : PdxFuture<PdxResult>

		loginThirdPartyAccount : function() : PdxFuture<PdxLoginResult>
	end

	mouse : Mouse
	key : Key
	dnd : DnD
	inputAction : InputAction
	byId : ById
	camera : Camera
	sound : Sound
	musicPlayer : MusicPlayer
	backend : Backend
	voiceOverManager : VoiceOverManager
	byEntity : ByEntity
	contextHelper : ContextHelper
	construction : Construction
	mission : Mission
	guide : Guide
	game : Game
	map : Map
	benchMark : BenchMark
	rendering : Rendering
	debug : Debug
	achievements : Achievements
	genericRep : GenericRep

	StyleSheet : StyleSheet
	NinePatch : NinePatch
end

recordDef = false
