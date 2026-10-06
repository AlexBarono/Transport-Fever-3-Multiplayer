recordDef = true

--- Module controlling high level functions for the application, can be used to manipulate save games.

global record App
	record ProgressMonitor
		--- Returns the current progress as a value from 0 to 1
		getProgress : function(ProgressMonitor) : number
		--- Returns the current task being executed
		getTask : function(ProgressMonitor) : string
	end

	--- Application level resource repositories.
	--- Note: climateRep, economyRep and terrainGeneratorRep are only populated in the main menu,
	--- in the game UI use the corresponding repositories in `api.res`.
	record Res
		--- A resource repository containing data for the climates.
		climateRep : ResTypeRep<integer,ClimateDesc>
		--- A resource repository containing data from the ".eco" economy resources.
		economyRep : ResTypeRep<integer,EconomyDesc>
		--- A resource repository containing data for the terrain generation.
		terrainGeneratorRep : ResTypeRep<integer,TerrainGeneratorDesc>
		--- A repository for playlists.
		playlistRep : ResTypeRep<integer,PlaylistDesc>
		--- A resource repository for names.
		nameRep : ResTypeRep<integer,NameDesc>
		--- A resource repository for campaign chapters.
		campaignRep : ResTypeRep<integer,CampaignDesc>
		--- A resource repository for campaign missions.
		missionRep : ResTypeRep<integer,MissionDesc>
	end

	--- The application level resource repositories.
	res : Res

	--- Quit the application.
	--- @param instant immediately quit one exit
	quit : function(instant : boolean)

	--- Restart the application
	restart : function()

	--- Prints memory statistics to the log output.
	printMemoryStats : function()

	--- Starts a new test game by specifying some basic parameters
	--- @param startGameParams start game parameters (optional) - if not set, the game will start with default values
	startGame : function(startGameParams? : StartGameParams)

	--- Starts a new game
	--- @param map the map to use
	--- @param seed the seed use for the map generation
	--- @param startDate the start date
	--- @param startTimeOfDaySeconds is the start time of the day in seconds
	--- @param startCloudCoverage is the start cloud coverage
	--- @param isMapEditor starting from map editor
	--- @param mods list of mods to start the game with
	--- @param configDict list of game settings
	--- @param modParams list of mod params
	startGame2 : function(map : GameMap, seed : string, startDate : Date, startTimeOfDaySeconds : integer, startCloudCoverage : number, isMapEditor : boolean, mods : {Mod.ModId}, configDict : {{string, string}}, modParams : {string : {string : integer}})

	--- Stops the current game.
	stopGame : function()

	--- Obtain list of all savegames.
	--- @param namespace from which to obtain information (see app.SaveGameNamespace.getSavemap() or app.SaveGameNamespace.getSavegame() for the namespaces)
	--- @return a list of all savegame
	findAllSavegames : function(namespace : string) : {SaveGameInfo}

	--- Loads a savegame
	--- @param saveId the savegame id
	--- @param isMapEditor if the savegame is loaded in the map editor
	--- @param info savegame info (optional)
	--- @param isTutorialInit if the savegame is loaded as a tutorial init (optional)
	loadGame : function(saveId : SaveGameId, isMapEditor : boolean, info? : SaveGameData.SaveGameDetails, isTutorialInit? : boolean)
	
	--- Loads a mission
	--- @param saveId the savegame id
	--- @param campaign campaign name
	--- @param mission mission name
	loadMission : function(saveId : SaveGameId, campaign : string, mission : string)

	--- Saves the current game.
	--- @param name the name of the savegame
	--- @param callBack callback when the savegame is finished
	--- @param isMapEditor is saving from the map editor
	--- @param skipSetName skips setting the savegame name as the current default savegame name (optional)
	saveGame : function(name : string, callBack : function(), isMapEditor : boolean, skipSetName? : boolean)

	--- Parse savegame info from its file name
	--- @param savegameName the name of the savegame
	--- @return The info (most notably, savegame type and group name)
	parseSavegameName : function(savegameName : string) : ParsedSavegameName

	--- Get an estimated value of the savegame complexity
	--- @param saveGameDetails the savegame data of the savegame
	--- @return a value that represents the estimate size of the savegame
	getSavegameComplexity : function(saveGameDetails : SaveGameData.SaveGameDetails) : integer

	--- Get an limit for the savegame complexity for the current platform
	--- @return the complexity limit for the current platform
	getSavegameComplexityLimit : function() : integer

	--- Loads savegame metadata asynchronously.
	--- @param saveId the savegame id
	--- @return an async object with the savegame data
	getSavegameInfo : function(saveId : SaveGameId) : Async<SaveGameData>

	--- Obtains the savegame preview image
	-- Note: This is - usually, if not explicitly changed in userdata - the same image as GameMetadata.screenshot but with the full available resolution
	--- @param saveId the savegame id
	--- @return the image, or nil if no preview image is available
	getSavegameImage : function(saveId : SaveGameId) : GameScreenshot | nil

	--- Deletes a savegame
	--- @param saveId the savegame to delete
	--- @return if the savegame was successfully deleted
	deleteSavegame : function(saveId : SaveGameId) : boolean

	--- Obtain the user profile.
	--- @return the user profile
	getUserProfile : function() : UserProfile

	--- Obtains a list of built-in savegames.
	--- @param isMapSave true to list built-in maps, false to list built-in savegames
	--- @return list of savegames
	findBuiltinSavegames : function(isMapSave : boolean) : {SaveGameInfo}

	--- Returns the savegame storage infos
	--- @return savegame storage info
	getSaveGameStorageInfo : function() : SaveGameStorageInfo

	--- Returns the supported MSAA sample counts
	--- @return list of supported sample counts
	getSupportedMSAASampleCounts : function() : {integer}

	--- Load a custom userdata file
	--- @param directory a folder in the userdata directory
	--- @param fileName a lua filename (without .lua extension)
	--- @return the deserialized lua data
	loadUserdata : function(directory : string, fileName : string) : table

	--- Saves a custom table as lua file.
	--- @param directory a folder in the userdata directory
	--- @param fileName the filename to save to (without .lua extension)
	--- @param table the table to serialize
	saveUserdata : function(directory : string, fileName : string, table : table)

	--- Removes a userdata.
	--- @param directory a folder in the userdata directory
	--- @param fileName the filename to remove (without .lua extension)
	removeUserdata : function(directory : string, fileName : string)

	--- Returns a list of all saved mod preset names.
	--- @param directory a folder in the userdata directory
	--- @return a list of mod preset names
	getAllUserdata : function(directory : string) : {string}

	--- Plays a voice over if not currently playing, otherwise stops it.
	--- @param resName the file to play
	playVoiceOverOrStop : function(resName : string)

	--- Creates an empty map (for tooling / map generation workflows).
	--- @param climate climate resource name
	--- @param numTiles map dimension in tiles
	--- @param waterLevel water level height
	--- @return the map
	makeEmptyMap : function(climate : string, numTiles : Vec2i, waterLevel : number) : GameMap

	--- Returns the global input action repository.
	--- @return input action repository
	getInputActionRep : function() : InputActionRep

	--- Refreshes the installed mods
	refreshMods : function()

	--- Wait for the game to be ready to start. This is called when loading a game to prevent the game from starting automatically
	setWaitForStartReadyGame : function()

	--- Return if the `setWaitForStartReadyGame` had been called for this game.
	isWaitForStartReadyGame : function() : boolean

	--- Start Game that is fully loaded and ready to play. This is called after the progress page has finished loading the game.
	startReadyGame : function()

	--- Gets the list of random tips
	---	@return a list of tips as string
	getRandomTips : function() : {string}

	--- Returns a translated name for a mod tag.
	--- @param tag tag to translate
	--- @return the translated tag
	getModTagTranslation : function(tag : string) : string

	--- Gets the load progress monitor 
	getProgressMonitor : function() : ProgressMonitor

	--- Opens the user data folder in the OS file manager
	openUserDataFolder : function()

	--- Opens the heightmaps folder in the OS file manager
	-- @param directory subfolder
	openUserDataSubFolder : function(directory : string)

	--- Gets the directory containing userdata
	getUserDataFolder : function() : string

	--- Gets a list of all heightmaps in the userdata directory
	--- @return list of heightmaps files
	getAllHeightmaps : function() : {string}

	--- Gets a list of all biomes in the userdata directory
	--- @return list of biomes files
	getAllBiomes : function() : {string}

	-- Opens the biomes folder
	openBiomesFolder : function()

	-- Gets the path to the biome folder
	--- @return path to biome folder
	getBiomesFolder : function() : string

	--- Get information about the GPU
	getGPUCapabilities : function() : GPUCapabilities

	--- Writes a heightmap image (and optionally an STL) for a map.
	--- @param map the map to write
	--- @param path the relative path (extension will be added if missing)
	--- @param writeStl write as an STL file as well
	--- @param sixteenBits use 16 bits depth for the heightmap (default 8 bits depth)
	--- @param biomesData if biomes data should as well be exported (will be written in the biomes folder)
	--- @return if the heightmap was successfully written
	writeHeightmap : function(map : GameMap, path : string, writeStl : boolean, sixteenBits : boolean, biomesData : boolean) : boolean

	--- Shows the node editor.
	showNodeEditor : function()

	--- Savegame namespace constants.
	record SaveGameNamespace
		--- Returns the userdata savegame namespace.
		getUserdata : function() : string
		--- Returns the savegame namespace.
		getSavegame : function() : string
		--- Returns the savemap namespace.
		getSavemap : function() : string
	end

	record Debug
		--- Overrides gamepad dynamic scroll repeat speed.
		--- @param speed the scroll speed (0: 1/sec, 3: max speed), or nil to clear the override
		setForcedGamepadDynamicScrollRepeatSpeed : function(speed? : integer)

		--- Pushes a gamepad button event into the input queue.
		--- @param gamepadButtonName the button to push
		--- @param press if pressed
		pushGamepadButtonKeyInputEvent : function(gamepadButtonName : string, press : boolean)
	end
	debug : Debug
end

recordDef = false
