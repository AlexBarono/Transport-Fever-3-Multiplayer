recordDef = true

--- Contains API for reading the game engine state.
--- This module is available as read-only access to the entire engine state (in particular to the entire entity component system). It can be accessed from both the GUI State and the Engine State.

global type Collider
global type EngineUtil
global type System

--- Main Engine interface
--- @category main
global record Engine
	type Entity = integer

	--- Keeps track of modifications to entities.
	record Revision
		num : {integer, integer, integer}
	end

	record Component
		--- Contains financial data. Usually attached to the player Entity
		record Account
			new : function() : Account

			--- Current balance
			balance : integer
			--- Current loan
			loan : integer
		end

		--- Data attached to aircraft
		record Aircraft
			new : function() : Aircraft

			--- Has the runway been reserved for takeoff
			reservedTakeOffRunway : boolean
			--- Has the runway been reserved for landing
			reservedLandingRunway : boolean
			--- Edge index on the path
			pathIndex : integer
			--- Edge index on the path from which the reservation starts
			reservedFrom : integer
			--- Edge index on the path on which the reservation stops
			reservedTo : integer
		end

		--- Data attached to animals. Contains information about position and movement
		record Animal
			new : function() : Animal

			--- Current location in the game world
			worldPosition : Vec3f
			--- Direction in which the animal is oriented
			lookingAt : Vec2f
			--- Destination where the animal is heading
			targetCoord : Vec2f
			--- The forward speed
			movementSpeed : number
			--- The turn speed
			angularSpeed : number
			--- Time since the last update of the animal
			lastUpdateElapsed : number
			--- Time since the last reorientation of the animal
			targetChangedElapsed : number
			--- Time since the animal is in an invalid location
			invalidTileElapsed : number
			--- Index of the current movement type
			movementType : integer
			--- Current roll value
			roll : number
			--- Scale of the animal
			scaling : number
			--- Offset for each of the flock animals relative to the worldPosition
			flock : {Vec3f}
		end

		--- Data attached to assets, in particular trees. 
		-- Assets are grouped together when built together in order to speed up rendering performance.
		-- Usually comes together with a ModelInstanceList
		record AssetGroup
			new : function() : AssetGroup
 		end

		--- Data attached to assets entities to enable automatic removal when it collides with newly built objects
		record AssetGroupAutoRemove
			new : function() : AssetGroupAutoRemove
		end

		--- An entity with an AudioEmitter emits a sound source
		record AudioEmitter
			new : function() : AudioEmitter

			--- Audio emitter reference
			emitter : integer
		end

		--- Type attached to streets and tracks, specifying the street type and other details.
		-- A BaseEdge usually also has a BaseEdgeStreet and a TransportNetwork
		record BaseEdge
			new : function() : BaseEdge
			clone : function(BaseEdge) : BaseEdge

			type : BaseEdgeType
			typeIndex : integer
			objects : {{Engine.Entity, EdgeObjectType}}
			laneConfigs : {LaneConfig}
			laneConfigs_native : Vector<LaneConfig>
			--- prevent towns from updating or extending this road
			roadDevelopmentLocked : boolean

			node0 : Engine.Entity
			node1 : Engine.Entity
			position0 : Vec3f
			position1 : Vec3f
			tangent0 : Vec3f
			tangent1 : Vec3f

			laneConfig : {LaneConfig}

			edgeDecorations : {{integer, boolean}}

			distance : number

			--- Type of road (STREET or TRACK)
			roadType : RoadType
			--- Road template resource name
			roadTemplate : ResName
			--- Road style resource name
			roadStyle : ResName
		end

		--- Contains details about an object attached to a BaseEdge
		record EdgeObject
			new : function() : EdgeObject

			--- Relative location on the edge, from 0 to 1
			param : number
			--- Position of the object in world coordinates
			transf : Mat4f
			--- The resource name of the object (Construction)
			edgeObjectConstruction : ResName
			--- Arbitrary params
			params : table
		end

		--- Contains details about a base edge when it is a street
		record BaseEdgeStreet
			new : function() : BaseEdgeStreet

			--- Precedence preference at first node
			precedenceNode0 : PrecedencePreference
			--- Precedence preference at second node
			precedenceNode1 : PrecedencePreference
		end

		--- A node in a street graph, e.g. a railroad crossing, a switch, or street crossing
		record BaseNode
			new : function() : BaseNode
			clone : function(BaseNode) : BaseNode

			--- Position of the node in world coordinates
			position : Vec3f
		end

		--- A signle state (= phase) of the traffic light
		record TrafficLightState
			new : function() : TrafficLightState
			clone : function(trafficLightState : TrafficLightState) : TrafficLightState

			lockedLanes : {integer}
			duration : number
			minDuration : number
			canSkip : boolean
		end

		--- Traffic light configuration for the node, including phases (states)
		record TrafficLightConfig
			new : function() : TrafficLightConfig
			clone : function(trafficLightConfig : TrafficLightConfig) : TrafficLightConfig

			states : {TrafficLightState}
			trafficLightType : integer
		end

		--- A custom configuration for the lanes
		record BaseNodeConfig
			new : function() : BaseNodeConfig

			laneConnections : {LaneConnection}
			crosswalks : {Entity}
			trafficLightPreference : TrafficLightPreference
			trafficLightConfig : TrafficLightConfig
			doubleSlipSwitch : boolean

			userModifiedLaneConnections : boolean
			userModifiedTrafficLightStates : boolean
		end

		--- Additional traffic light data for a base node
		record BaseNodeTrafficLight
			new : function() : BaseNodeTrafficLight

			trafficLightData : TrafficLightData
			state : integer
			time : number
			stateTimes : {integer}
		end

		--- Stores groups of ranges (a range is reflected as a BaseEdgeRange)
		record BaseParallelStrip
			new : function() : BaseParallelStrip

			--- Stores a fraction of a base edge (BaseEdge)
			record BaseEdgeRange
				new : function() : BaseEdgeRange

				edge : Engine.Entity
				bounds : {number, number}
			end
			rangeGroups : {{BaseEdgeRange}}
			rangeGroups_native : Vector<Vector<BaseEdgeRange>>
		end

		--- Contains the bounding box of an entity
		record BoundingVolume
			new : function() : BoundingVolume

			--- The axis aligned bounding box
			bbox : Box3f
		end

		--- Contains the full information and the entire spline of a bridge, if this was configured to do so
		record Bridge
			new : function() : Bridge

			--- A subsection of a bridge
			record Interval
				new : function() : Interval

				splines : {{Vec3f}}
				railingModels : {{integer, Mat4f}}
			end
			intervals : {Interval}
		end

		--- Stores the costs of an entity (e.g. Constructions or Edges)
		record BuildCost
			new : function() : BuildCost

			buildCost : integer
			bulldozeCost : integer
			noCostAtAll : boolean
		end

		--- Allows to set certain entities to be not bulldozable
		record BulldozerInfo
			new : function() : BulldozerInfo

			locked : boolean
		end

		--- Represents a single waggon of a train (a single carriage or engine).
		record Carriage
			new : function() : Carriage

			--- true if the train travels reversed
			reversed : boolean
		end

		--- Represents a list of engines and carriages (usually of a train)
		record CarriageList
			new : function() : CarriageList

			--- all waggons and engines
			carriages : {Engine.Entity}
		end

		--- A list of colliders of different shapes, with an extra transformation
		record ColliderList
			new : function() : ColliderList

			--- a list of colliders and transformation that belong to the entity
			colliders : {{Collider, Mat4f}}
		end

		--- Specifies the color of an entity
		record Color
			new : function() : Color

			--- the RGB color of the entity
			color : Vec3f
		end

		--- A construction: usually contains stations, depots, town buildings or industries.
		record Construction
			new : function() : Construction

			record ConstructionParams
				new : function() : ConstructionParams

				seed : integer
				year : integer
				modules : {integer : any}
			end

			--- the name of the construction (or the id in case of dynamic constructions)
			fileName : ResName
			--- the parameters, passed to the `updateFn`.
			params : ConstructionParams
			params_native : NativeLuaTable
			--- the world transformation of the construction
			transf : Mat4f
			--- the in-game time when the construction was first placed
			timeBuilt : integer
			--- nodes that belong to the construction and cannot be moved
			frozenNodes : {Engine.Entity}
			--- edges that belong to the construction and cannot be moved
			frozenEdges : {Engine.Entity}
			--- depots that belong to the construction
			depots : {Engine.Entity}
			--- stations that belong to the construction
			stations : {Engine.Entity}
			--- industries that belong to the construction
			industries : {Engine.Entity}
			--- town building that belong to the construction
			townBuildings : {Engine.Entity}
			--- all subconstructions generated by the construction
			subconstructions : {Engine.Entity}

			--- all metadata that is persisted in the component
			persistentMetadata : ConstructionInstanceMetadata

			--- all slots of the modular construction
			slots : {Slot}
			--- configuration by slot type
			slotConfig : {string : SlotConfig}
			dependentSlots : {integer, {integer}}

			tag2modelInstance : {string, {{Engine.Entity, integer}}}
			entityAndIndex2labelTexts : {{Engine.Entity, integer}, {string}}
			tag2segments : {string, {Engine.Entity}}
		end

		--- The internal state of a custom entity state
		record CustomState
			new : function() : CustomState

			--- the internal state as a generic table
			state : table
		end

		--- An emission emitter, which emits pollution and/or noise
		record EmissionEmitter
			new : function() : EmissionEmitter

			--- the position of the emission emitter
			position : Vec3f
			--- the radius in which the emitter is applied (usually 0)
			radius : number
			--- the noise power of the emission emitter
			noisePower : number
			--- the pollution power of the emission emitter
			pollutionPower : number
		end

		--- The grid containing the emission data
		record EmissionGrid
			new : function() : EmissionGrid

			--- The emission grid type
			record Type 
				Noise : Type -- 0
				Pollution : Type -- 1
			end

			--- the bottom left corner x coordinate
			X0 : integer
			--- the bottom left corner y coordinate
			Y0 : integer
			width : integer
			height : integer

			--- the resolution of the grid
			gridPointSize : Vec2f

			concentrationBuffer : Gridf
			averageConcentration : Gridf

			--- enum type for noise (0) or pollution (1)
			type : Type
			--- global wind direction
			wind : Vec2f
		end

		--- Contains data representing a farm field on the terrain
		record Field
			new : function() : Field
		end

		--- The internal state of a single gamescript
		record GameScript<T>
			new : function() : GameScript<T>

			--- the gamescript for this entity
			gameScript : ResName
			addedToExistingSavegame : boolean
			--- the internal state as a generic table
			state : T
			state_native : NativeLuaTable
			--- the event subscriptions for this gamescript
			eventSubscriptions : any
		end

		--- Information about the current game simulation and calendar speed.
		record GameSpeed
			new : function() : GameSpeed

			--- multiplier for game simulation speed (non-negative, 0 = paused)
			speedup : integer
			--- length of an in-game calendar day in milliseconds (affected by speedup, 0 = paused)
			millisPerDay : integer
		end

		--- Information about the current ingame time.
		record GameTime
			new : function() : GameTime

			--- the current ingame time
			gameTime : integer
			--- the ingame time when the last update occured
			gameTime0 : integer
			dates : {{integer, Date}}
			timeOfDaySec : integer
			--- number of simulation ticks, ticks also when the game is paused (once per frame)
			tickCount : integer
			--- number of simulation updates, does not tick when the simulation is paused
			updateCount : integer
		end

		--- Contains information about industries.
		record Industry
			new : function() : Industry

			--- stock list entity
			stockList : Engine.Entity
			--- the current level of the construction
			level : integer
			--- time after which the building will be closed
			closureTimeStamp : integer
			--- the progress towards upgrade/downgrade
			upgradeProgress : number
			--- set to true if industries do not start to close/stop countdown and do not level up or down
			manualDevelopment : boolean
			--- the construction entity
			construction : Engine.Entity
			--- the maximum level of the construction
			maxLevel : integer
		end

		--- Information about landmarks used for path finding.
		record Landmark
			new : function() : Landmark

			--- the entity for the landmark
			transportNetworkEntity : Engine.Entity
			--- whether the landmark is currently active
			active : boolean
		end

		--- Represents a vehicle travelling on roads (either bus or truck)
		record LandVehicle
			new : function() : LandVehicle

			--- The fast-changing component of a LandVehicle.
			record DynState
				new : function() : DynState

				--- time in seconds that counts down. When positive, braking lights are on
				brakingTimer : number
				--- true if the vehicle is turning left
				turnLeft : boolean
				--- true if the vehicle is turning right
				turnRight : boolean
			end

			isTram : boolean
			--- the fast-changing component of the LandVehicle
			dyn : DynState
		end

		--- An line with stops and configurations
		record Line
			new : function() : Line
			new : function(Line) : Line

			--- Type of loading/waiting for the line.
			record LoadMode
				LOAD_IF_AVAILABLE : LoadMode
				FULL_LOAD_ANY : LoadMode
				FULL_LOAD_ALL : LoadMode
				LEGACY_UNLOAD_ONLY : LoadMode
			end

			--- Configuration details for a line stop
			record StopConfig
				new : function(?StopConfig) : StopConfig

				--- for each cargo type, if it should be loaded
				load : {boolean}
				--- for each cargo type, its max allowed fraction of total capacity (from 0 to 1)
				maxLoad : {number}
				--- whether to unload cargo at compatible input-stocks, even if there is no space in that stock (cargo will be destroyed)
				forceUnload : boolean
				--- whether to destroy cargo to allow changing the load config of a vehicle (even without compatible input-stock).
				-- This only happens in case a different cargo type is available to be loaded up at this stock.
				destroyForConfigChange : boolean
				--- whether to destroy cargo that was originally picked up by the vehicle at this output-stock (even without compatible input-stock).
				-- This only happens in case the cargo did a full round trip and new cargo of the same type is available to be loaded up at this stock.
				destroyForRefresh : boolean
			end

			--- Configuration for a line stop
			record Stop
				new : function() : Stop

				--- the station group entity to which the line stop belongs
				stationGroup : Engine.Entity
				--- the station (within the station group)
				station : integer
				--- the terminal (within the station) for the stop
				terminal : integer
				--- Alternative terminals for the stop
				alternativeTerminals : {StationTerminal}
				--- the configuration of what to load and not to load
				loadMode : LoadMode

				--- minimum waiting time at this stop
				minWaitingTime : number
				--- maximum waiting time at this stop
				maxWaitingTime : number
				--- maximum additional waiting time (after unloading/loading) at this stop
				maxAdditionalWaitingTime : number

				--- all waypoints after the stop
				waypoints : {Waypoint}

				--- configuration how much of what cargo type to load and unload
				stopConfig : StopConfig
			end

			--- all line stops in order
			stops : {Stop}
			--- information about vehicles of the line
			vehicleInfo : LineVehicleInfo
			customFilters : boolean
			reservationPriority : number
		end

		--- A LogBook contains information about the evolution of a variable (e.g. amounts of money) over time.
		-- Be caucious when working with this component, as it can grow quite large over time and lua performance might not be ideal.
		-- Prefer the native utilities in `api.engine.util.logbook` whenever possible.
		record LogBook
			new : function() : LogBook

			--- A Log is an entry into a LogBook and keeps track of the evolution of data in time.
			record Log
				new : function() : Log

				times : {integer}
				values : {integer}
				times_native : Vector<integer>
				values_native : Vector<integer>
			end
		
			-- some logbooks hold logs relating to other entries (for example "target town entity" where carogo is delivered)
			refEntity2name2log : {Engine.Entity : {string : Log}}
			--- A map from a key to a Log
			name2log : {string : Log}
			name2log_native : Map<string, Log>
		end

		--- Information about ground textures that are paining the terrain
		record LotList
			new : function() : LotList

			--- Actual information of a LotList
			record Lot
				new : function() : Lot

				--- list vertices of the lot
				vertices : {Vec2f}
				--- list of texture coordinates for the lot (same length as vertices)
				texCoords : {Vec2f}
				--- alternative to vertices, a list of triangles can be specified instead (must be a multiple of 3)
				triangles : {integer}
				--- the ground texture key to use
				texKey : ResName
				solid : boolean
			end

			--- a list of lots for the entity
			lots : {Lot}
		end

		--- Contains the maintenance cost of objects
		record MaintenanceCost
			new : function() : MaintenanceCost

			--- the maintenance cost of an object
			maintenanceCost : integer
			accumulatedCost : {{Carrier, Carrier} : integer}
		end

		--- Contains all models rendered by the entity
		record ModelInstanceList
			new : function() : ModelInstanceList

			--- A list of models with a full transform attached
			fatInstances : {ModelInstance}
			--- A list of models with very simple data attached
			thinInstances : {ThinModelInstance}

			--- native variant for more performant access
			fatInstances_native : Vector<ModelInstance>
			--- native variant for more performant access
			thinInstances_native : Vector<ThinModelInstance>
			dynamic : boolean
		end

		--- Additional data for persons walking in the world
		record ModelPerson
			new : function() : ModelPerson

			--- the current path of the person
			path : ExtPath
			--- the current position on the path
			pathPos : PathPos
			--- whether a person is currently not walking
			stopped : boolean
			--- the maximal speed of a person
			topSpeed : number
			--- the current speed of a person
			speed : number
			--- the current deceleration speed of persons
			brakeDecel : number
			--- an offset perpendicular to the path
			offset : number
			--- the position in the world
			position : Vec3f
			--- the animation used to move the person
			movementType : integer
			--- distance from the target
			dist : number
			--- distance from the target (last frame)
			dist0 : number
			--- the animation timer
			stateTime : integer
			--- waiting beside a car (before getting in, after coming out) start
			startWaitTime : number
			--- waiting in front of a car (before getting in, after coming out) end
			endWaitTime : number
		end

		--- Additional data for idle person
		record ModelPersonIdle
			new : function() : ModelPersonIdle

			--- the time since the person stopped
			arrivalTime : integer
		end

		--- Represents a path a vehicle is currently following
		record MovePath
			new : function() : MovePath

			--- The fast-changing component of the position on a path.
			record DynState
				new : function() : DynState

				--- the position on the path
				pathPos : PathPos
				speed : number
				brakeDecel : number
				accel : number
				timeUntilAccel : number
				timeStanding : number
				timeToIgnore : number
				approachingStation : boolean
			end

			--- a series of edges the vehicle is following
			path : Path

			endParam : number
			endPos : number
			state : VehicleState
			blocked : integer
			allowEarlyArrival : boolean
			reverse : boolean
			servedFrom : integer
			servedTo : integer
			occupiedBackIndex : integer
			occupiedFrontIndex : integer

			--- the fast-changing component of the position on the path
			dyn : DynState
			--- the dyn state at the beginning of the simulation frame (optional)
			dyn0 : DynState
		end

		record MovePathAircraft
			new : function() : MovePathAircraft

			--- Additional data for aircraft path
			record AircraftState
				new : function() : AircraftState

				record DynState
					new : function() : DynState

					velocity : Vec2f
					lastAccel : Vec2f
					pitch : number
					pitchV : number
					roll : number
					rollV : number
					thrust : number
					thrustV : number
					elevator : number
					aileronLeft : number
					propPhase : number
					flaps : number
					alt : number
				end

				--- current flight state of the aircraft
				flightState : FlightState
				cruiseAlt : number
				waitingDistance : number
				waitingPriority : integer
				gear : boolean
				gearTime : integer
				dyn : DynState
				dyn0 : DynState
			end

			record ShipState
				new : function() : ShipState

				record DynState
					new : function() : DynState

					lastAccel : number
					tractiveEffort : number
					tractiveEffortV : number
					roll : number
					rollV : number
					powerOutput : number
					approachingStation : boolean
					paddlePhase : number
					actualPos : PathPosData
				end

				waitingDist : number
				clearToLand : boolean
				startPathPosData : PathPosData
				targetPathPosData : PathPosData
				dyn : DynState
				dyn0 : DynState
			end

			record PathState
				PATH0 : PathState
				PATH1 : PathState
				PATH2 : PathState
			end

			path0 : Path
			path1 : {{EdgeGeometry, boolean}}
			path2 : Path
			pathPos : PathPos
			pathPos0 : PathPos
			state : VehicleState
			pathState : PathState

			speed : number
			speed0 : number
			brakeDecel : number

			aircraftState : AircraftState
			shipState : ShipState
		end

		--- Specifies the name of an entity
		record Name
			new : function() : Name

			--- the name of the entity
			name : string
		end

		--- A parcel is a region of space near a road where a town building can be built.
		record Parcel
			new : function() : Parcel

			record CollisionType
				Environment : CollisionType
				Parcel : CollisionType
			end

			record Face
				new : function() : Face

				points : {Vec3f}
				collision : {CollisionType : boolean}
			end

			--- the street edge to which the parcel belongs
			streetSegment : Engine.Entity
			left : boolean
			curveParam : number
			offset : number
			faces : {Face}
		end

		--- Contains information about a workplace of household.
		record PersonCapacity
			new : function() : PersonCapacity

			record PathfindingPreference
				new : function() : PathfindingPreference

				destinationWeight : number
				disallowedMoveModes : {MoveMode}
			end

			--- the type of capacity (1 = residential, 2 = commercial, 3 = industrial)
			type : LandUseType
			--- total capacity (tenants or workers) of the Entity
			capacity : integer
			personNodes : {NodeId}
			vehicleNodes : {NodeId}
			pathfindingPreference : PathfindingPreference
		end

		--- Represent a player
		record Player
			new : function() : Player

			--- the current headquarters construction
			headquarters : Engine.Entity
		end

		--- An entity with player owner is property of the owner and can be bulldozed only by him.
		record PlayerOwned
			new : function() : PlayerOwned

			--- the owner of the entity
			player : Engine.Entity
		end

		--- A railroad crossing
		record RailroadCrossing
			new : function() : RailroadCrossing

			--- Animation state of a railroad crossing
			record State
				OPEN : State
				CLOSED : State
				WAITING : State
			end

			--- nodes belonging to the railroad crossing
			nodes : {Engine.Entity}
			--- edges belonging to the railroad crossing
			edges : {Engine.Entity}
			--- the type of crossing, as an index in api.res.railroadCrossingTypeRep.
			typeIndex : integer
			--- the current animation
			state : State
			--- the animation timer
			stateTime : integer
		end
		
		--- All runways for the entity transport network.
		record RunwayList
			new : function() : RunwayList

			runways : {Runway}
		end

		record Scaffold
			new : function() : Scaffold

			record Type
				NEW : Type
				UPGRADE : Type
				DOWNGRADE : Type
			end
			type : Type

			oldModelId : integer
			oldTransf : Mat4f
			oldBuildingFace : {{Vec2f}}
			oldFloorLevel : {{number}}
			oldHeight : number
			buildingFace : {{Vec2f}}
			floorLevel : {{number}}
			height : number
			constructionStartTime : integer
			constructionEndTime : integer
			cranePosition : Vec2f
			craneAngle : number
			craneTerrainHeight : number
			craneAngleSpan : {number}
		end

		--- Contains a list procedurally generated shapes.
		record ShapeList
			new : function() : ShapeList

			--- a list of shapes
			shapes : {Shape}
		end

		--- Contains information about pathing and extra data of ships.
		record Ship
			new : function() : Ship

			--- the current position on the path
			pathIndex : integer
			--- the starting edge reserved by the ship
			reservedFrom : integer
			--- the ending edge reserved by the ship
			reservedTo : integer
		end

		--- Contains a list of signals for the entity.
		record SignalList
			new : function() : SignalList

			--- a list of signals
			signals : {Signal}
		end

		--- Additional data for cargo.
		record SimCargo
			--- Historic transport data for cargo items.
			record PickupPoint
				new : function() : PickupPoint

				--- the vehicle the cargo item was transported with
				vehicle : Engine.Entity
				--- the line the cargo item was transported on
				line : Engine.Entity
				--- the position of the cargo item on the vehicle
				position : Vec3f
				--- the transport method used to transport the cargo item
				carrier : Carrier
			end

			new : function() : SimCargo

			--- The cargo type of the cargo (never 0)
			cargoType : CargoTypeId
			--- the entity of the target where the cargo item heads to
			targetOrPickupEntity : Engine.Entity
			
			--- the entity of the source where the cargo item came from
			sourceEntity : Engine.Entity

			pickupPoints : {PickupPoint}

			speed : number
			--- the timestamp when the cargo item was produced
			startTime : integer
			--- the timestamp when the cargo item was picked up
			pickupTime : integer
			--- the duration of extra time to deliver the cargo
			deliveryExtensionDuration : integer
		end

		--- Additional data for entities waiting at buildings.
		record SimEntityAtBuilding
			new : function() : SimEntityAtBuilding

			--- How long the entity has been waiting
			waitingTime : number
		end

		--- Additional data for entities waiting at industries.
		record SimEntityAtStock
			new : function() : SimEntityAtStock

			--- The industry the entity is waiting at
			stock : {Engine.Entity, StockId}
			--- the timestamp when the item arrived at the industry
			arrivalTime : integer
		end

		--- Additional data for entities waiting at terminals.
		record SimEntityAtTerminal
			new : function() : SimEntityAtTerminal

			--- The line the entity is waiting for
			line : Engine.Entity
			--- The stop the entity is waiting at
			lineStop0 : integer
			--- The stop the entity will get off the vehicle
			lineStop1 : integer
			--- the timestamp when the item arrived at the station terminal
			arrivalTime : number
			--- the vehicle the entity is currently waiting for
			vehicle : Engine.Entity
		end

		--- Additional data for entities travelling on a vehicle.
		record SimEntityAtVehicle
			new : function() : SimEntityAtVehicle

			--- The line the entity is currently using
			line : Engine.Entity
			--- The stop the entity waited at
			lineStop0 : integer
			--- The stop the entity will get off the vehicle
			lineStop1 : integer
			--- the vehicle the entity is currently in
			vehicle : Engine.Entity
			--- how often the entity reached the stock again where it was by the vehicle loaded
			roundTripCounter : integer
		end

		--- Additional data for entities that are idle.
		record SimEntityIdle
			new : function() : SimEntityIdle
		end

		--- Additional data for entities that need path calculation.
		record SimEntityNeedsPath
			new : function() : SimEntityNeedsPath

			input : PathFactoryInput
			output : PathFactoryOutput
		end

		--- Additional data for entities that are moving.
		record SimEntityMoving
			new : function() : SimEntityMoving

			--- The line the entity is currently using
			line : Engine.Entity
			--- The stop the entity waited at
			lineStop0 : integer
			lineStop1 : integer
			--- true if the path complete until the destination
			partialPath : boolean

			expectedArrivalTime : number
		end

		--- Additional data for a person waiting at the terminal
		record SimPersonAtTerminal
			new : function() : SimPersonAtTerminal

			--- the edge of the transport network the entity is waiting at
			edgeId : EdgeId
			--- the place on the edge
			place : integer
		end

		--- Additional data for a person travelling on a vehicle
		record SimPersonAtVehicle
			new : function() : SimPersonAtVehicle

			--- the vehicle the entity is using
			vehicle : Engine.Entity
			--- the vehicle part (carriage) the entity is using
			part : integer
			--- the place (seat) in the vehicle
			place : integer

			expectedArrivalTime : number
		end
		
		--- Additional data for persons.
		record SimPerson
			new : function() : SimPerson

			--- the cargo type of the person (always 0)
			cargoType : CargoTypeId
			--- the destinations for residence, shopping and work
			destinations : {Engine.Entity}
			moveModes : {MoveMode}
			travelTimes : {number}
			--- the entity where the person is or where the person heads to
			targetOrAtEntity : Engine.Entity
			lastNonResType : LandUseType
			--- the last used move mode
			lastMoveMode : MoveMode
			walkSpeed : number
			--- the model that is used for the person
			modelIdPerson : integer
			--- the color config for the clothes of the person
			colorConfigPerson : integer
			--- the model that is used as a car
			modelIdCar : integer
			--- the color config for the car
			colorConfigCar : integer
			--- the timestamp of the latest destination recalculation
			lastDestinationUpdate : integer
			landUse2ReachableWalkDrive : {integer, integer}
			landUse2ReachableLines : {integer, integer}
			pickupTime : integer
			happiness : number
		end

		--- Defines a station, i.e. a group of terminals (places where a vehicle stops and loads cargo)
		type Station = Station
		
		--- Defines a group of stations, can group together stations with very different transport modes
		record StationGroup
			new : function() : StationGroup

			--- A list of stations that are grouped together
			stations : {Engine.Entity}
		end

		--- Stock list data.
		record StockList
			--- Stock data for a single stock in a StockList.
			record Stock
				new : function() : Stock

				type : StockListType
				cargoType : CargoTypeId
				cargoTypes : CargoTypeSet
				mixedTypes : boolean
				capacity : integer
				loadSpeedModifier : number
				loadIndicatorModelInstanceIndices : {integer}
				tag : integer
			end

			--- StockData for a StockList.
			record StockData
				new : function() : StockData

				consumeFrequency : number
			end

			--- Rule data for a StockList.
			record Rule
				new : function() : Rule

				input : {{integer}}
				output : {CargoTypeId : integer}
				capacity : integer
				consumptionFactor : number
				booster : boolean
				boostFactor : number
				priority : integer
				slot : integer
			end

			--- RuleData data for a StockList.
			record RuleData
				new : function() : RuleData

				--- ApplyInfo data for a StockList.
				record ApplyInfo
					new : function() : ApplyInfo

					time : integer
					interval : integer
					consumedCargo : {StockId}
					producedCargo : {{CargoTypeId, integer}}
					end

				applyHistory : {ApplyInfo}
				lastApplyDecayFactor : number
			end

			--- CargoData for a StockList.
			record CargoData
				new : function() : CargoData

				produceFrequency : integer
			end

			--- Modifiers for the stocklist
			record Modifiers
				new : function() : Modifiers
				new : function(Modifiers) : Modifiers
				--- the productivity of the stocklist
				productivity : number
			end

			new : function() : StockList

			stocks : {Stock}
			rules : {Rule}
			stockDatas : {StockData}
			ruleDatas : {RuleData}
			cargoData : {CargoTypeId : CargoData}

			thrownAwayCargo : integer
			modifiers : Modifiers
		end	
		
		--- Subconstruction data.
		record Subconstruction
			new : function() : Subconstruction

			tag : integer
			--- Slots that are assigned to this subconstruction, for selection/bulldoze purposes
			slotIds : {integer}
			metadata : SubconstructionInstanceMetadata
		end

		--- Contains information about the map.
		record Terrain
			new : function() : Terrain

			--- the number of tiles of the terrain
			size : Vec2i
			--- number of base levels
			baseLevels : integer
			--- resolution for all three dimensions
			baseResolution : Vec3f
			highLevels : integer
			offsetZ : number
			--- level for the surface of the navigatable water
			waterLevel : number
			dataMaps : {string, HeightmapNew}
		end

		--- Contains information about how terrain needs to be aligned.
		record TerrainAlignmentList
			new : function() : TerrainAlignmentList

			terrainAlignments : {TerrainAlignment}
		end

		--- Contains information about a single tile of the map.
		--- A tile is a 256m x 256m chunk of the map.
		record TerrainTile
			new : function() : TerrainTile

			--- a reference to the entity with terrain information
			terrainEntity : Engine.Entity
			--- the position of the tile in the tile grid
			position : Vec2i
		end

		--- Contains information about the brush layer of a tile of the map.
		record TerrainTileBrush
			new : function() : TerrainTileBrush

			--- contains the material id of the brush layer
			materialIndexBrush : {integer}
			forceAboveBit : {boolean}
		end

		--- Contains information about the geometry of the tile.
		record TerrainTileHeightmap
			new : function() : TerrainTileHeightmap

			--- contains the heightmap information for the tile. Each value is for a position in the heightmap grid of the tile with a 4m resolution
			vertices : {integer}
		end

		--- Tracks information about the last time an entity was modified or added.
		record TickEpoch
			new : function() : TickEpoch

			--- a unique index incrementing each simulation update step
			time : integer
			--- a unique index counting commands within a frame
			commandIndex : integer
			--- a unique increasing index within a command
			subIndex : integer
		end

		--- Contains information about a single town.
		record Town
			new : function() : Town

			--- initial capacities for the residential, commercial and industrial district of the town
			initialLandUseCapacities : {integer}
			capacityScalingFactor : number
			levelToCapacityDistributionWeights : {{number}}
			--- a base size of the town
			sizeFactors : {number}
			--- list of cargo type ids for the needs of each of the three town districts **residential**, **commercial** and **industrial**
			cargoNeeds  : {{{CargoTypeId, number}}}
			--- turns off growth of the town
			developmentActive  : boolean
			--- the accumulated noise in decibels, it's prefered to use `api.engine.util.getTownEmissionDB`
			noise : number
			--- the accumulated noise in decibels, it's prefered to use `api.engine.util.getTownEmissionDB`
			pollution : number
		end

		--- Contains information about a town building.
		record TownBuilding
			new : function() : TownBuilding

			personCapacity : Engine.Entity
			stockList : Engine.Entity
			construction : Engine.Entity
			--- level of the building (1-4)
			level : integer
			--- parcels occupied by the building
			parcels : {Engine.Entity}
			--- the depth in number of parcels (1-4)
			depth : integer
			--- the height in meters of the building
			height : number
			--- the town entity
			town : Engine.Entity
			--- the timestamp when the building was built
			timeBuilt : integer
			--- block town developer from changing this building
			blockedDevelopment : boolean
		end

		--- Defines a connection between towns.
		record TownConnection
			new : function() : TownConnection

			--- first town
			entity0 : Engine.Entity
			--- second town
			entity1 : Engine.Entity
			--- position of the first town
			position0 : Vec2f
			--- position of the second town
			position1 : Vec2f
			--- approximate time taken to travel the connection
			time : number
			currentTime : number
			lastUpgradeYear : integer
			valid : boolean
		end

		--- Represents a link between transport networks.
		-- A link is an automatic pedestrian connection.
		record TpNetLink
			new : function() : TpNetLink

			--- link starting edge position
			from : EdgePos
			--- link end edge position
			to : EdgePos
		end

		--- Represents an entire train
		record Train
			new : function() : Train
		end

		--- Contains the graph of edges and nodes onto which vehicles and person move.
		record TransportNetwork
			new : function() : TransportNetwork

			--- The list of nodes of the transport network
			nodes : {Node}
			--- The list of edges of the transport network
			edges : {Edge}
			--- for each edge, the index of the first edge on the opposite lane
			turnaroundEdges : {integer}
		end

		--- Data for TransportNetworkNodes marker component.
		record TransportNetworkNodes
			new : function() : TransportNetworkNodes
		end

		--- Represents a single transport vehicle
		record TransportVehicle
			--- Contains modifiers for the entire transport vehicle
			record Modifiers
				new : function() : Modifiers
				new : function(Modifiers) : Modifiers

				--- allows scaling the transport vehicle top speed
				topSpeedScale : number
				--- allows scaling the transport vehicle noise
				noiseScale : number
				--- allows scaling the transport vehicle pollution
				pollutionScale : number
				--- allows scaling the transport vehicle comfort
				comfortScale : number
			end
			
			--- Contains current effective modifiers for the transport vehicle load speed.
			record LoadSpeedModifiers
				--- the modifier poriton because of overlength with the terminal
				vehicleOverlength : number
				--- the compatibility with the stock
				stockCompatibility : number
				--- the compatibility with the terminal
				vehicleCompatibility : number
				--- the incompatibility with the terminal
				vehicleIncompatibility : number

				--- computed total penalty from all modifiers
				getTotalPenalty : function(LoadSpeedModifiers) : number
			end

			--- Contains additional data for the transport vehicle
			record Config
				new : function() : Config

				transportModes : {TransportMode : boolean}
				allCaps : {CargoTypeId}
				--- all cargo capacities of the vehicle
				capacities : {CargoTypeId}
				loadSpeeds : {number}
				reversible : boolean
			end

			--- Contains additional data for the transport vehicle
			record LoadState
				new : function() : LoadState

				None : LoadState
				Arrived : LoadState
				Unloading : LoadState
				Loading : LoadState
				WaitForScheduledDeparture : LoadState
				Departing : LoadState
			end

			--- Contains information about pending split income for the transport vehicle
			record PendingIncomeParams
				new : function() : PendingIncomeParams

				--- Contains information about entity and revision for the pending income
				record EntityRev0
					--- the entity id
					entity : Engine.Entity
					--- the revision 0 of the entity
					rev0 : integer
				end

				--- total income pending to be unloaded
				amount : integer
				--- the carrier for which the income is pending
				carrier : Carrier
				--- accounted vehicle entity id
				vehicleEntity : Engine.Entity
				--- accounted line entity id
				lineEntity : Engine.Entity
			end

			new : function() : TransportVehicle

			--- the type of transport vehicle
			carrier : Carrier
			--- the configuration of vehicle models in this vehicle
			transportVehicleConfig : TransportVehicleConfig
			--- various configuration properties for the vehicle
			config : Config
			--- current state of the vehicle
			state : TransportVehicleState
			--- whether or not the user stopped the vehicle
			userStopped : boolean
			--- if in depot, the Entity Id of the depot
			depot : Engine.Entity
			--- whether or not the vehicle will be sold on arrival
			sellOnArrival : boolean
			--- the entity of the line (if assigned to one)
			line : Engine.Entity
			--- the stop index of the line (if assigned to one)
			stopIndex : integer

			--- The terminal to which the vehicle currently tries to go
			arrivalStationTerminal : StationTerminal
			--- If the arrivalStationTerminal is the final decision
			arrivalStationTerminalLocked : boolean
			--- timestamps of the last departures at each line stop
			lineStopDepartures : {integer}
			--- timestamp of the last departure at any line
			lastLineStopDeparture : integer
			--- time taken for each section between line stops
			sectionTimes : {number}
			--- available capacity per cargo type for each line stop
			lineStop2cargo2available : {{CargoTypeId}}

			--- current loading state of the vehicle
			loadState : LoadState
			--- how much time is left until the vehicle will start loading cargo
			timeUntilNextScheduledDeparture : number
			--- current effective load speed modifiers per cargo type
			loadSpeedModifiers : {CargoTypeId : LoadSpeedModifiers}
			--- how much time is left until the vehicle starts closing the doors
			timeUntilCloseDoors : number
			--- how much time is left until the vehicle leaves the terminal
			timeUntilDeparture : number
			--- time until the next load per cargo type
			timeUntilNextLoad : {CargoTypeId : number}
			--- time until the next unload per cargo type
			timeUntilNextUnload : {CargoTypeId : number}
			--- index of the last station/stock where cargo was loaded/unloaded if multiple compatible stocks are in reach of the current
			--- terminal of the currently loading/unloading cargo type.
			lastStationStockIndex : integer

			--- time at which the door have been closed/open
			doorsTime : integer
			--- amount of days waiting in depot
			daysInDepot : integer
			--- amount of days waiting at terminal
			daysAtTerminal : integer
			--- whether doors should be open or closed
			doorsOpen : boolean
			--- whether or not the vehicle has a path
			noPath : boolean
			--- whether the vehicle departure is managed by the game or not
			autoDeparture: boolean
			--- the maintenance station maintaining the vehicle
			maintenanceStation : Engine.Entity
			--- modifiers applied to the transport vehicle
			modifiers : Modifiers
			--- list of pending income
			unloadPendingIncome : PendingIncomeParams
			--- the closest town to the vehicle
			closestTown : Engine.Entity

			--- The last stops on the line the transport vehicle stopped at
			--- The length is limited to the number of stops on the line
			visitedStops : {integer}
		end

		--- Defines a vehicle depot
		record VehicleDepot
			new : function() : VehicleDepot

			--- The transport method for the depot, affects available vehicles
			carrier : Carrier
			transportModes : {TransportMode : boolean}
			--- the nodes that are entry points for the depot
			inNodes : {NodeId}
			--- the nodes that are exit points for the depot
			outNodes : {NodeId}
			state : integer
			doors : number
			stateTime : integer
			--- the area around the station where vehicles are maintained
			catchmentArea : CatchmentArea

			--- number of vehicles that can be maintained
			maintenancePool : integer
			--- maximum number of vehicles that were recently maintained at the same time
			maxPoolUsage : number
			--- average accumulated number of vehicles that were recently maintained at the same time
			averagePoolUsage : number
			--- number of ticks for recently maintained vehicles statistics
			poolUsageTicks : integer
			--- vehicle filter tags
			filterTags : {string}
		end

		--- Contains information about precedence and breaking.
		record VehicleOrder
			new : function() : VehicleOrder
			equals : function(VehicleOrder, VehicleOrder) : boolean

			--- the vehicle entity of the vehicle before this vehicle
			entity : Engine.Entity
			strongBrakeEntity : boolean
			waitingForSpace : boolean
			waitingForTrafficLight : boolean
		end

		--- Contains information about warehouses.
		record Warehouse
			new : function() : Warehouse

			--- contains coresponding stock list
			stockList : Engine.Entity
			--- containing the warehouse
			construction : Engine.Entity
		end

		--- Contains the geometry information for a single tile of water.
		record WaterMesh
			new : function() : WaterMesh

			--- Represents the boundary of a water mesh.
			record Contour
				new : function() : Contour

				--- The list of vertices of the contour
				vertices : {Vec2f}
				--- The list of normals at the vertex
				normals : {Vec2f}
			end

			--- level for the surface of the navigatable water
			waterLevel : number
			--- the list of vertices of the mesh
			vertices : {Vec2f}
			--- the water depth at the vertex position
			depths : {number}
			indices : {integer}
			--- a list with boundaries of the water mesh
			contours : {Contour}
			--- coordinate of the tile
			pos : Vec2i
		end

		--- The World Component
		record World
			new : function() : World
			cloudCoverage : number
		end
	end

	--- Represents a single component that can be attached to an entity.
	record ComponentType
		AIRCRAFT : ComponentType
		ANIMAL : ComponentType
		ASSET_GROUP : ComponentType
		BASE_EDGE : ComponentType
		BASE_EDGE_STREET : ComponentType
		BASE_NODE : ComponentType
		BASE_PARALLEL_STRIP : ComponentType
		CUSTOM_STATE : ComponentType
		EMISSION_EMITTER : ComponentType
		FIELD : ComponentType
		GAME_TIME : ComponentType
		GAME_SPEED : ComponentType
		MODEL_INSTANCE_LIST : ComponentType
		NAME : ComponentType
		LINE : ComponentType
		LOG_BOOK : ComponentType
		MODEL_PERSON : ComponentType
		MOVE_PATH : ComponentType
		MOVE_PATH_AIRCRAFT : ComponentType
		STATION : ComponentType
		STATION_GROUP : ComponentType
		SIM_PERSON : ComponentType
		SIM_PERSON_AT_TERMINAL : ComponentType
		SIM_PERSON_AT_VEHICLE : ComponentType
		SIM_CARGO : ComponentType
		SIM_ENTITY_AT_BUILDING : ComponentType
		SIM_ENTITY_AT_VEHICLE : ComponentType
		SIM_ENTITY_AT_TERMINAL : ComponentType
		SIM_ENTITY_IDLE : ComponentType
		SIM_ENTITY_MOVING : ComponentType
		SIGNAL_LIST : ComponentType
		TOWN : ComponentType
		INDUSTRY : ComponentType
		STOCK_LIST : ComponentType
		TOWN_BUILDING : ComponentType
		TRANSPORT_VEHICLE : ComponentType
		TRAIN : ComponentType
		CARRIAGE : ComponentType
		CARRIAGE_LIST : ComponentType
		VEHICLE_DEPOT : ComponentType
		COLOR : ComponentType
		BOUNDING_VOLUME : ComponentType
		CONSTRUCTION : ComponentType
		SUBCONSTRUCTION : ComponentType
		PERSON_CAPACITY : ComponentType
		PLAYER_OWNED : ComponentType
		ACCOUNT : ComponentType
		GAME_SCRIPT : ComponentType
		WAREHOUSE : ComponentType
		TRANSPORT_NETWORK : ComponentType
		MAINTENANCE_COST : ComponentType
		RAILROAD_CROSSING : ComponentType
		PLAYER : ComponentType
		WORLD : ComponentType
		BRIDGE : ComponentType
		BASE_NODE_CONFIG : ComponentType
		LAND_VEHICLE : ComponentType
		BASE_NODE_TRAFFIC_LIGHT : ComponentType
		EDGE_OBJECT : ComponentType
		EMISSION_GRID : ComponentType
		TERRAIN : ComponentType
		SHIP : ComponentType
	end

	--- Obtains a component from an entity, if available.
	--- @param entity the entity (must be a valid, existing entity)
	--- @param type the component type to obtain
	--- @return the component if the entity has one, or nil otherwise
	getComponent : function<T>(Entity, ComponentType) : T

	--- Optional filter configuration for `getEntitiesWithComponent`.
	record EntityFilters
		--- Only include entities owned by the given player entity.
		requireOwnedByPlayer : Engine.Entity

		--- Custom filter: Most flexible - but very slow.
		filterFn : function(Engine.Entity) : boolean
	end

	--- Loop over each entity with a given component.
	--- @param fn the callback called for each entity with the given component
	--- @param componentType the component used to filter the entities
	forEachEntityWithComponent : function(function(Entity), ComponentType)

	--- Loop over each entity in the engine.
	--- @param callback the callback called for each entity
	forEachEntity : function(function(Entity))

	--- Get each entity with a given component.
	--- @param componentType the component used to filter the entities
	--- @param filters optional table with filter configuration (`requireOwnedByPlayer` and `filterFn`)
	getEntitiesWithComponent : function(ComponentType, filters? : EntityFilters) : {Engine.Entity}

	--- Returns the revision of the entity.
	--- @param entity the entity
	--- @return the entity revision
	getRevision : function(Entity) : Revision

	--- Checks whether an entity exists.
	--- @param entity the entity
	--- @return true if the entity exists
	entityExists : function(Entity) : boolean

	record UtilTerrain
		--- Check if coordinate is within bounds of world.
		--- @param position world position with x and y coordinate from center of the map
		--- @return true if valid coordinate, false if non valid coordinate
		isValidCoordinate : function(Vec2f) : boolean

		--- Fetches height at the world position. When the coordinates are outside the map, the value of the nearest position on the map is returned.
		--- @param position world position with x and y coordinate from center of the map
		--- @return the height at the position
		getHeightAt : function(Vec2f) : number

		--- Fetches base height at the world position. Differently than `getHeightAt`, this does not include terrain alignments (non-permanent modifications)
		--- and has a lower resolution of 4 meters. When the coordinates are outside the map, the value of the nearest position on the map is returned.
		--- @param position world position with x and y coordinate from center of the map
		--- @return the height at the position
		getBaseHeightAt : function(Vec2f) : number

		--- Returns whether the given world position is on water, i.e. below the water level.
		--- @param position world position with x and y coordinate from center of the map
		--- @return true if the position is on water, false otherwise
		isOnWater : function(Vec2f) : boolean

		--- Fetches the entity at the given tile position.
		--- @param position tile position
		--- @return the heightmap entity at the position
		getHeightmapEntity : function(Vec2i) : Engine.Entity

		--- Returns the bounding box of the terrain.
		--- @return bounding box of the terrain
		getBoundingBox : function() : Box2f

		--- Creates a map data structure from the current game state.
		--- @param withHeightmap include heightmap data
		--- @param withTowns include town data
		--- @param withIndustries include industry data
		--- @param withAssets include asset data
		--- @return the generated map
		makeMapFromGame : function(withHeightmap : boolean, withTowns : boolean, withIndustries : boolean, withAssets : boolean) : GameMap

		--- Gets the entity revision numbers for all terrain entities.
		--- @return map of entity to revision number
		getTerrainEntityRevisions : function() : {Engine.Entity : Engine.Revision}

		--- Gets the base resolution of the terrain.
		--- @return the base resolution
		getBaseResolution : function() : Vec3f

		--- Gets the high resolution of the terrain.
		--- @return the high resolution
		getHighResolution : function() : Vec3f

		--- Calculates the ceiling of terrain fragment size in tiles based on percentage.
		--- @param percentage the percentage value
		--- @return the calculated terrain fragment size in tiles
		ceilTerrainFragmentInTiles : function(percentage : number) : integer
	end

	record MapGen
		--- Create a town proposal from a town list.
		createTowns : function(name : string, {GameMap.Town}) : TownResult

		--- Create an industry proposal from an industry list.
		createIndustries : function(name : string, {GameMap.Industry}) : IndustryResult

		--- Create default town connections.
		getDefaultTownConnections : function({GameMap.Town}) : {{integer, integer}}

		--- Returns the absolute limits of terrain height ranges.
		getMinMaxValidTerrainHeight : function() : {number, number}

		--- Returns the absolute limits of number of towns.
		getMinMaxValidNumTowns : function() : {integer, integer}

		--- Returns the absolute limits of number of industries.
		getMinMaxValidNumIndustries : function() : {integer, integer}
	end

	record Config
		--- Returns the config dict for the game.
		getConfigDict : function() : { string : string }

		--- Returns the mod params for the game.
		getModParams : function() : { string : table }
	end

	system : System
	terrain: UtilTerrain
	mapgen: MapGen
	util : EngineUtil
	config : Config
end

recordDef = false
