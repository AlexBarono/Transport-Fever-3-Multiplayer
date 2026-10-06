recordDef = true
--- The module is available on both the GUI State and the Engine State (and the Console State as well). However,
-- it works in a slightly different manner depending on where it is used from.
--
-- On the engine states, commands are executed immediately and the effects are immediately noticeable. Moreover, the callback function
-- will be called immediately.
--
-- On the gui and console states, commands are executed in the next simulation step, and the effects are noticeable only after a few frames.
-- The callback function will be called the frame after the command has been executed, after which the changes are visible on the gui and engine
-- state.

--- Journal entry used by journal-related commands.
global type JournalEntry

--- Command object sent via `cmd.sendCommand`.
global record Command<T is ICommandData>
end

--- Marker interface for command data payloads.
global interface ICommandData
end

-- animal

--- Sends a command object to be executed later or immediately depending on the context.
global record AnimalSetStateCommandData is ICommandData
	--- Entity id of the animal that should be updated.
	animalEntity : Engine.Entity
	---  the index of the configuration in the animals metadata movementTypes list
	movementType : integer
	--- Time since the current target destination was selected.
	targetChangedElapsed : number
	--- Time since the animal got into an invalid area.
	invalidTileElapsed : number
	--- speed that should be used.
	movementSpeed : number
	--- angularSpeed angular speed that should be used.
	angularSpeed : number
end

--- Command data for `cmd.makeAnimalSpawnAtCmd`.
global record AnimalSpawnAtCommandData is ICommandData
	---  reference to the animal model that should be spawned.
	modelId : integer
	--- position coordinates of the position where the animal should be spawned.
	position : Vec2f
	--- lookAt the direction the animal is looking.
	lookAt : Vec2f
	--- resultEntity The entity id of the spawned animal, used as a result only.
	resultEntity : Engine.Entity
end

-- custom entity

--- Command data for `cmd.makeCustomEntityDestroyCmd`.
global record CustomEntityDestroyCommandData is ICommandData
	--- Entity id of the custom entity.
	entity : Engine.Entity
end

--- Command data for `cmd.makeCustomEntityCreateCmd`.
global record CustomEntityCreateCommandData is ICommandData
	--- Model id of the custom entity.
	modelId : integer
	--- Created entity id (result only).
	resultEntity : Engine.Entity
end

--- Command data for `cmd.makeCustomEntityUpdateStateCmd`.
global record CustomEntityUpdateStateCommandData is ICommandData
	--- Entity id of the custom entity.
	entity : Engine.Entity
	--- New custom state.
	customState : table
end

--- Command data for `cmd.makeCustomEntityUpdateTransformationCmd`.
global record CustomEntityUpdateTransformationCommandData is ICommandData
	--- Entity id of the custom entity.
	entity : Engine.Entity
	--- New transformation.
	transf : Mat4f
end

--- Command data for `cmd.makeCustomVehicleCreateOrUpdateCmd`.
global record CustomVehicleCreateCommandData is ICommandData
	-- Vehicle entity to update, nil will create a new entity
	vehicleEntity : Engine.Entity

	--- Model id of the custom entity.
	carrier : Carrier
	--- List of carriages to add to the vehicles (model id and reversed status)
	vehicles : {{integer, boolean}}

	--- The move path for aircraft and ships (not all members are utilized, path0 and 2 must be empty and must be in flight state)
	movePathAircraft : Engine.Component.MovePathAircraft

	--- Created entity id (result only).
	resultEntity : Engine.Entity
end

-- entity

--- Command data for `cmd.makeEntitySetColorCmd`.
global record EntitySetColorCommandData is ICommandData
	--- Entity id.
	entity : Engine.Entity
	--- RGB color.
	color : Vec3f
end

--- Command data for `cmd.makeEntitySetEmissionsCmd`.
global record EntitySetEmissionsCommandData is ICommandData
	--- Entity id of the emission emitter.
	entity : Engine.Entity
	--- Noise in power.
	noisePower : number
	--- Pollution in power.
	pollutionPower : number
	--- Emission radius in meters.
	radius : number
end

--- Command data for `cmd.makeEntitySetNameCmd`.
global record EntitySetNameCommandData is ICommandData
	--- id of the entity that should be renamed.
	entity : Engine.Entity
	--- the name that should be set.
	name : string
end

--- Command data for `cmd.makeEntitySetPlayerCmd`.
global record EntitySetPlayerCommandData is ICommandData
	--- Entity id for which the player will be assigned.
	entity : Engine.Entity
	--- Player entity id.
	playerEntity : Engine.Entity
end

-- game

--- Command data for `cmd.makeGameAddPlayerCmd`.
global record GameAddPlayerCommandData is ICommandData
	--- Player name.
	name : string
	--- Player color.
	color : Vec3f
	--- Created player entity id (result only).
	resultEntity : Engine.Entity
end

--- Command data for `cmd.makeGameSetCalendarSpeedCmd`.
global record GameSetCalendarSpeedCommandData is ICommandData
	--- Day length in milliseconds.
	millisPerDay : integer
end

--- Command data for `cmd.makeGameSetDateCmd`.
global record GameSetDateCommandData is ICommandData
	--- New date.
	date : Date
end

--- Command data for saving the game.
global record GameSaveCommandData is ICommandData
	modDescs : {Mod.GameModDesc}
	configData : table
	guiSaveData : table
	fileName : string
	isAutosave : boolean
	isMapsave : boolean
	screenshot : GameScreenshot
	error : integer
end

--- Command data for `cmd.makeGameSetSpeedCmd`.
global record GameSetSpeedCommandData is ICommandData
	--- Simulation speed.
	speedup : integer
end

--- Command data for `cmd.makeGameSetTimeOfDayCmd`.
global record GameSetTimeOfDayCommandData is ICommandData
	--- Time of day in seconds.
	timeOfDaySec : integer
end

--- Command data for `cmd.makeGameSetCloudCoverageCmd`.
global record GameSetCloudCoverageCommandData is ICommandData
	--- new cloud coverage.
	cloudCoverage : number
end

-- industry

--- Command data for `cmd.makeIndustrySetDespawnTimeCmd`._
global record IndustrySetDespawnTimeCommandData is ICommandData
	--- of the building entity of which the despawn timeStamp should change.
	entity : Engine.Entity
	--- time after which the building should be closed.
	timeStamp : integer
end

--- Command data for `cmd.makeIndustrySetManualDevelopmentCmd`.
global record IndustrySetManualDevelopmentCommandData is ICommandData
	--- Industry entity id.
	entity : Engine.Entity
	--- manual whether the entity should manually be developed.
	manual : boolean
end

--- Command data for `cmd.makeCreateIndustryExtendProposalCmd`.
global record CreateIndustryExtendProposalCommandData is ICommandData
	--- Entity id of the industry that should be extended.
	extendConstruction : Engine.Entity
	--- Number of slots to try to extend.
	numTrySlots : integer
	--- Number of slots to keep after the extension.
	numKeepSlots : integer
	--- The resulting proposal generated by the command (result only).
	resultProposal : Proposal
	--- The resulting colliding subconstructions generated by the command (result only).
	resultCollidingSubconstructions : {integer}
end

-- journal

--- Command data for `cmd.makeJournalBookAssetCmd`.
global record JournalBookAssetCommandData is ICommandData
	--- Player entity id.
	playerEntity : Engine.Entity
	--- Journal entry to add.
	journalEntry : JournalEntry
	--- World position of the journal entry.
	position : Vec3f
end

--- Command data for `cmd.makeJournalClearAllCmd`.
global record JournalClearAllCommandData is ICommandData end

--- Command data for `cmd.makeJournalLogEntryCmd`.
global record JournalLogEntryCommandData is ICommandData
	--- Entity to log on.
	entity : Engine.Entity
	--- Log name.
	logName : string
	--- Log time.
	time : number
	--- Log value.
	value : integer
end

-- line

--- Command data for `cmd.makeLineCreateCmd`.
global record LineCreateCommandData is ICommandData
	--- Line configuration.
	line : Engine.Component.Line
	--- new name component of the line.
	name : Engine.Component.Name
	--- new color component of the line.
	color : Engine.Component.Color
	--- new player owned component of the line.
	playerOwned : Engine.Component.PlayerOwned
	--- Created line entity id (result only).
	resultEntity : Engine.Entity
end

--- Command data for `cmd.makeLineDestroyCmd`.
global record LineDestroyCommandData is ICommandData
	--- Line entity id.
	lineEntity : Engine.Entity
end

--- Command data for `cmd.makeLineUpdateCmd`.
global record LineUpdateCommandData is ICommandData
	--- Line entity id.
	lineEntity : Engine.Entity
	--- New line component.
	line : Engine.Component.Line
end

-- scripting

--- Command data for `cmd.makeScriptingSendEventCmd`.
global record ScriptingSendEventCommandData is ICommandData
	--- Filename of the game script that should be the pretended origin of the event.
	fileName : string
	--- Identifier of the element that caused the event.
	id : string
	--- Identifier of the event type.
	name : string
	--- Parameters that depend on the context of the event.
	param : any
end

-- stocklist

--- Command data for `cmd.makeStockListDiscardCargoCmd`.
global record StockListDiscardCargoCommandData is ICommandData
	--- Stock list entity id.
	stockListEntity : Engine.Entity
	--- Stock ids to discard.
	stockIds : {StockId}
	--- Time until the cargo is delivered.
	remainingTimeToDelivery : number
end

--- Command data for `cmd.makeStockListSetStocksCargoTypeCmd`.
global record StockListSetStocksCargoTypeCommandData is ICommandData
	--- Stock list entity id.
	stockListEntity : Engine.Entity
	--- a list of stock ids to set the cargo type
	stockIds : {StockId}
	--- cargoType the cargo type to set, empty to reset
	cargoType : CargoTypeId
end

--- Command data for `cmd.makeStockListSetModifiersCmd`.
global record StockListSetModifiersCommandData is ICommandData
	--- Id of the industry entity of which the departure mode should change.
	entity : Engine.Entity
	--- a struct containing all modifiers applied to the industry.
	modifiers : Engine.Component.StockList.Modifiers
end

-- town

--- Command data for `cmd.makeTownConnectWithIndustriesCmd`.
global record TownConnectWithIndustriesCommandData is ICommandData
	--- Town entity ids to connect.
	townEntities : {Engine.Entity}
	--- Connections as pairs of indices into `townEntities` for start and end destinations
	connections : {{integer, integer}}
	--- Whether to keep existing street connections.
	keep : boolean
end

--- Command to automatically detect connection existing between towns.
global record TownAutoDetectConnectionsCommandData is ICommandData
	--- Entity ids of the towns to detect connections for.
	townEntities : {Engine.Entity}
end

--- Command data for `cmd.makeTownCreateCmd`.
global record TownCreateCommandData is ICommandData
	--- Town creation information.
	towns : {TownInfo}
	--- Whether to update initial land use capacities.
	updateInitialLandUseCapacities : boolean
end

--- Command data for `cmd.makeTownDestroyCmd`.
global record TownDestroyCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
end

--- Command data for `cmd.makeTownDevelopAtCmd`.
global record TownDevelopAtCommandData is ICommandData
	--- World position where development should be triggered.
	position : Vec2f
	--- Whether to develop streets.
	developStreets : boolean
	--- Whether to upgrade buildings.
	upgradeBuildings : boolean
end

--- Command data for `cmd.makeTownCustomDistributionWeightsCmd`.
global record TownCustomDistributionWeightsCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
	--- Level-to-capacity distribution weights for each land use type.
	levelToCapacityDistributionWeights : {{number, number, number, number}, {number, number, number, number}, {number, number, number, number}}
end

--- Command data for `cmd.makeTownSetDevelopmentActiveCmd`.
global record TownSetDevelopmentActiveCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
	--- Whether development should be set to active or inactive.
	developmentActive : boolean
end

--- Command data for `cmd.makeTownSetInitialLandUseCapacitiesCmd`.
global record TownSetInitialLandUseCapacitiesCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
	--- Initial capacities for the three land use types (residential, commercial and industrial).
	initialLandUseCapacities : {integer}
end

--- Command data for `cmd.makeTownUpdateCargoNeedsCmd`.
global record TownUpdateCargoNeedsCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
	--- Cargo needs per district (residential/commercial/industrial).
	cargoNeeds : {{CargoTypeId}}
	--- Whether to update all buildings to their target capacity.
	updateTownBuildings: boolean
end

--- Command data for `cmd.makeTownUpdateSizeCmd`.
global record TownUpdateSizeCommandData is ICommandData
	--- Town entity id.
	townEntity : Engine.Entity
	--- Size factors for residential/commercial/industrial.
	landUseSizeFactors : {number}
	--- Whether to update all buildings to their target capacity.
	updateAllBuildings : boolean
end

-- town building
global record TownBuildingSetBlockedDevelopment is ICommandData
	--- Town building entity id.
	townBuildingEntity : Engine.Entity
	--- Whether to prevent the town developer from changing the town building
	blockedDevelopment : boolean
end


-- vehicle

--- Command data for `cmd.makeVehicleBuyCmd`.
global record VehicleBuyCommandData is ICommandData
	--- Player entity id.
	playerEntity : Engine.Entity
	--- Depot entity id.
	depotEntity : Engine.Entity
	--- config data containing information about the vehicle being purchased.
	config : TransportVehicleConfig
	--- the entity id of the new vehicle, used only as output when the command is successful.
	resultVehicleEntity : Engine.Entity
end

--- Command data for `cmd.makeVehicleReplaceCmd`.
global record VehicleReplaceCommandData is ICommandData
	--- Vehicle entity id.
	vehicleEntity : Engine.Entity
	--- Bew ransport vehicle configuration.
	config : TransportVehicleConfig
	--- Whether to apply the purchase cost of the new vehicle.
	applyPurchaseCost : boolean
end

--- Command data for `cmd.makeVehicleReverseCmd`.
global record VehicleReverseCommandData is ICommandData
	--- Vehicle entity id of the vehicle that should be reversed
	vehicleEntity : Engine.Entity
end

--- Command data for `cmd.makeVehicleSellCmd`.
global record VehicleSellCommandData is ICommandData
	--- Vehicle entity ids.
	vehicleEntities : {Engine.Entity}
end

--- Command data for `cmd.makeVehicleSendToDepotCmd`.
global record VehicleSendToDepotCommandData is ICommandData
	--- Vehicle entity id.
	vehicleEntity : Engine.Entity
	---  if set to true, the vehicle will be sold upon arrival at the depot
	sellOnArrival : boolean
	jumpToDepotEntity : Engine.Entity
end

--- Command data for `cmd.makeVehicleSetLineCmd`.
global record VehicleSetLineCommandData is ICommandData
	--- Vehicle entity id.
	vehicleEntity : Engine.Entity
	--- id of the line on which the vehicle should be sent
	lineEntity : Engine.Entity
	--- the position of the stop on the line to which the vehicle should be sent
	stopIndex : integer
end

--- Command data for `cmd.makeVehicleSetManualDepartureCmd`.
global record VehicleSetManualDepartureCommandData is ICommandData
	--- Id of the vehicle entity of which the departure mode should change
	entity : Engine.Entity
	--- manual whether the entity should wait at the terminal or not
	manual : boolean
end

--- Command data for `cmd.makeVehicleSetModifiersCmd`.
global record VehicleSetModifiersCommandData is ICommandData
	--- Id of the vehicle entity of which the departure mode should change
	entity : Engine.Entity
	--- a struct containing all modifiers applied to the vehicle
	modifiers : Engine.Component.TransportVehicle.Modifiers
end

--- Command data for `cmd.makeVehicleSetStoppedByUserCmd`.
global record VehicleSetStoppedByUserCommandData is ICommandData
	--- id of the vehicle that should be stopped or started
	vehicleEntity : Engine.Entity
	--- true if the vehicle should be stopped
	userStopped : boolean
end

--- Command data for `cmd.makeVehicleTryToDepartCmd`.
global record VehicleTryToDepartCommandData is ICommandData
	--- id of the vehicle that should be stopped or started
	vehicleEntity : Engine.Entity
end

-- world

--- Command data for `cmd.makeWorldBuildProposalCmd`.
global record WorldBuildProposalCommandData is ICommandData
	---  The definition of the proposal
	proposal : Proposal
	--- A context with extra options for the build
	context : Context
	--- tells to ingore costs if set to true
	withCostRep : boolean
	--- tells to ingore costs if set to true
	ignoreErrors : boolean
	--- The resulting data generated by the proposal
	resultProposalData : ProposalData
	--- only relevant when obtained in callback result, after command has been ran
	resultEntities : {{Engine.Entity, Engine.Revision}}
	--- whether dust effect should be created
	doDust : boolean
end

--- Command data for `cmd.makeWorldChangeWindCmd`.
global record WorldChangeWindCommandData is ICommandData
	--- id of the emission grid affected (noise or pollution)
	emissionGridEntity : Engine.Entity
	--- the new wind velocity to set
	wind : Vec2f
end

--- Command data for `cmd.makeWorldReplaceTerrainCmd`.
global record WorldReplaceTerrainCommandData is ICommandData
	map : GameMap
	terrainConfig : BaseConfig.Terrain
	--- a seed for randomization purposes
	seedText : string
	--- id of the world, usually 0
	worldEntity: Engine.Entity
	--- if set to true, existing landscape assets are conserved
	keepAssets : boolean
end

--- Command data for `cmd.makeWorldSetBulldozableCmd`.
global record WorldSetBulldozableCommandData is ICommandData
	---  Id of the entity
	entity : Engine.Entity
	--- true if entity is bulldozable
	value : boolean
end

--- DEBUG

global record SimPersonSetStateCommandDataDEBUG is ICommandData
	entity : Engine.Entity
	type : integer
end

global record ComponentExchangeCommandDataDEBUG is ICommandData
	entity : Engine.Entity
	component : Engine.Component -- Engine.Component.EmissionEmitter|Engine.Component.ModelInstanceList
end

global record StockSetCargoAmountCommandDataDEBUG is ICommandData
	stockListEntity : Engine.Entity
	stock : StockId
	amount : integer
	cargoType : ResName
end

global record GamePerformSimulationStepsCommandDataDEBUG is ICommandData
	amount : integer
end

--- Command data to set new maintenance cost (debug).
global record MaintenanceCostUpdateCommandDataDEBUG is ICommandData
	--- The entity id of the maintenance cost
	maintenanceCostEntity : Engine.Entity
	--- The new maintenance cost amount
	amount : integer
	--- Whether to clean the accumulated cost
	resetAccumulatedCost : boolean
end

--- contains all commmand factory methods.
--- @category main
global record Cmd
	--- Sends a command object to be executed later or immediately depending on the state context. After the execution of the command, the callback function is called.
	-- The callback function receives two parameters:
	-- **cmd** the command that has been executed, depending on the context this might contain additional information.
	-- **success** a boolean value to indicate whether the command was successful
	-- @param cmd the command object to be sent
	-- @param callback an optional function that is called after the execution of the command
	-- @param progress an optional progress object to receive progress updates for long running commands
	sendCommand : function<T is ICommandData>(cmd : Command<T>, 
		callback? : function(data : T, success : boolean, resultEntities : {{Engine.Entity, Engine.Revision}}),
		progress? : CommandProgress)

	-- animal

	--- Makes an AnimalSetState command.
	-- When executed, the animal with the given entity Id will be updated.
	-- @param animalEntity the entity Id of the animal that should be updated
	-- @param movementType the index of the configuration in the animals metadata movementTypes list
	-- @param targetChangedElapsed time since the current target destination was selected
	-- @param invalidTileElapsed time since the animal got into an invalid area
	-- @param movementSpeed speed that should be used
	-- @param angularSpeed angular speed that should be used
	-- @return a newly created AnimalSetState command
	makeAnimalSetStateCmd : function(animalEntity : Engine.Entity, movementType : integer, targetChangedElapsed : number, invalidTileElapsed : number, movementSpeed : number, angularSpeed : number) : Command<AnimalSetStateCommandData>
	--- Makes an AnimalSpawnAt command.
	-- When executed, a new animal entity is spawned at the specified position.
	-- @param fileName reference to the animal model for the animal that should be spawned
	-- @param position world coordinates of the position where the animal should be spawned
	-- @param lookAt the direction the animal is facing in
	-- @return a newly created AnimalSpawnAt command
	makeAnimalSpawnAtCmd : function(fileName : string, position : Vec2f, lookAt? : Vec2f) : Command<AnimalSpawnAtCommandData>

	-- custom entity
	--- Makes a CustomEntityDestroy command.
	-- When executed, the command removes the custom entity with the given entity Id.
	-- @param entity the entity Id of the custom entity
	-- @return a newly created CustomEntityDestroy command
	makeCustomEntityDestroyCmd : function(entity : Engine.Entity) : Command<CustomEntityDestroyCommandData>
	--- Makes a CustomEntityCreate command.
	-- When executed, the command creates a new custom entity with the given model Id.
	-- @param modelId the model id of the custom entity
	-- @return a newly created CustomEntityCreate command
	makeCustomEntityCreateCmd : function(modelId : integer) : Command<CustomEntityCreateCommandData>
	--- Makes a CustomEntityUpdateState command.
	-- When executed, the command updates the state of the custom entity.
	-- @param entity the entity Id of the custom entity
	-- @param customState the new state of the custom entity
	-- @return a newly created CustomEntityUpdateState command
	makeCustomEntityUpdateStateCmd : function(entity : Engine.Entity, customState : ComponentCustomState) : Command<CustomEntityUpdateStateCommandData>
	--- Makes a CustomEntityUpdateTransformation command.
	-- When executed, the command updates the transformation of the custom entity.
	-- @param entity the entity Id of the custom entity
	-- @param transf the new transformation of the custom entity
	-- @return a newly created CustomEntityUpdateTransformation command
	makeCustomEntityUpdateTransformationCmd : function(entity : Engine.Entity, transf : Mat4f) : Command<CustomEntityUpdateTransformationCommandData>

	--- Makes a CustomVehicleCreateOrUpdateCmd command.
	-- When executed, the command updates or creates a custom vehicle entity.
	-- @param vehicleEntity the entity Id of the custom entity, if nil a new entity will be created
	-- @param carrier the carrier for the vehicleEntity (currently must be Air)
	-- @param vehicles a list of carriages, a pair of modelId and whether the model shall be reversed (currently only a single entry)
	-- @param movePathAircraft optional move path for air and water vehicles (currently path0 and path2 must be empty and the state must be in flight)
	-- @return a newly created CustomEntityUpdateTransformation command
	makeCustomVehicleCreateOrUpdateCmd : function(vehicleEntity : Engine.Entity, carrier : Carrier, vehicles : {{integer, boolean}}, 
		movePathAircraft : Engine.Component.MovePathAircraft | nil) : Command<CustomVehicleCreateCommandData>
	
	-- entity
	--- Makes an EntitySetColor command.
	-- When executed, the entity Id is set to the given color.
	-- @param entity the entity Id of the entity that should be colored
	-- @param color the rgb color
	-- @return a newly created EntitySetColor command
	makeEntitySetColorCmd : function(entity : Engine.Entity, color : Vec3f) : Command<EntitySetColorCommandData>
	--- Makes an EntitySetEmissions command.
	-- When executed, the emission values of the entity are set to the given values.
	-- @param entity the entity Id of the entity that should be updated
	-- @param noisePower the noise power of the entity
	-- @param pollutionPower the pollution power of the entity
	-- @param radius the radius of the noise emissions
	-- @param pollutionRadius the radius of the pollution emissions
	-- @return a newly created EntitySetEmissions command
	makeEntitySetEmissionsCmd : function(entity : Engine.Entity, 
			noisePower : number, pollutionPower : number, radius : number, pollutionRadius : number) : Command<EntitySetEmissionsCommandData>
	--- Makes an EntitySetName command.
	-- When executed, the entity Id is renamed with the given name.
	-- @param entity the entity Id of the entity that should be renamed
	-- @param name the new name that should be set
	-- @param forceSameEntity (optional, default false) Unless true, things like stations that don't have a name on their own will set the stem name instead.
	-- @return a newly created EntitySetName command
	makeEntitySetNameCmd : function(entity : Engine.Entity, name : string, forceSameEntity? : boolean) : Command<EntitySetNameCommandData>
	--- Makes an EntitySetPlayer command.
	-- When executed, the entity is set or unset to the player
	-- @param entity the entity Id of the entity
	-- @param player the entity Id of the player
	-- @return a newly created EntitySetPlayer command
	makeEntitySetPlayerCmd : function(entity : Engine.Entity, player : Engine.Entity) : Command<EntitySetPlayerCommandData>

	-- game
	--- Makes a GameAddPlayer command.
	-- When executed, a new player entity is created.
	-- @param name the player's name
	-- @param color the player's color
	-- @return a newly created GameAddPlayer command
	makeGameAddPlayerCmd : function(name : string, color : Vec3f) : Command<GameAddPlayerCommandData>
	--- Makes a GameSetCalendarSpeed command.
	-- When executed, the calendar speed is set to the given value (this affects only the speed of the calendar, and not the simulation speed).
	-- @param millisPerDay day length in milliseconds
	-- @return a newly created GameSetCalendarSpeed command
	makeGameSetCalendarSpeedCmd : function(millisPerDay : integer) : Command<GameSetCalendarSpeedCommandData>
	--- Makes a GameSetDate command.
	-- When executed, the calendar date (for vehicle availability, etc.) is set to the given date.
	-- @param date the new date that should be set
	-- @return a newly created GameSetDate command
	makeGameSetDateCmd : function(date : Date) : Command<GameSetDateCommandData>
	--- Makes a GameSetSpeed command.
	-- When executed, the game (simulation) speed is set to the given value.
	-- @param speedup a positive number: the speed that the simulation will run at
	-- @return a newly created GameSetSpeed command
	makeGameSetSpeedCmd : function(speedup : integer) : Command<GameSetSpeedCommandData>
	--- Makes a GameSetTimeOfDay command.
	-- @param timeOfDaySec a positive number: the time of day in seconds
	-- @return a newly created GameSetTimeOfDay command
	makeGameSetTimeOfDayCmd : function(timeOfDaySec : integer) : Command<GameSetTimeOfDayCommandData>
	--- Makes a GameSetCloudCoverage command.
	-- @param cloudCoverage the current cloud coverage
	-- @return a newly created GameSetCloudCoverage command
	makeGameSetCloudCoverageCmd : function(cloudCoverage : number) : Command<GameSetCloudCoverageCommandData>

	-- industry
	--- Makes an IndustrySetDespawnTime command.
	-- When executed, the command sets a new value to the closure time stamp of the given industry.
	-- @param industryEntity the entity Id of the industry
	-- @param timeStamp sets the despawn time of the industry
	-- @return a newly created IndustrySetDespawnTime command
	makeIndustrySetDespawnTimeCmd : function(industryEntity : Engine.Entity, timeStamp : integer) : Command<IndustrySetDespawnTimeCommandData>
	--- Makes an IndustrySetManualDevelopment command.
	-- When executed, the command sets the industry to manual mode if manual is true, or to automatic development mode if manual is set to false (default).
	-- @param industryEntity the entity Id of the industry
	-- @param manual set to true if industries do not start to close/stop countdown and do not level up or down
	-- @return a newly created IndustrySetManualDevelopment command
	makeIndustrySetManualDevelopmentCmd : function(industryEntity : Engine.Entity, manual : boolean) : Command<IndustrySetManualDevelopmentCommandData>

	--- Makes a CreateIndustryExtendProposal command.
	-- When executed, the command generates a new proposal to extend the given industry.
	-- @param extendConstruction the entity Id of the industry that should be extended
	-- @param numTrySlots the number of slots to try to extend
	-- @param numKeepSlots the number of slots to keep after the extension
	-- @return a newly created CreateIndustryExtendProposal command
	makeCreateIndustryExtendProposalCmd : function(extendConstruction : Engine.Entity, numTrySlots : integer, numKeepSlots : integer) : Command<CreateIndustryExtendProposalCommandData>

	-- journal
	--- Makes a JournalBookAsset command.
	-- When executed, the new journal entry is added to the players journal.
	-- @param player the entity Id of the player
	-- @param entry the entry to add
	-- @param position a position for the event
	-- @return a newly created JournalBookAsset command
	makeJournalBookAssetCmd : function(player : Engine.Entity, entry : JournalEntry, position? : Vec3f) : Command<JournalBookAssetCommandData>
	--- Makes a JournalClearAll command.
	-- When executed, the journal and logbook is cleared
	-- @return a newly created JournalClearAll command
	makeJournalClearAllCmd : function() : Command<JournalClearAllCommandData>
	--- Makes a JournalLogEntry command.
	-- When executed, the log book value is logged.
	-- @param entity the entity Id of the logbook
	-- @param logNamesAndValues a list of log names and values to log, where each entry contains the log name, value and whether the value is incremental
	-- @return a newly created JournalLogEntry command
	makeJournalLogEntryCmd : function(entity : Engine.Entity, logNamesAndValues : {{string, integer, boolean}}) : Command<JournalLogEntryCommandData>

	-- line
	--- Makes a LineCreate command.
	-- When executed, creates a new line with the given parameters.
	-- @param name the name of the new line
	-- @param color the color of the new line
	-- @param player the entity Id of the player owning the line
	-- @param line the configuration data for the line
	-- @return a newly created LineCreate command
	makeLineCreateCmd : function(name : string, color : Vec3f, player : Engine.Entity, line : Engine.Component.Line) : Command<LineCreateCommandData>
	--- Makes a LineDestroy command.
	-- When executed, the line with the given entity Id is removed.
	-- @param lineEntity the line that should be removed
	-- @return a newly created LineDestroy command
	makeLineDestroyCmd : function(lineEntity : Engine.Entity) : Command<LineDestroyCommandData>
	--- Makes a LineUpdate command.
	-- When executed, the line with the given entity Id is updated to the new line configuration.
	-- @param lineEntity the entity Id of the line which should be updated
	-- @param data the new line configuration
	-- @return a newly created LineUpdate command
	makeLineUpdateCmd : function(lineEntity : Engine.Entity, data : Engine.Component.Line) : Command<LineUpdateCommandData>

	-- scripting
	--- Makes a ScriptingSendEvent command.
	-- When executed, a script event will be broadcasted to all scripts.
	-- @param src the filename of the game_script that should be the pretended origin of the event
	-- @param id identifier of the element that caused the event
	-- @param name identifier of the event type
	-- @param param parameters that depend on the context of the event
	-- @return a newly created ScriptingSendEvent command
	makeScriptingSendEventCmd : function(src : string, id : string, name: string, param : any) : Command<ScriptingSendEventCommandData>

	-- stocklist
	--- Makes a StockListDiscardCargo command.
	-- When executed, discards the cargo of the given stock list.
	-- @param stockListEntity the entity Id of the stock list
	-- @param stockIds the list of stock ids
	-- @param remainingTimeToDelivery the time remaining to delivery
	-- @return a newly created StockListDiscardCargo command
	makeStockListDiscardCargoCmd : function(stockListEntity : Engine.Entity, stockIds : {StockId}, remainingTimeToDelivery : number) : Command<StockListDiscardCargoCommandData>
	--- Makes a StockListSetStocksCargoType command.
	-- When executed, sets or resets the cargo type of the given stocks.
	-- @param stockListEntity the entity Id of the stock list
	-- @param stockIds the list of stock ids
	-- @param cargoType the cargo type to set, empty if the cargo type should be reset
	-- @return a newly created StockListSetStocksCargoType command
	makeStockListSetStocksCargoTypeCmd : function(stockListEntity : Engine.Entity, stockIds : {StockId}, cargoType? : CargoTypeId) : Command<StockListSetStocksCargoTypeCommandData>
	--- Makes a StockListSetModifiers command.
	-- Allows changing some properties of industries
	-- @param industryEntity the entity Id of the industry of which the departure mode is to be changed
	-- @param modifiers a struct with the changes to the industry parameters
	-- @return a newly created StockListSetModifiers command
	makeStockListSetModifiersCmd : function(industryEntity : Engine.Entity, modifiers : Engine.Component.StockList.Modifiers) : Command<StockListSetModifiersCommandData>

	-- town
	--- Makes a TownConnectWithIndustries command.
	-- When executed, the command generates a new street network connecting the given towns and all existing industries.
	-- @param townEntities the entity Ids of the towns to connect together
	-- @param connections list with indices into the vector townEntities specifying which towns are to be connected
	-- @param keep set to true if existing street connections should be kept, otherwise the streets will be removed
	-- @return a newly created TownConnectWithIndustries command
	makeTownConnectWithIndustriesCmd : function(townEntities : {Engine.Entity}, connections : {{integer, integer}}, keep : boolean) : Command<TownConnectWithIndustriesCommandData>

	--- Makes a TownAutoDetectConnections command.
	-- When executed, the command tries to detect if an existing connections between towns exists
	-- @param townEntities the entity Ids of the towns to check for connections
	-- @return a newly created TownAutoDetectConnections command
	makeTownAutoDetectConnectionsCmd : function(townEntities : {Engine.Entity}) : Command

	--- Makes a TownCreate command.
	-- When executed, the command initiates the generation of new towns using information contained in TownInfo.
	-- @param towns a list of town creation information, one for each new town
	-- @return a newly created TownCreate command
	makeTownCreateCmd : function(towns : {TownInfo}) : Command<TownCreateCommandData>
	--- Makes a TownDestroy command.
	-- When executed, the town with the given entity Id is removed (all streets and buildings belonging to the town will be removed as well).
	-- @param townEntity the entity Id of the town that should be removed
	-- @return a newly created TownDestroy command
	makeTownDestroyCmd : function(townEntity : Engine.Entity) : Command<TownDestroyCommandData>
	--- Makes a TownDevelopAt command.
	-- When executed, the command triggers development of towns at the given position.
	-- By developing towns, new buildings or street segments are added at the given position.
	-- @param position the position where development should be triggered
	-- @param developStreets develop streets
	-- @param upgradeBuildings upgrade buildings
	-- @return a newly created TownDevelopAt command
	makeTownDevelopAtCmd : function(position : Vec2f, developStreets : boolean, upgradeBuildings : boolean) : Command<TownDevelopAtCommandData>
	--- Makes a TownCustomDistributionWeights command.
	-- When executed, the command sets the level to capacities distribution weights for the town.
	-- @param townEntitiy the entity Id of the town
	-- @param levelToCapacityDistributionWeights level to capacities distribution weights for each land use type
	-- @return a newly created TownCustomDistributionWeights command
	makeTownCustomDistributionWeightsCmd : function(townEntitiy : Engine.Entity, levelToCapacityDistributionWeights? : {{number}}) : Command<TownCustomDistributionWeightsCommandData>
	--- Makes a TownSetDevelopmentActive command.
	-- When executed, the command enables/disables the development of a town.
	-- @param entity the entity Id of the town
	-- @param developmentActive signals whether the town development should be enabled/disabled
	-- @return a newly created TownSetDevelopmentActive command
	makeTownSetDevelopmentActiveCmd : function(entity : Engine.Entity, developmentActive : boolean) : Command<TownSetDevelopmentActiveCommandData>
	--- Makes a TownSetInitialLandUseCapacities command.
	-- When executed, the town with the given entity Id is set to the given initial capacities.
	-- @param entity the entity Id of the town that should be updated
	-- @param landUseCapacities initial capacities for the residential, commercial and industrial. If not provided, capacities are automatically updated
	-- @return a newly created TownSetInitialLandUseCapacities command
	makeTownSetInitialLandUseCapacitiesCmd : function(entity : Engine.Entity, landUseCapacities? : {integer}) : Command<TownSetInitialLandUseCapacitiesCommandData>
	--- Makes a TownUpdateCargoNeeds command.
	-- When executed, the cargo needs of the town districts are updated to the provided needs.
	-- @param entity the entity Id of the town that should be updated
	-- @param cargoNeeds a list of cargo type Ids for the needs of each of the three town districts residential, commercial and industrial
	-- @param updateTownBuildings whether to update all buildings immediately
	-- @return a newly created TownUpdateCargoNeeds command
	makeTownUpdateCargoNeedsCmd : function(entity : Engine.Entity, cargoNeeds : {{CargoTypeId}}, updateTownBuildings : boolean) : Command<TownUpdateCargoNeedsCommandData>
	--- Makes a TownUpdateSize command.
	-- When executed, the town with the given entity Id is set to the given initial capacities.
	-- @param townEntity the entity Id of the town that should be updated
	-- @param sizeFactors initial capacities for the residential, commercial and industrial districts of the town
	-- @param updateAllBuildings whether to update all buildings immediately
	-- @return a newly created TownUpdateSize command
	makeTownUpdateSizeCmd : function(townEntity : Engine.Entity, sizeFactors : {number}, updateAllBuildings : boolean) : Command<TownUpdateSizeCommandData>

	--- Makes a TownBuildingSetBlockedDevelopment command.
	-- When executed, makes buildings "Historic" thatn cannot be changed
	-- @param townBuildingEntity the entity Id of the town building that should be updated
	-- @param blockedDevelopment decides whether to prevent the town developer from changing building
	-- @return a newly created TownBuildingSetBlockedDevelopment command
	makeTownBuildingSetBlockedDevelopmentCmd : function(townBuildingEntity : Engine.Entity, blockedDevelopment : boolean) : Command<TownBuildingSetBlockedDevelopment>

	-- vehicle
	--- Makes a VehicleBuy command.
	-- When executed, a new vehicle is bought and placed in the given depot.
	-- @param playerEntity the entity Id of the player
	-- @param depotEntity the entity Id of the depot in which the vehicle will appear
	-- @param tvc data containing information about the vehicle being purchased
	-- @return a newly created VehicleBuy command
	makeVehicleBuyCmd : function(playerEntity : Engine.Entity, depotEntity : Engine.Entity, tvc : TransportVehicleConfig) : Command<VehicleBuyCommandData>
	--- Makes a VehicleReplace command.
	-- When executed, the vehicle with the given entity Id will be replaced by the new vehicle configuration.
	-- @param vehicleEntity the entity Id of the vehicle that should be replaced
	-- @param tvc data containing information about the new vehicle being purchased
	-- @return a newly created VehicleReplace command
	makeVehicleReplaceCmd : function(vehicleEntity : Engine.Entity, tvc : TransportVehicleConfig) : Command<VehicleReplaceCommandData>
	--- Makes a VehicleReverse command.
	-- When executed, the vehicle with the given entity Id will be reversed.
	-- @param vehicleEntity the entity Id of the vehicle that should be reversed
	-- @return a newly created VehicleReverse command
	makeVehicleReverseCmd : function(vehicleEntity : Engine.Entity) : Command<VehicleReverseCommandData>
	--- Makes a VehicleSell command.
	-- When executed, the vehicle with the given entity Id will be sold.
	-- @param vehicleEntities the entity ids of the vehicles which should be sold
	-- @return a newly created VehicleSell command
	makeVehicleSellCmd : function(vehicleEntities : {Engine.Entity}) : Command<VehicleSellCommandData>
	--- Makes a VehicleSendToDepot command.
	-- When executed, the vehicle with the given entity Id will be sent to the nearest reachable depot and (optionally) be sold.
	-- @param vehicleEntity the entity Id of the vehicle that should be sent to the depot
	-- @param sellOnArrival if set to true, the vehicle will be sold upon arrival at the depot
	-- @param jumpToDepoEntity optional. If provided, then vehicle gets "teleported" to depot
	-- @return a newly created VehicleSendToDepot command
	makeVehicleSendToDepotCmd : function(vehicleEntity : Engine.Entity , sellOnArrival : boolean, jumpToDepoEntity? : Engine.Entity) : Command<VehicleSendToDepotCommandData>
	--- Makes a VehicleSetLine command.
	-- When executed, the vehicle with the provided entity Id is assigned to the line with given entity Id and sent to the stop with the given index.
	-- @param vehicleEntity the entity Id of the vehicle that should be assigned to the line
	-- @param lineEntity the entity Id of the line on which the vehicle should be sent
	-- @param stopIndex the position of the stop on the line to which the vehicle should be sent to
	-- @return a newly created VehicleSetLine command
	makeVehicleSetLineCmd : function(vehicleEntity : Engine.Entity, lineEntity : Engine.Entity, stopIndex : integer) : Command<VehicleSetLineCommandData>
	--- Makes a VehicleSetManualDeparture command.
	-- When an entity with component type TRANSPORT_VEHICLE is set to manual departure
	-- it will not depart from the terminal under any circumstance (the callback will always return success).
	-- If the entity is not a transport vehicle, the command callback will return False.
	-- @param vehicleEntity the entity Id of the vehicle of which the departure mode is to be changed
	-- @param manual whether the entity is managed or not
	-- @return a newly created VehicleSetManualDeparture command
	makeVehicleSetManualDepartureCmd : function(vehicleEntity : Engine.Entity, manual : boolean) : Command<VehicleSetManualDepartureCommandData>
	--- Makes a VehicleSetStoppedByUser command.
	-- When executed, the given vehicle is stopped or started as if the user controlled it in the vehicle dialog.
	-- @param vehicleEntity the entity Id of the vehicle that should be stopped or started
	-- @param stopped stopped true if the vehicle should be stopped
	-- @return a newly created VehicleSetStoppedByUser command
	makeVehicleSetStoppedByUserCmd : function(vehicleEntity : Engine.Entity, stopped : boolean) : Command<VehicleSetStoppedByUserCommandData>
	--- Makes a VehicleSetModifiers command.
	-- Allows changing some properties of transport vehicles
	-- @param vehicleEntity the entity Id of the vehicle of which the departure mode is to be changed
	-- @param modifiers a struct with the changes to the transport vehicle parameters
	-- @return a newly created VehicleSetModifiers command
	makeVehicleSetModifiersCmd : function(vehicleEntity : Engine.Entity, modifiers : Engine.Component.TransportVehicle.Modifiers) : Command<VehicleSetModifiersCommandData>
	--- Makes a VehicleTryToDepart command.
	-- When executed, and the vehicle with entity Id is at the terminal, the vehicle will immediately close
	-- the door and depart as soon as the doors are closed. The vehicle will ignore any departure condition and depart immediately.
	-- The command callback will return success if the entity has a TRANSPORT_VEHICLE component and
	-- is currently waiting at the terminal.
	-- @param vehicleEntity the entity Id of the vehicle at terminal that should depart
	-- @return a newly created VehicleTryToDepart command
	makeVehicleTryToDepartCmd : function(vehicleEntity : Engine.Entity) : Command<VehicleTryToDepartCommandData>

	-- world
	--- Makes a WorldBuildProposal command. This command is used to create new constructions and new streets via scripting.
	-- When executed, the given build proposal is built. The command might fail resulting in the proposal not being built.
	-- @param proposal a proposal containing a preview of the changes that will be applied with this command
	-- @param context a context with extra options for the proposal
	-- @param ignoreErrors a flag enabling the building of the proposal even if non-critical errors are triggered
	-- @param doDust whether dust effect should be created
	-- @param playerInitiated whether the command was initiated by a player
	-- @return a newly created WorldBuildProposal command
	makeWorldBuildProposalCmd : function(proposal : Proposal, context : any, ignoreErrors : boolean, playerInitiated : boolean, doDust? : boolean) : Command<WorldBuildProposalCommandData>
	makeWorldBuildProposalCmd : function(proposal : SimpleProposal, context : any, ignoreErrors : boolean, playerInitiated : boolean, doDust? : boolean) : Command<WorldBuildProposalCommandData>
	--- Makes a WorldChangeWind command.
	-- When executed, the EmissionGrid with the given entity Id is updated to run with the new wind given.
	-- @param emissionGridEntity the entity Id of the game's emission grid
	-- @param wind the new wind
	-- @return a newly created WorldChangeWind command
	makeWorldChangeWindCmd : function(emissionGridEntity : Engine.Entity, wind : Vec2f) : Command<WorldChangeWindCommandData>
	--- Makes a WorldReplaceTerrain command.
	-- When executed, the terrain is replaced. This is similar to the generation in map editor.
	-- @param map an object that specifies the data for the new terrain (heightmap, assets, water level...)
	-- @param terrainConfig configuration parameters for the new terrain
	-- @param seedText a seed for randomization purposes
	-- @param worldEntity the entity Id of the world, usually 0
	-- @param keepAssets if set to true, existing landscape assets are conserved
	-- @return a newly created WorldReplaceTerrain command
	makeWorldReplaceTerrainCmd : function(map : GameMap, terrainConfig : BaseConfig.Terrain, seedText : string, worldEntity : Engine.Entity, keepAssets : boolean) : Command<WorldReplaceTerrainCommandData>
	--- Makes a WorldSetBulldozable command.
	-- Sets whether an entity can be bulldozed or not.
	-- @param entity entity ID
	-- @param bulldozable whether bulldozeable or not
	-- @return a newly created WorldSetBulldozable command
	makeWorldSetBulldozableCmd : function(entity : Engine.Entity, bulldozable : boolean) : Command<WorldSetBulldozableCommandData>

	--- Debug command helpers.
	record Debug
		--- Makes a MaintenanceCostUpdate command.
		-- When executed, the maintenance cost amount is updated
		-- @param maintenanceCostEntity the entity Id of the maintenance cost about to change
		-- @param amount of the new maintenance cost
		-- @param reset the accumulated cost
		-- @return a newly created MaintenanceCostUpdate command
		makeMaintenanceCostUpdateCmd : function(maintenanceCostEntity : Engine.Entity, amount : integer, resetAccumulatedCost : boolean) : Command
		--- Sets the state of a simulated person.
		-- @param entity the entity Id
		-- @param simPersonState the new state
		-- @return a newly created SimPersonSetState command
		makeSimPersonSetStateCmd : function(entity : Engine.Entity, simPersonState :integer) : Command<SimPersonSetStateCommandDataDEBUG>
		--- Sets the happiness value of a simulated person.
		-- @param entity the entity Id
		-- @param happiness the new happiness value
		-- @return a newly created SimPersonSetHappiness command
		makeSimPersonSetHappiness : function(entity : Engine.Entity, happiness : number) : Command
		--- Replaces a component on an entity for debugging purposes.
		-- @param entity the entity Id
		-- @param component the component (EmissionEmitter or ModelInstanceList)
		-- @return a newly created ComponentExchange command
		makeComponentExchangeCmd : function(entity : Engine.Entity, component : Engine.Component) : Command<ComponentExchangeCommandDataDEBUG> -- component is Engine.Component.EmissionEmitter|Engine.Component.ModelInstanceList
		--- Sets the cargo amount for a stock.
		-- @param entity stocklist entity
		-- @param stockId the stock ID
		-- @param amount the cargo amount
		-- @param cargoType optional cargo type URI
		-- @return a newly created StockSetCargoAmount command
		makeStockSetCargoAmountCmd : function(entity : Engine.Entity, stockId : StockId, amount : integer, cargoType? : string) : Command<StockSetCargoAmountCommandDataDEBUG>
		--- Advances the simulation by a given number of steps.
		-- @param amount the number of steps
		-- @return a newly created GamePerformSimulationSteps command
		makeGamePerformSimulationStepsCmd : function(amount : integer) : Command<GamePerformSimulationStepsCommandDataDEBUG>
		--- Clears either town or global logbooks.
		-- @param towns whether to clear town logbooks
		-- @return a newly created ClearLogbooks command
		makeClearLogbooksCmd : function(towns : boolean) : Command
	end
	debug : Debug
end

recordDef = false
