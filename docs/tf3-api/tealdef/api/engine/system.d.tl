recordDef = true

--- Contains definitions for of api.engine.system

global interface ISystem 
	forEach : function(Engine.Entity)
end

--- Line System.
-- Contains cached information about lines.
global record LineSystem
	--- Gets all lines on the map.
	--- @return line entities
	getLines : function() : {Engine.Entity}
	--- Gets all lines belonging to the player.
	--- @param playerEntity the player for which the lines should be fetched
	--- @return line entities
	getLinesForPlayer : function(playerEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all lines going through a waypoint.
	--- @param waypointEntity the waypoint for which the lines should be fetched
	--- @return line entities
	getLinesForWaypoint : function(waypointEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all line waypoints at the specific signal+lane
	--- @param waypointEntity the signalList entity
	--- @param signalIndex the signal index inside the SignalList
	getLinesForWaypointLane : function(waypointEntity : Engine.Entity, signalIndex : integer) : {{Engine.Entity, integer, integer}}
	--- Gets all lines stopping at a station group.
	--- @param stationGroupEntity the stationGroup for which the lines should be fetched
	getLineStops : function(stationGroupEntity : Engine.Entity) : {{Engine.Entity, integer}}
	--- Gets all lines stopping at a station.
	--- @param stationEntity the station for which the lines should be fetched
	getLineStopsForStation : function(stationEntity : Engine.Entity) : {{Engine.Entity, integer}}
	--- Gets all lines stopping at a terminal.
	--- @param stationEntity the station for which the lines should be fetched
	--- @param terminal the terminal of the station for which the lines should be fetched
	getLineStopsForTerminal : function(stationEntity : Engine.Entity, terminal : integer) : {{Engine.Entity, integer}}
	--- Gets all lines for the given station group.
	--- @param stationGroup the stationGroup for which the lines should be fetched
	--- @return line entities
	getLinesForStationGroup : function(stationGroup : Engine.Entity) : {Engine.Entity}
	--- Gets all lines having an issue, and the issue in question.
	--- @param playerEntity the player for which the lines should be fetched
	getProblemLines : function(playerEntity : Engine.Entity) : {{Engine.Entity, LineProblem}}
	--- Gets all stops in a station group.
	getStationGroup2LineStopsMap : function() : {Engine.Entity : {{Engine.Entity, integer}}}
	--- Gets all stops in a terminal.
	getTerminal2lineStops : function() : {{Engine.Entity, integer} : {{Engine.Entity, integer}}}
	--- Gets best terminal assignments for line.
	--- @param lineEntity the line for which the computation should happen
	--- @param lineData the line component data, stops may have station = -1 and terminal = -1
	--- @param allowTerminalChanges
	getBestLineAssignment : function(lineEntity : Engine.Entity, lineData : Engine.Component.Line, allowTerminalChanges : boolean) : {StationTerminal}
end

--- Station System.
-- Contains cached information about stations.
global record StationSystem
	--- Gets all transport network nodes associated with a station terminal.
	getPersonNodeId2StationTerminalsMap : function() : {NodeId : {{Engine.Entity, integer}}}
	--- Gets a map from stations to towns.
	getStation2TownMap : function() : {Engine.Entity : Engine.Entity}
	--- Gets all stations in a town.
	--- @param townEntity the entity of the town that is queried for
	getStations : function(townEntity : Engine.Entity) : {Engine.Entity}
	--- Gets the station terminal to which the node belongs.
	--- @param nodeId the vehicle node id that is queried for
	getStationTerminalForVehicleNode : function(nodeId : NodeId) : {Engine.Entity, integer}
	--- Gets the station terminals to which the person edge belongs.
	--- @param nodeId the edge id that is queried for
	getStationTerminalsForPersonEdge : function(edgeId : EdgeId) : {{Engine.Entity, integer}}
	--- Gets the station terminals to which the person node belongs.
	--- @param nodeId the person node id that is queried for
	getStationTerminalsForPersonNode : function(nodeId : NodeId) : {{Engine.Entity, integer}}
	--- Gets all station grouped by towns.
	getTown2StationsMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Gets a the town of the station.
	--- @param stationEntity the entity of the station that is queried for
	getTown : function(stationEntity : Engine.Entity) : Engine.Entity
	--- Gets the mapping from vehicle node to station terminal.
	getVehicleNodeId2StationTerminalsMap : function() : {NodeId : {{Engine.Entity, integer}}}
	--- Loops over all stations.
	forEach : function(Engine.Entity)
end

--- Station Group System.
-- Contains cached information about station groups.
global record StationGroupSystem
	--- Gets station groups that no longer contain stations and are thus about to be removed.
	--- @param time the time stamp until when the stations with this condition are removed
	getExpiredStationGroups : function(time : integer) : {Engine.Entity}
	--- Gets progress on the removal of station groups.
	--- @param stationGroupEntity the entity of the station group that is about to be removed
	--- @param time the time for which th progress is requested
	getExpiryProgress : function(stationGroupEntity : Engine.Entity, time : integer) : number
	--- Obtains the station group to which the station belongs.
	--- @param stationEntity the entity of the station for which the parent station group is queried
	getStationGroup : function(stationEntity : Engine.Entity) : Engine.Entity
	--- Gets the carriers of the station / terminal.
	--- @param stationGroup entity
	--- @param station The station index (or -1 to get superset over all terminals)
	--- @param terminal The terminal index inside the station (or -1 if station == -1)
	getCarriers : function(stationGroup : Engine.Entity, station : integer, terminal : integer) : {{Carrier}, {TransportMode}}
end

--- Town Building System.
-- Manages town buildings and parcels.
global record TownBuildingSystem
	--- Obtains the building (if any) that is placed on the given parcel.
	--- @param parcelEntity the entity of the parcel
	getBuilding : function(parcelEntity : Engine.Entity) : Engine.Entity
	--- Obtains information about towns and cargo.
	--- @param townEntity the entity of the town
	getCargoSupplyAndLimit : function(townEntity:Engine.Entity, landUse? : LandUseType) : {CargoTypeId:{number, number, integer}}
	--- Obtains information about land use and person capacities.
	--- @param townEntity the entity of the town
	getLandUsePersonCapacities : function(townEntity : Engine.Entity) : {integer}
	--- Obtains map from parcel to building occupying the parcel.
	getParcel2BuildingMap : function() : {Engine.Entity : Engine.Entity}
	--- Obtains map from person capacities to town buildings.
	getPersonCapacity2townBuildingMap : function() : {Engine.Entity : Engine.Entity}
	--- Obtains map from town to town buildings of the town.
	getTown2BuildingMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Obtains map from town to person capacities of the town.
	--- @return a map of town to an array of integer. {integer} is an array of 3 ints capa per landuse: { RESIDENTIAL, COMMERCIAL, INDUSTRIAL }
	getTown2personCapacitiesMap : function() : {Engine.Entity : {integer}}
	--- Checks if parcel is occupied by building.
	--- @param parcelEntity the entity of the parcel
	hasBuilding : function(parcelEntity : Engine.Entity) : boolean
end

--- Sim Person System.
-- System managing persons.
global record SimPersonSystem
	--- Gets number of people on the map.
	--- @return number of people
	getCount : function() : integer
	--- Gets list of people for every destination.
	getDestination2SpMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Gets all persons waiting at the given transport network.
	--- @param tnEntity the entity of the transport network
	getSimPersonsAtTerminalForTransportNetwork : function(tnEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all persons that have an entity as one of their destination.
	-- Destinations are a home, a work and a shopping destination.
	--- @param destination the destination entity
	getSimPersonsForDestination : function(destination : Engine.Entity) : {Engine.Entity}
	--- Gets all persons travelling with the given line.
	--- @param lineEntity the entity of the line
	getSimPersonsForLine : function(lineEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all persons currently trying to reach given target.
	--- @param targetEntity the entity of the target
	getSimPersonsForTarget : function(targetEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all idle persons on a transport network.
	--- @param tnEntity the entity of the transport network
	getSimPersonsIdleForTransportNetwork : function(tnEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all moving persons over a transport network.
	--- @param tnEntity the entity of the transport network
	getSimPersonsMovingForTransportNetwork : function(tnEntity : Engine.Entity) : {Engine.Entity}
end

--- Sim Entity At Stock System.
-- System managing cargo produced by industries or transported to a warehouse.
global record SimEntityAtStockSystem
	--- Obtains a map, mapping the stock to the cargo waiting there.
	getStock2SimEntityMap : function() : {{Engine.Entity, StockId} : {Engine.Entity}}
	--- Obtains the amount of specific item id waiting at a given stock.
	--- @param stockEntity the entity of the stock holding entity, e.g. industry
	--- @param stockId the id of the stock
	getStockCount : function(stockEntity:Engine.Entity, stockId : StockId) : integer
	--- Obtains the amount of specific item id waiting at a given stock and cargo type.
	--- @param stockEntity the entity of the stock holding entity, e.g. industry
	--- @param stockId the id of the stock
	--- @param cargoTypeId the id of the cargo type
	getStockCountForCargoType : function(stockEntity : Engine.Entity, stockId : StockId, cargoTypeId : CargoTypeId) : integer
	--- Obtains all entities waiting at a given stock.
	--- @param stockEntity the entity of the stock holding entity, e.g. industry
	--- @param stockId the id of the stock
	getStockEntities : function(stockEntity : Engine.Entity, stockId : StockId) : {{integer, Engine.Entity}}
	--- Obtains the entity that was waiting longest at a given stock.
	--- @param stockEntity the entity of the stock holding entity, e.g. industry
	--- @param stockId the id of the stock
	getStockSimEntity : function(stockEntity : Engine.Entity, stockId : StockId) : Engine.Entity
end

--- Sim Entity At Terminal System.
-- System managing entities waiting at terminals.
global record SimEntityAtTerminalSystem
	--- Gets the count of entities (SimPersons) waiting at the terminal.
	--- @param entity the line entity
	--- @param stopIndex the index of the stop in the line
	--- @param cargoType the id of the cargo type
	--- @return the count of entities at that line stop
	getLineStopSimEntitiesCount : function(entity : Engine.Entity, stopIndex : integer, cargoType : CargoTypeId) : integer
	--- Gets the count of entities (SimPersons) waiting at the terminal for the given cargo type.
	--- @param entity the line entity
	--- @param stopIndex the index of the stop in the line
	--- @param cargoType the id of the cargo type
	--- @return the sim entities of the given cargo type at that line stop
	getLineStopSimEntities : function(entity : Engine.Entity, stopIndex : integer, cargoType : CargoTypeId) : {Engine.Entity}
end

--- Sim Entity At Vehicle System.
-- System managing entities travelling in a vehicle.
global record SimEntityAtVehicleSystem
	--- Gets a map from vehicle Entity to a map from cargo to all "Sim" entities in the vehicle of the given cargo type.
	getVehicle2Cargo2SimEntitesMap : function() : {Engine.Entity : {CargoTypeId : {Engine.Entity}}}
	--- Gets the count of entities in the vehicle.
	--- @param vehicleEntity the entity of the vehicle that should be inspected
	--- @return the count of entities
	getVehicleSimEntitiesCount : function(vehicleEntity : Engine.Entity) : integer
	--- Gets the count of entities in the vehicle for the given cargo type.
	--- @param vehicleEntity the entity of the vehicle that should be inspected
	--- @param cargoType the id of the cargo type
	--- @return the count of entities
	getVehicleSimEntitiesCountForCargoType : function(vehicleEntity : Engine.Entity, cargoType : CargoTypeId) : integer
	--- Gets the vehicles with their round trip cargo counts.
	--- @return the vehicles with their round trip cargo counts
	getVehiclesWithRoundTripCount : function() : {Engine.Entity : integer}
	--- Check if the vehicle is not empty
	--- @return if the vehicle has loaded at least 1 passenger or cargo item
	hasAnythingLoaded : function(Engine.Entity) : boolean
end

--- Sim Person At Vehicle System.
-- System managing persons travelling on a vehicle.
global record SimPersonAtVehicleSystem
	--- Gets information about persons traveling on the given vehicle.
	--- @param vehicleEntity the entity of the vehicle that should be inspected
	--- @return Information about each vehicle part
	getVehiclePartInfoList : function(vehicleEntity : Engine.Entity) : {VehiclePartInfo}
end

--- Street Connector System.
-- Manages street connections.
global record StreetConnectorSystem
	--- Gets all sources for the destination entity.
	--- @param depotEntity the entity for which the containing construction should be fetched
	getConstructionEntityForDepot : function(depotEntity : Engine.Entity) : Engine.Entity
	--- Gets the construction that "owns" the given edge.
	--- @param edgeEntity the entity for which the containing construction should be fetched
	getConstructionEntityForEdge : function(edgeEntity : Engine.Entity) : Engine.Entity
	--- Gets the construction for the industry.
	--- @param industryEntity the entity for which the containing construction should be fetched
	getConstructionEntityForIndustry : function(industryEntity : Engine.Entity) : Engine.Entity
	--- Gets the construction to which the node (a frozen node in the construction) belongs.
	--- @param nodeEntity the entity for which the containing construction should be fetched
	getConstructionEntityForNode : function(nodeEntity : Engine.Entity) : Engine.Entity
	--- Gets the construction for the subconstruction.
	--- @param subconstruction the entity for which the containing construction should be fetched
	getConstructionEntityForSubconstruction : function(subconstruction : Engine.Entity) : Engine.Entity
	--- Gets the construction for the station.
	--- @param stationEntity the entity for which the containing construction should be fetched
	getConstructionEntityForStation : function(stationEntity : Engine.Entity) : Engine.Entity
	--- Gets the construction for the town building.
	--- @param townBuilding the entity for which the containing construction should be fetched
	getConstructionEntityForTownBuilding : function(townBuilding : Engine.Entity) : Engine.Entity
	--- Gets a mapping from frozen nodes to the construction they belong.
	getNode2StreetConnectorMap : function() : {Engine.Entity : Engine.Entity}
	--- Gets a mapping from stations to constructions.
	getStation2ConstructionMap : function() : {Engine.Entity : Engine.Entity}
	--- Loop over all constructions that have the specified metadata key in their static description.
	--- @param metadataKey metadata key
	--- @param constructionDescMeta if static metadata should be checked (on match, the callback's constructionId is >= 0)
	--- @param constructionInstanceMeta if instance metadata should be checked
	--- @param fn the callback called for each entity with the given component and its entry in constructionRep
	--- @param playerOwnedOnly if true, then skip constructions owned by other player or not owned at all
	forEachConstructionWithMetadata : function(metadataKey : string, constructionDescMeta : boolean, constructionInstanceMeta : boolean,
				fn : function(entity : Engine.Entity, construction : Engine.Component.Construction, constructionIdIfDescMatch :  ConstructionId),
				playerOwnedOnly? : boolean)
	--- Loop over all constructions that have the specified metadata key in their static description.
	--- @param constructionEntity the entity to check
	--- @param metadataKey metadata key
	getConstructionIdIfStaticMetadata : function(constructionEntity : Engine.Entity, metadataKey : string) : {ConstructionId, ResName}
	--- Gets the closest town to the construction.
	--- @param constructionEntity the entity for which the closest town should be fetched
	getConstructionClosestTown : function(constructionEntity : Engine.Entity) : Engine.Entity
	--- Gets constructions for which the town is the closest.
	--- @param townEntity the entity for which the closest constructions should be fetched
	getTownClosestConstructions : function(townEntity : Engine.Entity) : {Engine.Entity}
	--- Loops over all constructions.
	forEach : function(Engine.Entity)
end

--- Base Parallel Strip System.
-- Contain information about parallel edge ranges.
global record BaseParallelStripSystem
	--- Obtains all parallel strips of a base edge entity (there might be more than one parallel strip for each base edge).
	--- @param edgeEntity the entity of the edge that should be inspected
	getStrips : function(edgeEntity : Engine.Entity) : {Engine.Entity}
end

--- Street System.
-- Manages base edges.
global record StreetSystem
	--- Obtains the edge to which the edge object belongs.
	--- @param edgeEntity the entity of the edge object
	getEdgeForEdgeObject : function(edgeEntity : Engine.Entity) : Engine.Entity
	--- Obtains the mapping from edge object to edges they belong.
	getEdgeObject2EdgeMap : function() : {Engine.Entity : Engine.Entity}
	--- Obtains a map from all base nodes to base segments they are connected with.
	getNode2SegmentMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Obtains a map from all base nodes to base street segments they are connected with.
	getNode2StreetEdgeMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Obtains a map from all base nodes to base track segments they are connected with.
	getNode2TrackEdgeMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Checks if the node is a town crossing.
	isTownCrossingNode : function(Engine.Entity) : boolean
	--- Returns the node segments.
	--- @param nodeEntity the entity of the node
	getNodeSegments : function(nodeEntity : Engine.Entity) : {Engine.Entity}
	--- Returns the node street segments.
	--- @param nodeEntity the entity of the node
	getNodeStreetSegments : function(nodeEntity : Engine.Entity) : {Engine.Entity}
	--- Returns the node track segments.
	--- @param nodeEntity the entity of the node
	getNodeTrackSegments : function(nodeEntity : Engine.Entity) : {Engine.Entity}
end

--- Game Script System
-- Manages entities and components for gamescript.
global record GameScriptSystem
	--- Gets the entity onto which the gamescript state is attached
	--- @param name the name of the gamescript
	getEntityForGameScript : function(name : string) : Engine.Entity
end

--- Carriage list System.
-- Manages vehicles that are groups of multiple carriages.
global record CarriageListSystem
	record CarriageInfo
		owningVehicle : Engine.Entity
		index : integer
		offset : number
		reversed : boolean
		crew : boolean
		-- end : {boolean, boolean}
	end
	--- Gets more information about a train carriage/engine.
	--- @param vehicleEntity the entity of the vehicle.
	getVehicleInfo : function(vehicleEntity : Engine.Entity) : CarriageInfo
	--- Gets more information about a train carriage/engine.
	--- @param vehicleEntity the entity of the vehicle.
	getVehicleData : function(vehicleEntity : Engine.Entity) : VehicleData
	--- Loops over all carriage lists.
	forEach : function(Engine.Entity)
end

--- Transport Vehicle System.
-- Manages the movement and behaviour of transport vehicles. This covers all vehicles transporting cargo and passengers.
global record TransportVehicleSystem
	--- Gets all vehicles that are in a depot.
	--- @param depotEntity the entity of the depot
	getDepotVehicles : function(depotEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all vehicles heading for the depot.
	--- @param depotEntity the entity of the depot
	getGoingToDepotVehicles : function(depotEntity : Engine.Entity) : {Engine.Entity}
	--- Gets additional information about the vehicle.
	--- @param transportVehicleEntity the entity of the transport vehicle
	--- @return info about the transport vehicle
	getInfo : function(transportVehicleEntity : Engine.Entity) : any
	--- Gets a map of lines to the vehicles using the line.
	getLine2VehicleMap : function() : {Engine.Entity : {Engine.Entity}}
	--- Gets the vehicle stopped at the stop of a line.
	--- @param lineEntity the entity of the line
	--- @param stopIndex the index of the stop on the line
	getLineStopVehicles : function(lineEntity : Engine.Entity, stopIndex : number) : {Engine.Entity}
	--- Checks whether the specified stop has terminals that are too short for optimal loading.
	--- @param lineEntity the entity of the line
	--- @param stopIndex the index of the stop on the line
	checkLineStopForVehicleOverlength : function(lineEntity : Engine.Entity, stopIndex : number) : {StationTerminal : boolean}
	--- Gets all vehicles using a given line.
	--- @param lineEntity the entity of the line
	getLineVehicles : function(lineEntity : Engine.Entity) : {Engine.Entity}
	--- Gets all vehicles that cannot find a path to their destination.
	getNoPathVehicles : function() : {Engine.Entity}
	--- Gets the vehicle names of all vehicles for the given carrier.
	--- @param carrier the carrier for which the names should be fetched
	getVehicleNames : function(carrier : Carrier) : {string}
	--- Gets the vehicle using a certain transport network.
	--- @param tnEntities list of transport network entities
	--- @param wholePath true if the vehicle has to use the whole path
	getVehicles : function(tnEntities : {Engine.Entity}, wholePath : boolean) : {Engine.Entity}
	--- Gets all vehicles that are in the given state. This can be used, for instance, to obtain a list of all vehicles
	-- currently waiting at a terminal.
	--- @param state A state to filter the vehicles
	getVehiclesWithState : function(state : TransportVehicleState) : {Engine.Entity}
	--- Gets all vehicles that are maintained by the given maintenance station.
	--- @param maintenanceStation the entity of the maintenance station
	getVehiclesForMaintenanceStation : function(maintenanceStation : Engine.Entity) : {Engine.Entity}
	--- Checks if the vehicle is maintained by the given maintenance station.
	--- @param vehicle the entity of the vehicle
	--- @param maintenanceStation the entity of the maintenance station
	isVehicleMaintainedByStation : function(vehicle : Engine.Entity, maintenanceStation : Engine.Entity) : boolean
	--- Gets cargo info for a line.
	--- @param lineEntity the entity of the line
	--- @param cargoTypeId the id of the cargo type
	getLineCargoInfo : function(lineEntity : Engine.Entity, cargoTypeId : CargoTypeId) : LineCargoInfo
end

--- Land Vehicle Move System.
-- Manages the movement of land vehicles.
global record LandVehicleMoveSystem
	--- Gets all trains that are blocked by another train.
	getBlockedTrains : function() : {{Engine.Entity, Engine.Entity}}
	--- Gets more information about a vehicle.
	--- @param vehicleEntity the entity of the vehicle.
	getVehicleInfo : function(vehicleEntity : Engine.Entity) : LandVehicleMoveInfo
	--- Checks if a train is waiting for a free path.
	--- @param trainEntity the entity of the train.
	isTrainWaitingForFreePath : function(trainEntity : Engine.Entity) : boolean
	--- Loops over all trains.
	forEach : function(Engine.Entity)
end

--- Aircraft Move System.
-- System managing the movement of airplanes.
global record AircraftMoveSystem is ISystem
	--- Obtains Aircraft information for the given entity.
	--- @param vehicleEntity the entity id of the aircraft that should be inspected
	getAirCraftInfo : function(vehicleEntity : Engine.Entity) : AircraftInfo
	--- Checks if a given edge is reserved by an aircraft.
	--- @param edgeId the edgeId that should be inspected
	--- @return true if reserved
	isReserved : function(edgeId : EdgeId) : boolean
	--- Loops over all aircraft.
	forEach : function(Engine.Entity)
end

--- Grid Collision System.
-- Single instance of the grid collision system.
global record GridCollisionSystem
	--- Gets collision data at a given position (0 = no collision)
	getCollisionDataAt : function(GridCollisionSystem, Vec2f) : number
end

--- Catchment Area System.
-- Contains cached information about reachability of stations and destinations.
global record CatchmentAreaSystem
	--- Obtains a map mapping transport network edges to stations that can be reached from that edge.
	getEdge2stationsMap : function() : {EdgeId : {{Engine.Entity, integer}}}
	--- Obtains a map mapping stations to all reachable edges from that station (the actual catchment area of the station).
	getStation2edgesMap : function() : {Engine.Entity : {{EdgeId, integer}}}
	--- Obtains a map, mapping station to all reachable stations in the catchment area, and, additionally, the distance of the
	-- shortest path.
	getStation2stationsAndDistancesMap : function() : {Engine.Entity : {Engine.Entity : integer}}
	--- Obtains a list of all catchables (entities holding a StockList or PersonCapacity component) for the station.
	--- @param stationEntity the entity of the station
	--- @param cargo wether to return cargo or passenger catchables
	getStationCatchables : function(stationEntity : Engine.Entity, cargo : boolean) : {Engine.Entity}
end

--- Transport Network System.
-- Manages transport networks (and transport network edges and nodes).
global record TransportNetworkSystem
	--- Gets all intersections within a transport network (e.g. all intersections in a base node).
	--- @param tnEntity the entity of the transport network
	getIntersections : function(tnEntity : Engine.Entity) : {any}
	--- Gets a structure representing the graph of the transport network.
	getTpNetData : function() : TpNetData
end

--- Emission grid system.
-- Manages emission grid data.
global record EmissionGridSystem
	--- Returns the interpolated emission at a given position.
	--- @param pos the position at which the emission should be sampled
	--- @param useAverage whether to use average or not
	--- @param type the type of emission to query
	--- @return the interpolated emission value
	getInterpolatedEmission : function(pos : Vec2f, useAverage : boolean, type : Engine.Component.EmissionGrid.Type) : number

	--- Returns the EmissionGrid entity for the noise or pollution
	--- @param noise Which type of emission: noise or pollution
	--- @return an entity with the EmissionGrid component
	getEmissionGridEntity : function(noise : boolean) : Engine.Entity
end

--- Railroad Crossing System.
-- Contains information about raiload crossings.
global record RailRoadCrossingSystem
	--- Gets all railroad crossings of the given base edge entity.
	--- @param edgeEntity the entity id of the edge that should be inspected
	getRailroadCrossingForEdge : function(edgeEntity : Engine.Entity) : Engine.Entity
	--- Gets all railroad crossings of the given base node entity.
	--- @param nodeEntity the entity id of the node that should be inspected
	getRailroadCrossingForNode : function(nodeEntity : Engine.Entity) : Engine.Entity
end

--- River System.
-- Contains information about water in the map.
global record RiverSystem
	--- Gets all water meshes within the bounds.
	getWaterMeshEntities : function(tile0 : Vec2i, tile1 : Vec2i) : {Engine.Entity}
end

--- Runway System.
-- Contains information about runway edges.
global record RunwaySystem
	--- Gets all stations reachable from that landing node.
	getLandingNodeIdMap : function() : {NodeId : Engine.Entity}
	--- Gets all station from which the takeoff node can reached.
	getTakeoffNodeIdMap : function() : {NodeId : Engine.Entity}
end

--- Ship Move System.
-- Contains information about the movement of ships.
global record ShipMoveSystem
	--- Gets more path and movement information about ships.
	--- @param vehicleEntity the entity id of the ship that should be inspected
	getShipInfo : function(vehicleEntity : Engine.Entity) : ShipInfo
	--- Loops over all ships.
	forEach : function(Engine.Entity)
end

--- Signal System.
-- Contains information about Signals (waypoints, path and one way signals)
global record SignalSystem
	--- Gets the signal from an @{api.type.EdgeId} at the given direction.
	-- Notice: there can be at most one signal per direction per transport network edge.
	--- @param edgeId the id of the edge hosting the signal
	--- @param reversed false if signal in direction of edge is requested
	getSignal : function(edgeId : EdgeId, reversed : boolean) : SignalId
end

--- Cargo System.
-- System managing cargo.
global record SimCargoSystem
end

--- Person At Building System.
-- System managing persons at a building.
global record SimPersonAtBuildingSystem
	--- Gets list of entities currently at the building
	--- @param simBuildingEntity the entity of the building that should be inspected
	getSimPersonAtBuilding : function(simBuildingEntity : Engine.Entity) : {Engine.Entity}
end

--- Person At Terminal System.
-- System managing persons waiting at terminal.
global record SimPersonAtTerminalSystem
	--- Gets information about persons waiting at the terminals.
	getEdgeInfoMap : function() : {EdgeId : any}
	--- Gets number of free waiting places for the given transport network edge.
	--- @param edgeId the id of the edge that should be inspected
	getNumFreePlaces : function(edgeId : EdgeId) : integer
	--- Gets the position on the transport network edge for the given place.
	--- @param edgeId the id of the edge that should be inspected
	--- @param place the waiting place number
	--- @return the position
	getPos01 : function(edgeId : EdgeId, place : integer) : {number, number}
end

--- Stock List System.
-- Manages stocks.
global record StockListSystem
end

--- Parcel System.
-- Manages and returns information about parcels.
global record ParcelSystem
	--- Obtains all parcels belonging to a segment.
	--- @param segmentEntity the segment of which to obtain all attached parcels
	getParcelData : function(segmentEntity : Engine.Entity) : any
	--- Obtains a map of all segments to the parcel data of the segment.
	getSegment2ParcelData : function() : {Engine.Entity : any}
end

--- Transport Network Link System.
-- Manages transport networks links (small links between roads and constructions).
global record TpNetLinkSystem
	--- Gets a map from all edges to the links touching the edge.
	getEdgeId2linkEntities : function() : {EdgeId : {Engine.Entity}}
	--- Gets all links within a transport network edge.
	--- @param edgeId the edge id for which the links should be fetched
	getLinkEntities : function(edgeId : EdgeId) : {Engine.Entity}
end

--- Vehicle Depot System.
-- Manages depots and vehicles in depots.
global record VehicleDepotSystem
	--- Gets the depot entity to which the node belongs.
	--- @param nodeId the id of the node for which the depot should be fetched
	getDepotForInNodeId : function(nodeId : NodeId) : Engine.Entity
	--- Loops over all depots.
	forEach : function(Engine.Entity)
end

--- Animal Move System.
-- Manages animals.
global record AnimalMoveSystem
	--- Loops over all animals.
	forEach : function(Engine.Entity)
end

--- Contains multiple grids holding data
-- Contains multiple grids holding diverse data
global record GridCollision
	--- Gets the grid collision system with the given index.
	--- @param index the index of the system to get
	getGridCollisionSystem : function(index : integer) : GridCollisionSystem
	--- Gets the grid collision system tracking player owned structures.
	getPlayerInfrastructureCollisionSystem : function() : GridCollisionSystem
end

--- Octree System.
-- An octree that contains all entities with a bounding box. It enables fast query and location of entities in the map.
global record OctreeSystem
	--- Fetches all entities in a box and runs a callback for them.
	--- @param box Box in which all entities are searched.
	--- @param callback A function called for each matching entity within box. The callback obtains an entity and a bounding volume.
	findIntersectingEntities : function(box : Box3f, callback : function(Engine.Entity, Engine.Component.BoundingVolume))
end

--- Landmark system.
-- Manages landmarks data.
global record LandmarkSystem
	--- Returns distances from landmark entity to transport network edges.
	--- @param landmarkEntity entity of the landmark
	getLandmarkData : function(landmarkEntity : Engine.Entity) : {EdgeId : number}
end

--- A system is a simulation object that controls entities with specific components or caches additional computed data
--- for entities after listening for component changes
--- @category main
global record System
	--- Controls animal simulation and movement
	animalMoveSystem : AnimalMoveSystem
	--- Controls aircraft (helicopters and airplanes) simulation (reservation, pathing, ...) and movement
	aircraftMoveSystem : AircraftMoveSystem
	--- A cache of data that is computed from parallel strip data
	baseParallelStripSystem : BaseParallelStripSystem
	--- A cache of data for carriage lists
	carriageListSystem : CarriageListSystem
	catchmentAreaSystem : CatchmentAreaSystem
	emissionGridSystem : EmissionGridSystem
	gameScriptSystem : GameScriptSystem
	landVehicleMoveSystem : LandVehicleMoveSystem
	landmarkSystem : LandmarkSystem
	--- Manages all line data
	lineSystem : LineSystem
	--- Efficient way to collect entities in a specific region of space
	octreeSystem : OctreeSystem
	--- Manages parcels for towns, and provides inverse relation from segment to parcels
	parcelSystem : ParcelSystem
	railRoadCrossingSystem : RailRoadCrossingSystem
	--- Create a vector field of waterfronts for street and construction alignment
	riverSystem : RiverSystem
	runwaySystem : RunwaySystem
	shipMoveSystem : ShipMoveSystem
	signalSystem : SignalSystem
	simCargoSystem : SimCargoSystem
	simPersonSystem : SimPersonSystem
	simPersonAtBuildingSystem : SimPersonAtBuildingSystem
	simPersonAtTerminalSystem : SimPersonAtTerminalSystem
	simPersonAtVehicleSystem : SimPersonAtVehicleSystem
	simEntityAtStockSystem : SimEntityAtStockSystem
	simEntityAtTerminalSystem : SimEntityAtTerminalSystem
	simEntityAtVehicleSystem : SimEntityAtVehicleSystem
	stationSystem : StationSystem
	stationGroupSystem : StationGroupSystem
	stockListSystem : StockListSystem
	streetSystem : StreetSystem
	--- Caches relations between constructions and base edges
	streetConnectorSystem : StreetConnectorSystem
	townBuildingSystem : TownBuildingSystem
	tpNetLinkSystem : TpNetLinkSystem
	transportNetworkSystem : TransportNetworkSystem

	--- Manages cargo loading and unloading, as well as arrival of any transport vehicle
	transportVehicleSystem : TransportVehicleSystem

	--- Manages door animation of depots
	vehicleDepotSystem : VehicleDepotSystem

	--- A generic system representing a 2d grid in the world of miscelaneous data
	gridCollision : GridCollision
end

recordDef = false
