recordDef = true

--- Contains definitions for of api.engine.util

global type JournalEntry

global record UtilTransport
	--- Calc position along a transport edge.
	-- @param eg edge geometry
	-- @param t progress along the edge [ 0, 1 ]
	-- @return position on the edge
	calcPosition : function(eg : EdgeGeometry, t : number) : Vec3f
	--- Calc position along a transport edge.
	-- @param eg edge geometry
	-- @param t progress along the edge [ 0, 1 ]
	-- @param forward optional bool (forward or backward t -> t - 1.0)
	-- @return position on the edge and direction
	calcPositionAndDirection : function(eg : EdgeGeometry, t : number, forward? : boolean) : {Vec3f} -- pos, dir
	--- Transform list of transport modes to a vector of carriers.
	-- @param transportModes list of transport modes
	-- @return carriers for a given set of transport modes
	transportModesToCarriers : function(transportModes : {TransportMode}) : {Carrier}
	--- Obtains the start connection of this edge.
	-- @param edge the edge with direction
	-- @return PortId at the edge's start
	getStartPort : function(edge : {EdgeId, boolean}) : PortId
	--- Obtains the end connection of this edge.
	-- @param edge the edge with direction
	-- @return PortId at the edge's end
	getEndPort : function(edge : {EdgeId, boolean}) : PortId
	--- Check if a port is locked.
	-- @param port the port
	-- @return true if the port is locked, false otherwise
	isPortLocked : function(port : integer) : boolean
end

global record UtilStock
	--- Get stock cargo types.
	-- @param stockListEntity entity containting the stocklist component
	-- @param stockId stock id
	-- @return set of CargoTypeId
	getStockCargoTypes : function(stockListEntity : Engine.Entity, stockId : StockId) : {CargoTypeId}
	--- Get num cargo shipped per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo shipped per year
	getCargoTypeShippedPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo shipped per year
	-- @param stockListEntity list entity
	-- @return num cargo shipped per year
	getCargoShippedPerYear : function(stockListEntity : Engine.Entity) : integer
	--- Get num cargo delivered per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo delivered per year
	getCargoTypeDeliveredPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo delivered (to entity) per year
	-- @param stockListEntity stock list entity
	-- @return num cargo delivered per year
	getCargoDeliveredPerYear : function(stockListEntity : Engine.Entity) : integer
	--- Get num cargo consumed per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo consumed per year
	getCargoConsumedPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo produced per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo produced per year
	getCargoProducedPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo max production per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo max production per year
	getCargoMaxProductionPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo max consumption per year
	-- @param stockListEntity list entity
	-- @param cargoTypeId cargo type id
	-- @return num cargo max consumption per year
	getCargoMaxConsumptionPerYear : function(stockListEntity : Engine.Entity, cargoTypeId : CargoTypeId) : integer
	--- Get inputs and outputs from rules
	-- @param stockListEntity list entity
	-- @return inputs and outputs cargo types
	getInputsOutputsFromRules : function(stockListEntity : Engine.Entity) : {{CargoTypeId}, {CargoTypeId}}
	--- Get the total number of cargo produced per year
	-- @param stockListEntity list entity
	-- @return num cargo produced per year
	getCargoOutputPerYear : function(stockListEntity : Engine.Entity) : integer
	--- Get cargo log value in the last year for cargo type
	-- @param stockListEntity stock list entity
	-- @param logType the logbook type
	-- @param cargoTypeId cargo type
	-- @return cargo log value difference in the last year for cargo type
	getCargoLogValueDiffPerYear : function(stockListEntity : Engine.Entity, logType : string, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo log per year
	-- @param sourceStockListEntity stock list entity
	-- @param targetStockListEntity stock list entity
	-- @param logType the logbook type
	-- @param cargoTypeId the cargo type
	-- @return num cargo shipped per year
	getCargoLogPerYearForTarget : function(sourceStockListEntity : Engine.Entity, targetStockListEntity : Engine.Entity, logType : string, cargoTypeId : CargoTypeId) : integer
	--- Get num cargo log per year
	-- @param sourceStockListEntity stock list entity
	-- @param targetFilter filter function to filter target entities
	-- @param logType the logbook type
	-- @param cargoTypeId the cargo type
	-- @return num cargo shipped per year
	getCargoLogPerYearForTargetFilter : function(sourceStockListEntity : Engine.Entity, targetFilter : function(Engine.Entity) : boolean, logType : string, cargoTypeId : CargoTypeId) : integer
	--- Get stocklist production rating
	-- @param stockListEntity list entity
	-- @return production rating
	getProductionRating : function(stockListEntity : Engine.Entity) : number
	--- Get stock groups by type and cargo types
	-- @param stockListEntity list entity
	-- @param sortByType sort by type
	-- @param showEmpty show empty groups
	-- @return {StockListType, {StockId}, {CargoTypeId}, int} list of stock list type, stock ids, cargo types and count per group
	getStockGroupsByTypeAndCargoTypes : function(
		stockListEntity : Engine.Entity,
		sortByType : boolean,
		showEmpty : boolean,
		producedOnly : boolean) : {{StockListType, {StockId}, {CargoTypeId}, integer}}
	--- Get stock lists with thrown away cargo
	-- @return map of entity to amount thrown away
	getStockListsWithThrownAwayCargo : function() : {Engine.Entity : integer}
	--- Check if any stock is compatible
	-- @param entities list of entities to check
	-- @param cargoTypeId cargo type
	-- @param load whether to check for loading/input (true) or unloading/output (false)
	-- @return true if any stock is compatible
	hasAnyCompatibleStock : function(entities : {Engine.Entity}, cargoTypeId : CargoTypeId, load : boolean) : boolean
	--- Get adjusted delivery time
	-- @param cargoTypeId cargo type
	-- @return adjusted delivery time in seconds
	getAdjustedDeliveryTime : function(cargoTypeId : CargoTypeId) : integer
	--- Check if cargo type is currently produced
	-- @param cargoTypeId cargo type
	-- @return true if cargo type is currently produced
	isCargoTypeCurrentlyProduced : function(cargoTypeId : CargoTypeId) : boolean
end

global record UtilLine 
	record LineCapacityUsage
		--- Currently used capacity
		used : number
		--- Total capacity
		capacity : number
	end

	record PathProblemLocation
		edgeIndex : integer
		node : NodeId
		nodePosition : Vec3f

		--- compatible transport modes present on the last compatible edge (e.g. ELECTRIC_TRAIN)
		okModes : {TransportMode : boolean}

		--- compatible relaxed transport modes on the first incompatible edge.
		--- Example 1: okModes[ELECTRIC_TRAIN], relaxedModes[TRAIN] -> relaxation allowed the use of non-electric train, indicating missing catenaries
		--- Example 2: okModes[TRAM], relaxedModes[ROAD] -> relaxation allowed the use of road instead of tram, indicating missing tram lanes
		--- note that this can never overlap with okModes (otherwise there would not be a problem here)
		relaxedModes : {TransportMode : boolean}

		--- Allowed modes for the line / vehicle in general
		allowedModes : {TransportMode : boolean}
	end

	record TerminalCapacityUsage
		equals : function(TerminalCapacityUsage, TerminalCapacityUsage) : boolean
		--- Currently used capacity
		used : number
		--- Total capacity
		capacity : number
	end

	--- Information about the problem of a line.
	record StopState
		--- No vehicles and less than 2 stops
		empty : boolean
		--- No path between stops
		noPath : boolean
		--- No path from an alternative stop {flattenedTerminalIndex, optional problem location}
		noPathFromAlternative : {integer, PathProblemLocation}
		--- No path to an alternative stop {flattenedTerminalIndex, optional problem location}
		noPathToAlternative : {integer, PathProblemLocation}
		--- Stop is a duplicate
		duplicateStop : boolean
		--- Stop is incompatible with the line's transport mode
		incompatibleStop : boolean
		--- Optional problem location in case of noPath
		noPathLocation : PathProblemLocation
	end

	--- Get line capacity usages.
	-- @param line line entity
	-- @param allCapacities whether to return all capacities or the capacities for the vehicles current load config
	-- @return map of cargo type to capacity usage
	getLineCapacityUsages : function(line : Engine.Entity, allCapacities : boolean) : {CargoTypeId : LineCapacityUsage}
	--- Calc line throughput
	-- @param lineEntity line entity
	-- @return throughput value
	calcLineStationThroughput : function(lineEntity : Engine.Entity) : integer
	--- Get line max frequency
	-- @param lineEntity line entity
	-- @return max frequency
	getMaxFrequency : function(lineEntity : Engine.Entity) : number
	--- Get lines with detailed problems per stop
	-- @param lineEntity line entity
	-- @return list of stop problems
	getDetailedLineProblems : function(lineEntity : Engine.Entity) : {{StopState}}
	--- Get lines with problems
	-- @return list of {line entity, problem type, optional info about 1st problem and its location}
	getLineProblems : function() : {{Engine.Entity, integer, PathProblemLocation}}
	--- Get station problems with lines
	-- @return list of line entity, station group entity and problem type
	getLineStationProblems : function() : {{Engine.Entity, Engine.Entity, LineStationProblem}} 
	--- Check if line is ok with provided carrier
	-- @param lineEntity line entity
	-- @param carrier carrier type
	-- @param distinguishTramFromRoad if tram should not be counted as road
	-- @return true if the line is compatible with the specified carrier
	isLineCompatibleWithCarrier : function(lineEntity : Engine.Entity, carrier : Carrier, distinguishTramFromRoad : boolean) : boolean
	--- Check if line is ok with any of provided carriers
	-- @param lineEntity line entity
	-- @param carriers list of carrier types
	-- @param distinguishTramFromRoad if tram should not be counted as road
	-- @return true if the line is compatible with any of the specified carriers
	isLineCompatibleWithAnyCarrier : function(lineEntity : Engine.Entity, carriers : {Carrier}, distinguishTramFromRoad : boolean) : boolean
	--- Get union of all transport modes offered by all lines stops
	-- @param lineEntity line entity
	-- @return List of transport modes
	getLineTransportModesUnion : function(lineEntity : Engine.Entity) : {TransportMode : boolean}

	--- Check if line supports reservations
	-- @param lineEntity line entity
	-- @return whether line supports reservations
	supportsReservation : function(lineEntity : Engine.Entity) : boolean
	
	--- Get line configuration problems for the line
	-- @param lineEntity line entity
	-- @param allIssues whether to return all issues
	-- @return all line issues of the line
	getLineIssues : function(lineEntity : Engine.Entity, allIssues : boolean) : {LineIssue}
	--- Get line configuration problems for the player lines
	-- @param playerEntity player entity
	-- @param allIssues whether to return all issues
	-- @return all line issues of the lines belonging to the player
	getLinesIssues : function(playerEntity : Engine.Entity, allIssues : boolean) : {Engine.Entity : {LineIssue}}

	--- Get the reason for failed pathfinding search
	-- @param vehicle vehicle entity
	-- @param line line entity
	-- @param fullLine whether to check full line
	-- @return failure reason
	getFailedPathReason : function(vehicle : Engine.Entity, line : Engine.Entity, fullLine? : boolean) : Failure
	--- Get nodes (construction entities) without any road connection
	-- @return list of node entities
	getNoRoadConnectionProblems : function() : {Engine.Entity}
end 

global record UtilLogbook
	--- Get log value difference in the last year for cargo type
	-- @param entity entity with logbook component
	-- @param logName log entry name
	-- @return log value difference in the last year for cargo type
	getLogValuePerYear : function(entity : Engine.Entity, logName : string) : integer
	--- Get most recent log value
	-- @param entity entity with logbook component
	-- @param logName log entry name
	-- @return log value difference in the last year for cargo type
	getLogValueMostRecent : function(entity : Engine.Entity, logName : string) : integer
	--- Get oldest log value
	-- @param entity entity with logbook component
	-- @param logName log entry name
	-- @return oldest log value
	getLogValueOldest : function(entity : Engine.Entity, logName : string) : integer
	--- Log a value
	-- @param entity entity with logbook component
	-- @param logName log entry name
	-- @param value value to log
	logValue : function(entity : Engine.Entity, logName : string, value : integer)
	--- Get chart for logbook
	-- @param logbookEntity entity with logbook component
	-- @param logNames log types
	-- @param xMin Starting value of x-axis (automatically reduced to the lowest x in the data)
	-- @param xMax End value of x-axis (automatically increased to the highest x in the data)
	-- @param yMin Starting value of y-axis (automatically reduced to the lowest y in the data)
	-- @param yMax End value of y-axis (automatically increased to the highest y in the data)
	-- @param ChartConfig config of the chart to get
	-- @return chart result
	getChart : function(
		logbookEntity : Engine.Entity,
		logNames : {string},
		xMin? : number,
		xMax? : number,
		yMin? : number,
		yMax? : number,
		config? : ChartConfig
	) : ChartResult
	--- Get diff chart for logbooks
	-- @param entity entity with logbook component
	-- @param logNames log types
	-- @param config chart config
	-- @return chart result
	getChartDiff : function(entity : Engine.Entity, logNames : {string}, config : ChartConfig) : ChartResult
end

global record UtilChart
	--- Get label for X axis of date charts.
	-- @param config chart config
	-- @param index group index of which the label should be returned
	-- @param abbreviated if label should be for range (true) or point (false)
	-- @return chart label string
	getChartLabel : function(config : ChartConfig, index : integer, abbreviated : boolean) : string

	--- Set the last value for a chart result.
	-- @param chartResult chart result containing the series to be updated
	-- @param series series index of which the last value should be set
	-- @param value value to set as the last value of the series
	setLastValue : function(chartResult : ChartResult, series : integer, value : number)
end

global record UtilOctree
	--- Get entities in given radius and component type
	-- @param center center position
	-- @param radius search radius
	-- @param componentType component type
	-- @return list of entities
	findEntitiesInCircle : function(center : Vec2f, radius : number, componentType : Engine.ComponentType) : {Engine.Entity}
	--- Get transport network nodes in given radius
	-- @param center center position
	-- @param radius search radius
	-- @return list of node IDs
	findTransportNetworkNodesInCircle : function(center : Vec2f, radius : number) : {NodeId}
	--- Check if waypoints are on a line
	-- @param waypoints list of positions
	-- @param lineEntity the line entity
	-- @param tolerance distance tolerance
	-- @return true if waypoints are on line
	areWaypointsOnLine : function(waypoints : { Vec2f }, lineEntity : Engine.Entity, tolerance : number) : boolean
end

global record UtilParallelStrip
	record StripInfo
		carrier : Carrier
		edgeType : BaseEdgeType
		edgeTypeIndex : integer
	end

	--- Get strip information for a parallel strip entity
	-- @param entity parallel strip entity
	-- @return strip information
	getStripInfo : function(entity : Engine.Entity) : StripInfo
	--- Check if entity is a bridge
	-- @param entity parallel strip entity
	-- @return true if bridge
	isBridge : function(entity : Engine.Entity) : boolean
	--- Check if entity is a tunnel
	-- @param entity parallel strip entity
	-- @return true if tunnel
	isTunnel : function(entity : Engine.Entity) : boolean
end

global record UtilPathfinding
	record EdgeIdDirAndLength
		--- Edge ID
		edgeId : EdgeId
		--- Direction
		dir : boolean
		--- Length
		length : number
		--- Generates a new item.
		new : function(edgeId : EdgeId, dir : boolean, length : number) : EdgeIdDirAndLength
	end

	record EdgeIdDir
		--- Edge ID
		edgeId : EdgeId
		--- Direction
		dir : boolean
		--- Generates a new item.
		new : function(edgeId : EdgeId, dir : boolean) : EdgeIdDir
	end

	--- Find a path between starting edges and end destination nodes, using a given set of transport modes.
	-- @param startingEdgesAndLengths Vector of EdgeIdDirAndLength
	-- @param destinationNodes Vector of NodeId
	-- @param transportModeSet Vector of TransportMode
	-- @param maxLength maximum path length
	-- @return a vector with pairs of EdgeId and bool values
	findPath  : function(startingEdgesAndLengths : {EdgeIdDirAndLength}, destinationNodes : {NodeId}, transportModeSet : {TransportMode}, maxLength : number) : {{EdgeId, boolean}}
	
	--- Find a path between starting nodes and end destination nodes, using a given set of transport modes.
	-- @param startNodes Vector of NodeId
	-- @param destinationNodes Vector of NodeId
	-- @param transportModeSet Vector of TransportMode
	-- @return a vector with pairs of EdgeId and bool values
	findPathNodeToNode : function({NodeId}, {NodeId}, {TransportMode}) : {{EdgeId, boolean}}

	getTargetsByLandUse : function() : table

	--- Find a Dubins path between two points with directions
	-- @param p0 first point
	-- @param t0 tangent at p0
	-- @param p1 second point
	-- @param t1 tangent at p1
	-- @param turnRadius maximal turn radius
	-- @return A list of EdgeGeometries and direction
	findDubinsPath : function(p0 : Vec3f, t0 : Vec3f, p1 : Vec3f, t1 : Vec3f, turnRadius : number) : {{EdgeGeometry, boolean}}
end

global record UtilMaintenance
	--- Calculate maintenance cost for a station group
	-- @param stationGroupEntity station group entity
	-- @return maintenance cost
	calcMaintenanceForStationGroup : function(stationGroupEntity : Engine.Entity) : integer

	--- Calculate maintenance cost for a subconstruction
	-- @param subconstructionEntity subconstruction entity
	-- @return maintenance cost
	calcMaintenanceForSubconstruction : function(subconstructionEntity : Engine.Entity) : integer
end

global record UtilVehicle
	--- Searches the best line and depot for the vehicle
	-- @param vehicleEntity the vehicle for which to search the best line and depot
	-- @return line and depot entities, if found
	findBestLineAndDepotForVehicle : function(vehicleEntity : Engine.Entity) : {Engine.Entity, Engine.Entity}

	--- Searches the best depot for the line or position (in case of air vehicles)
	-- @param carrier the carrier to search for
	-- @param transportModes the transport modes to check for connectivity
	-- @param lineEntity the line to search the depot for
	-- @param position the position from which to search (air/water vehicles only)
	-- @return best depot, if any
	findBestDepotForLine : function(carrier : Carrier, transportModes : {TransportMode}, lineEntity : Engine.Entity, position : Vec3f) : Engine.Entity

	--- Get speed of the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return speed
	getSpeed : function(vehicleEntity : Engine.Entity) : number
	--- Get the position of the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return world position
	getPosition : function(vehicleEntity : Engine.Entity) : Vec3f
	--- Get the position, direction and curvature of the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return position and direction information for the vehicle
	calcPathPosData : function(vehicleEntity : Engine.Entity) : PathPosData
	--- Get the direction of the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return direction
	getDirection : function(vehicleEntity : Engine.Entity) : Vec3f
	--- Gets all vehicles using by a given carrier
	-- @param carrier kind of carrier
	-- @return list of vehicle entities
	getVehiclesByCarrier : function(carrier : Carrier) : {Engine.Entity}
	--- Gets all vehicles
	-- @return list of vehicle entities
	getVehicles : function() : {Engine.Entity}
	--- Get running cost of the vehicle per year
	-- @param vehicleEntity vehicle entity
	-- @return running cost
	getRunningCost : function(vehicleEntity : Engine.Entity) : number
	--- Get vehicle depreciated value
	-- @param vehicleEntity vehicle entity
	-- @return depreciated value
	getDepreciatedValue : function(vehicleEntity : Engine.Entity) : integer
	--- Get vehicle part value
	-- @param part transport vehicle part
	-- @return value
	getPartPrice : function(part : TransportVehiclePart) : integer
	--- Get length of the vehicle model
	-- @param modelAsset model asset
	-- @return length
	getLength : function(modelAsset : Model) : number
	--- Get cargo in CargoTypeSet
	-- @param cargoTypeSet cargo type set
	-- @return CargoTypeId in the set
	getAllCargoForCargoTypeSet : function(cargoTypeSet : CargoTypeSet) : {CargoTypeId}
	--- Get list of cargo types loaded in the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return list of cargo types loaded in the vehicle
	getVehicleLoadedCargoTypes : function(vehicleEntity : Engine.Entity) : {CargoTypeId}
	--- Get vehicles with problems
	-- @return vehicle entity and problem
	getVehicleProblems  : function() : {{{Engine.Entity}, VehicleProblem}}
	--- Get vehicle emission penalty in percent
	-- @param maintenanceState maintenance state
	-- @return emission penalty in percent
	getMaintenanceEmissionPenalty : function(maintenanceState : number) : number
	--- Get vehicle comfort penalty in percent
	-- @param maintenanceState maintenance state
	-- @return comfort penalty in percent
	getMaintenanceComfortPenalty : function(maintenanceState : number) : number
	--- Get vehicle top speed penalty in percent
	-- @param topSpeedMaintenanceFactorPenaltyPerLevel penalty factor per level
	-- @param maintenanceState maintenance state
	-- @return top speed penalty in percent
	getMaintenanceTopSpeedPenalty : function(topSpeedMaintenanceFactorPenaltyPerLevel : number, maintenanceState : number) : number
	--- Get vehicle running cost penalty in percent
	-- @param maintenanceState maintenance state
	-- @return running cost penalty in percent
	getMaintenanceRunningCostPenalty : function(maintenanceState : number) : number
	--- Get the vehicle's type
	-- @param vehicleEntity vehicle entity
	-- @return vehicle type
	getVehicleType : function(vehicleEntity : Engine.Entity) : integer -- VehicleIconType
	--- Get vehicle capacities
	-- @param vehicleEntity vehicle entity
	-- @return vehicle capacities
	getVehicleCapacities : function(vehicleEntity : Engine.Entity) : {integer}
	--- Get vehicle unset capacities
	-- @param vehicleEntity vehicle entity
	-- @return vehicle unset capacities for each unset capacity
	getVehicleUnsetCapacities : function(vehicleEntity : Engine.Entity) : {{integer}}
	--- Get vehicle maintenance state
	-- @param vehicleEntity vehicle entity
	getVehicleMaintenanceState : function(vehicleEntity : Engine.Entity) : number
end

global record UtilStation
	record StationUsage
		totalUsed : integer
		overflow : integer
		poolCapacity : integer
		terminalCapacity : integer
	end
	--- Get station usages
	-- @param station station entity
	-- @return total usage, overflow and pool capacity for station
	calculateStationUsage : function(station : Engine.Entity) : StationUsage

	--- Get station terminal usages
	-- @param station station entity
	-- @param terminalIndex terminal index
	-- @return capacity and usage for a terminal (or the pool if terminal is -1)
	calculateStationTerminalUsage : function(station : Engine.Entity, terminalIndex : integer) : UtilLine.TerminalCapacityUsage

	record StationGroupCapacityUsage
		equals : function(StationGroupCapacityUsage, StationGroupCapacityUsage) : boolean

		capacity : integer
		waitingHallCapacity : integer
		used : integer
		overflow : boolean
	end
	--- Get station group cargo usage
	-- @param stationGroup station group entity
	-- @param flatTerminalIndex terminal index
	-- @return capacity and usage + overflow for a StationGroup
	calculateStationGroupCargo : function(stationGroup : Engine.Entity, flatTerminalIndex : integer) : StationGroupCapacityUsage

	--- Check if station supports cargo/passengers
	-- @param stationEntity station entity
	-- @param cargo check for cargo support or passenger support
	-- @return whether station supports cargo/passengers
	isStationOfType: function(stationEntity : Engine.Entity, cargo : boolean) : boolean
	--- Check for stations with overlapping catchment areas
	-- @return list of station group entity pairs
	findStationGroupWithOverlappingCatchmentOfDifferentCarriers : function() : {{Engine.Entity, Engine.Entity}}
end

global record UtilTown 
	record TownReachability
		commercialPrivate : integer
		commercialPublic : integer
		industrialPrivate : integer
		industrialPublic : integer
	end
	record TownCapacityUsage
		used : integer
		capacity : integer
	end
	record TownEmission
		noise : number
		pollution : number
		areaSquareKm : number
	end
	record DestinationUseCount
		count : integer
		linesUseCount : integer
	end

	record TownHappinessStats
		record ByResident
			resident : {integer, integer}
			nonResident : {integer, integer}
		end
		travellingInside : {integer, integer}
		travellingTo : ByResident
		travellingFrom : ByResident
		atBuilding : {integer, integer}
		byCar : {integer, integer}
		walking : {integer, integer}
		byLine : {{Engine.Entity, ByResident}}
	end
	
	--- Get weighted target level to capacities distribution for each land use type for the town
	-- @param townEntity town entity
	-- @return level to capacities distribution
	computeWeightedTargetTownBuildingCapacityPerType : function(townEntity : Engine.Entity) : {{integer, integer, integer, integer}}
	--- Get unweighted target level to capacities distribution for each land use type for the town
	-- @param townEntity town entity
	-- @return level to capacities distribution
	computeUnweightedTargetTownBuildingCapacityPerType : function(townEntity : Engine.Entity) : {{integer, integer, integer, integer}}
	--- Get actual level to capacities distribution for each land use type for the town
	-- @param townEntity town entity
	-- @return level to capacities distribution
	computeActualTownBuildingCapacityPerType : function(townEntity : Engine.Entity) : {{integer, integer, integer, integer}}
	--- Get town available cargo needs
	-- @return map of land use to cargo types
	getLandUse2CargoTypes : function() : {LandUseType : {CargoTypeId}}
	--- Get town reachability
	-- @param townEntity town entity
	-- @return reachability data
	getTownReachability : function(townEntity : Engine.Entity) : TownReachability
	--- Get town emission in power
	-- @param townEntity town entity
	-- @return emission data in power
	getTownEmission : function(townEntity : Engine.Entity) : TownEmission
	--- Get town emission in decibel
	-- @param townEntity town entity
	-- @return emission data in decibel
	getTownEmissionDB : function(townEntity : Engine.Entity) : TownEmission
	--- Get town capacity usage
	-- @param townEntity town entity
	-- @return capacity usage per land use type
	getTownCapacityUsage : function(townEntity : Engine.Entity) : {TownCapacityUsage}
	--- Get number of unhappy people travelling by lines to or from the town
	-- @param townEntity town entity
	-- @param numTopLines number of top lines to consider for the stat
	-- @return number of unhappy and total people travelling by lines
	getTownHappinessStats : function(townEntity : Engine.Entity, numTopLines : integer) : TownHappinessStats
	--- Get town cargo deliveries stats
	-- @param townEntity town entity
	-- @param interval time interval in miliseconds for the stats
	-- @param perLine whether to get stats per line
	-- @param perCargoType whether to get stats per cargo type
	-- @return delivery stats
	getTownDeliveriesStats : function(townEntity : Engine.Entity, interval : integer, perLine : boolean, perCargoType : boolean) : {Engine.Entity : {CargoTypeId : {integer, integer}}}
	--- Obtains information about towns and cargo
	-- @param townEntity the entity of the town
	-- @return map of cargo type to stock and capacity
	getTownStockCargo : function(townEntity : Engine.Entity) : {CargoTypeId : {integer, integer}}
	--- Get the impact of using terrain brush on towns reputation
	-- @param proposal the terrain change proposal
	-- @return the impact change for volume added and volume removed for each town
	getTerrainBrushVolumeImpact : function(proposal : Proposal) : {Engine.Entity : {number, number}}
	--- Get the terrain alignment impact on towns reputation
	-- @param proposalData the proposal data
	-- @return the impact change for volume added and volume removed for each town
	getTerrainAlignmentImpact : function(proposalData : ProposalData) : {Engine.Entity : {number, number}}
	--- Get the impact from auto removal of trees and rocks on towns reputation
	-- @param proposalData the proposal data
	-- @return the impact change for removed trees and rocks for each town
	getAutoRemovalEntityImpact : function(proposalData : ProposalData) : {Engine.Entity : {number, number}}
	--- Get town noise per district
	-- @param townEntity town entity
	-- @param landUseTypes land use types to check
	-- @return average noise and affected capacity per district
	getTownNoisePerDistrict : function(townEntity : Engine.Entity, landUseTypes : {LandUseType}) : {LandUseType : {number, integer}}
	--- Get the impact for reputation the distance has for towns
	-- @param distance distance value
	-- @return the impact from the distance
	getImpactFromDistance : function(distance : number) : number
	--- Get traffic speed for all towns
	-- @param samplesCoefficient coefficient to adjust the number of samples of streets used for traffic rating calculation
	-- @return traffic speed and number of streets per congestion level
	computeTownsTrafficSpeedMap : function(samplesCoefficient : number) : {Engine.Entity : {number, {integer}}}
	--- Get towns with problems
	-- @return town entity and problem
	getTownProblems : function() : {{{Engine.Entity}, TownProblem}}
	--- Check if town is neighbor town
	-- @param townEntity1 town entity
	-- @param townEntity2 town entity
	-- @return whether town is neighbor
	isNeighbourTown : function(townEntity1 : Engine.Entity, townEntity2 : Engine.Entity) : boolean
	--- Get closest town to position
	-- @param position world position
	-- @return closest town entity
	getClosestTown : function(position : Vec3f) : Engine.Entity
	--- Get a random 2d point inside the voronoi cell of the town
	-- @param townEntity the town in which to search
	-- @param seed a random seed for the generation
	-- @return a point inside the town voronoi cell
	getRandomTownPosition : function(townEntity : Engine.Entity, seed : integer) : Vec2f
	--- Check if Line has at least 1 stop in the town's area
	-- @param lineEntity line entity
	-- @param townEntity town entity
	-- @return whether line stops in town
	isLineStoppingInTown : function(lineEntity : Engine.Entity, townEntity : Engine.Entity) : boolean
	--- Get town line usage
	-- @param townEntity town entity
	-- @return fraction of people using lines in the town
	getTownLineUsage : function(townEntity : Engine.Entity) : number
	--- Get town destinations table content (work, shop and line usage info)
	-- @param townEntitiy town entity
	-- @param destinationIsTownMap map of entity to isTown (destinations of town)
	-- @param selectLandUse 0 (Usage), 1 (Shopping), 2 (Work)
	-- @return destination use counts
	getSourceToDestinationCount : function(townEntitiy : Engine.Entity, destinationIsTownMap : {Engine.Entity : boolean}, selectLandUse : integer) : {Engine.Entity : DestinationUseCount}
	--- Get the district center of the town entity
	-- @param entity town entity
	-- @param landUseTypes land use types to check
	-- @return destination use counts
	getTownDistrictCenter : function(entity : Engine.Entity, landUseType : LandUseType) : Vec3f
end

global record UtilCargo
	--- Check if a cargo is in time / a person is happy
	-- @param sim cargo or person entity
	-- @return true if good quality
	isGoodQuality: function(passengerOrCargoEntity : Engine.Entity) : boolean

	record CargoQualityData
		userdata
		clone : function(CargoQualityData) : CargoQualityData

		countBad : integer
		countTotal : integer
		averageQuality : number | nil
		isVeryBad : boolean
	end
	record SummarizedCargoQualityData
		userdata
		clone : function(SummarizedCargoQualityData) : SummarizedCargoQualityData

		passengers : CargoQualityData
		cargo : CargoQualityData
	end
	--- Get cargo type quality data in a line.
	-- @param lineEntity line entity
	-- @param cargoTypeId cargo type (passengers allowed)
	-- @return data about cargo quality
	getCargoQualityDataForLine : function(lineEntity : Engine.Entity, cargoTypeId : CargoTypeId) : UtilCargo.CargoQualityData
	--- Get cargo type quality data in a vehicle.
	-- @param vehicleEntity vehicle entity
	-- @param cargoTypeId cargo type (passengers allowed)
	-- @return data about cargo quality
	getCargoQualityDataForVehicle : function(vehicleEntity : Engine.Entity, cargoTypeId? : CargoTypeId) : UtilCargo.CargoQualityData

	--- Get all persons waiting at a station plus the number of unhappy ones.
	-- @param stationEntity station entity
	-- @param cargoTypeId the cargo type (passengers allowed)
	-- @return cargo quality data
	getCargoQualityDataAtStation : function(stationEntity: Engine.Entity, cargoTypeId : CargoTypeId) : UtilCargo.CargoQualityData
	--- Get all persons waiting at station group plus the number of unhappy ones.
	-- @param stationGroupEntity station group entity
	-- @param cargoTypeId the cargo type (passengers allowed)
	-- @return cargo quality data
	getCargoQualityDataAtStationGroup : function(stationGroupEntity: Engine.Entity, CargoTypeId) : UtilCargo.CargoQualityData
	--- Get all persons waiting at a certain line stop plus the number of unhappy ones.
	-- @param lineEntity line entity
	-- @param stopIndex index of stop
	-- @param cargoTypeId the cargo type (passengers allowed)
	-- @return cargo quality data
	getCargoQualityDataAtStop : function(lineEntity : Engine.Entity, stopIndex : integer, CargoTypeId) : UtilCargo.CargoQualityData
	--- Get all persons waiting at a certain terminal plus the number of unhappy ones.
	-- @param stationGroupEntity station group entity
	-- @param stationTerminal the affected station and terminal indices
	-- @param cargoTypeId the cargo type (passengers allowed)
	-- @return cargo quality data
	getCargoQualityDataAtTerminal : function(stationGroupEntity : Engine.Entity, stationTerminal : StationTerminal, CargoTypeId) : UtilCargo.CargoQualityData
	--- Get stock list cargo type quality.
	-- @param stockListEntity stockList entity
	-- @param cargoTypeId the cargo type (passengers allowed but doesn't make sense)
	-- @return cargo quality data
	getCargoQualityDataForStockList : function(stockListEntity : Engine.Entity, CargoTypeId) : UtilCargo.CargoQualityData		
	--- Get stock cargo type quality (over all cargo types).
	-- @param stockListEntity stockList entity
	-- @param stockId stock id inside the stock list
	-- @param cargoTypeId the cargo type (passing nil will aggregate over all cargo types)
	-- @return cargo quality data
	getCargoQualityDataForStock : function(stockListEntity : Engine.Entity, StockId, ?CargoTypeId) : UtilCargo.CargoQualityData

	--- Get stock list cargo type quality (over all cargo types).
	-- @param stockListEntity stockList entity
	-- @return cargo quality data
	getSummarizedCargoQualityDataForStockList : function(stockListEntity : Engine.Entity) : UtilCargo.SummarizedCargoQualityData
	--- Get cargo type quality summary.
	-- @param lineEntity line entity
	-- @return cargo quality data
	getSummarizedCargoQualityDataForLine : function(lineEntity : Engine.Entity) : UtilCargo.SummarizedCargoQualityData
	--- Get cargo type quality summary.
	-- @param vehicleEntity vehicle entity
	-- @return cargo quality data
	getSummarizedCargoQualityDataForVehicle : function(vehicleEntity : Engine.Entity) : UtilCargo.SummarizedCargoQualityData

	--- Get total amount of cargo loaded in the vehicle
	-- @param vehicleEntity vehicle entity
	-- @return number of cargo items per type
	getNumCargoPerTypeInVehicle : function(vehicleEntity : Engine.Entity) : {integer}
end

global record UtilConstruction
	--- Get total number of auto fill slots and number of filled auto fill slots.
	-- @param entity construction entity
	-- @return num filled auto fill slots
	getNumAndFilledAutoFillSlots : function(entity : Engine.Entity) : {integer, integer}
	--- Gets construction entity for the entity.
	-- @param depotEntity the entity for which the containing construction should be fetched
	-- @return construction entity
	getConstructionEntity : function (depotEntity : Engine.Entity) : Engine.Entity
	--- Get slot types of construction.
	-- @param entity construction entity
	-- @return slot types
	getSlotTypes : function(entity : Engine.Entity) : {string}
	--- Get construction result for a given construction.
	-- @param constructionResName resource name of the construction
	-- @param constructionTemplate template index
	-- @param parameters parameters for the updateFn
	-- @return construction result
	getConstructionResult : function(constructionResName : ResName, constructionTemplate : integer, parameters : table) : ConstructionResult
	--- Get global construction params
	-- @return global construction parameters
	getGlobalConstructionParams : function() : {string : number}
	--- Get cost multiplier for year
	-- @param costMultipliers cost multipliers by year
	-- @param currentYear current year
	-- @return cost multiplier
	getCostMultiplierForYear : function(costMultipliers : {integer : number}, currentYear : integer) : number
	--- Get street segments to remove when a construction entity is removed
	-- @param constructionEntity the construction entity we want to find segments for
	-- @param keepIndustryRoads (default = false) whether to keep the segments that are built with the industry
	-- @return the street segments to remove
	findSegmentsToDelete : function(constructionEntity : Engine.Entity, keepIndustryRoads? : boolean) : {Engine.Entity}
end

global record UtilFinance
	--- Get chart for account (income and costs).
	-- @param entity entity with account component
	-- @param config chart config
	-- @return chart result
	getAccountChart : function(entity : Engine.Entity, config : ChartConfig) : ChartResult
	--- Get chart for debts.
	-- @param entity entity with account component
	-- @param config chart config
	-- @return chart result
	getDebtChart : function(entity : Engine.Entity, config : ChartConfig, currentDebt : integer) : ChartResult
	--- Get (summed) balance of entities
	-- @param entities (having an account)
	-- @param begin time (interval)
	-- @param end time (interval)
	-- @param true if only maintenance/income entries are to be considered
	-- @param only consider for given maintenance type (use nil for all)
	-- @return (summed) balance over given interval's time
	calculateBalance : function(entities : {Engine.Entity}, startTime : integer, endTime : integer, maintenanceIncomeOnly : boolean, maintenanceTye? : JournalEntry.Maintenance) : integer
	--- Get the earnings from beginning of the year to now
	-- @param playerEntity player entity
	-- @return earnings
	calculateEarnings : function(playerEntity : Engine.Entity) : integer
	--- Get current state of fincance table.
	-- @param playerEntity player entity
	-- @param config config of chart behind the table
	-- @return struct holding all the relevant values
	computeFinanceTable : function(playerEntity : Engine.Entity, config : ChartConfig) : FinanceData
	--- Get balance of the player's bank account.
	-- @param playerEntity the player entity
	-- @return balance or nil, if player has won the lottery and money is infinite
	getPlayersBalance : function(playerEntity : Engine.Entity) : integer
	--- The income since the specified time (non-inclusive).
	-- @param current game time
	-- @param playerEntity the player entity
	-- @return The income
	calcIncomeSince : function(time : number, playerEntity : Engine.Entity) : number
	--- The time of the last income.
	-- @param playerEntity the player entity
	--- @return The time of the last income entry
	getLastIncomeTime : function(playerEntity : Engine.Entity) : integer
	---  The time of the first income.
	-- @param playerEntity the player entity
	--- @return The time of the first income entry
	getFirstIncomeTime : function(playerEntity : Engine.Entity) : integer
end

global record UtilEmission
	--- Get current emission at entity.
	-- @param entity the entity with Emission component
	-- @param type emission type
	-- @return emission value
	getCurrentEmission : function(entity : Engine.Entity, type : Engine.Component.EmissionGrid.Type) : number
	--- Get all pollution emitters in settlement area.
	-- @param entity the town entity
	-- @return list of emitters with emission values
	getPollutionEmittersInSettlementArea : function(entity : Engine.Entity) : {{Engine.Entity, number}}
	---Get all noise emitters near land uses of a settlement.
	-- @param entity the settlement entity
	-- @param distance maximum distance
	-- @param landUseTypes land use type filter
	-- @return list of emitters with emission values
	getNoiseEmittersNearSettlementLandUses : function(entity : Engine.Entity, distance : number, landUseTypes : {LandUseType}) : {{Engine.Entity, number}}
end

global record UtilHeadquarters
	--- Obtains the transportation data.
	-- @return some transportation statistics for the company
	getTransportedData : function() : TransportationStats
	--- Obtains the companie's value
	-- @return company value data
	getCompaniesValue : function() : CompanyValue
end

global record UtilIndustry
	record IndustryProductivityInfo
		producing : boolean
		boostFromRule : boolean
		boostFromPersonCapacity : boolean
	end
	---Get the industry's productivity
	-- @param entity the industry entity
	-- @return productivity info
	getIndustryProductivityInfo : function(entity : Engine.Entity) : IndustryProductivityInfo
	--- Get list of industries that are closing
	-- @return list of industry entities and their resource names
	getClosingIndustries : function() : {{Engine.Entity, ResName}}

	---Get the cargo dependencies of an economy
	-- @param economyId the economy id
	-- @return A map from cargoTag to a map of industryTag to count
	getEconomyCargoDependencies : function(economyId : integer) : {string : {string : number}}
end

global record UtilProposal
	makeProposalData : function(proposal : Proposal, context? : Context) : ProposalData
	--- Tries to generate a proposal for randomly placing an industry.
	-- @param industryTypeTag The type of the industry
	-- @param townEntity the town designating the target voronoi cell (or nil to spawn anywhere in the world)
	-- @return the generated proposal, or nil
	makeIndustrySpawnProposal : function(typeTag : string, townEntity? : Engine.Entity) : Proposal
	--- Makes a proposal to remove segments
	-- @param segmentsToRemove list of segments to remove
	-- @return the generated proposal
	makeSegmentsRemoveProposal : function(segmentsToRemove : {Engine.Entity}) : Proposal
	--- Tries to generate a proposal to remove a construction
	-- @param entity the entity to remove
	-- @param context construction context
	-- @return the generated proposal, or nil
	createProposalRemove : function(entity : Engine.Entity, context : Context) : Proposal
	--- Replaces an existing construction with a new one
	-- @param entity the entity to replace
	-- @param params parameters for the new construction
	-- @param newResName resource name of the new construction (if nil, the same as the old one is used)
	-- @return the generated proposal, or nil
	createProposalReplaceConstruction : function(entity : Engine.Entity, params : table, newResName? : ResName) : Proposal
	--- Tries to generate a proposal to build an industry
	-- @param seed random seed
	-- @param industryRectangle industry rectangle data
	-- @param context construction context
	-- @return the generated proposal, or nil
	createIndustryProposal : function(seed : string, industryRectangle : IndustryInfo, context : Context) : Proposal
	--- Creates a bridge or tunnel proposal for changing the type of a parallel strip entity.
	-- @param parallelStripEntity parallel strip entity
	-- @param newTypeIndex new resource type index for bridge or tunnel
	-- @return the generated proposal
	createBridgeOrTunnelProposal : function(parallelStripEntity : Engine.Entity, newTypeIndex : integer) : Proposal
	--- Creates a double slip switch proposal for changing the switch type of a base node configuration entity.
	-- @param entity base node entity
	-- @param doubleSlipSwitch double slip switch true to create double slip switch, false for single slip switch
	createDoubleSlipSwitchProposal : function(entity : Engine.Entity, doubleSlipSwitch : boolean) : Proposal
	--- Creates a proposal that changes the traffic light configuration of a base node
	-- @param entity base node entity
	-- @param trafficLightConfig the configuration of traffic light, including phases and type
	-- @param trafficLightPreference whether a traffic light should be generated or not (or automtically decided)
	createTrafficLightProposal : function(entity : Engine.Entity, trafficLightConfig : Engine.Component.TrafficLightConfig, trafficLightPreference : TrafficLightPreference) : Proposal
	--- Gets bridge or tunnel related revisions for a parallel strip entity.
	-- @param parallelStripEntity parallel strip entity
	-- @return map of entity to revision
	getBridgeOrTunnelRelatedRevisions : function(parallelStripEntity : Engine.Entity) : {Engine.Entity:Engine.Revision}
	--- Checks if bridge or tunnel related revisions changed for a parallel strip entity.
	-- @param parallelStripEntity parallel strip entity
	-- @param revisions map of entity to revision
	-- @return true if any related revision changed
	didBridgeOrTunnelRelatedRevisionsChange : function(parallelStripEntity : Engine.Entity, revisions : {Engine.Entity:Engine.Revision}) : boolean
	--- Creates a reforestation proposal.
	-- @param seed random seed
	-- @param numTilesToUpdate maximum number of tiles being updated
	-- @param maxTreesPerTile maximum number of trees planted per tile
	-- @return the generated proposal
	makeReforestationProposal : function(seed : integer, numTilesToUpdate : integer, maxTreesPerTile : integer) : Proposal
	--- Refreshes a construction. This returns a proposal that needs to be applied with a `makeWorldBuildProposalCmd`
	--- @param entity the entity with a construction to refresh
	--- @param constructionFilepath the construction to refresh the entity with
	--- @return a proposal for the refreshed construction
	refreshConstruction : function(entity : Engine.Entity, constructionFilepath? : string) : Proposal

	--- Refreshes a street/track segment (base edge). This returns a proposal that needs to be applied with a `makeWorldBuildProposalCmd`
	--- @param entity the entity with a construction to refresh
	--- @param streetTemplate the street template file path to refresh the entity with (optionally). Use with caution.
	--- @return a proposal for the refreshed segment
	replaceSegment : function(entity : Engine.Entity, streetTemplate? : ResName) : Proposal

	--- Check if a street proposal connects the start node to the target node.
	-- @param startNode the starting base node entity
	-- @param startEdge the starting base edge entity
	-- @param targetNode the target node entity
	-- @param streetProposal the street proposal to check
	-- @param isApply whether the proposal is being applied
	-- @param maxDepth (optional) specify a maximum distance which is traversed in the network
	-- @return true if the proposal connects the nodes
	checkProposalConnectsNodes : function(startNode : Engine.Entity, startEdge : Engine.Entity, targetNode : Engine.Entity, streetProposal : Proposal.StreetProposal, isApply : boolean, maxDepth? : number) : boolean

	--- Create proposal to extend industry
	-- @param industry industry entity
	-- @param trySlots number of slots to try extending to
	-- @param numExtendSlots number of slots to extend
	-- @return the proposal and (if it is colliding) indices of colliding subconstructions
	makeIndustryExtendProposal : function(industry : Engine.Entity, trySlots : integer, numExtendSlots : integer) : {Proposal, {integer}}

	createSubconstructionLotList : function(subconstruction : Proposal.Subconstruction, transf : Mat4f) : Engine.Component.LotList

	--- Calculate the area of new constructions in the proposal.
	-- @param proposal the proposal to calculate the area for
	-- @return the approximate area of new constructions in the proposal in square meters
	getConstructionArea : function(proposal : Proposal) : number
end

--- Collection of engine specific utils grouped by system
--- @category main
global record EngineUtil
	--- Obtains the player entity.
	-- @return entity id
	getPlayer : function() : Engine.Entity
	--- Obtains the world entity.
	-- @return entity id
	getWorld : function() : Engine.Entity
	--- Return the calendar date of the gametime, assuming current ingame speed.
	-- @param gameTime gametime for which to obtain the date
	-- @return calendar date matching the game time at the current speed
	getCalendarDate : function(gameTime : number) : Date
	-- Return year of the gametime
	-- @treturn integer calendar year matching the game time at the current speed
	getYear : function() : integer
	--- Returns true if currently an active mission, started from the menu, is running
	-- @return true if mission is running
	hasStartedAsMission : function() : boolean
	
	--- Get name of an (existing) entity, computing it from the base construction if needed.
	-- @return string Entity name, or nil
	getEntityName : function(entity : Engine.Entity) : string

	--- Get name stem of an (existing) entity
	-- @return string Entity name and Entity where the stem came from (both can be nil)
	getEntityNameStem : function(entity : Engine.Entity) : {string, Engine.Entity}

	cargo : UtilCargo
	construction : UtilConstruction
	chart : UtilChart
	finance : UtilFinance
	headquarters : UtilHeadquarters
	line : UtilLine
	logbook : UtilLogbook
	maintenance : UtilMaintenance
	octree : UtilOctree
	parallelStrip : UtilParallelStrip
	pathfinding : UtilPathfinding
	station : UtilStation
	stock : UtilStock
	town : UtilTown
	transport : UtilTransport
	vehicle : UtilVehicle
	industry : UtilIndustry
	proposal : UtilProposal
	emission : UtilEmission

	--- Format age of a vehicle using current ingame speed.
	-- @param begin timestamp of the time interval
	-- @param end timestamp of the time interval
	-- @return formatted output, e.g. "6 years"
	formatAge : function(time0 : integer, time1 : integer) : string
end

recordDef = false
