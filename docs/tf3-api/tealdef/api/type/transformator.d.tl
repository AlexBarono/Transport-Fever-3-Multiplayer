recordDef = true

--- Contains all type definitions for transformators
global type Engine

--- Transformator types
--- @category main
global record Transformator
	--- EmitModel in transformator
	record ModelEmitter
		getModelId : function(
			modelEmitter : ModelEmitter,
			resName : string
		) : integer
		emitModel : function(
			modelEmitter : ModelEmitter,
			modelId : integer,
			transfMat : Mat4f,
			animationStates : {Transformator.AnimationState},
			group : string,
			alignToTerrain : boolean
		)
		emitModels : function(
			modelEmitter : ModelEmitter,
			modelIds : {integer},
			gridSize : Vec2i,
			transfMat : Mat4f,
			distances : Vec2f,
			animationStates : {Transformator.AnimationState},
			alignToTerrain : boolean
		)
	end

	--- ParticleSystem of transformator
	record ParticleSystem
		getModelIndices : function(
			particleSystem : ParticleSystem
		) : {integer}
		setLifeTime : function(
			particleSystem : ParticleSystem,
			index : integer,
			lifeTime : ParticleParamFloat
		)
		getSize : function(
			particleSystem : ParticleSystem
		) : integer
		setFrequencyScale : function(
			particleSystem : ParticleSystem,
			index : integer,
			frequencyScale : number
		)
		setLifeTimeScale : function(
			particleSystem : ParticleSystem,
			index : integer,
			lifeTimeScale : number
		)
		setVelocityDampingFactor : function(
			particleSystem : ParticleSystem,
			index : integer,
			velocity : number
		)
		setColorOffset : function(
			particleSystem : ParticleSystem,
			index : integer,
			colorOffset : Vec3f
		)
		setVelocity : function(
			particleSystem : ParticleSystem,
			index : integer,
			velocity : Vec3f
		)
		setSizeScale01: function(
			particleSystem : ParticleSystem,
			index : integer,
			scale0 : number,
			scale1 : number
		)
		setAlbedoTexture : function(
			particleSystem : ParticleSystem,
			index : integer,
			albedoTexture : string
		)
		setNormalMapTexture : function(
			particleSystem : ParticleSystem,
			index : integer,
			normalMapTexture : string
		)
		setNumFrames : function(
			particleSystem : ParticleSystem,
			index : integer,
			numFrames : Vec2i
		)
		setFrame : function(
			particleSystem : ParticleSystem,
			index : integer,
			frame : ParticleParamFloat
		)
		setFrameProgressOverLifeTime : function(
			particleSystem : ParticleSystem,
			index : integer,
			frameProgressOverLifeTime : ParticleParamFloat
		)
		setFrameSpeed : function(
			particleSystem : ParticleSystem,
			index : integer,
			frameSpeed : ParticleParamFloat
		)
		setGravity : function(
			particleSystem : ParticleSystem,
			index : integer,
			gravity : ParticleParamFloat
		)
		setRotation : function(
			particleSystem : ParticleSystem,
			index : integer,
			rotation : ParticleParamFloat
		)
		setRotationByDirection : function(
			particleSystem : ParticleSystem,
			index : integer,
			rotationByDirection : ParticleParamFloat
		)
		setRotationSpeed : function(
			particleSystem : ParticleSystem,
			index : integer,
			rotationSpeed : ParticleParamFloat
		)
		getParticleId : function(
			particleSystem : ParticleSystem,
			index : integer
		) : string
	end

	--- Wheel information for user transformations
	record UserTransf
		transf : Mat4f
		type : integer
	end

	--- Information about the state for animations
	record StateInfo
		state : integer
		stateTime : integer
	end

	--- Information about depot for animations
	record DepotInfo
		stateInfo : StateInfo
	end

	--- Information about signals for animations
	record SignalListInfo
		stateInfo : StateInfo
	end

	--- Information about traffic lights for animations
	record TrafficLightInfo
		stateInfo : StateInfo
	end

	--- Information of rail road crossings for animations
	record RailRoadCrossingInfo
		stateInfo : StateInfo
		trafficDelay : integer
	end

	--- Information about persons for animations
	record ModelPersonInfo
		stateInfo : StateInfo
		movementType : integer
		distance : number
	end

	--- Information of idle persons for animations
	record ModelPersonIdleInfo
		arriveTime : integer
	end

	--- State information of animals for animations
	record AnimalAnimationStateInfo
		movementTypeIndex : integer
		targetChangedElapsed : number
		instIndex : integer
	end

	--- Information about group
	record GroupInfo
		children : {integer}
	end

	--- Information about bogie
	record BogieInfo
		posMin : number
		posMax : number
		offset : number
		zOffset : number
		upright : boolean
	end

	--- Vehicle Scripting Information
	record VehicleScriptingInfo
		speed : number
		topSpeed : number
		speed01 : number
		powerOutput : number
		power : number
		power01 : number

		cargoCapacityVehicle01 : number	-- -1.0 if no capacity in entire vehicle
		cargoCapacities01 : {number}	-- -1.0 for each carriage with no capacity

		loadState : Engine.Component.TransportVehicle.LoadState

		doorAnimationInfo : DoorAnimationInfo
		doorsLeft : boolean

		carriageListLength : integer
		positionInCarriageList : integer -- 0 index based

		maintenance : number	-- 0 is best, 1 is worst
		velocity : Vec3f
		direction : Vec3f
		acceleration : number
		brakeDecel : number
		inTunnel : boolean
		timeStanding : number
		approachingStation : boolean

		indicesLoadConfig : {integer}
		color : Vec3f
	end

	--- Aircraft Scripting Information
	record AircraftScriptingInfo
		flightState : FlightState
		gearTime : number
		gear : boolean
		hasPropsBlurred : boolean
		gearDuration : number
		bodyAngle : number
		wheelAngleZ : number
		totalDist : number
		touchesGround : boolean
		waiting : boolean

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

	--- Aircraft Static Scripting Information
	record AircraftStaticScriptingInfo
		isHelicopter : boolean
		powerIdle : number
		hasFlaps : boolean
		flapsDuration : number
	end

	--- Ship Scripting Information
	record ShipScriptingInfo
		rudderAngleZ : number
		taxiState : boolean

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

	--- Tram Scripting Information
	record TramScriptingInfo
		--NOTE: currently empty
	end

	--- Rail Vehicle Scripting Information
	record RailVehicleScriptingInfo
		axleRefWeight : number
		brakeDecelSmoothed : number
		chuffStep : number
		curvature : number
		curveSpeedLimit : number
		gameSpeedUp : number
		maxSideForce : number
		numAxles : number
		sideForce : number
		weight : number
	end

	--- Road Vehicle Scripting Information
	record RoadVehicleScriptingInfo
		wheelRotation : number
	end

	--- Land Vehicle Scripting Information
	record LandVehicleScriptingInfo
		wheelAnimationInfo : WheelAnimationInfo
		leftStationSince : number
		reversed : boolean
		carriagesReversed : {boolean}
		side : {boolean, boolean}
		brakingTimer : number
		turnLeft : boolean
		turnRight : boolean
	end

	--- Air Water Vehicle Scripting Information
	record AirWaterVehicleScriptingInfo
		--NOTE: currently empty
	end

	--- Industry Scripting Information
	record IndustryScriptingInfo
		boosted01 : number
		doubleBoosted01 : number
		idle01 : number
		level : number
		production01 : number

		workplaces : number
		progress : { number }
		producing : boolean
		boosting : boolean
	end

	--- Station Scripting Information
	record StationScriptingInfo
		cargo : number
		cargo01 : number
		crowd : number
		crowd01 : number
		terminals : number
	end

	--- Town Building Scripting Information
	record TownBuildingScriptingInfo
		underConstruction : number
		scaffold : boolean
	end

	record ModelMetadataInfo
		record Seat 
			transf : Mat4f
			animation : string
			group : string
			instanceIndex : number
			crew : boolean
		end

		seats : {Seat}
	end

	--- Information about wheel animation
	record WheelAnimationInfo
		totalDist : number
		drivingWheelRadius : number
		wheelDuration : number
	end
	--- Information for door animation
	record DoorAnimationInfo 
		name : string
		doorTime : number
		duration : number
	end
	--- Information about town building simulation persons for animations
	record SimPersonInfo 
		entity : Engine.Entity
		modelId : integer
	end
	--- Information about person capacity for animations
	record PersonCapacityInfo
		simPersons : {SimPersonInfo}
	end
	--- Information about a model
	record ModelInfo
		record WheelInfo
			index : integer
			x : number
			radius : number
			z : number
			animated : boolean
		end

		axles : {WheelInfo}
		wheels : {WheelInfo}
		wheelSigns : {Vec2f}
		steeringParts : {integer}
	end

	--- Vehicle Static Scripting Information
	record VehicleStaticScriptingInfo
		carriageEntity : Engine.Entity -- entity of the individual member of the carriage list
		modelInfo : ModelInfo
		purchaseTime : integer
	end

	--- Calendar Information
	record Calendar
		year : integer
		month : integer
		day : integer
	end

	--- Wall Clock Information
	record WallClock
		hour : integer
		minute : integer
		second : integer
	end

	--- World Scripting Information
	record WorldScriptingInfo
		cloudCoverage : number
		gameTime : integer
		timeOfDaySec : integer
		calendar : Calendar
		wallClock : WallClock
	end

	--- Info containing values for the edge at the requested position, some values are only valid at that exact point, others for the entire edge
	record VehicleEdgeInfo
		offset : number
		offsetClampedToPathEnd : number
		width : number -- 0 for rail tracks
		curvature : number
		slope : number -- 0 to 1.0 at 45 degrees slope
		speedLimit : number
		curveSpeedLimit : number
		hasElectricTrack : boolean
		catenaryHeight : number
	end

	record EdgeObjectInfo
		type : integer -- 0 stop left, 1 stop right, 2 signal
	end

	record EdgeDecorationInfo
		categories : {string}
	end

	--- Information related to one specified base edge or base node
	record BaseEdgeInfo
		edgeOffset : integer
		edgeOffsetClampedToEdgesCount : integer -- < 0 if not a valid BaseEdgeInfo result

		length : number

		onBaseEdge : boolean -- otherwise on BaseNode (crossing, ...) or construction (switch, depot, ...)
		onBaseNode : boolean

		roadType : integer -- 0 track, 1 street
		baseEdgeType : integer -- 0 normal, 1 bridge, 2 tunnel
		typeIndex : integer -- bridge/tunnel type
		edgeObjectInfos : {EdgeObjectInfo}
		edgeDecorationInfos : {EdgeDecorationInfo}
		catenaryHeight : number
		railBase : number
		railHeight : number
		railWidth : number
		streetCategories : {string}
	end

	--- Mini Api to request data related to land vehicles
	record LandVehicleScriptingApi
		getVehicleEdgeInfo : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			offset : number
		) : VehicleEdgeInfo
		getBaseEdgeInfo : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			edgeIndexOffset : integer
		) : BaseEdgeInfo
		getAverageCurvature : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			distanceFront : number,
			distanceBack : number
		) : number
		getAverageSlope : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			distanceFront : number,
			distanceBack : number
		) : number
		getAverageSpeedLimits : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			distanceFront : number,
			distanceBack : number
		) : {number, number} -- speedLimit, curveSpeedLimit
		getElectrificationChange : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			distanceFront : number
		) : {number, number} -- distance to next change, change tendency - < 0 changes to non-electrified, > 0 changes to electrified, == 0 no change
		getAverageCatenaryHeight : function(
			landVehicleScriptingApi : LandVehicleScriptingApi,
			distanceFront : number,
			distanceBack : number
		) : number
	end

	record AnimationState 
		userdata
		new : function() : AnimationState

		animation : string
		loop : boolean
		param : integer
		reversed : boolean
		startTime : integer
	end

	--- Transformation output, which contains user transformations and animations of transformation lua scripts
	record TransfOutput
		userdata

		getUserTransfs : function(
			transfOutput : TransfOutput
		) : {Transformator.UserTransf}
		setUserTransf : function(
			transfOutput : TransfOutput,
			index : integer,
			transfMat : Mat4f,
			absolute? : boolean
		)
		
		getAnimationStates : function(
			transfOutput : TransfOutput
		) : {AnimationState}

		--- Sets a specific animation to a specific frame
		--- @param transfOutput Handle to self
		--- @param animation Name of the animation to play
		--- @param startTime If non-negative, will be used as an offset into global time, i.e. param = gameTime - startTime
		--- @param param Only used if startTime is < 0, in  which case is the time (in milliseconds) of the animation frame
		--- @param loop Whether the animation should loop around or should stop at the end
		--- @param reversed Whether the animation has to loop backwards
		addAnimationState : function(
			transfOutput : TransfOutput,
			animation : string,
			startTime : number,
			param : number,
			loop : boolean,
			reversed : boolean
		)

		--- Start an animation for the running in the given interval (and then gets removed)
		--- @param transfOutput Handle to self
		--- @param animation Name of the animation to play
		--- @param startTime Initial keyframe (in milliseconds) of the animation, or nil for beginning of the animation
		--- @param endTime Final keyframe (in milliseconds) of the animation, or nil to run until animation end
		triggerAnimation : function(
			transfOutput : TransfOutput,
			animation : string,
			startTime? : integer,
			endTime? : integer
		)

		--- Sets custom values for instance attributes of the model instances as Vec4f
		--- Used to set colors
		--- @param transfOutput Handle to self
		--- @param position Position of the instance attribute (see below for builtin positions)
		--- @param value Value to set the attribute to
		setModelInstanceAttributeVec4f : function(
			transfOutput : TransfOutput,
			position : integer,
			value : Vec4f
		)
		
		--- Sets custom values for instance attributes of the model instances as Vec3f
		--- @param transfOutput Handle to self
		--- @param position Position of the instance attribute (see below for builtin positions)
		--- @param value Value to set the attribute to
		setModelInstanceAttributeVec3f : function(
			transfOutput : TransfOutput,
			position : integer,
			value : Vec3f
		)
		
		--- Sets custom values for instance attributes of the model instances as Vec2f
		--- @param transfOutput Handle to self
		--- @param position Position of the instance attribute (see below for builtin positions)
		--- @param value Value to set the attribute to
		setModelInstanceAttributeVec2f : function(
			transfOutput : TransfOutput,
			position : integer,
			value : Vec2f
		)

		--- Sets custom values for instance attributes of the model instances as floats
		--- Used to set age values
		--- @param transfOutput Handle to self
		--- @param position Position of the instance attribute (see below for builtin positions)
		--- @param value Value to set the attribute to
		setModelInstanceAttributeFloat : function(
			transfOutput : TransfOutput,
			position : integer,
			value : number
		)
	end

end

recordDef = false
