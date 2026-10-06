global recordDef = true

--- Contains game command objects and related utilities.

global type Engine
global type JournalEntry
global type CargoType
global type LayerConfig
global type Transformator
global type Mod
global type ModId
global type Modhub
global type TrackType

global type ResName = string
global type FilePath = string
global type Index = integer

global type CargoTypeId = integer
global type CargoClassId = integer
global type ConstructionId = integer
global type StockId = integer
global type App

global record orderedPairs<T, V>
	metamethod __call : (function({T : V}, any) : function() : T, V)
end

global record Vector<T>
	new : function() : Vector<T>
	--- 1-base index into a standard C++ vector
	at : function(v : Vector<T>, i : integer) : T
	pushBack : function(v : Vector<T>, t : T)
	size : function(v : Vector<T>) : integer
	asTable : function(v : Vector<T>) : {T}
	clone : function(v : Vector<T>) : Vector<T>
end

global record ipairs_native<T>
	metamethod __call : function(Vector<T>) : function() : integer, T
end

global record pairs_native<T, V>
	metamethod __call : function(Map<T, V>) : function() : T, V
end

global record Set<T>
	contains : function(s : Set<T>, t : T) : boolean
	insert : function(s : Set<T>, t : T) : boolean
	size : function(s : Set<T>) : integer
	asTable : function(s : Set<T>) : {T:boolean}
end

global record Map<K, V>
	find : function(m : Map<K, V>, k : K) : V
	insert : function(m : Map<K, V>, k : K, v : V)
	size : function(m : Map<K, V>) : integer
	asTable : function(m : Map<K, V>) : {K : V}
	next: function(k : K) : K
end

global type NativeLuaValue = string|number|boolean|nil|NativeLuaTable

global record NativeLuaTable
	find : function(m : NativeLuaTable, k : NativeLuaValue) : NativeLuaValue
	findPath : function(m : NativeLuaTable, k : {NativeLuaValue}) : NativeLuaValue
	insert : function(m : NativeLuaTable, k : NativeLuaValue, v : any)
	insert_native : function(m : NativeLuaTable, k : NativeLuaValue, v : NativeLuaValue)
	remove : function(m : NativeLuaTable, k : NativeLuaValue)
	size : function(m : NativeLuaTable) : integer
	asTable : function(m : NativeLuaTable) : table
	clone : function(m : NativeLuaTable) : NativeLuaTable
	next: function(m : NativeLuaTable, k? : NativeLuaValue) : NativeLuaValue
end

--- Savegame identifier with path and namespace
global record SaveGameId
	new : function() : SaveGameId
	path : string
	saveGameName : string
	saveGameNamespace : string
end

--- Platform device specifications
global record PlatformDeviceSpec
	gen : ConsoleGen
	resolution : Vec2i
end

global record GPUCapabilities
	hasDiscreteGPU : boolean
	hasUnsupportedGPU : boolean
end

--- Game screenshot data
global record GameScreenshot
	--- Screenshot width in pixels
	width : integer
	--- Screenshot height in pixels
	height : integer
	--- Raw image data
	image : {integer}
	--- Native vector of image data
	image_native : Vector<integer>
end

--- A structure that holds information about the company's value
global record CompanyValue
	totalScore : integer

	railVehicles : integer
	trams : integer
	roadVehicles : integer
	aircrafts : integer
	ships : integer

	trackTotalLength : integer
	trackElectricLength : integer
	bridgeTotalLength : integer
	tunnelTotalLength : integer
	roadTotalLength : integer
	suppliedTowns : integer
	connectedIndustries : integer

	numberOfLines : integer

	totalStations : integer
	railStations : integer
	tramStations : integer
	roadStations : integer
	aircraftStations : integer
	shipStations : integer

	topSpeed : number
	topLength : number
	oldestTransportVehicle : integer

	balance : integer
	totalAssets : integer
	debt : integer
end

--- A structure that holds information about the transportation data statistics.
global record TransportationStats
	passengersTransported : integer
	cargoTransported : integer
end

--- Marker for type-safe savegame metadata table
global record SavegameScriptMetadata
end

--- Game metadata from a savegame
global record GameMetadata
	date : integer
	--- Player's account balance
	balance : integer
	--- Current world population
	population : integer
	--- List of game mods used
	--- Year the game was started
	startYear : integer
	--- The number of vehicle models present in the savegame
	numVehicleModels : integer
	--- Map dimensions in meters
	terrainDimensions : Vec2i
	companyValue : CompanyValue
	transportationStats : TransportationStats

	scriptMetadata : SavegameScriptMetadata
	gameModDescs : {Mod.GameModDesc}
	--- Whether achievements can be earned
	achievementsEarnable : boolean

	--- Screenshot of the game
	screenshot : GameScreenshot
end

--- Information about savegame storage capacity
global record SaveGameStorageInfo
	--- Total storage space available, in bytes
	totalSpace : number
	--- Storage space currently used, in bytes
	usedSpace : number
end

--- Savegame data with info and error message
global record SaveGameData
	--- Detailed information about a savegame
	record SaveGameDetails
		new : function(SaveGameDetails) : SaveGameDetails

		metadata : GameMetadata
		mods : {Mod.ModId}
		configDict : {{string, string}}
		modParams : {string : {string : integer}}
		campaign : string
		mission : string
	end

	new : function(SaveGameData) : SaveGameData
	--- Error message if loading failed (empty string otherwise)
	errorMsg : string
	info : SaveGameDetails
end

global record SaveGameType
	Manual : SaveGameType
	Autosave : SaveGameType
	Crash : SaveGameType
	Exit : SaveGameType
end

--- Savegame info extracted solely from its filename
global record ParsedSavegameName
	type : SaveGameType
	groupName : string
	ingameTimestamp : string -- only for type == "autosave"
	fileTimestamp : string -- only for type == "crash"
end

--- Information about the map, for map generation purposes.
global record GameMap
	--- Information about towns on a map
	record Town
		new : function() : Town

		--- Town placement position
		pos : Vec2f

		--- Town name
		name : string
		--- The size factor for each district
		sizeFactors : {number}

		--- Cargo categories per land use type (note: these are *not* CargoTypeId's)
		landUse2CargoNeeds : {LandUseType : {{string, number}}}

		--- The town entity if it already exists
		existing : Engine.Entity
	end

	--- Information about industries on a map
	record Industry
		new : function() : Industry

		pos : Vec2f
		angle : number
		onWater : boolean
		fileName: string
		tag : string

		--- The industry entity if it already exists
		existing : Engine.Entity
	end

	--- Container for tree data to be placed on the map
	record MapTree
		--- Adds a tree to the map
		-- @param category The tree category
		-- @param position The world position
		add : function(GameMap.MapTree, string, Vec3f)
	end

	--- Container for asset data to be placed on the map
	record MapAsset
		--- Adds an asset to the map
		-- @param category The asset category
		-- @param position The world transform
		add : function(GameMap.MapAsset, string, Mat4f)
	end

	--- A single tree on the map
	record Tree
		--- Tree model id
		id : integer
		--- Tree position
		pos : Vec3f
	end

	--- A single asset on the map
	record Asset
		--- Asset model id
		id : integer
		--- Asset transform
		transf : Mat4f
	end

	new : function() : GameMap
	--- Copy constructor
	new : function(?GameMap) : GameMap

	setHeightMap : function(GameMap, integer, number)
	setBiomeMap : function(GameMap, integer, integer, integer) 

	heightmap : {number}

	--- numTilesX number of tiles (256 m x 256 blocks) in X direction
	numTilesX : integer
	--- numTilesY number of tiles (256 m x 256 blocks) in Y direction
	numTilesY : integer

	levels : integer
	offsetZ : number
	waterLevel : number
	climateId : string
	resolution : Vec3f
	towns : {GameMap.Town}
	industries : {GameMap.Industry}
	townConnections : {{integer, integer}}
	trees : GameMap.MapTree
	assets : GameMap.MapAsset
end

--- Asynchronous operation wrapper for background tasks
global record Async<T>
	isCompleted : function(Async<T>) : boolean
	--- Block until the task is complete and then return its result
	get : function(Async<T>) : T
	abort : function(Async<T>)
	getProgressMonitor : function(Async<T>) : App.ProgressMonitor
end

--- Information about a savegame
global record SaveGameInfo
	--- Creates a new SaveGameInfo.
	-- @return New SaveGameInfo
	new : function() : SaveGameInfo
	equals : function(SaveGameInfo, SaveGameInfo) : boolean

	--- File size in bytes
	size : integer
	timestamp : integer
	path : string
	--- ModId of the mod providing this save
	modId : ModId
	saveName : string
end

--- Parameters for starting a new game
global record StartGameParams
	--- Constructor
	new : function() : StartGameParams

	--- Map size in tiles
	numTiles : Vec2i
	--- Climate generator script resource name
	climateGenerator : string
	--- Terrain generator script resource name
	terrainGenerator : string
	--- Economy difficulty script resource name
	economy : string
	--- List of mod identifiers to load
	mods : {string}
	--- List of mod parameters
	modParams : {string : {string : integer}}
	--- Random seed for map generation
	seed : string
	--- Starting date for the game
	startDate : Date
	--- Starting time in seconds of the time
	startTimeOfDaySeconds : integer
	--- Starting cloud coverage
	startCloudCoverage : number
	--- Whether to start the game in map editor mode
	isMapEditor : boolean
	--- Whether to generate towns
	generateTowns : boolean
	--- Whether to generate industries
	generateIndustries : boolean
	--- Whether to generate assets
	generateAssets : boolean
	--- Configuration for the placement of industry and towns on max generation
	locationsConfig : BaseConfig.Locations
end

--- LogLevel for logging
global record LogLevel
	Critical : LogLevel
	Error : LogLevel
	Warning : LogLevel
	Message : LogLevel
	Verbose : LogLevel
end

--- DateFormat used for formatting calendar entries
global record DateFormat
	LONG : DateFormat
	SHORT : DateFormat
	MEDIUM : DateFormat
	FULL : DateFormat
	FILENAME : DateFormat
	--- Only output year
	YEAR : DateFormat
end

--- Carrier types for journal entries
global record Carrier
	metamethod __index : function(Carrier, string) : Carrier

	--- Road vehicles (trucks, buses, cars)
	ROAD : Carrier
	--- Rail vehicles (trains)
	RAIL : Carrier
	--- Tram vehicles
	TRAM : Carrier
	--- Other types of carriers
	OTHER : Carrier
	--- Aircraft (planes, helicopters)
	AIR : Carrier
	--- Water vehicles (ships, boats)
	WATER : Carrier
end

--- Types of objects that can be placed on a BaseEdge
global record EdgeObjectType
	--- Stop on the left side of the edge
	STOP_LEFT : EdgeObjectType
	--- Stop on the right side of the edge
	STOP_RIGHT : EdgeObjectType
	--- Signal controlling rail reservation
	SIGNAL : EdgeObjectType
end

--- Current state of a vehicle's movement
global record VehicleState
	--- Vehicle is actively moving
	RUNNING : VehicleState
	--- Vehicle is in the process of stopping (due to player / script interaction)
	STOPPING : VehicleState
	--- Vehicle is completely stopped and must be un-stopped by player / script
	STOPPED : VehicleState
	--- Vehicle has arrived at its destination
	ARRIVED : VehicleState
end

--- Current state of TransportVehicle
global record TransportVehicleState
	--- Vehicle is in a depot
	IN_DEPOT : TransportVehicleState
	--- Vehicle is traveling between terminals
	EN_ROUTE : TransportVehicleState
	--- Vehicle is at a terminal (station/stop)
	AT_TERMINAL : TransportVehicleState
	--- Vehicle is traveling to a depot
	GOING_TO_DEPOT : TransportVehicleState
end

--- TrafficLightPreference: controls whether a node/edge has a traffic light.
global record TrafficLightPreference
	YES : TrafficLightPreference
	NO : TrafficLightPreference
	AUTO : TrafficLightPreference
end

--- Base edge type
global record BaseEdgeType
	NORMAL : BaseEdgeType
	BRIDGE : BaseEdgeType
	TUNNEL : BaseEdgeType
end

--- A 2d vector of integers
-- Supports array subscript with `vec[i]` access. Supports addition `+`, subtraction `-`, multiplication `*` and division `/`.
global record Vec2i
	--- Creates a new vector.
	-- @return Vec2i(0,0),
	new : function() : Vec2i
	--- Creates a new vector.
	-- @param v Single value to set both x and y (optional)
	-- @return Vec2i(v,v)
	new : function(v : integer) : Vec2i
	--- Creates a new vector.
	-- @param x X coordinate
	-- @param y Y coordinate
	-- @return Vec2i(x,y)
	new : function(x : integer, y : integer) : Vec2i
	-- check for value-based equality
	equals : function(a : Vec2i, b : Vec2i) : boolean

	--- x coordinate
	x : integer
	--- y coordinate
	y : integer

	metamethod __add : function(Vec2i, Vec2i) : Vec2i
	metamethod __sub : function(Vec2i, Vec2i) : Vec2i
	metamethod __mul : function(Vec2i, Vec2i) : Vec2i
	metamethod __div : function(Vec2i, Vec2i) : Vec2i
end

--- A 2d vector of floats
-- Supports array subscript with `vec[i]` access. Supports addition `+`, subtraction `-`, multiplication `*` and division `/`.
global record Vec2f
	--- Creates a new vector.
	-- @return Vec2f(0,0)
	new : function() : Vec2f
	--- Creates a new vector.
	-- @param v Single value to set both x and y (optional)
	-- @return Vec2f(v,v)
	new : function(v : number) : Vec2f
	--- Creates a new vector.
	-- @param x X coordinate (optional)
	-- @param y Y coordinate (optional)
	-- @return Vec2f(x,y)
	new : function(x : number, y : number) : Vec2f
	-- check for value-based equality
	equals : function(a : Vec2f, b : Vec2f) : boolean

	-- creates a copy of a vec2f
	clone : function(Vec2f) : Vec2f

	--- x coordinate
	x : number
	--- y coordinate
	y : number

	metamethod __add : function(Vec2f, Vec2f) : Vec2f
	metamethod __sub : function(Vec2f, Vec2f) : Vec2f
	metamethod __mul : function(Vec2f, number) : Vec2f
	metamethod __div : function(Vec2f, number) : Vec2f

	--- Scale a vector by an amount
	-- @param s Scale amount
	-- @return Scaled vector
	scale : function(v : Vec2f, s : number) : Vec2f
	--- Normalize vector to unit length
	-- @return Normalized vector
	normalize : function(v : Vec2f) : Vec2f
	--- Calculate length of a vector
	-- @return Length
	length : function(v : Vec2f) : number

	--- Calculate distance between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Distance
	distance : function(a : Vec2f, b : Vec2f) : number
	--- Calculate squared distance between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Squared Distance
	distance2 : function(a : Vec2f, b : Vec2f) : number

	--- Linear interpolation between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @param t Interpolation parameter (0 to 1)
	-- @return Interpolated vector
	lerp : function(a : Vec2f, b : Vec2f, t : number) : Vec2f

	--- Calculate angle between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return angle (in radians)
	angle : function(Vec2f, Vec2f) : number
	--- Rotate vector by angle
	-- @param angle Rotation angle in radians
	-- @return Rotated vector
	rotate : function(v : Vec2f, angle : number) : Vec2f
end

--- A 3d vector of floats
-- Supports array subscript with `vec[i]` access. Supports addition `+`, subtraction `-`, multiplication `*` and division `/`.
global record Vec3f
	--- Creates a new vector.
	-- @return Vec3f(0,0,0)
	new : function() : Vec3f
	--- Creates a new vector.
	-- @param v Single value to set all components
	-- @return Vec3f(v,v,v)
	new : function(v : number) : Vec3f
	--- Creates a new vector.
	-- @param x X coordinate
	-- @param y Y coordinate
	-- @param z Z coordinate
	-- @return Vec3f(x,y,z)
	new : function(x : number, y : number, z : number) : Vec3f
	-- check for value-based equality
	equals : function(a : Vec3f, b : Vec3f) : boolean
	--- Create a copy of the vector
	-- @return Cloned vector
	clone : function(self : Vec3f) : Vec3f

	--- x coordinate
	x : number
	--- y coordinate
	y : number
	--- z coordinate
	z : number

	metamethod __add : function(Vec3f, Vec3f) : Vec3f
	metamethod __sub : function(Vec3f, Vec3f) : Vec3f
	metamethod __mul : function(Vec3f, number) : Vec3f
	metamethod __div : function(Vec3f, number) : Vec3f

	--- Scale vector by a factor
	-- @param s Scale factor
	-- @return Scaled vector
	scale : function(v : Vec3f, s : number) : Vec3f
	--- Normalize vector to unit length
	-- @return Normalized vector
	normalize : function(v : Vec3f) : Vec3f
	--- Calculate length of the vector
	-- @return Length
	length : function(v : Vec3f) : number

	--- Calculate distance between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Distance
	distance : function(a : Vec3f,  b : Vec3f) : number
	--- Calculate squared distance between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Squared distance
	distance2 : function(a : Vec3f, b : Vec3f) : number
	--- Calculate squared distance between the xy components of two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Squared distance
	distance2_2 : function(Vec3f, Vec3f) : number
	--- Calculate distance between xy components of two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return Squared distance
	distance_2 : function(a : Vec3f, b : Vec3f) : number

	--- Linear interpolation between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @param t Interpolation parameter (0 to 1)
	-- @return Interpolated vector
	lerp : function(a : Vec3f, b : Vec3f, t : number) : Vec3f
	--- Calculate angle between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return angle (in radians)
	angle : function(a : Vec3f, b : Vec3f) : number
	--- Calculate dot product of two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @return dot product
	dot : function(a : Vec3f, b : Vec3f) : number
end

--- A 4d vector of floats
-- Supports array subscript with `vec[i]` access. Supports addition `+`, subtraction `-`, multiplication `*` and division `/`.
global record Vec4f
	--- Creates a new vector.
	-- @return Vec4f(0,0,0,0)
	new : function() : Vec4f
	--- Creates a new vector.
	-- @param v Single value to set all components
	-- @return Vec4f(v,v,v,v)
	new : function(v : number) : Vec4f
	--- Creates a new vector.
	-- @param x X coordinate
	-- @param y Y coordinate
	-- @param z Z coordinate
	-- @param w W coordinate
	-- @return Vec4f(x, y, z, w)
	new : function(x : number, y : number, z : number, w : number) : Vec4f
	--- Creates a new vector from Vec3f and w component.
	-- @param v Vec3f for x, y, z components
	-- @param w W coordinate
	-- @return New Vec4f
	new : function(v : Vec3f, w : number) : Vec4f
	-- check for value-based equality
	equals : function(a : Vec4f, b : Vec4f) : boolean

	--- x coordinate
	x : number
	--- y coordinate
	y : number
	--- z coordinate
	z : number
	--- w coordinate
	w : number

	metamethod __add : function(Vec4f, Vec4f) : Vec4f
	metamethod __sub : function(Vec4f, Vec4f) : Vec4f
	metamethod __mul : function(Vec4f, number) : Vec4f
	metamethod __div : function(Vec4f, number) : Vec4f

	--- Linear interpolation between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @param t Interpolation parameter (0 to 1)
	-- @return Interpolated vector
	lerp : function(a : Vec4f, b : Vec4f, t : number) : Vec4f
end

--- A 5d vector of floats
-- Supports array subscript with `vec[i]` access. Supports addition `+`, subtraction `-`, multiplication `*` and division `/`.
global record Vec5f
	--- Creates a new vector.
	-- @return Vec5f(0, 0, 0, 0, 0)
	new : function() : Vec5f
	--- Creates a new vector.
	-- @param v Single value to set all components
	-- @return Vec5f(v, v, v, v, v)
	new : function(v : number) : Vec5f
	--- Creates a new vector.
	-- @param x X coordinate
	-- @param y Y coordinate
	-- @param z Z coordinate
	-- @param w W coordinate
	-- @param q Q coordinate
	-- @return Vec5f(x, y, z, w, q)
	new : function(x : number, y : number, z : number, w : number, q : number) : Vec5f
	-- check for value-based equality
	equals : function(a : Vec5f, b : Vec5f) : boolean

	--- x coordinate
	x : number
	--- y coordinate
	y : number
	--- z coordinate
	z : number
	--- w coordinate
	w : number
	--- q coordinate
	q : number

	metamethod __add : function(Vec5f, Vec5f) : Vec5f
	metamethod __sub : function(Vec5f, Vec5f) : Vec5f
	metamethod __mul : function(Vec5f, number) : Vec5f
	metamethod __div : function(Vec5f, number) : Vec5f

	--- Linear interpolation between two vectors
	-- @param a First vector
	-- @param b Second vector
	-- @param t Interpolation parameter (0 to 1)
	-- @return Interpolated vector
	lerp : function(a : Vec5f, b : Vec5f, t : number) : Vec5f
end

--- A 4x4 transformation matrix
-- Supports addition `+`, subtraction `-` and multiplication `*`. Supports array subscript with `mat[i]` access (16 elements in column-major order).
global record Mat4f
	--- Creates a new matrix.
	-- @return Identity matrix
	new : function() : Mat4f

	--- Creates a new matrix from Vec4f.
	-- @param v Vec4f to initialize all columns
	-- @return New Mat4f
	new : function(Vec4f) : Mat4f

	--- Creates a new matrix from four column vectors.
	-- @param col1 First column
	-- @param col2 Second column
	-- @param col3 Third column
	-- @param col4 Fourth column
	-- @return New Mat4f
	new : function(col1 : Vec4f, col2 : Vec4f, col3 : Vec4f, col4 : Vec4f) : Mat4f

	--- Create a copy of the matrix
	-- @return Cloned matrix
	clone : function(matrix : Mat4f) : Mat4f

	metamethod __index : function(Mat4f, integer) : number

	metamethod __add : function(Mat4f, Mat4f) : Mat4f
	metamethod __sub : function(Mat4f, Mat4f) : Mat4f
	metamethod __mul : function(Mat4f, Mat4f) : Mat4f

	--- Get column vector at index
	-- @param matrix the matrix
	-- @param colIndex Column index (1-4)
	-- @return Column vector
	cols : function(matrix : Mat4f, colIndex : integer) : Vec4f

	--- Get translation component of the matrix
	-- @return Translation vector
	getTransl : function(matrix : Mat4f) : Vec3f
	--- Set translation component of the matrix
	-- @param v Translation vector
	-- @return Modified matrix
	setTransl : function(matrix : Mat4f, v : Vec3f) : Mat4f

	--- Transform a position by the matrix
	-- @param v Position to transform
	-- @return Transformed position
	transformPosition : function(matrix : Mat4f, v : Vec3f) : Vec3f

	--- Transform a direction by the matrix
	-- @param v Direction to transform
	-- @return Transformed direction
	transformDirection : function(matrix : Mat4f, v : Vec3f) : Vec3f

	--- Creates a new Z-axis rotation
	-- @param angle Rotation angle in radians
	-- @return Rotation matrix
	rotZ : function(angle : number) : Mat4f
	--- Creates a new Y-axis rotation
	-- @param angle Rotation angle in radians
	-- @return Rotation matrix
	rotY : function(angle : number) : Mat4f
	--- Creates a new X-axis rotation
	-- @param angle Rotation angle in radians
	-- @return Rotation matrix
	rotX : function(angle : number) : Mat4f

	--- Creates a new Z-axis rotation matrix plus translation
	-- @param angle Rotation angle in radians
	-- @param transl Translation vector
	-- @return Transformation matrix
	rotZTransl : function(angle : number, transl : Vec3f) : Mat4f
	--- Creates a new Z-axis and Y-axis rotation matrix plus translation
	-- @param angles Rotation angles (x: Z angle, y: Y angle)
	-- @param transl Translation vector
	-- @return Transformation matrix
	rotZYTransl : function(angles : Vec2f, transl : Vec3f) : Mat4f
	--- Create scale matrix
	-- @param scale Scale factors
	-- @return Scale matrix
	scale : function(scale : Vec3f) : Mat4f
	--- Creates a new Z-axis rotation matrix plus translation and scale
	-- @param scale Scale factors
	-- @param angle Rotation angle in radians
	-- @param transl Translation vector
	-- @return Transformation matrix
	scaleRotZTransl : function(scale : Vec3f, angle : number, transl : Vec3f) : Mat4f
	--- Creates a new translation and scaling matrix
	-- @param scale Scale factors
	-- @param transl Translation vector
	-- @return Transformation matrix
	scaleTransl : function(scale : Vec3f, transl : Vec3f) : Mat4f
	--- Creates a new translation matrix
	-- @param transl Translation vector
	-- @return Translation matrix
	transl : function(transl : Vec3f) : Mat4f
end

--- A 3d bounding box
global record Box3f
	--- Creates a new Box3f
	new : function() : Box3f
	--- Creates a new Box3f
	new : function(min : Vec3f, max : Vec3f) : Box3f

	--- Minimum corner of the box
	min : Vec3f
	--- Maximum corner of the box
	max : Vec3f
end

--- A 2d bounding box
global record Box2f
	--- Creates a new Box2f
	new : function() : Box2f
	--- Creates a new Box2f
	new : function(min : Vec2f, max : Vec2f) : Box2f

	--- Minimum corner of the box
	min : Vec3f
	--- Maximum corner of the box
	max : Vec3f
end

--- A 2D grid of float values
global record Gridf
	--- Creates a new empty grid.
	-- @return New empty Gridf
	new : function() : Gridf
	--- Creates a new grid with specified dimensions.
	-- @param x0 X offset of the grid
	-- @param y0 Y offset of the grid
	-- @param width Grid width
	-- @param height Grid height
	-- @return New Gridf
	new : function(x0 : integer, y0 : integer, width : integer, height : integer) : Gridf
	--- Creates a new grid with specified dimensions and initial value.
	-- @param x0 X offset of the grid
	-- @param y0 Y offset of the grid
	-- @param width Grid width
	-- @param height Grid height
	-- @param value Initial value for all cells
	-- @return New Gridf
	new : function(x0 : integer, y0 : integer, width : integer, height : integer, value : number) : Gridf

	--- Grid width
	width : integer

	--- Grid height
	height : integer

	--- Get value at position. Returns 0 if position is out of bounds.
	-- @param pos Grid position
	-- @return Value at position
	at : function(pos : Vec2i) : number
end

--- A 2D grid of Vec2f values
global record GridVec2f
	--- Creates a new empty grid.
	-- @return New empty GridVec2f
	new : function() : GridVec2f
	--- Creates a new grid with specified dimensions.
	-- @param x0 X offset of the grid
	-- @param y0 Y offset of the grid
	-- @param width Grid width
	-- @param height Grid height
	-- @return New GridVec2f
	new : function(x0 : integer, y0 : integer, width : integer, height : integer) : GridVec2f
	--- Creates a new grid with specified dimensions and initial value.
	-- @param x0 X offset of the grid
	-- @param y0 Y offset of the grid
	-- @param width Grid width
	-- @param height Grid height
	-- @param value Initial value for all cells
	-- @return New GridVec2f
	new : function(x0 : integer, y0 : integer, width : integer, height : integer, value : number) : GridVec2f

	--- Grid width
	width : integer
	--- Grid height
	height : integer
	--- X offset of the grid
	x0 : integer
	--- Y offset of the grid
	y0 : integer
	--- Get value at position
	-- @param grid Grid to query
	-- @param pos Grid position
	-- @return Vec2f value at position
	at : function(grid : GridVec2f, pos : Vec2i) : Vec2f
end

--- Camera view information
global record View
	--- Get the camera eye position
	-- @return Eye position
	getEye : function(view : View) :Vec3f
	--- Get the camera center position
	-- @return Center position
	getCenter : function(view : View) : Vec3f
	--- Get the camera up vector
	-- @return Up vector
	getUp : function(view : View) : Vec3f

	--- Check if a sphere is visible in the current view
	-- @param view The view
	-- @param position Center of the sphere
	-- @param radius Radius of the sphere
	-- @return True if visible
	isVisible : function(view : View, position : Vec3f, radius : number) : boolean
end

--- Date representation with year, month, and day
global record Date
	--- Creates a new date from year, month and day.
	-- @param year Year
	-- @param month Month (1-12)
	-- @param day Day (1-31)
	-- @return New Date
	new : function(year : integer, month : integer, day : integer) : Date
	--- Creates a new date from year
	-- @param year Year
	-- @return New Date
	new : function(year : integer) : Date

	--- Get date of current day
	-- @return Current date
	now : function() : Date

	--- Create date at the first day of the given year
	-- @param integer year integer
	-- @return A new Date
	fromYear : function(year : integer) : Date

	--- Parse date from string
	-- @param str Date string
	-- @return Parsed date
	fromString : function(str : string) : Date

	--- Get the last day of the current month
	-- @param current Current date
	-- @return Date representing end of month
	getEndOfMonth : function(current : Date) : Date
	--- Get the day of the week of the current date
	-- @param current Current date
	-- @return The day of the week
	getDayOfWeek : function(current : Date) : integer

	--- add offset in days
	-- @param date the date to offset
	-- @param numDays number of days to add
	-- @return New Date offset by the given number of days
	addOffsetDays : function(date : Date, numDays : integer) : Date

	--- Year component
	year : integer
	--- Month component (1-12)
	month : integer
	--- Day component (1-31)
	day : integer
end

--- Identifies a Terminal inside a StationGroup
global record StationTerminal
	--- Constructor: creates empty terminal reference
	new : function() : StationTerminal
	--- Copy constructor
	new : function(StationTerminal) : StationTerminal
	--- Constructor with station and terminal indices
	-- @param station The zero-based station index in the StationGroup
	-- @param terminal The zero-based terminal index in the Station
	new : function(station : integer, terminal : integer) : StationTerminal

	--- The zero-based station index in the StationGroup
	station : integer
	--- The zero-based terminal index in the Station
	terminal : integer
end

--- A single node within a TRANSPORT_NETWORK component.
global record Node
end

--- Defines the geometry (shape) of an edge
global record EdgeGeometry
	--- Type of the edge geometry
	record Type
		ARC : Type
		STRAIGHT : Type
		CUBIC_SPLINE : Type
		CUBIC_OFFSET_SPLINE : Type
	end
	--- Arc geometry parameters
	record Arc
		new : function() : Arc
		--- Center point of the arc
		center : Vec2f
		--- Radius of the arc
		radius : number
		--- Starting angle in radians
		startAngle : number
		--- Arc angle in radians
		angle : number
	end
	--- Straight line geometry parameters
	record Straight
		new : function() : Straight
		--- Start and end positions
		pos : {Vec2f}
	end
	--- Cubic spline geometry parameters
	record CubicSpline
		new : function() : CubicSpline
		--- Start and end positions
		pos : {Vec2f}
		--- Tangent vectors at start and end
		tangent : {Vec2f}
	end
	--- Cubic offset spline geometry parameters
	record CubicOffsetSpline
		new : function() : CubicOffsetSpline
		--- Start and end positions
		pos : {Vec2f}
		--- Tangent vectors at start and end
		tangent : {Vec2f}
		--- Offset value
		offset : number
	end

	new : function() : EdgeGeometry

	--- Type for the 2D (xy) shape
	type : Type

	--- Arc parameters (if type is ARC)
	arc : Arc
	--- Straight parameters (if type is STRAIGHT)
	straight : Straight
	--- Cubic spline parameters (if type is CUBIC_SPLINE)
	cubicSpline : CubicSpline
	--- Cubic offset spline parameters (if type is CUBIC_OFFSET_SPLINE)
	cubicOffsetSpline : CubicOffsetSpline

	--- Vertical tangents at start and end
	tangent : Vec2f
	--- Heights at start and end
	height : Vec2f
	--- Length of the edge
	length : number
	--- Width of the edge
	width : number

	--- Finds the parameter on a spline for a given world position
	-- @param geom the edge geometry to sample
	-- @param pos a 3d world position to search for
	-- @param maxSteps the maximum number of steps to perform
	-- @param tol a maximal distance for the point to be found
	-- @return paramAndFound the parameter value and whether there was a point on the spline
	locate : function(geom : EdgeGeometry, pos : Vec3f, maxSteps : integer, tol : number) : {number, boolean}

	--- Calculate a position on an edgegeometry, given a parameter in [0, 1]
	-- @param geom the edge geometry to sample
	-- @param param a number in [0, 1]
	-- @return the position, tangent and second derivative at the specified param
	calcPos : function(geom : EdgeGeometry, param : number) : {Vec3f, Vec3f, Vec3f}
end

--- A single edge within a Transport Network.
global record Edge
	--- Start and end node
	conns : {NodeId}
	--- Edge geometry definition
	geometry : EdgeGeometry
	--- Transport modes allowed on this edge
	transportModes : {TransportMode : boolean}
	--- Speed limit for the edge
	speedLimit : number
	--- Speed limit due to curvature
	curveSpeedLimit : number
	--- Current speed on the edge (for statistics)
	curSpeed : number

	linkable : integer

	--- Penalty for pedestrian walking
	pedestrianWalkPenalty : number

	precedence : boolean

	--- Noise modifier
	noiseModifier : number

	--- Pollution modifier
	pollutionModifier : number

	--- Whether the edge needs reservation
	needsReservation : boolean

	--- Whether the edge only allowed to be traversed in forward direction
	forwardOnly : boolean
end

--- References a single transport network node within a transport network entity
global record NodeId
	new : function() : NodeId
	--- Constructor
	-- @param entity The TransportNetwork entity
	-- @param index The zero-based index within the nodes field of the TransportNetwork component
	new : function(entity : Engine.Entity, index : integer) : NodeId

	--- The TransportNetwork entity
	entity : Engine.Entity

	--- The zero-based index within the nodes field of the TransportNetwork component
	index : integer
end

--- References a single transport network edge within a transport network entity
global record EdgeId
	new : function() : EdgeId
	--- Constructor with entity and index
	-- @param entity The TransportNetwork entity
	-- @param index The zero-based index within the edges field of the TransportNetwork component
	new : function(entity : integer, index : integer) : EdgeId

	--- The TransportNetwork entity
	entity : Engine.Entity

	--- The zero-basd index within the edges field of the TransportNetwork component
	index : integer
end

--- References a position inside an EdgeId
global record EdgePos
	new : function() : EdgePos
	--- Copy constructor
	new : function(EdgePos) : EdgePos

	equals : function(a : EdgePos, b : EdgePos) : boolean

	--- The edge (entity and index within TransportNetwork)
	edgeId : EdgeId

	--- The position on the edge
	param : number
end

global record PrecedencePreference
	YES : PrecedencePreference
	NO : PrecedencePreference
	AUTO : PrecedencePreference
end

--- A custom configuration for lanes on crossings
global record LaneConnection
	--- Incoming segment entity
	segment0 : Engine.Entity
	--- Incoming lane index (zero-based, from left to right when looking from the Node to segment0)
	lane0 : integer
	--- Outgoing segment entity
	segment1 : Engine.Entity
	--- Outgoing lane index (zero-based, from left to right when looking from the Node to segment1)
	lane1 : integer
	--- Whether connection supports road
	withRoad : boolean
	--- Whether connection supports tram
	withTram : boolean
end

--- Additional traffic light data for a base node
global record TrafficLightData
	state2lockedLanes : {{integer}}
	state2redLightModelIndices : {{integer}}
	state2duration : {number}
	animatedModels : {integer}
end


--- Contains a procedurally generated sub-shape.
global record SubShape
	faces : {{Vec3f}}
	startRule : integer
	--- Min height for collision purposes.
	height0 : number
	--- Max height for collision purposes.
	height1 : number
end

--- Contains a procedurally generated shape.
global record Shape
	--- List of subshapes for the shape.
	subShapes : {SubShape}
	--- Procedural generator (index) used to generate the shape.
	generator : integer
end

--- References the position of a waypoint, which is either an EdgePos or a Vec3f
global record Waypoint
	new : function() : Waypoint
	new : function(Waypoint) : Waypoint
	clone : function(Waypoint) : Waypoint

	equals : function(a : Waypoint, b : Waypoint)

	--- Edge position when using lanes
	edgePos : EdgePos
	--- 3D position for ships and aircraft
	pos : Vec3f

	--- tag to uniquely identify a waypoint even across addition/removal
	tag : integer
end

--- Identifies a street/track signal
global record SignalId
	new : function() : SignalId
	new : function(SignalId) : SignalId

	--- The entity of the SignalList
	entity : Engine.Entity
	--- The zero-based index of the signal inside the signal list
	index : integer
end

--- Data for a Station terminal.
global record Terminal

	--- The position (node) where the vehicle will attempt to stop
	vehicleNodeId : NodeId

	--- List of all nodes for the person/cargo wait area
	personNodes : {NodeId}
	--- List of all edges for the person/cargo wait area
	personEdges : {EdgeId}
	--- list of all edges for the vehicle to stop
	vehicleEdges : {EdgePos}

	--- Identifying tag
	tag : integer

	--- Whether this terminal can handle cargo
	cargoLoad : boolean
	--- Whether this terminal can handle passengers
	passengersLoad : boolean
	--- Whether this terminal can handle cargo
	cargoUnload : boolean
	--- Whether this terminal can handle passengers
	passengersUnload : boolean

	transportModes : {TransportMode : boolean}

	--- Information about terminal cargo transfer speeds
	record TerminalCargoTransferSpeed
		--- Set of cargo types this setting applies to
		cargoTypeSet : CargoTypeSet
		--- Speed modifier for loading cargo
		loadSpeedModifier : number
		--- Length of the terminal section
		length : number
	end

	--- List of cargo transfer speed configurations
	cargoTransferSpeeds : {TerminalCargoTransferSpeed}
	--- Control happiness decrease speed for waiting passengers
	comfortFactor : number

	--- How many people can fit the specific terminal
	capacity : integer
	--- Weighting for the automatic terminal assignment of lines, lower means less important
	terminalAssignmentWeight : number
end

--- Data for a Station
global record Station
	--- Defines a common pool in a station for overflowing terminal capacities
	record Pool
		new : function() : Pool

		--- the list of edges of the shared waiting area
		edges : {EdgeId}
		--- the size of the shared pool
		capacity : integer
	end
		
	new : function() : Station
			
	--- A tag for identifying station between upgrades
	tag : integer
	-- list of all terminals
	terminals : {Terminal}
	-- list of all catchment areas
	catchmentAreas : {CatchmentArea}
	-- pool
	pool : Pool
end

--- A custom component might contain any data in form of a lua table (without functions) and can used with custom
--- scripts to create new custom objects in game
global record ComponentCustomState
	new : function() : ComponentCustomState
	new : function(ComponentCustomState) : Engine.Component.Line

	--- Any lua table, as long as it is serializable
	state : table
end

--- Configuration for loading cargo into a vehicle compartment
global record LoadConfig
	new : function() : LoadConfig

	--- Index of the load configuration
	loadConfigIndex : integer
	--- Type of cargo to load
	cargoTypeId : CargoTypeId
end

--- Contains all data describing a game script
global record GameScriptDesc
	new : function() : GameScriptDesc
	new : function(GameScriptDesc) : GameScriptDesc

	postUpdateScript : ScriptRef
	handleEventScript : ScriptRef
	guiUpdateScript : ScriptRef
	guiHandleEventScript : ScriptRef
	updateScript : ScriptRef
end

--- References a function in a lua script file with ".script" extension.
global record ScriptRef
	new : function() : ScriptRef

	--- The script path, toghether with the lua path inside the function.
	-- <p/>
	-- For example, this is the reference for a Crane flock function:<br/>
	-- "models/model/animal/animal.flock.crane"
	-- <ul>
	-- <li>the tokens separated by '/' before '.' are taken as part of the the path: "models/model/animal/animal"</li>
	-- <li>the tokens after the second '.' represent the lua path (in this case "flock.crane")</li>
	-- </ul>
	fileName : string

	--- A lua table of closure parameters that will be added at the end of the parameter list when the script is called.
	params : table
end

--- Used to configure new modules
global record ModuleDesc
	new : function() : ModuleDesc
	
	--- Resource name of the module file
	fileName : ResName

	--- Type of the module, a module of a specific type can be built only on slots with the same type
	type : string

	--- Whether it is automatically removed when building something on it (e.g. farm fields)
	autoRemovable : boolean

	--- Availability by year for module builder
	availability : ModelMetadata.Availability
	--- Localized strings and icons paths for user interface
	description : ModelMetadata.Description
	--- Unused
	category : ModelMetadata.Category
	--- Cost per unit
	cost : ModelMetadata.Cost
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory

	-- Sound resource (.builder_audio) for construction action
	builderAudioRes : ResName

	--- Additional metadata as table
	metadata : table
	--- Additional metadata as native map
	metadata_native : Map<string, number>

	--- Deprecated
	relativePath : string
	--- Script function that gets called once per build module after the updateScript of the construction has run
	updateScript : ScriptRef
	--- Script function used to generate module preview when building with module builder
	getModelsScript : ScriptRef
end

--- Environmental modifiers affecting construction or vehicle performance
global record Modifiers
	new : function() : Modifiers
	new : function(copy : Modifiers) : Modifiers
	equals : function(a : Modifiers, b : Modifiers) : boolean

	--- Noise level modifier as an additive factor
	noiseModifier : number
	--- Pollution level modifier as an additive factor
	pollutionModifier : number
	--- Top speed modifier as an additive factor
	maxSpeedModifier : number
end

--- Modular construction slot
global record Slot
	--- Autofill slots are used by field construction to add satellites automatically when the construction spawns
	autoFill : boolean
	--- Unique identifier for the slot, can also be used to reconstruct the coordinates of the slot when encoded as specific pattern
	id : integer
	--- Type of the slot: only modules of the same type can be built on this slot
	type : string
	--- Transformation relative to the construction origin
	transf : Mat4f
	--- Extent of the slot relative to it's origin, (x, y) are the distances to the left, resp. right, and (z, w) are the distances
	--- to the south and north part (when seen from above)
	spacing : Vec4f

	--- Height of the slot for collision purposes
	height : number
	--- Shape of the module snap point visualization, 0 = square, 1 = triangle, 2 = rectangle
	shape : integer
	--- Slots with this flag will be moved vertically to macht the height of the terrain (used e.g. for fields)
	alignToTerrain : boolean
	--- Modules in slots with this flag can be replaced by other modules of the same type without bulldozing first
	replaceable : boolean
end

--- Slot configuration can specify additional properties for slots of a given type
global record SlotConfig
	--- Max number of modules of this type that might be built
	maxModules : integer
	--- Message for when this limit is reached
	message : string
	--- Slots with this flag will not collide with other objects, but only the slot itself, the final construction
	--- still has to pass the usual collision checks
	skipCollisionCheck : boolean
end

--- Contains information about a street/track signal
global record Signal
	--- Enum containing the type of the signal
	record Type
		--- Normal signal
		SIGNAL : Type
		--- One-way signal
		ONE_WAY_SIGNAL : Type
		--- Waypoint
		WAYPOINT : Type
	end

	--- EdgeId and direction pair
	edgePr : {EdgeId, boolean}
	--- The type of the signal
	type : Type
	--- Current animation playing
	state : integer
	--- Timer for the animation
	stateTime : integer
end

--- Configuration for a single vehicle part/unit
global record VehiclePart
	new : function() : VehiclePart

	modelId : integer
	--- Whether the vehicle part is reversed (facing backwards)
	reversed : boolean
	--- Cargo configuration for the model. One entry per compartment. -1 means automatic selection of load config.
	compartment2loadConfig : {LoadConfig}

	color : Vec3f
end

--- A subsection of a Transport Vehicle.
global record TransportVehiclePart
	--- Creates a new TransportVehiclePart.
	-- @return New TransportVehiclePart
	new : function() : TransportVehiclePart

	--- Base vehicle part configuration
	part : VehiclePart
	--- Game time when this part was purchased
	purchaseTime : integer
	maintenanceChange : number
	maintenanceState : number
	--- Automatic load configuration per compartment
	autoLoadConfig : { boolean }
end

--- Complete configuration for a TransportVehicle (train consist, bus, etc.)
global record TransportVehicleConfig
	new : function() : TransportVehicleConfig
	new : function(TransportVehicleConfig) : TransportVehicleConfig

	--- List of all vehicle parts in order
	vehicles : {TransportVehiclePart}
	--- Vehicles can be composed into groups, each entry is the size of the group.
	-- The sum of all entries must be the total of vehicles.
	-- <p/>Example:<br/> for a train made of a multiple unit with three cars and 1 extra waggon would be `{3, 1}`.
	vehicleGroups : {integer}
	--- for each group, if it is a multiple unit, stores the res name
	muFileNames : {string}
end

--- Movement information for land vehicles (trains, trams, road vehicles)
global record LandVehicleMoveInfo
	availPower : number
	traction : number
	tractiveEffort : number
	--- Available power per vehicle part
	vehicleAvailPower : {number}
end

--- Configuration of vehicles that can use the line
global record LineVehicleInfo
	--- Type of tranport modes that can use the line
	transportModes : {TransportMode : boolean}
end

--- Movement information for ships
global record ShipInfo
	--- Maximum speed (in m/s)
	topSpeed : number
	maxTractiveEffort : number
	availablePower : number
end

--- Movement information for aircraft
global record AircraftInfo
	--- Aircraft weight (in kg)
	weight : number
	--- Maximum speed (in m/s)
	topSpeed : number
	--- Distance required for landing (in meters)
	landingDistance : number
	--- Maximum engine thrust (in kN)
	maxThrust : number
	--- Idle engine thrust (in kN)
	idleThrust : number
	--- Position of main landing gear
	mainGear : Vec2f

	bodyAngle : number

	--- How far forward the front of the airfract is (in meters)
	forwardOffset : number
	--- How far backwards the front of the airfract is (in meters)
	backwardOffset : number

	--- How far from the hold line the aircraft is supposed to wait (meters)
	taxiHoldOffset : number

	--- Whether the aircraft has flaps
	hasFlaps : boolean

	--- Whether this is a helicopter
	isHelicopter : boolean
end

--- Specify additional variants of the construction by providing a list of modules and the slot in which they belong
global record ConstructionTemplateData
	--- List of modules that come with the construction
	initialModules : {ResName : integer}
	--- Additional scriptparams that are used for this specific template
	params : {ScriptParam}
end

--- Static construction template configuration
global record StaticConstructionTemplate
	initialModules : {ResName : integer}
end

--- Dynamic construction template configuration
global record DynamicConstructionTemplate
	params : {ScriptParam}
end

--- Construction template with availability and type information
global record ConstructionTemplate
	--- Specific availability (date) for the template (optional)
	availability : ModelMetadata.Availability
	--- Localized strings and icons paths for user interface
	desc : ModelMetadata.Description
	--- Additional slot configuration and params
	data : ConstructionTemplateData
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory
	-- Sound resource (.builder_audio) for construction action
	builderAudioRes : ResName
	configureHudIconsScript : ScriptRef
end

--- Town building parameters
global record TownBuildingParams
	--- One of residential, commercial or industrial
	landUseType : LandUseType
	--- Level, which is directly related to capacity and size of the building
	level : integer
	--- (x, y) dimension in parcel cells for the building
	parcelSize : Vec2i
end

--- Specification for town building types
global record BuildingType
	constructionFile : string
	params : TownBuildingParams
end

global record ConstructionInstanceMetadata
end

global record SubconstructionInstanceMetadata
end

global record ConstructionDescMetadata
	record EmissionConfig
		noise : number
		pollution : number
	end

	emissionConfig : EmissionConfig
end

--- Describes a construction
global record ConstructionDesc
	record SnapConfig
		rail : boolean
		road : boolean
		water : boolean
	end
	record EdgeObject
		--- Minimum distance to crossings (in meters)
		minDistToCrossing : number
		--- Whether edge object snaps to streets
		snapToStreet : boolean
		--- Whether edge object snaps to tracks
		snapToTrack : boolean
		--- Whether edge object has cargo catchment area
		catchmentCargo : boolean
		--- Whether edge object has passenger catchment area
		catchmentPassengers : boolean
		--- Catchment area radius (in meters)
		catchmentAreaRadius : number
	end
	new : function(?ConstructionDesc) : ConstructionDesc

	updateScript : ScriptRef

	configureLayerScript : ScriptRef
	configureHudIconsScript : ScriptRef
	hudIconScript : ScriptRef
	entityWindowScript : ScriptRef

	--- A file name or unique identifier for the construction.
	fileName : string

	availability : ModelMetadata.Availability
	--- Defines the sound emitted by the model when in-game
	soundConfig : ModelMetadata.SoundConfig
	description : ModelMetadata.Description
	categoryList : ModelMetadata.CategoryList

	--- A list of parameters that can be used to configure the construction.
	params : {ScriptParam}
	categories : {string}
	order : number
	menuCategory : ModelMetadata.MenuCategory
	--- [DEPRECATED] Use metaconstructions instead
	constructionTemplates : {ConstructionTemplate}
	--- [DEPRECATED] Use metaconstructions instead
	constructionTemplates_native : Vector<ConstructionTemplate>
	placementTag : string
	metadata : ConstructionDescMetadata
	snapping : SnapConfig
	
	undergroundView : boolean
	heightAdjustable : boolean
	isIndustry : boolean
	--- Optional edge object configuration
	edgeObject : EdgeObject

	townBuildingParams : TownBuildingParams
	costsYearProgression : boolean
end


global record ConstructionScriptParam
	enum Type
		--- Push button
		"Button"
		--- Slider
		"Slider"
		--- Drop-down combo box
		"ComboBox"
		--- Button with an icon
		"IconButton"
		--- Check box
		"CheckBox"
	end

	enum Location
		--- Default construction parameter panel
		"Default"
		--- Toolbar area of construction panel
		"Toolbar"
	end

	enum DisplayMode
		--- For BottomBar==on is Horizontal, for BottomBar==off is Sparse
		"Default"
		--- Value is collapsed, full parameter is shown in a callout
		"Compact"
		--- Label is shown left of value
		"Horizontal"
		--- Label is shown above value
		"Vertical"
		--- Label is shown above the value, and the value might grow to multiple lines
		"Sparse"
	end

	--- Unique key that is passed to the construction functions
	key : string
	--- Display name
	name : string
	--- Display Group:
	--- - If hideLabel is true, items will be grouped horizontally
	--- - Else items will be separated by a divider
	group : string
	--- Tooltip to display over certain parameters
	tooltip : string
	--- All display values of the params
	values : {string}
	--- Specified return values instead of default 1, 2, 3...
	numbers : {number}
	--- Tooltips for the individual values
	tooltips : {string}
	--- This param can be changed when the construction is already built
	postConstructionModifiable : boolean
	--- Allow to hide the label
	hideLabel : boolean
	--- Image representations of the values (for Compact Mode)
	images : {string}
	--- Default index/state
	defaultIndex : Index

	--- Type of ui shown in user interface selection
	uiType : Type
	--- construction menu has two possible locations for parameters: default or toolbar
	location : Location
	--- displayMode controls whether the parameter is displayed in default or compact mode
	displayMode : DisplayMode

	--- Tags associated with the script param for filtering
	tags : {string}
	--- Availability from
	yearFrom : integer
	--- Availability to
	yearTo : integer

	--- callback function to allow dynamic disabling or hiding of the paramter
	--- function(params : {string : number}, scriptRefParams : table) : ConstructionMenuParam.CheckEnabledResult
	checkEnabledScript : ScriptRef

	--- callback function to allow returning any value on input actions
	--- function(value : number, direction : integer, precise : boolean) : number
	stepValueScript : ScriptRef

	--- callback function to allow formatting the value display in the UI
	--- function(value : number) : string
	formatValueScript : ScriptRef
end

--- A Metaconstruction is a collection of constructions and modules that can be simultaneously be built
--- (replaces the deprecated construction templates)
global record MetaConstructionDesc
	--- Creates a new MetaConstructionDesc object
	new : function(?MetaConstructionDesc) : MetaConstructionDesc

	--- Main menu availability range
	availability : ModelMetadata.Availability
	--- Textual description and icons
	description : ModelMetadata.Description
	--- Configuration for building sounds
	soundConfig : ModelMetadata.SoundConfig
	--- Additional tags
	categoryList : ModelMetadata.CategoryList

	--- Parameters passed to the template function
	params : {ConstructionScriptParam}
	--- Menu category
	menuCategory : ModelMetadata.MenuCategory

	--- Enable underground parameters when building
	undergroundView : boolean
	--- Enable height adjustment options when building
	heightAdjustable : boolean
	isIndustry : boolean
	--- Enable heigh modification grid visualization when building
	heightModView : boolean

	--- Custom layer function for display when building
	configureLayerScript : ScriptRef
	--- Custom layer function for display when building
	configureHudIconsScript : ScriptRef

	--- Additional user defined metadata
	metadata : ConstructionDescMetadata

	--- Relative path to use withing template script
	relativePath : string
	--- A definition of a script function returning a list of construction, modules and transforms
	createTemplateScript : ScriptRef

	order : integer
end

--- A very precise clock.
global record Clock
	--- Constructs a new intance of a clock and starts its timer
	new : function() : Clock

	--- Get elapsed time since clock construction in microseconds
	getTime : function(Clock) : integer
end

--- Helper class that allows loading and calling files in other modules
global record LoaderHelper
	useFn : function(LoaderHelper, string)
end

--- An object used to disconnect callbacks.
global record Connection
	--- The callback will be no longer called
	disconnect : function(Connection)
end

--- Enumeration for land use types
global record LandUseType
	RESIDENTIAL : LandUseType
	COMMERCIAL : LandUseType
	INDUSTRIAL : LandUseType
end

--- Enum containing the type of the signal
global record SignalType
	PATH_SIGNAL : SignalType
	WAYPOINT : SignalType
	ONE_WAY_PATH_SIGNAL : SignalType
end

global record VehicleEngineType
	HORSE : VehicleEngineType
	STEAM : VehicleEngineType
	ELECTRIC : VehicleEngineType
	DIESEL : VehicleEngineType
end

--- Defines the stock list type
global record StockListType
	InputStock : StockListType
	OutputStock : StockListType
	StorageStock : StockListType
end

--- Defines the type of a tram track.
global record TramTrackType
	NO : TramTrackType
	YES : TramTrackType
	ELECTRIC : TramTrackType
end

--- Platform represents the platform type.
global record Platform
	Windows : Platform
	Linux : Platform
	Mac : Platform
	XBoxSeries : Platform
	PS5 : Platform
	PS : Platform
	XBox : Platform
	Desktop : Platform
	Console : Platform
end

global record ConsoleGen
	Gen9pro : ConsoleGen
	Gen9standard : ConsoleGen
	Gen9base : ConsoleGen
	PC : ConsoleGen
end

--- Represent the reason why the user doesn't have access to UGC content
global record UgcAccessLimitedReason
	None : UgcAccessLimitedReason
	NotSignedIn : UgcAccessLimitedReason
	Restricted : UgcAccessLimitedReason
	Error : UgcAccessLimitedReason
end

--- Vendor represents the vendor (store) type.
global record Vendor
	Steam : Vendor
	Gog : Vendor
	Eos : Vendor
	MacAppstore : Vendor
	Microsoft : Vendor
	Sony : Vendor
	Dev : Vendor
end


--- Road vs Track type.
global record RoadType
	STREET : RoadType
	TRACK : RoadType
end

--- UI Type for displaying the parameter. Used to configure the parameters used for constructions.
global record ScriptParamType
	Button : ScriptParamType
	Slider : ScriptParamType
	ComboBox : ScriptParamType
	IconButton : ScriptParamType
	CheckBox : ScriptParamType
end

--- Controls bottom bar mode of the parameter
global record ScriptParamLocation
	Default : ScriptParamLocation
	--- special location for construction menu parameters, which will be displayed in the tool bar on the left side
	Toolbar : ScriptParamLocation
end

--- Controls how the parameter is displayed in the UI
global record ScriptParamDisplayMode
	--- For BottomBar==on is Horizontal, for BottomBar==off is Sparse
	Default : ScriptParamDisplayMode
	--- Value is collapsed, full parameter is shown in a callout
	Compact : ScriptParamDisplayMode
	--- Value is shown left of value
	Horizontal : ScriptParamDisplayMode
	--- Value is shown above value
	Vertical : ScriptParamDisplayMode
	--- Label is shown above the value, and the value might grow to multiple lines
	Sparse : ScriptParamDisplayMode
end

--- DistanceSpeedUnit represents the unit of measurement used for distance and speed.
global record DistanceSpeedUnit
	Metric : DistanceSpeedUnit
	Imperial : DistanceSpeedUnit
end

--- HudEffectMode configures the HUD effects
global record HudEffectMode
	Always : HudEffectMode
	CockpitOnly : HudEffectMode
	Never : HudEffectMode
end

--- FontScaleClass represents the current UI font scaling factor.
global record FontScaleClass
	Small : FontScaleClass
	Medium : FontScaleClass
	Large : FontScaleClass
end

--- MoneyMode represents the money mode.
global record MoneyMode
	RAW : MoneyMode
	KMB : MoneyMode
end

--- PowerUnit represents the unit of measurement used for power.
global record PowerUnit
	KW : PowerUnit
	HP : PowerUnit
end

--- WeightUnit represents the unit of measurement used for weight.
global record WeightUnit
	T : WeightUnit
	KG : WeightUnit
	TN_SH : WeightUnit
	LB : WeightUnit
end

--- ForceUnit represents the unit of measurement used for force.
global record ForceUnit
	KN : ForceUnit
	KGF : ForceUnit
	LBF : ForceUnit
end

global record Gender
	FEMALE : Gender
	MALE : Gender
end

--- Flight State of an Aircraft
global record FlightState
	Taxi0 : FlightState
	TakeOff : FlightState
	Flight : FlightState
	Approach : FlightState
	Landing : FlightState
	Taxi1 : FlightState
end

--- Easing functions for particle curve interpolation
global record Easing
	Linear : integer
	EaseOutSqrt : integer
	EaseInSine : integer
	EaseOutSine : integer
	EaseInOutSine : integer
	EaseInQuad : integer
	EaseOutQuad : integer
	EaseInOutQuad : integer
	EaseInCubic : integer
	EaseOutCubic : integer
	EaseInOutCubic : integer
	EaseInQuart : integer
	EaseOutQuart : integer
	EaseInOutQuart : integer
	EaseInQuint : integer
	EaseOutQuint : integer
	EaseInOutQuint : integer
	EaseInExpo : integer
	EaseOutExpo : integer
	EaseInOutExpo : integer
	EaseInCirc : integer
	EaseOutCirc : integer
	EaseInOutCirc : integer
	EaseInBack : integer
	EaseOutBack : integer
	EaseInOutBack : integer
	EaseInElastic : integer
	EaseOutElastic : integer
	EaseInOutElastic : integer
	EaseInBounce : integer
	EaseOutBounce : integer
	EaseInOutBounce : integer
end

global record BackgroundContrastMode
	Never : integer
	LineVehicleManager : integer
	ModuleBuilder : integer
	Both : integer
end

global record Enum
	LogLevel : LogLevel
	SaveGameType : SaveGameType
	DateFormat : DateFormat
	EdgeObjectType : EdgeObjectType
	TransportVehicleState : TransportVehicleState
	Carrier : Carrier
	SignalType : SignalType
	VehicleEngineType : VehicleEngineType
	LineProblem : LineProblem
	LineStationProblem : LineStationProblem
	VehicleProblem : VehicleProblem
	VehicleIconType : VehicleIconType
	TownProblem : TownProblem
	StockListType : StockListType
	ConstructionType : ConstructionType
	TransportMode : TransportMode
	TramTrackType : TramTrackType
	LandUseType : LandUseType
	InputMode : InputMode
	GamepadType : GamepadType
	Platform : Platform
	Vendor : Vendor
	ConsoleGen : ConsoleGen
	TrafficLightPreference : TrafficLightPreference
	BaseEdgeType : BaseEdgeType
	MoveMode : MoveMode
	RoadType : RoadType
	ScriptParamType : ScriptParamType
	ScriptParamLocation : ScriptParamLocation
	ScriptParamDisplayMode : ScriptParamDisplayMode
	DistanceSpeedUnit : DistanceSpeedUnit
	HudEffectMode : HudEffectMode
	FontScaleClass : FontScaleClass
	MoneyMode : MoneyMode
	PowerUnit : PowerUnit
	WeightUnit : WeightUnit
	ForceUnit : ForceUnit
	Gender : Gender
	UgcAccessLimitedReason : UgcAccessLimitedReason
	FlightState : FlightState
	Easing : Easing
	PdxErrorCodes : PdxErrorCodes
	PdxThirdPartyLinkState : PdxThirdPartyLinkState
	PdxThirdPartyAutoLoginPromptState : PdxThirdPartyAutoLoginPromptState
	BackgroundContrastMode : BackgroundContrastMode
end

--- Information about the problem of a line.
global record LineProblem
	NOTHING  : integer
	ZERO_OR_ONE_STATION : integer
	DOUBLE_STATIONS : integer
	INCOMPATIBLE_STATIONS : integer
	NO_PATH : integer
	BAD_ALTERNATIVE_TERMINAL : integer
end

--- Information about the problem of station within a line.
global record LineStationProblem
	StopUseless  : integer
	PassengerStopUseless : integer
	CargoStopUseless : integer
	AllPassengerStopUseless : integer
	CargoTypeUnloadUseless : integer
	CargoTypeLoadUseless : integer
end

--- Information about the problem of a vehicle.
global record VehicleProblem
	NoPathElectric  : integer
	NoPathShip : integer
	NoPathAircraft : integer
	NoPathGeneric : integer
	Blocked : integer
end

--- Icon type used to represent a vehicle.
global record VehicleIconType
	Bus : VehicleIconType
	Truck : VehicleIconType
	TrainSteam : VehicleIconType
	TrainElectric : VehicleIconType
	TrainDiesel : VehicleIconType
	Tram : VehicleIconType
	Aircraft : VehicleIconType
	Helicopter : VehicleIconType
	Ship : VehicleIconType
end

--- Town connection problem.
global record TownProblem
	Disconnected  : TownProblem
	Overlength : TownProblem
end

--- Type of the construction for displaying in the correct UI category and controlling specific behaviour for the type.
global record ConstructionType
	STREET_STATION : ConstructionType
	RAIL_STATION : ConstructionType
	AIRPORT : ConstructionType
	HARBOR : ConstructionType
	STREET_STATION_CARGO : ConstructionType
	RAIL_STATION_CARGO : ConstructionType
	HARBOR_CARGO : ConstructionType
	STREET_DEPOT : ConstructionType
	RAIL_DEPOT : ConstructionType
	WATER_DEPOT : ConstructionType
	INDUSTRY : ConstructionType
	WAREHOUSE : ConstructionType
	ASSET_DEFAULT : ConstructionType
	ASSET_TRACK : ConstructionType
	TOWN_BUILDING : ConstructionType
	STREET_CONSTRUCTION : ConstructionType
	NONE : ConstructionType
	AIRPORT_CARGO : ConstructionType
	TRACK_CONSTRUCTION : ConstructionType
	WATER_WAYPOINT : ConstructionType
end

--- Defines the transport mode (this is used to blacklist/whitelist vehicles onto transport network edges).
-- These values are mosly used in a bit field to influence the pathfinding for vehicles and people.
global record TransportMode
	PERSON : TransportMode
	CARGO : TransportMode
	CAR : TransportMode
	BUS : TransportMode
	TRUCK : TransportMode
	TRAM : TransportMode
	ELECTRIC_TRAM : TransportMode
	TRAIN : TransportMode
	ELECTRIC_TRAIN : TransportMode
	AIRCRAFT : TransportMode
	SHIP : TransportMode
	SMALL_AIRCRAFT : TransportMode
	SMALL_SHIP : TransportMode
	HELICOPTER : TransportMode
	TRAM_TRACK : TransportMode
	ELECTRIC_TRAM_TRACK : TransportMode
end

--- A model in the world, with complete information
global record ModelInstance
	--- The model id, referenced in modelRep
	modelId : integer
	--- The model transform at the previous frame
	transf0 : Mat4f
	--- The model transform
	transf: Mat4f
	--- Zero-basd index of the transformator for the model (-1 if none)
	transformator : integer
end

--- A model in the world, with very light information
global record ThinModelInstance
	--- The model id, referenced in modelRep
	modelId : integer
	--- The position in the world
	pos : Vec3f
	--- The rotation angle (in radians)
	rot : number
	--- The scale in all directions
	scale : number
end

global record LineOrEdges
	line : Engine.Entity
	lineStop0 : integer
	lineStop1 : integer
	lineTerminal1 : {Engine.Entity, integer}
	edges : {EdgePos}
end

--- A path comprised of EdgeId and directions
global record Path
	--- Create a new instance of a Path object
	new : function() : Path

	--- List of edges and their directions (true = forward, false = reverse)
	edges : {{EdgeId, boolean}}
	--- The actual end of the path (i.e. where to stop) as offset from the end
	endOffset : integer
	--- The position at which the alternative terminal choice will start, as an offset from the end
	terminalDecisionOffset : integer

	earlyArrivalIndices : integer
end

--- The position on a Path
global record PathPos
	--- Create a new instance of a PathPos object
	new : function() : PathPos

	--- The zero-based index within a path
	edgeIndex : integer
	--- The position on the spline, relative to the length of the spline
	pos : number
	--- The position on the spline, normalized as parameter from 0 to 1
	pos01 : number
end

--- The position in the world
global record PathPosData
	--- Position in world coordinates
	position : Vec3f
	--- First derivative of position (velocity direction)
	pPrime : Vec3f
	--- Second derivative of position (acceleration direction)
	pPrimePrime : Vec3f
end

--- A path comprised of EdgePathEdges that does not necessarily start/end on a Port
global record ExtPath
	--- A path edge of an ExtPath.
	-- It can be either an EdgeRange (a sub-interval of an edge) or a LinkEdge connecting two arbitrary points of different edges.
	record ExtPathEdge
		--- If the edge represents an EdgeRange, provides access to its data (nil otherwise)
		range : EdgeRange
		--- If the edge represents a LinkEdge, provides access to its data (nil otherwise)
		link : LinkEdge

		--- An EdgeRange of an ExtPath.ExtPathEdge
		record EdgeRange
			--- The ID of the corresponding transport edge
			edgeId : EdgeId
			--- The start and end positions (range: 0.0 - 1.0)
			params : {number, number}
			--- Direction along the edge (true if along the direction of edgeId, false for reverse)
			dir : boolean
		end

		--- A LinkEdge of an ExtPath.ExtPathEdge
		record LinkEdge
			--- The two locations that are connected
			points : {EdgePos, EdgePos}
		end
	end

	edges : {ExtPathEdge}
end

--- Specifies the intersection of two edges, with waiting area for vehicles.
global record EdgeIsect
	--- Data for an edge intersection entry
	record Info
		--- The index of the other edge in the intersection
		index : integer
		--- The parameter position on the edge
		param : number
		--- The world position of the intersection
		pos : Vec3f
	end

	--- The two intersection info entries for each of the two edges
	infos : {Info, Info}
end

global record PathFactoryInput
	fromEdgesWalk : {EdgePos}
	fromEdgesDrive : {EdgePos}
	fromLineOrEdges : LineOrEdges
	moveMode2costFactor : {number, number, number}
	toEntityWalk : Engine.Entity
	toEdgesDrive : {EdgePos}
	fromEdgesWalkForDrive : {EdgePos}
	toEdgesWalkForDrive : {EdgePos}
	cargoType : CargoTypeId
end

global record MoveMode
	WALK : MoveMode
	DRIVE : MoveMode
	LINES : MoveMode
end

--- Output result from pathfinding
global record PathFactoryOutput
	record LineSection
		line : Engine.Entity
		lineStop0 : integer
		lineStop1 : integer
	end

	line0 : LineSection
	line1 : LineSection
	path : ExtPath
	cost : number
	moveMode : MoveMode
end

--- Runway type enumeration
global record RunwayType
	--- Landing runway
	LANDING : RunwayType
	--- Takeoff runway
	TAKEOFF : RunwayType
end

--- Contains runway data
global record Runway
	--- Type of runway (landing or takeoff)
	type : RunwayType
	--- Node ID of the runway
	nodeId : NodeId
	--- List of edge IDs that make up the runway
	edgeIds : {EdgeId}
end

--- Abstraction of heightmap data, consisting of a cell with floating point values at each point
global record HeightmapNew
	--- The total size of the heightmap (x, y)
	getSize : function() : Vec2i
	--- Get the value of the heightmap at the given x, y coordinate
	--- @param x x coordinate
	--- @param y y coordinate
	at : function(integer, integer) : number
end

--- Log level enumeration
global record LogLevel
	Raw : LogLevel
	Error : LogLevel
	Warning : LogLevel
	Message : LogLevel
	Verbose : LogLevel
end

--- Terrain alignment type enumeration
global record TerrainAlignmentType
	EQUAL : TerrainAlignmentType
	LESS : TerrainAlignmentType
	GREATER : TerrainAlignmentType
end

--- Terrain alignment configuration
global record TerrainAlignment
	triangles : {{Vec3f, Vec3f, Vec3f}}
	weights : {{number, number, number}}
	type : TerrainAlignmentType
	bbox : Box2f
end

--- Identifies a Port of a Node within a transport network
global record PortId
	--- The NodeId of the node this port belongs to
	nodeId : NodeId
	--- The zero-based port index on the node
	port : integer
end

--- Contains the processed result with all edge links.
global record TpNetLinkProposal
	--- An individual link entry in a TpNetLinkProposal
	record Data
		--- The EdgePos pair making up the link
		link : {EdgePos, EdgePos}
	end

	--- Links to remove
	toRemove : {Data}
	--- Links to add
	toAdd : {Data}
end

--- Information about the problem state of a stop within a line.
global record StopState
	--- Stop is empty / valid
	empty : boolean
	--- No path between stops
	noPath : boolean
	--- No path from an alternative stop
	noPathFromAlternative : boolean
	--- No path to an alternative stop
	noPathToAlternative : boolean
	--- Stop is a duplicate
	duplicateStop : boolean
	--- Stop is incompatible with the line's transport mode
	incompatibleStop : boolean
	--- No path for a location stop
	noPathLocation : boolean
end

--- Proposal context to configure how the proposal is to be applied
global record Context
	new : function() : Context

	checkTerrainAlignment : boolean
	--- If true, attempts to simplifyy the base edge and base node graph 
	cleanupStreetGraph : boolean
	gatherBuildings : boolean
	gatherFields : boolean
	player : Engine.Entity
	refundableEntities : {{Engine.Entity, integer}, {Engine.Revision, integer}}
	--- Find colliding bridge pillars and try to move them off the side
	extendProposalRedoPillars : boolean
end

--- A more complete version of the SimpleProposal.
-- Most data can be read from a ProposalData or in the result of api.cmd.makeWorldBuildProposalCmd.
global record Proposal
	userdata

	--- Edge object information
	record EdgeObject
		--- Resulting entity
		resultEntity : Engine.Entity
		--- Category (0 = stop, 1 = waypoint, 2 = signal)
		category : integer
		--- Model instance for the edge object
		modelInstance : ModelInstance
		--- Player entity that owns this edge object
		playerEntity : Engine.Entity
		--- Whether on left side
		left : boolean
	end

	--- An entity with a BaseNode.
	-- Used to specify a new base node entity to be added.
	record NodeAndEntity
		new : function() : NodeAndEntity
		entity : Engine.Entity
		comp : Engine.Component.BaseNode
	end

	--- An entity with a BaseEdge component and extra information.
	record SegmentAndEntity
		new : function() : SegmentAndEntity
		entity : Engine.Entity
		comp : Engine.Component.BaseEdge
		--- Type (0 = street, 1 = track)
		type : integer -- 0 = street, 1 = track
		--- Street edge component
		streetEdge : Engine.Component.BaseEdgeStreet

		--- Emission emitter component (optional)
		emissionEmitter : Engine.Component.EmissionEmitter
		--- Player owned component (optional)
		playerOwned : Engine.Component.PlayerOwned
	end

	--- An entity with a BaseNodeLaneConnection component.
	-- Used to specify a new base node configuration entity to be added.
	record BaseNodeLaneConnectionAndEntity
		new : function() : BaseNodeLaneConnectionAndEntity
		comp : Engine.Component.BaseNodeConfig
		entity : Engine.Entity
	end

	--- A more complete version of the SimpleStreetProposal.
	-- Most data can be read from a ProposalData or in the result of cmd.makeWorldBuildProposalCmd.
	record StreetProposal
		--- Added nodes
		addedNodes : {NodeAndEntity}
		--- Added nodes as native vector
		addedNodes_native : Vector<NodeAndEntity>

		--- Added segments
		addedSegments : {SegmentAndEntity}
		--- Added segments as native vector
		addedSegments_native : Vector<SegmentAndEntity>

		--- Removed segments
		removedSegments : {SegmentAndEntity}
		--- Removed nodes
		removedNodes : {NodeAndEntity}

		--- Edge objects to add
		edgeObjectsToAdd : {EdgeObject}
		--- Mapping of new to old edge objects
		new2oldEdgeObjects : {Engine.Entity : {Engine.Entity}}
		--- Mapping of old to new edge objects
		old2newEdgeObjects : {Engine.Entity : {Engine.Entity}}

		--- Node configurations that will be added
		nodeConfigsToAdd : {BaseNodeLaneConnectionAndEntity}
		--- Node configurations that will be removed (node itself cannot be removed at the same time)
		nodeConfigsToRemove : {Engine.Entity}
	end

	--- Transformed model information
	record TransformedModel
		id : string
		tag : integer
		transf : Mat4f
		thin : boolean
	end

	record Subconstruction
		models : {TransformedModel}
		models_native : Vector<TransformedModel>
		metadata : SubconstructionInstanceMetadata -- used by nils to fill C++ (updateFn)
		station : Station
		colliders : {Collider}
	end

	--- A construction: usually contains stations, depots, town buildings or industries.
	record Construction
		--- all subconstructions generated by the construction
		subconstructions : {Subconstruction}
		--- all subconstructions generated by the construction, as native vector
		subconstructions_native : Vector<Subconstruction>

		--- the resource name of the construction (or the id in case of dynamic constructions)
		fileName : string

		--- nodes that belong to the construction and cannot be moved
		frozenNodes : {Engine.Entity}
		--- frozenEdges edges that belong to the construction and cannot be moved
		frozenEdges : {Engine.Entity}

		--- depots that belong to the construction
		depots : {Engine.Entity}

		--- stations that belong to the construction
		stations : {Engine.Entity}

		--- industries that belong to the construction
		industries : {Engine.Entity}

		--- town buildings that belong to the construction
		townBuildings : {Engine.Entity}

		--- Construction metadata persisted per instance
		persistentMetadata : ConstructionInstanceMetadata

		--- construction params
		params : table
	end

	record StreetTerminal
		cargo : boolean
		passengers : boolean
		capacity : integer
		wantSymmetric : boolean
		cargoUnload : boolean
		cargoLoad : boolean
	end

	record Signal
		type : SignalType
	end

	--- Construction entity data for use in proposals
	-- Most data can be read from a ProposalData or in the result of cmd.makeWorldBuildProposalCmd.
	record ConstructionEntity
		--- Construction resource name
		fileName : ResName
		--- Whether it has cargo platform
		hasCargoPlatform : boolean
		--- Construction description
		desc : ConstructionDesc
		--- Construction data
		construction : Construction
		--- Transformation matrix
		transf : Mat4f
		--- Owning player entity
		playerEntity : Engine.Entity
	end

	--- Contains proposal terrain modifications.
	record Terrain
		baseHeightMod : GridVec2f
	end

	new : function() : Proposal
	clone : function(Proposal) : Proposal

	--- Street proposal
	proposal : StreetProposal
	--- Entities to remove
	toRemove : {Engine.Entity}
	--- Entities to remove as native vector
	toRemove_native : Vector<Engine.Entity>

	--- Mapping from old to new entities
	old2new : {Engine.Entity : integer}

	--- Construction entities to add
	toAdd : {ConstructionEntity}

	--- Construction entities to add as native vector
	toAdd_native : Vector<ConstructionEntity>

	--- Terrain modifications
	terrain : Terrain
end

--- Contains the processed result of a construction
global record ConstructionResult
	subconstructions : {Proposal.Subconstruction}
	metadata : ConstructionInstanceMetadata
	cost : number
	maintenanceCost : number
	maintenanceCarrier : string
	streetTerminal : Proposal.StreetTerminal
	params : table
end

--- Contains the processed result of a Proposal.
global record ProposalData
	record SubconstructionData
		station : Engine.Component.Station
	end

	record ConstructionData
		boundingVolume : Engine.Component.BoundingVolume
		subconstructionDatas : {SubconstructionData}
		subconstructionDatas_native : Vector<SubconstructionData>
	end

	-- Collision information of the Proposal.
	record CollisionInfo
		--- More data about the collision.
		record EntityData
			entity : Engine.Entity
		end

		collisionEntities : {EntityData}

		autoRemovalEntity2models : {Engine.Entity : {{integer, integer}}}

		buildingEntities : {Engine.Entity}
		removableModules : {Engine.Entity}
	end

	--- Contains error information for a proposal.
	-- Wherever a construction cannot be built for any reason, then the ErrorState will contain
	-- one or more message signaling the error type.
	record ErrorState
		critical : boolean
		messages : {string}
		warnings : {string}
		infos : {string}
	end

	--- Information about a parallel strip proposal.
	record ParallelStripProposal
		--- The parallel strips to add
		toAdd : {Engine.Component.BaseParallelStrip}
		--- The parallel strips to add as native vector
		toAdd_native : Vector<Engine.Component.BaseParallelStrip>

		--- The parallel strips to remove
		toRemove : {Engine.Entity}
		--- The parallel strips to remove as native vector
		toRemove_native : Vector<Engine.Entity>
	end

	collisionInfo : CollisionInfo
	old2new : {Engine.Entity : integer}
	toAddData : {ConstructionData}
	toAddData_native : Vector<ConstructionData>

	parallelProposal : ParallelStripProposal

	terrainPreviewHeightModLocations : {Vec3f}
	terrainPreviewHeightModCutFill : {Vec2f}

	errorState : ErrorState

	entity2tn : {Engine.Entity : Engine.Component.TransportNetwork}
	tpNetLinkProposal : TpNetLinkProposal

	costs : integer
end

--- A structure holding information to add street and track entities together with a SimpleProposal. <p/>
-- A street proposal can add, remove and modify street, tracks, nodes and edge objects. To modify a street, you
-- need to remove all appropriate entities and add them with the correct information.
global record SimpleStreetProposal
	--- A structure that holds information about new edgeobjects added to the streets
	record EdgeObject
		--- Creates a new EdgeObject object
		new : function() : EdgeObject

		--- Edge entity (must be a new edge in edgesToAdd, starting from -1 and decreasing)
		edgeEntity : Engine.Entity
		--- Position between 0.0 and 1.0 within said edge
		param : number
		--- Flag specifying if one way or not
		oneWay : boolean
		--- Flag specifying the side of the road
		left : boolean
		--- Model id of the edge object
		model : ResName
		--- Owner of the object
		playerEntity : Engine.Entity
		--- Name to give the object
		name : string
	end

	new : function() : SimpleStreetProposal
	--- List of base nodes to add (entity id will be decreasing starting from -1 for all new entities)
	nodesToAdd : { Proposal.NodeAndEntity }
	--- List of base edges to add (includes edge object reference which must match the content of `edgeObjectsToRemove`)
	edgesToAdd : { Proposal.SegmentAndEntity }
	--- List of entities with component BaseNode to remove
	nodesToRemove : { Engine.Entity }
	--- List of entities with component BaseEdge to remove
	edgesToRemove : { Engine.Entity }
	--- List of EdgeObject to add (must be compatible with `edgesToAdd`)
	edgeObjectsToAdd : { EdgeObject }
	--- List of entities to be removed
	edgeObjectsToRemove : { Engine.Entity }
	--- List of node configurations to add
	nodeConfigsToAdd : { Proposal.BaseNodeLaneConnectionAndEntity }
	--- List of node configuration entities to remove
	nodeConfigsToRemove : { Engine.Entity }
	--- A map from node to railroad crossing type index
	node2rcType : {Engine.Entity : integer}
end

--- Event data provided in builder.proposalApply event
global record ProposalEventData
	proposal : Proposal
	data : ProposalData
	result : { Engine.Entity }
end

--- A structure holding information to build/remove and update constructions and streets.<p/>
-- It offers much more functionality than a simple ".con" file. See also `build_street.lua` for an example.
-- The most important operations that can be performed with a Simple Proposal is adding/removing and modifying
-- the following objects: constructions (stations, depots, ), (base) edges and (base) nodes, and edgeobjects (signals, 
-- street terminals, waypoints).
-- <p/>
-- In general, there are a few rules concerning this proposal. First, old entities are reference with the usual non-negative
-- id, whilst new entities are assigned a decreasing negative number starting at -1.
-- <p/>
-- The general rule is that the modification/upgrade of a construction entails removing it and adding it
-- anew. The same rule applies to streets and edgeobjects.
-- <p/>
-- The proposal will take care of updating lines, stop, people and cargo.
global record SimpleProposal
	new : function() : SimpleProposal

	--- A structure holding information to add construction entities together with a `SimpleProposal`.
	-- It uses the data contained in a ".con" file (or added via `api.res.constructionRep`) to specify a construction.
	record ConstructionEntity
		new : function() : ConstructionEntity

		--- A fileName (or identifier in the case of dynamic constructions)
		fileName : string
		--- The parameters, as received by the updateFn
		params : table
		--- The local transformation in the world, used also as local transformation for models and modules
		transf : Mat4f
		--- A name to give to the final resulting entity
		name : string
		--- The player entity who will own the construction
		playerEntity : Engine.Entity

		--- If true, the suitable (auto-fillable) construction slots will be automatically filled with modules
		autoFillSlots : boolean
	end
	
	--- List of constructions to add (the entity id for constructions in this vector are an decreasing starting from -1)
	constructionsToAdd : {ConstructionEntity}
	--- List of construction entities to remove
	constructionsToRemove : {Engine.Entity}
	--- Mapping from old construction entities to new construction entities (must be an index in constructionsToAdd)
	old2new : {Engine.Entity : integer}

	--- Block defining modification and addition of streets
	streetProposal : SimpleStreetProposal
end

--- A catchment area is a cylinder around a position with a specific radius
global record CatchmentArea 
	position : Vec3f
	radius : number
end

-- Settings

--- Specification for audio settings
global record AudioEffectSettings
	--- Bulldozer sound effects enabled
	bulldozer : boolean
	--- Construction sound effects enabled
	construction : boolean
end

--- Game settings
global record AppConfig
	new : function(?AppConfig) : AppConfig
	equals : function(AppConfig, AppConfig) : boolean

	--- Unit of measurement for distance
	distanceSpeedUnit : DistanceSpeedUnit

	--- Main menu state data (filled by the UI scripts to persist things like the list of active mods)
	mainMenuState : table
	--- Whether keyboard and mouse input is enabled
	enableKeyboardMouse : boolean
	--- Keybindings (stored `settings_keys_v*.lua`)
	keyCmdDefinitions : {string : {KeyComboDef}}
	--- Prefix for money display
	moneyPrefix : string
	--- Whether camera tool is enabled
	cameraTool : boolean
	--- Whether to show release notes
	showReleaseNotes : boolean
	--- Whether an initial thank you message for owning deluxe edition has been shown before
	hasShownInitialDeluxeThankYou : boolean
	--- Last update message ID shown
	updateMessageID : integer
	--- Whether debug mode is enabled
	debugMode : boolean
	--- Whether guide system is active
	guideSystemActive : boolean	
	--- Whether the terrain node graph editor is enabled
	experimentalTerrainGeneratorEditor : boolean
	--- Whether experimental map features are enabled
	experimentalMapFeatures : boolean
	--- Screen mode setting (WINDOWED = 0, BORDERLESS = 1, FULLSCREEN = 2)
	screenMode : integer
	--- Whether to enable the seamless construction mode for the street builder
	enableSeamlessStreetBuilder : boolean

	--- Display unsupported hardware info
	showIntelHDwarning : boolean

	--- Whether music is enabled
	musicEnabled : boolean
	--- Whether menu music is enabled
	menuMusicEnabled : boolean
	--- Whether voice-over is enabled
	voiceOverEnabled : boolean
	--- Master volume level
	masterVolume : number
	--- Sound effects volume level
	soundVolume : number
	--- Music volume level
	musicVolume : number
	--- Voice-over volume level
	voiceOverVolume : number
	--- Audio effect settings
	audioEffectSettings : AudioEffectSettings

	--- Enable experimental tunnel/bridge height settings
	experimentalTunnelAndBridgeMinHeight : boolean 

	--- Render extent scale for in-game viewport
	resolutionScale : number

	-- How fast animations and transitions are played for GUI objects - default is 1, 0 means no effect at all
	cssEffectsVelocity : number

	-- Selects the contrast mode in LVM and module builder
	backgroundContrastMode : BackgroundContrastMode
end

--- Used to configure the parameter-based UI
global record ScriptParam
	new : function() : ScriptParam

	--- Unique key that is passed to the construction functions
	key : string
	--- Display name
	name : string
	--- Display Group:
	--- - If hideLabel is true, items will be grouped horizontally
	--- - Else items will be separated by a divider
	group : string
	--- Tooltip to display over certain parameters
	tooltip : string
	--- All possible values of the params
	values : {string}
	--- Allow numbers to be used as value
	numbers : {number}
	--- Allow tooltips to be used as value
	tooltips : {string}
	--- This param can be changed when the construction is already built
	postConstructionModifiable : boolean
	--- Allow to hide the label
	hideLabel : boolean
	--- Image representations of the values (for Compact Mode)
	images : {string}
	--- Default index/state
	defaultIndex : Index
	
	--- Type of ui shown in user interface selection
	uiType : ScriptParamType
	--- construction menu has two possible locations for parameters: default or toolbar (see ScriptParamLocation)
	location : ScriptParamLocation
	--- displayMode controls whether the parameter is displayed in default, compact, or sparse mode (see ScriptParamDisplayMode)
	displayMode : ScriptParamDisplayMode

	--- Tags associated with the script param for filtering
	tags : {string}
	--- Availability from
	yearFrom : integer
	--- Availability to
	yearTo : integer

	--- callback function to allow dynamic disabling or hiding of the paramter
	--- function(params : {string : number}, scriptRefParams : table) : ConstructionMenuParam.CheckEnabledResult
	checkEnabledScript : ScriptRef

	--- callback function to allow returning any value on input actions
	--- function(value : number, direction : integer, precise : boolean) : number
	stepValueScript : ScriptRef

	--- callback function to allow formatting the value display in the UI
	--- function(value : number) : string
	formatValueScript : ScriptRef
end

--- Contains all active and installed mods and their description
global record ModRep
	getInstalledMods : function(ModRep) : {Mod.ModId}
	exists : function(ModRep, Mod.ModId) : boolean
	getModDesc : function(ModRep, Mod.ModId) : Mod.ModDesc
	getModSize : function(ModRep, Mod.ModId) : Mod.ModSize
	getGameModDesc : function(ModRep, Mod.ModId) : Mod.GameModDesc
	getModSource : function(ModRep, Mod.ModId) : string
	exists : function(ModRep, Mod.ModId) : boolean
	wouldForceActivateAchievements : function(ModRep, modIds : {Mod.ModId}) : boolean
	couldAchievementsBeEarned : function(ModRep, modIds : {Mod.ModId}) : boolean
end

--- Localization information
global record LangKey
	new : function() : LangKey
	equals : function(LangKey, LangKey) : boolean
	--- Language code as two characters code or two characters and a two character rvariant code separated by underscore
	code : string
	--- Mod from which the lanuage is originating from
	mod : Mod.ModId
end

--- Contains all available languages of the application, including languages added by mods
global record LanguageRep
	getAllLanguages : function(LanguageRep) : {{string, LangKey}}
end

global record AnyKey
end

global record AnyAxis
end

--- InputMode represents the current input mode.
global record InputMode
	Undefined : InputMode
	KeyboardMouse : InputMode
	Gamepad : InputMode
end

--- GamepadType represents the current gamepad.
global record GamepadType
	None : GamepadType
	XBox : GamepadType
	PlayStation5 : GamepadType
	PlayStation4 : GamepadType
end

--- Key combination for input binding
global record KeyCombo
	new : function(KeyComboDef) : KeyCombo

	toString : function(KeyCombo) : string
	isModifierOnly : function(KeyCombo) : boolean
	relevantFor : function(KeyCombo, InputMode) : boolean
end

--- Key combination definition for input binding
global record KeyComboDef
	new : function() : KeyComboDef
	new : function(KeyComboDef) : KeyComboDef

	--- Set the trigger key to this scancode (ignored if scancode is a modifier key)
	setKeyScancode : function(combo : KeyComboDef, scancode : integer)

	--- Add a modifier scancode to this combination (ignored if scancode is not a modifier key)
	addModifierKey : function(combo : KeyComboDef, scancode : integer)

	--- Trigger condition for the key combination<p/>
	-- `0`: Initial trigger on keydown or when conflicting longpress is rejected<br/>
	-- `1`: Initial triggers when keycombo is pressed for X time)
	condition : integer
end

--- Description of an input action for key binding
global record InputActionDesc
	--- Display name in UI
	uiName : string
	--- Type index<p/>
	-- `0`: Simple
	-- `1`: AxisLinear
	-- `2`: AxisRadial
	type : integer
	--- Default key bindings for this action
	defaultBindings : {KeyComboDef}
	--- Whether this action is modifier-only (i.e. has no trigger key and can be triggered even if the keys are already used elsewhere)
	modifierOnly : boolean
	--- UI category for organization in settings menu
	uiCategory : string
	--- Display order inside the category in settings menu
	uiOrder : integer

	--- This is supposed to be an alias only duplicateOf
	duplicateOf : string
	--- If keybindings are configured exactly as for the duplicateOf. UI should hide the entry in this case.
	duplicatedKeybindings : boolean
end

global record InputActionRep
	getAll : function(InputActionRep) : {string}
	get : function(InputActionRep, string) : InputActionDesc
end

--- Map generation mode for heightmap generation
global record HeighmapGenerationMode
	new : function() : HeighmapGenerationMode
	--- Terrain generator script resource name
	terrainGenerator : string
	--- Whether to generate towns
	generateTowns : boolean
	--- Whether to generate industries
	generateIndustries : boolean
	--- Whether to generate assets
	generateAssets : boolean
	--- Whether to keep the heightmap
	keepHeightmap : boolean
	--- Whether to keep the biomes
	keepBiomes : boolean
end

--- Map generation mode for street generation
global record StreetGenerationMode
	new : function() : StreetGenerationMode
end

--- Map generation mode for adding towns and industries
global record TownIndustryGenerationMode
	new : function() : TownIndustryGenerationMode
	--- Number of towns to add
	numTownsToAdd : integer
	--- if industries should be added
	addIndustries : boolean
	--- Whether to show existing towns
	showExistingTowns : boolean
	--- Whether to show existing industries
	showExistingIndustries : boolean
	--- Whether to preserve existing towns when generating new towns
	keepExistingTowns : boolean
	--- Whether to preserve existing industries when generating new industries
	keepExistingIndustries : boolean
end

--- Map generation mode for importing or exporting heightmaps
global record ImportExportHeightmapMode
	new : function() : ImportExportHeightmapMode

	--- File name for import/export
	fileName : string
	--- Whether to import (true) or export (false)
	import : boolean
	--- Whether to generate assets
	generateAssets : boolean
	--- Minimum height value
	minH : number
	--- Maximum height value
	maxH : number
end

--- Map generation mode for importing biomes
global record ImportBiomesMode
	new : function() : ImportBiomesMode

	--- Terrain generator script resource name
	terrainGenerator : string
	--- Biome map filename for import
	biomeMap : string
	--- Additional layer map filenames for import
	layerMaps : {string : string}
end

--- Extended town information for map generation
global record TownInfo
	--- Name of the town
	name : string
	--- World position of the town
	position : Vec2f
	--- Initial size for residential, commercial, industrial zones
	initialLandUseCapacities : {integer}
	--- Cargo needs for residential, commercial, industrial zones
	landUse2CargoNeedsCategories : {LandUseType : {string}}
	--- Major street angle
	majorStreetAngle : number
	--- Initial major street angle
	initialMajorStreetAngle : number
	--- Capacity scaling factor
	capacityScalingFactor : number
end

--- Results of town generation operations
global record TownResult
	toRemove : {Engine.Entity}
	toAdd : {TownInfo}
end

--- Industry placement information
global record IndustryInfo
	fileName : string
	bbox : Box2f
	streetPoint : Vec2i
	transf : Mat4f
	onWater : boolean
end

--- Results of industry generation operations
global record IndustryResult
	toRemove : {Engine.Entity}
	toAdd : {IndustryInfo}
end

--- A player stat, used for start tracking
global record PlayerStatDesc
	--- The unique id for that stat
	id : string
end

--- The value of a player stat
global record PlayerStatProgress
	--- the unique id for the stat
	id : string
	--- the value of the stats (either the current value or a target value depending on the use context)
	getValue : function(PlayerStatProgress) : number
end

--- Repository for all player stat types (static data)
--- Access the current state of a player stats, use UserProfile:getPlayerStatProgress
global record PlayerStatRep 
	--- Get a player stat description from its id
	--- @param playerStatRep the player start rep
	--- @param statId the player stat id
	--- @return the player stat desc
	get : function(playerStatRep : PlayerStatRep, statId : string) : PlayerStatDesc
end

--- The description of an achievement
global record AchievementDesc
	--- The unique id as a string
	id : string
	--- The display name of the achievement
	name : string
	--- The description of the acheivement
	description : string
	--- The icon once completed of the achievement
	icon : string
	--- The icon while not yet completed
	lockedIcon : string
	--- The grade of the achievement for platform that supports it
	grade : string
	--- If the achievement is hidden until it's completed
	hidden : boolean
	--- If it's a campaign achievement
	campaign : string
	--- If the achievement can always be earned regardless
	alwaysEarnable : boolean
	--- The score (points) earned when completing the achievements for platforms that supports it
	score : integer
	--- The player start value to reach to unlock the achievement (optional)
	playerStatTarget : PlayerStatProgress
end

--- Repository for all achievement types (static data)
--- To access the current state of a player achievements, use UserProfile:getUnlockedAchievementIds
global record AchievementRep 
	--- Get the number of achievement types
	--- @param achievementRep the achievement rep
	--- @return the number of achievements
	getNumAchievements : function(achievementRep : AchievementRep) : integer

	--- Get an achievement data by its index
	--- @param achievementRep the achievement rep
	--- @param index the achievement index (use `getNumAchievements` to iterate over all achievement types)
	--- @return the achievement desc
	get : function(achievementRep : AchievementRep, index : integer) : AchievementDesc
end

--- Campaign and mission identifier
global record MissionCampaign
	userdata
	campaign : ResName
	mission : ResName
end

--- Particle system parameter for float values
global record ParticleParamFloat
	--- Creates a new particle parameter
	new : function() : ParticleParamFloat
	--- Creates a new particle parameter with a value
	new : function(value : number) : ParticleParamFloat
	--- Creates a new particle parameter with a range
	new : function(range : RandomMinMax) : ParticleParamFloat
	--- Creates a new particle parameter with a component-wise range
	new : function(range : ComponentWiseMinMax) : ParticleParamFloat

	--- Random min/max range for particle parameters
	record RandomMinMax
		new : function() : RandomMinMax
		new : function(min : number, max : number) : RandomMinMax

		--- Minimum value
		min : number
		--- Maximum value
		max : number
	end
	
	--- Random min/max range for particle parameters
	record ComponentWiseMinMax
		new : function() : ComponentWiseMinMax
		new : function(min : number, max : number) : ComponentWiseMinMax

		--- Minimum value
		min : number
		--- Maximum value
		max : number
	end

	--- Value or range (variant of number or RandomMinMax)
	value : any -- variant number|RandomMinMax
end


--- Particle system parameter for vec2f values
global record ParticleParamVec2f
	--- Creates a new particle parameter
	new : function() : ParticleParamVec2f
	--- Creates a new particle parameter with a value
	new : function(value : Vec2f) : ParticleParamVec2f
	--- Creates a new particle parameter with a range
	new : function(range :RandomMinMax) : ParticleParamVec2f
	--- Creates a new particle parameter with a component-wise range
	new : function(range :ComponentWiseMinMax) : ParticleParamVec2f

	--- Random min/max range for particle parameters
	record RandomMinMax
		new : function() : RandomMinMax
		new : function(min : Vec2f, max : Vec2f) : RandomMinMax
		
		--- Minimum value
		min : Vec2f
		--- Maximum value
		max : Vec2f
	end

	--- Random min/max range for particle parameters
	record ComponentWiseMinMax
		new : function() : ComponentWiseMinMax
		new : function(min : Vec2f, max : Vec2f) : ComponentWiseMinMax
		
		--- Minimum value
		min : Vec2f
		--- Maximum value
		max : Vec2f
	end

	--- Value or range (variant of Vec2f or RandomMinMax)
	value : any -- variant Vec2f|RandomMinMax
end


--- Particle system parameter curve for float values
global record ParticleParamCurveFloat
	--- Creates a new particle parameter curve
	new : function() : ParticleParamCurveFloat
	--- Creates a new particle parameter curve with curve points
	new : function(points : {CurvePoint}) : ParticleParamCurveFloat

	--- Curve point for float curve
	record CurvePoint
		new : function() : CurvePoint
		new : function(time : number, value : number, easing? : integer) : CurvePoint
		
		--- Time point (0.0 to 1.0)
		time : number
		--- Value at this time point
		value : number
		--- Easing function (enum.Easing)
		easing : integer
	end

	--- Array of curve points
	curve : {CurvePoint}
end


--- Particle system parameter curve for vec2f values
global record ParticleParamCurveVec2f
	--- Creates a new particle parameter curve
	new : function() : ParticleParamCurveVec2f
	--- Creates a new particle parameter curve with curve points
	new : function(points : {CurvePoint}) : ParticleParamCurveVec2f

	--- Curve point for vec2f curve
	record CurvePoint
		new : function() : CurvePoint
		new : function(time : number, value : Vec2f, easing? : integer) : CurvePoint
		
		--- Time point (0.0 to 1.0)
		time : number
		--- Value at this time point
		value : Vec2f
		--- Easing function (enum.Easing)
		easing : integer
	end

	--- Array of curve points
	curve : {CurvePoint}
end


--- Particle system parameter curve for vec3f values
global record ParticleParamCurveVec3f
	--- Creates a new particle parameter curve
	new : function() : ParticleParamCurveVec3f
	--- Creates a new particle parameter curve with curve points
	new : function(points : {CurvePoint}) : ParticleParamCurveVec3f

	--- Curve point for vec3f curve
	record CurvePoint
		new : function() : CurvePoint
		new : function(time : number, value : Vec3f, easing? : integer) : CurvePoint
		
		--- Time point (0.0 to 1.0)
		time : number
		--- Value at this time point
		value : Vec3f
		--- Easing function (enum.Easing)
		easing : integer
	end

	--- Array of curve points
	curve : {CurvePoint}
end


--- UserProfile
global record UserProfile
	getModRep : function(UserProfile) : ModRep
	getLanguageRep : function(UserProfile) : LanguageRep
	getUserName : function(UserProfile) : string
	changeLanguage : function(UserProfile, LangKey)
	getLanguage : function(UserProfile) : LangKey
	subscribeMod : function(UserProfile, string)
	unsubscribeMod : function(UserProfile, string)
	getUnlockedAchievementIds : function(UserProfile) : {string : boolean}
	getAchievementRep : function(UserProfile) : AchievementRep
	getPlayerStatProgress : function(UserProfile, string) : number
	getPlayerStatsProgress : function(UserProfile) : {string : number}
	getLastMission : function(UserProfile, string) : {string, SaveGameId} -- campaign
	getLastSavegameForMission : function(UserProfile, campaign : string, mission : string) : SaveGameId
	getLastGame : function(UserProfile) : SaveGameId | MissionCampaign -- campaign
	isMissionCompleted : function(UserProfile, string, string) : boolean -- campaign, mission
	isCurrentMissionCompleted : function(UserProfile) : boolean -- automatically gets campaign/mission from running game
	noteEditorsNoteShown : function(UserProfile)
	isEditorsNoteShown : function(UserProfile)
	noteMedalState : function(UserProfile, medal : string, achieved : boolean) -- automatically gets campaign/mission from running game
	getMedalsState : function(UserProfile, campaign : string, mission : string) : { string : boolean }
	noteStarState : function(UserProfile, star : string, achieved : boolean) -- automatically gets campaign/mission from running game
	getStarsState : function(UserProfile, campaign : string, mission : string) : { string : boolean }
	hasUgcAccess : function(UserProfile) : boolean
	checkUgcRestrictions : function(UserProfile) : boolean
	hasAgeGroupForUgc : function(UserProfile) : boolean
	getUgcAccessLimitedReason : function(UserProfile) : UgcAccessLimitedReason
	openUrl : function(UserProfile, string)
end

--- Command progress tracker
global record CommandProgress 
	new : function() : CommandProgress
	get : function(CommandProgress) : number
end

--- Base configuration of a single game
global record BaseConfig
	--- Advanced gameplay option
	record AdvancedOptions
		trafficSpeedSensitivityScale : number
		vehicleMaintenanceEmissionsEffect : number
		vehicleMaintenancePerformanceEffect : number
		vehicleMaintenanceRunningCostsEffect : number
		missionVehicleMaintenanceDisableRepair : boolean
		missionDisableTunnelBuilding : boolean
		missionEmissionsScriptFactor : number
		simPersonHappinessDecayAtVehicle : number
		simPersonHappinessDecayAtTerminal : number

		subventionMode : integer
		subventionRisk : integer
		-- Multiplier for the financial reward of subsidies (subventions)
		subventionFinancialRewardMultiplier : number

		landmarkResources : number

		isReforestationActive : boolean
	end

	--- Configuration for animal spawning
	record Animal
		--- Creates a new object of type Animal
		new : function() : Animal

		--- Multiply the density (in square exemplars per square km) by this factor for all animals
		populationDensityMultiplier : number
		--- Spawning only looks at the existing population within localTileSize squared boxes instead of the entire map (results in density 
		--- more similarly distributed to the actual scoring functions)
		useLocalSpawning : boolean
		--- Size used for controlling local spawning
		localTileSize : number
		--- Add notification when a named animal despawns
		notifyAnimalDespawn : boolean
	end

	--- Configuration for the placement of industry and towns on max generation
	record Locations
		--- Creates a new object of type Locations
		new : function() : Locations

		--- Configuration parameters for industries
		record IndustryParamList
			--- Creates a new object of type IndustryParamList
			new : function() : IndustryParamList

			--- Spawning will ensure at least this number of industries is present on the map
			absoluteMinimum : integer
			--- Spawning will ensure that the density per square km will not exceed this number
			maxNumberPerArea : number
			--- Spawning will try to spawn this number of industries
			industryDensity : number
			--- Productivity will be randomized slightly to induce more variation
			randomSize : boolean
			--- Scale the industry productivity by this factor
			industryProductivity : number
		end
		--- Configuration parameters for towns
		record TownParamList
			--- Creates a new object of type TownParamList
			new : function() : TownParamList
			
			--- Spawning will ensure at most this density per square km
			maxNumberPerArea : number
			--- Town will be able to spawn in uneven and slightly unsuitable terrain, the resulting town might 
			--- be smaller than it's target size
			allowInRoughTerrain : boolean
			--- Number of towns per sqm
			townFrequency : number
			--- Population will be scaled by this factor
			populationDensity : number
		end

		--- Configuration for town spawning at map generation
		town : TownParamList
		--- Configuration for industry spawning at map generation
		industry : IndustryParamList

		--- Add small streets at the edge of industries
		makeInitialStreets : boolean
	end

	--- Configuration for the terrain mesh (Deprecated)
	record Terrain
		--- (Deprecated) Only used with legacy terrain, determines the quality of the terrain mesh
		lodErrorMultiplier : number
	end
	
	--- Configures cargo relations and industry developement for a single game
	record Economy
		--- Creates a new empty economy
		new : function() : Economy

		--- Parameters for the town developement
		record TownDevelopment
			--- Number of initial cargo needs when the town ist first built
			cargoNeedsPerTown : integer
			--- The minimum a distric fraction (compared to other disctricts) can shrink
			townGrowthMinDistrictFraction : number
		end
		--- Parameters for the industry developement
		record IndustryDevelopment
			--- Unused
			spawnTargetTimeSpan : number
			--- Control the frequency at which enw industries appear
			spawnProbabilityExponent : number
			--- Control whether new industry might spawn on the map
			spawnIndustries : boolean
			--- Control the mean time after which an industry will begin closing after not being used
			unusedTimeSpan  : number
			--- Controls the grace period the player has to prevent closure
			closureCountdownTimeSpan  : number
			--- Controls how likely an unused industry has of being closed
			closureProbability  : number
			--- Control how often the industry will build new satellites
			extendTimeSpan  : number
		end

		--- A script reference controlling the income of a given cargo given specific parameters
		cargoIncomeScript : ScriptRef
		--- A script reference controlling the income of a given passengers given specific parameters
		passengerIncomeScript : ScriptRef
		--- Controls the automatic development of towns
		townDevelopment : TownDevelopment
		--- Controls the automatic developement of industries
		industryDevelopment : IndustryDevelopment
	end

	--- Graphic settings for main quality modes, camera tool and cockpit
	record Settings
		--- Creates a new graphic settings parameters
		new : function() : Settings

		--- Contains information about graphi quality of a single game
		record GeometryQualityOption
			--- Creates a new GeometryQualityOption
			new : function() : GeometryQualityOption
			--- Distance im meters of near and far plane
			viewNearFar : Vec2f
			--- Unused
			fogStartEndFarPerc : Vec2f
			--- A factor multiplying all lod distances
			lodDistanceScaling : number
		end

		--- Quality settings for: {low, medium, high, cockpit, camera tool}
		geometryQualityOptions : { GeometryQualityOption }
	end

	--- Configures water look and feel
	record Water
		--- Configures water textures
		record Textures
			--- Normal texture for water foam
			foamNormal : string
			--- Extra detail texture for water foam
			foamDetail : string
			--- Albedo texture for water foam
			foam : string
		end

		--- Configures water textures
		textures : Textures
	end


	record Particles
		record Textures
			noise0 : string
			noise1 : string
			smoke : string
			smokeNormal : string
		end

		textures : Textures
	end

	record Emissions
		noiseLowerBoundDB : number
		noiseUpperBoundDB : number
		pollutionLowerBoundDB : number
		pollutionUpperBoundDB : number

		townNoiseResidentialAffected : boolean
		townNoiseCommercialAffected : boolean
		townNoiseIndustrialAffected : boolean
	end

	--- Defines the properties of an animal
	animal : Animal
	locations : Locations
	settings : Settings
	particles : Particles
	water : Water
	emission : Emissions

	scaffold : { string : { string : {string }}}
	costs : { string : number }

	advancedOptions : AdvancedOptions
	economy : Economy
	terrain : Terrain

	environment : ResName
	economyId : ResName
	nameId : ResName
	climate : ResName

	trackCatenaryYearFrom : integer
	busLaneYearFrom : integer

	terrainToolMinStrength : number
	terrainToolMaxStrength : number

	enforceMainConnections : boolean

	townDevelopInterval : number
	chargeMaintenanceInterval : number

	simulateCargoWeight : boolean
	simPersonDestinationRecomputationProbability : number

	townMajorStreetAngleRange : number
	townConnectionMaxBridgeLength  : number

	maxVehicleCloneAmount : number

	trainAccelerationFactor : number
	trainBrakeDeceleration : number

	terrainToolMinSize : number
	terrainToolMaxSize : number
	terrainToolScale : number
	terrainToolMaxSizeEditor : number
	terrainPainterMinSize : number
	terrainPainterMaxSize : number
	terrainPainterMaxSizeEditor : number
	terrainPainterScale : number
	assetBrushMinSize : number
	assetBrushMaxSize : number
	assetBrushScale : number

	treeCostYearMultipliers : {integer : number}

	townInitialMajorStreetAngleRange : number
	townCapacityScalingFactor : number

	sandboxMode : boolean
	noCosts : boolean

	constructionScript : ScriptRef
end

--- Types namespace (used in `api.type.`...)
--- @category main
global record Type
	ScriptParam : ScriptParam
	
	LangKey : LangKey
	ModDesc : Mod.ModDesc
	ModId : Mod.ModId
	KeyCombo : KeyCombo
	KeyComboDef : KeyComboDef
	AppConfig : AppConfig

	enum : Enum

	Vec5f : Vec5f
	Vec4f : Vec4f
	Vec3f : Vec3f
	Vec2f : Vec2f

	Mat4f : Mat4f

	Vec2i : Vec2i

	Box3 : Box3f
	Box2 : Box2f


	Clock : Clock

	CommandProgress : CommandProgress

	LoaderHelper : LoaderHelper
	Connection : Connection

	ComponentType : Engine.ComponentType
	Date : Date

	JournalEntry : JournalEntry

	EdgeId : EdgeId
	EdgePos : EdgePos
	NodeId : NodeId
	Waypoint : Waypoint
	SignalId : SignalId
	StationTerminal : StationTerminal

	ScriptRef : ScriptRef
	ModuleDesc : ModuleDesc
	ConstructionDesc : ConstructionDesc
	GameScriptDesc : GameScriptDesc
	DynamicConstructionTemplate : DynamicConstructionTemplate

	Line : Engine.Component.Line
	EmissionGrid : Engine.Component.EmissionGrid
	MovePathAircraft : Engine.Component.MovePathAircraft
	TransportVehicle : Engine.Component.TransportVehicle

	LoadConfig : LoadConfig

	BaseConfig : BaseConfig
	
	CargoTypeSet : CargoTypeSet

	TransportVehiclePart : TransportVehiclePart
	TransportVehicleConfig : TransportVehicleConfig

	Context : Context
	Proposal : Proposal
	SimpleProposal : SimpleProposal
	ProposalData : ProposalData
	StreetProposal : Proposal.StreetProposal
	SimpleStreetProposal : SimpleStreetProposal

	CatchmentArea : CatchmentArea

	LayerConfig : LayerConfig
	NodeViewerData : NodeViewerData

	ParticleParamFloat : ParticleParamFloat
	ParticleParamVec2f : ParticleParamVec2f
	ParticleParamCurveFloat : ParticleParamCurveFloat
	ParticleParamCurveVec2f : ParticleParamCurveVec2f
	ParticleParamCurveVec3f : ParticleParamCurveVec3f

	Path : Path
	PathPos : PathPos

	AnimationState : Transformator.AnimationState

	HeighmapGenerationMode : HeighmapGenerationMode
	TownIndustryGenerationMode : TownIndustryGenerationMode
	ImportExportHeightmapMode : ImportExportHeightmapMode
	ImportBiomesMode : ImportBiomesMode
	StreetGenerationMode : StreetGenerationMode
	Map : GameMap
	StartGameParams : StartGameParams
	SaveGameInfo : SaveGameInfo
	SavegameId : SaveGameId
	SaveGameDetails : SaveGameData.SaveGameDetails
	SaveGameData : SaveGameData

	ChartConfig : ChartConfig

	FinanceData : FinanceData

	Failure : Failure

	NodeAndEntity : Proposal.NodeAndEntity
	SegmentAndEntity : Proposal.SegmentAndEntity
	BaseNodeLaneConnectionAndEntity : Proposal.BaseNodeLaneConnectionAndEntity

	EdgeGeometry : EdgeGeometry

	MetadataMap : ModelMetadata
	Collider : Collider

	mod : Mod

	modhub : Modhub

	TrackType : TrackType
	GenericGameRes : GenericGameRes
	BridgeType : BridgeType

	Industry : Engine.Component.Industry
	StockList : Engine.Component.StockList

	LineIssue : LineIssue

	TrafficLightConfig : Engine.Component.TrafficLightConfig
	TrafficLightState : Engine.Component.TrafficLightState

end

global GlobalType = Type

--- Specification for cargo type set
global record CargoTypeSet
	new : function() : CargoTypeSet

	--- cargo classes included
	cargoClassesIncluded : {string}
	--- cargo classes excluded
	cargoClassesExcluded : {string}
	--- cargo types included
	cargoTypesIncluded : {ResName}
	--- cargo types excluded
	cargoTypesExcluded : {ResName}
end

--- Configure sound effects for entities
global record SoundSet
	tracks : {SoundClip}
	events : {string : SoundClipList}

	updateScript : ScriptRef

	attrs : SoundAttributes
end

--- Contains all metadata of a model. A specific metadata might be nil.
global record ModelMetadata
	record Animal
		record MovementType
			description : string
		end
		record Config
			density : number
			fish : boolean
		end
		config : Config
		movementTypes : {MovementType}
		idForAchievement : string
	end

	record Description
		name : string
		description : string
		iconSmall : string
		iconSmallCblend : string
		icon : string
		icon20 : string
		icon3d : string
		icon20cblend : string
		lockedIcon : string
		previewIcon : string
		attributes : { string : { number, number } }
		attributes_native : Map<string, { number, number }>
		cargoTypeSet : CargoTypeSet
	end

	record Category
		categories : {string}
	end

	record CategoryList
		categories : {string}
	end

	record MenuCategory
		record CategoryWithOrder
			new : function() : CategoryWithOrder

			category : string
			order : integer
			filterCategories : {string}
		end
		categories : {CategoryWithOrder}
	end

	record Availability
		yearFrom : integer
		yearTo : integer
		-- Emit notification when becoming available (default = true)
		notifyWhenAvailable : boolean
		notificationGroup : string
		notificationSortKey : integer
	end

	record SoundConfig
		record SoundSet
			name : string
		end
		soundSet : SoundSet

		--- Sound effects, map from key to list of file paths
		--- used to overwrite certain clips in SoundSet (if SoundSet is set and has those)
		effects : {string : {string}}

		-- Sound resource (.builder_audio) for construction action
		builderAudioRes : ResName
	end

	record Maintenance
		lifespan : integer
		runningCosts : number
		runningCostScale : number
		maintenanceScale : number
		topSpeedMaintenanceFactorPenaltyPerLevel : number
	end

	record Emission
		idle : number
		speed : number
		power : number
		score : number
	end

	record Emissions
		noise : Emission
		pollution : Emission
	end
	record VehicleEngine
		power : number
		tractiveEffort : number
		type : VehicleEngineType
	end
	record TransportVehicle
		record CargoEntry
			cargoTypeSet : CargoTypeSet
			capacity : integer
			seats : {integer}
			--- Used in conjunction with transport vehicle / industry metadata to define cargo positioning of custom cargo models
			loadIndicator : string
		end
		record LoadConfig
			new : function() : LoadConfig

			cargoEntry : CargoEntry
			toHide : {string}
		end
		record Compartment
			loadConfigs : {LoadConfig}
		end
		line : Engine.Entity
		carrier : Carrier
		compartments : {Compartment}
		loadSpeed : number
		reversible : boolean
		arrivalDelay : integer
		departureDelay : integer
		groupFileName : ResName
		transportModes : {TransportMode}
		engineTransportModes : {TransportMode}
		filterTags : {string}
		comfortFactor : number
		priceFactor : number
		maintenanceFactor : number
		noCblendMask : boolean
	end
	record Cost
		priceScale : number
		price : integer
	end
	record LandVehicle
		topSpeed : number
		weightEmpty : number
		weightMaxPayload : number
		engines : {VehicleEngine}
		friction : number
	end
	record WaterVehicle
		topSpeed : number
		weightEmpty : number
		weightMaxPayload : number
		availPower : number
		maxRpm : number
		area : number
	end
	record AirVehicle
		topSpeed : number
		weightEmpty : number
		weightMaxPayload : number
		maxThrust : number
		isHelicopter : boolean
	end
	record Person
		gender : Gender
	end
	record Tree
		reputationFactor : number
	end
end

-- Core Types

--- Campaign description
global record CampaignDesc
	new : function() : CampaignDesc
	name : string
	description : string
	icon : string
	map : string
	order : number
	voiceOver : string
	requiresCompleted : string
	unlockingProgression : boolean
end

--- Campaign mission description
global record MissionDesc
	--- Campaign mission medal information
	record Medal
		id : string
		name : string
		nameLocked : string
		iconLocked : string
		iconCompleted : string
	end

	--- Campaign mission star (achievement) information
	record Star
		id : string
		name : string
		description : string
		iconLocked : string
		iconCompleted : string
	end

	--- Campaign mission character information
	record Character
		name : string
		info : string
		portrait : string
	end

	name : string
	description : string
	campaign : string
	characters : {Character}
	order : integer
	image : string
	imagePreview : string
	imageSuccess : string
	imageFailure : string
	loadscreen : string
	loadscreenDescription : string
	loadscreenVoiceOver : string
	savegame : string
	languageScript : string
	playlistOverride : string
	medals : {Medal}
	starsDescription : string
	stars : {Star}
	voiceOver : string
	location : string
	year : string
	musicTracks : {{ResName, boolean}}
end

--- Name list description for procedural name generation
global record NameDesc
	name : string
	personNamesScript : string
	townNamesScript : string
	streetNamesScript : string
end

--- Music playlist description
global record PlaylistDesc
	name : string
	tracks : {PlaylistTrack}
	order : integer
	hidden : boolean
	allFilter : boolean
end

--- Music playlist track information
global record PlaylistTrack
	--- id
	name : string
	--- file path to the music file
	fileName : string
	--- Year when track becomes available
	yearFrom : integer
	--- Last year before track becomes unavailable
	yearTo : integer
end

--- SoundClip attributes
global record SoundAttributes
	gain : number
	refDist : number
	rolloffFact : number
	hasVelocity : boolean
end

--- SoundClip for SoundSet, BuilderAudioSet, ...
global record SoundClip
	name : string
	attrs : SoundAttributes
end

--- SoundClipList for SoundSet 
global record SoundClipList
	names : {string}
	attrs : SoundAttributes
end

global record BuilderAudioSet
	attrs : SoundAttributes
	dragStart : SoundClip
	drag : {SoundClip}
	dragBridge : {SoundClip}
	dragTunnel : {SoundClip}
	dragEnd : SoundClip
	dragOffset : number
	build : {SoundClip}
	noMoney : {SoundClip}
	bulldoze : {SoundClip}
	terraform : {SoundClip}
end

-- Game Types

--- Information about cargo on a line
global record LineCargoInfo
	--- Real times for each section
	realSectionTimes : {{number, integer}}
	--- Scheduled times for each section
	sectionTimes : {number}
	--- Frequency of the cargo on the line
	frequency : number
	--- Real drive times for each section
	driveRealSectionTimes : {{number, integer}}
	--- Drive times for each section
	driveSectionTimes : {number}
	--- Number of vehicles
	numVehicles : integer
	--- Total capacity
	totalCapacity : integer
	--- Available capacities
	availableCapacities : {integer}
	--- Comfort factor for this cargo on the line
	comfortFactor : number
	--- Price factor for this cargo on the line
	priceFactor : number
end

--- Entities attached to a segment
global record ParcelData
	--- Parcels on the left of the segment
	leftEntities : {Engine.Entity}
	--- Parcels on the right of the segment
	rightParcels : {Engine.Entity}
end

--- A single instance of a grid collision system
global record GridCollisionSystem
	--- Gets the collision data at the specified position
	getCollisionDataAt : function(GridCollisionSystem, Vec2f) : integer
end

--- Target data for land use types
global record TargetDataEntry
	entity : Engine.Entity
	freeCapacity : integer
	capacity : integer
	edgeWalk : {integer, integer}
	edgeDrive : {integer, integer}
	destinationWeight : number
	isReachableDrive : boolean
	isReachableWalk : boolean
	isReachableLines : boolean
end
--- Information about target destinations
global record TargetData
	entries : {TargetDataEntry}
	edges : {EdgePos}
end
--- Target destinations organized by land use type
global record TargetsByLandUse
	targets : {TargetData, TargetData}
end

-- Layer Types
--- Struct containing information for rendering transport network edges of a BaseNode
global record NodeViewerData
	new : function() : NodeViewerData
	clone : function(NodeViewerData) : NodeViewerData

	-- The index inside the TransportNework edge list
	edgeIdx : integer
	--- Colors that will be smoothly interpolated from the beginning to the end of the edge
	colors : {Vec4f}
	--- Rendering order of the edge
	order : integer
	--- Width of the edge
	width : number
end

--- Describes configuration for 3d layers that can be enabled with the react interface
global record LayerConfig
	new : function() : LayerConfig
	new : function(LayerConfig) : LayerConfig

	--- Colors entities and terrain based on 
	record EmissionColorMap
		new : function() : EmissionColorMap
		new : function(EmissionColorMap) : EmissionColorMap

		--- Thresholds and colors for the emission visualization gradient
		record Colors
			new : function() : Colors
			new : function(Colors) : Colors
			numberOfLevels : integer
			colors : {Vec4f}
			thresholds : {number}
		end

		--- Type of visualization for the emission color
		record VisualizationType 
			DecibelCurrent : VisualizationType
			DecibelAverage : VisualizationType
			Combined : VisualizationType
		end

		--- Configures colors as a gradient map from the given threshold
		colors : Colors
		--- Choose among visualization of noise or pollution
		currentEmissionId : Engine.Component.EmissionGrid.Type
		--- The type of emission visualization to dsplay: average or instant
		visualizationType : VisualizationType
	end

	--- Configures the terrain to be visualize terrain heightmap features like elevation and presence of navigable waters
	record TerrainColorMap
		--- Iniztialize a new TerrainColorMap object
		new : function() : TerrainColorMap
		--- Copy constructs a TerrainColorMap
		new : function(TerrainColorMap) : TerrainColorMap

		--- Actual color configuration for the terrain visualization
		record Colors
			new : function() : Colors
			new : function(Colors) : Colors
			numberOfLevels : integer
			--- Set the colors corrsponding to the thresholds, length must be equal to numerOfLevels and less than 4
			colors : {Vec4f}
			--- Elevation thresholds (in meters above water) for the matching colors
			thresholds : {number}
			--- Color (as RGBA value) of non-navigable waters
			water : Vec4f
			--- Color (as RGBA value) of navigable waters
			navigableWater : Vec4f
			--- Smoothen edges of navigable water grid with linear interpolation for more pleasant (yet imprecise) look
			interpolateNavigableWater : boolean
		end

		--- Color configuration for the TerrainColorMap
		colors : Colors
	end

	--- Configuration for contour lines
	record TerrainContours
		new : function() : TerrainContours
		new : function(TerrainContours) : TerrainContours

		--- Configuration of a single contour (level line)
		record Contour
			new : function() : Contour
			new : function(Contour) : Contour

			-- color RGBA value of the contour for this level
			color : Vec4f
			-- height in meters of the contour for this level
			level : number
			--- Thicknes of the contour
			thickness : number
			--- how far the countour lines will be visible for
			fadeDistance : number
		end

		--- List of contours for  the terrain (at most 10)
		contours : {Contour}
	end

	--- Configures the coloring for entities: each entity type can be configured with its own specific coloring
	--- among a selection of available modes
	record ColorPassFn
		--- Creates a new isntance of a color pass configuration
		new : function() : ColorPassFn
		--- Copy the color pass function
		new : function(ColorPassFn) : ColorPassFn

		--- Generic static constant color for this type of entity, can be applied to any entity
		record BaseColor
			--- Creates a new instance of a basic color with default values or as a copy of an existing color
			new : function(?BaseColor) : BaseColor
			--- Create an instance of base color from a color
			fromColor : function(color : Vec4f, overrideColorMap? : boolean) : BaseColor
			--- Color RGBA value
			value : Vec4f
			--- If this value is set, the value of a configured color map (such as emission) will be overridden
			overrideColorMap : boolean
		end

		--- A color that depends on the given input values and applies a different gradient depending on the input
		record BaseMappedColor
			new : function() : BaseMappedColor
			new : function(BaseMappedColor) : BaseMappedColor
			new : function({number}, {Vec4f}, boolean, boolean) : BaseRangeColor
			--- Specifies values that are assigned to the specific colors
			thresholds : {number}
			--- List of colors for the matching thresholds. Must have the same length as thresholds
			colors : {Vec4f}
			--- Interpolation applied to color: if neares the gradient will only pick exact values of the color that are specified
			nearest : boolean
			--- If this value is set, the value of a configured color map (such as emission) will be overridden
			overrideColorMap : boolean
		end

		--- Specify two colors that will be mixed based on the input value
		record BaseRangeColor
			--- Constructs a new empty BaseRangeColor
			new : function() : BaseRangeColor
			--- Constructs a copy of the input color range
			new : function(BaseRangeColor) : BaseRangeColor
			--- Constructs a BaseRangeColor given a pair of colorsx
			new : function(minMax : {Vec4f}, overrideColorMap? : boolean) : BaseRangeColor
			--- A pair of colors among which the final color will be mixed
			minMax : {Vec4f}
			--- If this value is set, the value of a configured color map (such as emission) will be overridden
			overrideColorMap : boolean
		end

		--- Specifies colors for town buildings for each land use type based on production rating
		record CargoColor
			--- Constructs a new empty CargoColor
			new : function() : CargoColor
			--- Constructs a copy of the input cargo color
			clone : function(CargoColor) : CargoColor

			--- Color that applies to commercial land use type
			residential : BaseRangeColor
			--- Color that applies to industrial land use type
			industrial : BaseRangeColor
			--- Color that applies to commercial land use type
			commercial : BaseRangeColor
			--- Number of discrete steps the color is interpolated into (e.g. a value of 3 will result in interpolation values of 0, 0.5 and 1)
			numBuildingLevels : integer
			--- Whether to include passengers cargo for the coloring (rating also includes line usage for inhabitants)
			includePassengers : boolean
		end
	
		--- Specifiers colors for PersonCapacity entities based on whether any SimPerson has a destination to it, based
		--- on the specified filtering criteria.
		record DestinationColor
			--- Constructs an empty DestinationColor
			new : function() : DestinationColor
			--- Copies a given destination color
			new : function(DestinationColor) : DestinationColor
			--- Only consider TownBuildings that belong to a given Town 
			town : Engine.Entity
			--- Do consider SimPersons moving using Line movement types
			showPlayerTransport : boolean
			--- Do consider SimPersons moving using Drive or Walk movement types
			showPrivateTransport : boolean
			--- Select colors for people moving to residential destinations, if any filtered person satifies the criteria,
			--- the max color will be applied, otherwise the min color will be used
			residential : BaseRangeColor
			--- Select colors for people moving to industrial destinations, if any filtered person satifies the criteria, 
			--- the max color will be applied, otherwise the min color will be used
			industrial : BaseRangeColor
			--- Select colors for people moving to commercial destinations, if any filtered person satifies the criteria, 
			--- the max color will be applied, otherwise the min color will be used
			commercial : BaseRangeColor
			--- Number of discrete steps the color is interpolated into (e.g. a value of 3 will result in interpolation values of 0, 0.5 and 1)
			--  No effect in this case, always set it to two
			numBuildingLevels : integer
		end

		--- Color EmissionEmitter entities based on emission type and value
		record EmissionEmitterColor
			--- Creates a new empty instance of EmissionEmitterColor
			new : function() : EmissionEmitterColor
			--- Creates a new copy of an instance of EmissionEmitterColor
			new : function(EmissionEmitterColor) : EmissionImpactColor
			--- A pair of colors that will be interpolated, based on the value of the emission
			color : BaseRangeColor
			--- Selects the type of emission toconsider between noise and pollution
			currentEmissionId : Engine.Component.EmissionGrid.Type
			--- Lower bound for the range, at which  min color of color will be chosen
			lowerBound : number
			--- Upper bound for the range, at which max color of color will be chosen
			upperBound : number
			--- A pair of colors that will be interpolated, based on the value of the emission, when the emission is negative
			goodColor : BaseRangeColor
			--- Lower bound for the negative range, at which  min color of color will be chosen
			goodColorLowerBound : number
			--- Upper bound for the negative range, at which max color of color will be chosen
			goodColorUpperBound : number
		end

		--- Color the entity based on the current level of emission the entity is experiencing
		record EmissionImpactColor
			new : function() : EmissionImpactColor
			new : function(EmissionImpactColor) : EmissionImpactColor
			---  A pair of colors that maps lowerBoundDB (the min experienced emission) to uppedBoundDB (the max experienced emission)
			color : BaseRangeColor
			--- Selects the type of emission toconsider between noise and pollution
			currentEmissionId : Engine.Component.EmissionGrid.Type
			--- Choose to apply smoothed (averaged) emission isntead of instantaneous one
			useAverage : boolean
			--- This value maps to min color in color
			lowerBoundDB : number
			--- This value maps to max color in color
			upperBoundDB : number
		end

		--- Color chosen if no other selected type matches the entity
		record FallbackColor
			--- Creates a new empty isntance FallbackColor
			new : function() : FallbackColor
			--- Creates a copy of FallbackColor
			new : function(FallbackColor) : FallbackColor
			--- Color applied to the terrain and terrain-like entities
			terrain : BaseColor
			--- Color applied to water meshes
			water : BaseColor
			--- Color applied to entities with BaseEdge components
			edge : BaseColor
			--- Color applied to entities with BaseNode components
			node : BaseColor
			--- Color applied to entities with ParallelStrip components
			parallelStrip : BaseColor
			--- Color applied to any other entity not matching a specific type
			whatever : BaseColor
		end
		
		--- Apply a color to Industry entities
		record IndustryColor
			--- Creates a new empty IndustryColor
			new : function() : IndustryColor
			--- Creates a copy of an existing IndustryColor
			new : function(IndustryColor) : IndustryColor
			--- The color to apply
			industry : BaseColor
			--- Only apply the color if the entity also has an industrial PersonCapacity color
			onlyWithPersonCapacity : boolean
		end

		--- Apply colors to an entity based on the level of the TownBuilding, based on the LandUseType
		record LandUseColor
			--- Creates a new empty LandUseColor
			new : function() : LandUseColor
			--- Creates a copy of an existing LandUseColor
			new : function(LandUseColor) : LandUseColor
			--- Color to be applied to residential LandUseType
			residential : BaseRangeColor
			--- Color to be applied to industrial LandUseType
			industrial : BaseRangeColor
			--- Color to be applied to commercial LandUseType
			commercial : BaseRangeColor
		end
		
		--- Apply colors to vehicles based on the line color
		record LineVehicleColor
			--- Creates a new empty LineVehicleColor
			new : function() : LineVehicleColor
			--- Creates a copy of an existing LineVehicleColor
			new : function(LineVehicleColor) : LandUseColor
			--- Specify specific entites to apply an highlight effect to
			highlightedEntities : {Engine.Entity}
			--- Only apply the color to the selected entities
			carriers : {Carrier}
		end

		--- Apply colors based on the maintenance state of a specific vehicle
		record MaintainedTransportVehicleColor
			--- Creates a new empty MaintainedTransportVehicleColor
			new : function() : MaintainedTransportVehicleColor
			--- Creates a copy of an existing MaintainedTransportVehicleColor
			new : function(MaintainedTransportVehicleColor) : MaintainedTransportVehicleColor
			--- The color to apply if the entity is being maintaned
			color : BaseColor
			--- Filter the vehicle based on the specific maintenance station it is maintained with
			maintenanceStationEntity : Engine.Entity
		end

		--- Color stations based on the overcrowdedness of the station
		record StationOvercrowdedColor
			--- Creates a new empty StationOvercrowdedColor
			new : function() : StationOvercrowdedColor
			--- Creates a copy of an existing StationOvercrowdedColor
			new : function(StationOvercrowdedColor) : StationOvercrowdedColor
			-- The color is chosen based on the ratio between people being considered "overflowing" and the total capacity of the station
			color : BaseMappedColor
		end

		--- Color transport network extes based on the max speed of the transport network edge
		record SpeedLimitsColor
			--- Creates a new empty SpeedLimitsColor
			new : function() : SpeedLimitsColor
			--- Creates a copy of an existing SpeedLimitsColor
			new : function(SpeedLimitsColor) : SpeedLimitsColor
			--- Interolates colors in this list between the min speed and max speed, based on all available street templates for the year
			slowToFast : {BaseColor}
			--- Discretize the number of levels based on this value
			numberOfLevels : integer

			--- Hide edges that are not owned by the player
			hideNonPlayerOwned : boolean
			--- Hide edges that do not have the roadDevelopmentLocked flag
			hideNonLocked : boolean
		end

		--- Color the base edge based on the amount of traffic present on it
		record TrafficColor
			--- Creates a new empty TrafficColor
			new : function() : TrafficColor
			--- Creates a copy of an existing TrafficColor
			new : function(TrafficColor) : TrafficColor
			--- Interpolates colors in this list (must have three elements) based on the traffic rating of the edge
			poorToGood : {BaseColor}
			--- Discretize the number of levels based on this value
			numberOfLevels : integer
			--- Unused
			discrete : boolean
		end

		--- Apply color to entities (station, terminal and warehouse) based on the average happines of their users
		record HappinessColor
			--- Creates a new empty HappinessColor
			new : function() : HappinessColor
			--- Creates a copy of an existing HappinessColor
			new : function(HappinessColor) : HappinessColor
			--- Interpolates colors in this list (must have three elements) based on the average happines of the entity
			normalToPoor : {BaseColor}
		end

		--- Optional terrain painter configuration: nil or BaseColor
		terrainPainter : any -- variant nil|BaseColor

		--- Optional water painter configuration: nil or BaseColor
		waterPainter : any -- variant nil|BaseColor

		--- Optional town building painter configuration: nil, BaseColor, CargoColor, DestinationColor, EmissionImpactColor or LandUseColor
		townBuildingPainter : any -- variant nil|BaseColor|CargoColor|DestinationColor|EmissionImpactColor|LandUseColor

		--- Optional industry painter configuration: nil, IndustryColor or DestinationColor
		industryPainter : any -- variant nil|IndustryColor|DestinationColor

		--- Optional emission emitter painter configuration: nil or EmissionEmitterColor
		emissionEmitterPainter : any -- variant nil|EmissionEmitterColor

		--- Optional station painter configuration: nil, BaseColor, HappinessColor or StationOvercrowdedColor
		stationPainter : any -- variant nil|BaseColor|HappinessColor|StationOvercrowdedColor

		--- Optional warehouse painter configuration: nil or HappinessColor
		warehousePainter : any -- variant nil|HappinessColor

		--- Optional transport network painter configuration: nil, peedLimitsColor or TrafficColor
		transportNetworkPainter : any -- variant nil|SpeedLimitsColor|TrafficColor

		--- Optional transport vehicle painter configuration: nil, LineVehicleColor, TrafficColor or EmissionEmitterColor
		transportVehiclePainter : any -- variant nil|LineVehicleColor|TrafficColor|EmissionEmitterColor|MaintainedTransportVehicleColor

		--- Optional land vehicle painter configuration: nil or TrafficColor
		landVehiclePainter : any -- variant nil|TrafficColor

		--- Optional sim at terminal painter configuration: nil or HappinessColor
		simAtTerminalPainter : any -- variant nil|HappinessColor

		--- Fallback color (if none of the above matches)
		fallbackColor : FallbackColor
	end

	--- Configures a preview showing town buildings and parcels
	record BuildingRenderableConfig
		--- Creates a new empty BuildingRenerableConfig
		new : function() : BuildingRenderableConfig
		--- Creates a copy of BuildingRenderableConfig object
		new : function(BuildingRenderableConfig) : BuildingRenderableConfig

		--- Actually render this preview
		isVisible : boolean
		--- Apply the rendering to town building parcel faces
		includeTownBuildings : boolean
		--- Apply the rendering to the actual model instances of the town building
		includeTownBuildingModels : boolean
		--- Apply the rendering to the main model instance of the town building only, without set dressing
		includeTownBuildingMainModel : boolean
		--- Apply the rendering to entities with Industry component
		includeIndustries : boolean
		--- Apply the rendering to entities with Warehouse component
		includeWarehouses : boolean
		--- Apply the rendering to entities with Station component
		includeStations : boolean
		--- Apply the rendering to entities with BaseEdge component
		includeEdges : boolean
	end

	--- Configures the rendering of catchment area of entities
	record CatchmentAreaDisplaySettings
		--- Creates a new empty CatchmentAreaDisplaySettings
		new : function() : CatchmentAreaDisplaySettings
		--- Creates a copy of CatchmentAreaDisplaySettings object
		new : function(CatchmentAreaDisplaySettings) : CatchmentAreaDisplaySettings

		--- Color for catchment areas that apply to pasengers
		personBaseColor : Vec3f
		--- Color for catchment areas that apply to non-passenger cargo
		cargoBaseColor : Vec3f
		--- Color for catchment areas that are not affected by current selections
		inactiveColor : Vec3f
		--- Color for catchment areas that are not reachable
		unreachableColor : Vec3f
		--- Color for catchment areas that are being removed
		deleteColor : Vec3f
		--- Color for catchment areas for maintenance stations repairs
		maintenanceColor : Vec3f
		--- Color for  radii of noise emitters
		noiseColor : Vec3f
		--- Color for  radii of pollution emitters
		pollutionColor : Vec3f

		--- Transparency of the catchment area border
		borderAlpha : number
		--- Transparency of the catchment area border when the catchment area is not involved
		borderAlphaPassive : number
		--- Transparency of the middle positioning beam
		godrayAlpha : number
		--- Transparency of the middle positioning beam when the catchment area is not involved
		godrayAlphaPassive : number
		--- Transparency of the inside part of the circle
		innerAlpha : number
		--- Transparency of the town building
		buildingAlpha : number
		
		--- Width of the catchment are circle's perimeter
		borderWidth : number
	end

	--- Configures which catchment areas to render
	record CatchmentAreaRenderableConfig
		new : function() : CatchmentAreaRenderableConfig
		new : function(CatchmentAreaRenderableConfig) : VoronoiRenderableConfig
		
		--- Activates and deactivate rendering of catchment areas
		isVisible : boolean
		--- Configures the look and feel of the areas
		displaySettings : CatchmentAreaDisplaySettings

		--- Do display cargo-compatible areas
		cargo : boolean
		--- Do display passenger-compatible areas
		person : boolean
		--- Do display maintenance station radii
		maintenance : boolean

		--- Do display emission emitter noise radii
		noise : boolean
		--- Do display emission emitter pollution radii
		pollution : boolean
		--- Add positioning beams in the middle of the circle
		addGodrays : boolean
		--- Only add areas to the specific entity
		entity : Engine.Entity
		--- Only add areas that are affected by specific carriers
		carriers : { Carrier }
	end

	--- Configure industry plots renderable
	record PlotsRenderableConfig
		new : function() : PlotsRenderableConfig
		new : function(PlotsRenderableConfig) : PlotsRenderableConfig
		
		triangles : {Vec2f}
	end

	--- Configures the texttual display on edges
	record SignConfig
		--- Creates an empty SignConfig object
		new : function() : SignConfig
		--- Copies a given SignConfig object
		new : function(SignConfig) : SignConfig
		--- Maximal render distance for spped limits
		signRenderDistance : number
	end

	--- Add an extra layer on top of base edges showing cargo that flowed onto this edge
	record CargoEdgesRenderables
		--- Creates a new empty object of type CargoEdgesRenderables
		new : function() : CargoEdgesRenderables
		--- Creates a copy of an object of type CargoEdgesRenderables
		new : function(CargoEdgesRenderables) : CargoEdgesRenderables
		--- Filter only cargo types flowing towards this town entitsy
		town : Engine.Entity
		--- Filter only cargo transported of the given type
		cargoTypes : {CargoTypeId}
		--- Consider cargo transported via lines
		showPlayerTransport : boolean
		--- Consider cargo transported via private transport
		showPrivateTransport : boolean
		--- Color for low and hight occupancy of transported cargo on public transport (lines)
		playerTransportColor : {Vec4f, Vec4f}
		--- Color for low and hight occupancy of transported cargo on private transport (cargo)
		privateTransportColor : {Vec4f, Vec4f}

		--- Discretization levels for the cargo
		numTransportLevels : integer
		--- Configures look and feel of labels
		signConfig: SignConfig
	end

	--- Configures the rendering of cargo satisfaction on the edge
	record SatisfactionEdgesRenderables
		--- Creates a new empty object of type SatisfactionEdgesRenderables
		new : function() : SatisfactionEdgesRenderables
		--- Creates a copy of an object of type SatisfactionEdgesRenderables
		new : function(SatisfactionEdgesRenderables) : SatisfactionEdgesRenderables
		town : Engine.Entity
		--- Only consider this cargo types
		cargoTypes : {CargoTypeId}
		--- Interpotate based on satisfaction percentage of cargo transited through the edge
		colors: {Vec4f}
		--- Values for the gradient of colors (must have same length as colors)
		thresholds: {number}
		--- Configures look and feel of text labels
		signConfig: SignConfig
	end

	--- Configures the rendering of the speed limits on edges
	record SpeedLimitsEdgesRenderables
		--- Creates a new empty object of type SpeedLimitsEdgesRenderables
		new : function() : SpeedLimitsEdgesRenderables
		--- Creates a copy of an object of type SpeedLimitsEdgesRenderables
		new : function(SpeedLimitsEdgesRenderables) : SpeedLimitsEdgesRenderables
		--- Intepolate between these colors based on the speed of the edges
		speedColor : {Vec4f, Vec4f, Vec4f}
		--- Intepolate between these colors based on the speed of the edges (applied to tunnels)
		undergroundSpeedColor : {Vec4f, Vec4f, Vec4f}
		-- Number of discretizaton levels of speedColor
		numberOfLevels : integer
		--- Color of the outline on tunnels
		tunnelOutlineColor : Vec4f
		--- Width of the outline on tunnels
		tunnelOutlineSize : number
		--- Configures look and feel of text labels
		signConfig : SignConfig

		--- Hide edges that are not owned by the player
		hideNonPlayerOwned : boolean
		--- Hide edges that do not have the roadDevelopmentLocked flag
		hideNonLocked : boolean
	end

	--- Configures the rendering of traffic in edges
	record TrafficEdgesRenderables
		--- Creates a new empty object of type TrafficEdgesRenderables
		new : function() : TrafficEdgesRenderables
		--- Creates a copy of an object of type TrafficEdgesRenderables
		new : function(TrafficEdgesRenderables) : TrafficEdgesRenderables
		--- Interpolate bewteen these colors based on the amount of traffic on the edges
		trafficColor : {Vec4f, Vec4f, Vec4f}
		--- Interpolate bewteen these colors based on the amount of traffic on the edges  (applied to tunnels)
		undergroundTrafficColor : {Vec4f, Vec4f, Vec4f}
		--- Number of discretizaton levels of speedColor
		numberOfLevels : integer
		--- Unused
		discrete : boolean
		--- Color of the outline on tunnels
		tunnelOutlineColor : Vec4f
		--- Width of the outline on tunnels
		tunnelOutlineSize : number
	end
	
	--- Configure the rendering of town limits (based on closest distance to towns)
	record VoronoiRenderableConfig
		--- Creates a new empty object of type VoronoiRenderableConfig
		new : function() : VoronoiRenderableConfig
		--- Creates a copy of an object of type VoronoiRenderableConfig
		new : function(VoronoiRenderableConfig) : VoronoiRenderableConfig
		--- Only consider towns of interest
		showTowns : boolean

		--- Optional towns of interest: If set AND `showTowns` is true, only those townns are considered
		townsOfInterest : {Engine.Entity}

		--- Display also borders at the edge of the map
		showMapBorder : boolean
		--- Width of the line
		lineWidth : number
		--- Colors of the line (alternatings)
		colors : {Vec4f}
		--- Number of section for each color
		sectionsPerColor : integer
		--- Height at which rendering is no longer visible
		fadingMinHeight : number
		--- Height at which rendering stops is fadingMinHeight+fadingDeltaHeight
		fadingDeltaHeight : number
	end

	--- Configure wind display and its impact on diverse emisson types
	record WindRenderableConfig
		--- Creates a new empty object of type WindRenderableConfig
		new : function() : WindRenderableConfig
		--- Creates a copy of an object of type WindRenderableConfig
		new : function(WindRenderableConfig) : WindRenderableConfig
		--- Enables or disable rendering of the visualization
		isVisible : boolean
		--- Grid to use to chose the wind direction (usually applies only to pollution)
		emissionType : Engine.Component.EmissionGrid.Type
	end

	--- Configure 3d cargo flow arrows
	record CargoFlowRenderableConfig
		--- Creates a new empty object of type CargoFlowRenderableConfig
		new : function() : CargoFlowRenderableConfig
		--- Creates a copy of an object of type CargoFlowRenderableConfig
		new : function(CargoFlowRenderableConfig) : CargoFlowRenderableConfig
		
		record FlowData
			new : function() : FlowData
			new : function(FlowData) : FlowData

			from : Vec3f
			to : Vec3f
			speed : number
			arrowColors : {Vec4f}

			cargoIconAlpha : number
			cargoTypes : {CargoTypeId}
		end

		flowData : {FlowData}
	end

	--- Optional color map config: nil, EmissionColorMap or TerrainColorMap
	colorMap : any -- variant: nil|EmissionColorMap|TerrainColorMap

	-- Optional countour rendering config
	contours : TerrainContours -- variant: nil|TerrainContours

	-- Optional colorPassFn config
	colorPassFn : ColorPassFn -- variant: nil|ColorPassFn

	-- Whether to use colorPassFn only for buildings (default: false)
	colorPassFnForBuildingRenderableOnly : boolean

	buildingRenderableConfig : BuildingRenderableConfig
	catchmentAreaRenderableConfig : CatchmentAreaRenderableConfig

	-- Optional edge renderable config: nil, SpeedLimitsEdgesRenderables, CargoEdgesRenderables, SatisfactionEdgeRenderables or TrafficEdgesRenderables
	edgeRenderableConfig : any -- variant: nil|SpeedLimitsEdgesRenderables|CargoEdgesRenderables|SatisfactionEdgeRenderables|TrafficEdgesRenderables

	voronoiRenderableConfig : VoronoiRenderableConfig
	windRenderableConfig : WindRenderableConfig
	plotsRenderableConfig : PlotsRenderableConfig
	cargoFlowRenderableConfig : CargoFlowRenderableConfig

	--- Underground mode enables rendering and snapping of underground entities
	undergroundMode : boolean
	--- Display one way arrows on streets
	showOneWay : boolean

	--- Enable color mode rendering (overrides the default if set)
	colorMode : boolean | nil
	--- Sets the ambient scale, or default of not set (2 for color mode and 1 for non color mode)
	ambientScale : number | nil
end

-- Model Types

--- Information about the axis aligned bounding box of the model
global record BoundingInfo
	--- Creates a new empty bounding info
	new : function() : BoundingInfo
	--- Creates a new bounding info with specified bounds
	-- @param bbMin Corner with lowest coordinates
	-- @param bbMax Corner with highest coordinates
	new : function(bbMin : Vec3f, bbMax : Vec3f) : BoundingInfo
	--- Corner with lowest coordinates
	bbMax : Vec3f
	--- Corner with highest coordinates
	bbMin : Vec3f
end

--- Information about the game-logic related bounds, usually for vehicles (bbMax.x being the vehicle's front)
global record Extent
	--- Creates a new extent with zero bounds
	new : function() : Extent
	--- Creates a new bounding info with specified bounds
	-- @param bbMin Corner with lowest coordinates
	-- @param bbMax Corner with highest coordinates
	new : function(bbMin : Vec3f, bbMax : Vec3f) : Extent
	--- Corner with lowest coordinates
	bbMax : Vec3f
	--- Corner with highest coordinates
	bbMin : Vec3f
end

--- Information about the collider of the model
global record Collider
	record Type
		NONE : Type
		BOX : Type
		CYLINDER : Type
		POINT_CLOUD : Type
	end

	--- A rectangular parallelepiped used for colliders
	record Box
		--- Distance from transform position to define the cuboid (in the direction relative to the transform)
		halfExtents : Vec3f
	end

	--- A cylinder used for colliders
	record Cylinder
		--- The dimensions from the center the cylinder extends to. Before being transformed.
		halfExtents : Vec3f
	end

	--- A set of points used for collision
	record PointCloud
		--- A list of points specifying all collision points
		points : {Vec3f}
	end

	--- The transform of the collider, relative to which the other data is transformed
	transf : Mat4f
	--- The type of collider
	type : Type
	--- Only if type == 1, a collider with a cuboidal shape
	box : Box
	--- Only if type == 2, a collider with a cylindrical shape
	cylinder : Cylinder
	--- Only if type == 3, a collider made up of a set of points
	pointCloud : PointCloud
end

--- Information about a single model file: metadata and bounding information
global record Model
	--- Additional information about the model
	metadata : table
	--- Bounding box for the model
	boundingInfo : BoundingInfo
	--- Collider information
	collider : table
	-- Optional model path that is used when adding a new model from mod.script.tl
	modelPath : ResName
end

-- Res Types 

--- Specification for auto-generated ground textures
global record AutoGroundTex
	new : function() : AutoGroundTex
	category : string
	gridSize : integer
	countFrom : integer
	countTo : integer
	groundTex : string
	individual : boolean
	individualCategory : string
end

--- Specification for bridge types and also tunnels
global record BridgeType
	--- Localized strings and icons paths for user interface
	description : ModelMetadata.Description
	--- Era information for user interface
	availability : ModelMetadata.Availability
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory
	--- Cost per unit length
	cost : number
	--- Top speed over the section type, limits top speed of road and tracks
	speedLimit : number
	--- Creates a new empty bridge type
	new : function() : BridgeType
	--- Cost for extensions to bridges: thresold, exponent, offset within a curve
	costFactors : Vec3f
	--- Maintenance cost per unit length
	maintenanceCost : integer
	--- Carriers allowed on the bridge/tunnel
	carriers : {Carrier}
	--- Extra width added to the side of the bridge (in meters)
	padding : number
	--- Height (tunnel only): results in offset applied to the terrain alignment above the bridge
	height : number
	--- Overrides the sidewalk height for the bridge
	sidewalkHeight : number
	--- Width (in meters) of bridge pillars
	pillarWidth : number
	--- Length (in meters) of bridge pillars
	pillarLen : number
	--- Minimal distance (in meters) between bridge pillars along the length of the bridge
	pillarMinDist : number
	--- Maximal allowed (in meters) distance between pillars along the length of the bridge
	pillarMaxDist : number
	--- Targeted distance (in meters) between pillars, as allowed by the street segment
	pillarTargetDist : number
	--- Length of abutments along bridges (in meters)
	abutmentLen : number
	--- Wdith of abutments along bridges (in meters)
	abutmentWidth : number
	--- Override street materials by using the given configurations
	materialsToReplace : table
	--- Overrides street assets by using the given list
	assetsToReplace : table
	--- Ground textures applied to the base of bridge pillars
	pillarGroundTexture : string
	--- Extra padding applied to the ground texture shape below bridges
	pillarGroundTextureOffset : number
	--- A script precisely controlling placement of railing models, pillars and entrances
	updateScript : ScriptRef
	--- Allow to be used for auto bridge selection while building roads and tracks, nil defaults to true
	isAutoSelectable : boolean
	--- Deprecated
	portals : table
end

--- Describes a generic game resource
global record GenericGameRes
	--- Creates a new empty resource
	new : function() : GenericGameRes
	--- Each generic resource has a type to differentiate its uses and enable querying by type
	type : string
	--- Any serializable data might be stored in a generic resource
	data : table
	--- Utility function to quickly set a data table
	setData : function(res : GenericGameRes, data : table)
end

--- Describes a generic game resource
global record GenericGameResT<T>
	--- Creates a new empty resource
	new : function() : GenericGameResT<T>
	--- Each generic resource has a type to differentiate its uses and enable querying by type
	type : string
	--- Any serializable data might be stored in a generic resource
	data : T
	--- Utility function to quickly set a data table
	setData : function(res : GenericGameResT<T>, data : T)
end

--- Represent a group of cargo types that are transported with similar packaging/containers: e.g. liquid, bulk, ...
global record CargoCategory
	--- Tier level of the cargo category
	tier : integer
	--- Land use types associated with this category
	landUses : {LandUseType}
	--- Industry tags required for this cargo category
	requiredIndustryTags : {string}
	townConsumptionFactor : number
end

--- Contains all data relevant for the climate 
global record ClimateDesc
	-- The definition of terrain data for the climate
	record TerrainData
		key : string
		displayName : string
		color : Vec3f
		id : integer
	end

	-- Describes data associated with this climate (eg biomes or rivers maps)
	record DataMap
		-- Biomes definition, biomes are exclusive to eachother
		biomes : { TerrainData }
		-- Layers definition, layers can overlap with eachother and overlap biomes
		layers : { TerrainData }
	end

	--- Creates a new, empty climate description
	new : function() : ClimateDesc
	--- Unique identifier for te climate
	id : string
	--- Localized strings and icons paths for user interface
	desc : ModelMetadata.Description
	--- Category for content selection: only objects with matching categories in categoryList will be availalbe in a
	--- game
	category : string
	--- Order for UI sorting
	order : integer
	--- Configure visibility of clima zones in the selection screen
	visible : boolean
	--- Configures minimap preview in colors and look and feel
	mapColoring : PreviewColoring
	--- Default economy for the climate zone
	economy : string
	--- Default environment for the cliamte zone
	environment : string
	--- Default name lists for the cliate zone
	defaultNames : string
	-- List of data map that describes biomes and layers for the climate
	dataMaps : DataMap
end

--- Contains all data relevant for the economy.
global record EconomyDesc
	--- Contains all data relevant for adding new cargo requirements to a town at a specific level
	record TownCargoLevelInfo
		new : function() : TownCargoLevelInfo
		new : function(copy : TownCargoLevelInfo) : TownCargoLevelInfo

		minTier : integer
		maxTier : integer
		landUseType : LandUseType
	end

	--- Creates a new, empty economy description
	new : function() : EconomyDesc
	--- Localized strings and icons paths for user interface
	desc : ModelMetadata.Description
	--- User interface order for sorting
	order : integer
	--- Selects the availability of the economy on the selection screen
	visible : boolean
	--- Used for selecting content based on the economy, depending on whether the object has matching tags in categoryList categories
	category : string
	industryWeightsSum2Population : number
	placementParams : {string : PlacementParams}
	cargoCategories : {string : CargoCategory}
	townLevels2CargoInfos : {integer : {TownCargoLevelInfo}}
	cargoRequiredIndustries : table
	companyRankRequiredIndustries : table
	defaultIndustryDensity : number
	defaultPopulationDensity : number
	defaultIndustryProductivity : number
end

--- Contains all data relevant for the heightmap generation
global record TerrainGeneratorDesc
	new : function() : TerrainGeneratorDesc

	--- Localized strings and icons paths for user interface
	desc : ModelMetadata.Description

	order : integer
	--- Only selectable in editor
	editorOnly : boolean
	-- Is a generator used when importing biomes/heightmap
	isImportGenerator : boolean
	--- Invisible (will never be a choice)
	visible : boolean

	--- Climate resource name to which the generator belongs to
	climate : string
	--- Resource name for the tree generator associated to this terrain generator
	nodeTree : string

	--- Script parameters (passed as input to tree node generator)
	params : {ScriptParam}
end

--- Specification for town building types
global record BuildingType
	--- Resource name of the construction
	constructionFile : string
	params : TownBuildingParams
end

--- Specification for cargo types
global record CargoClass
	new : function() : CargoClass
	new : function(copy : CargoClass) : CargoClass

	--- unique tag
	tag : string

	--- display name
	name : string

	--- detailed info
	description : string

	--- display icon path
	icon : string

	--- color of the cargo class
	color : Vec3f

	--- display ordering
	order : integer
end

--- Specification for cargo types
global record CargoType
	new : function() : CargoType
	new : function(copy : CargoType) : CargoType

	--- Display name
	name : string
	--- Display icon path
	icon : string
	--- Color of the cargo
	color : Vec3f
	--- Reference to cargo income factor script
	scriptRef : ScriptRef
	--- Weight of a unit of cargo
	weight : number

	cargoClasses : {string}
	--- Order for sorting in cargo type lists
	order : integer
	--- Category of the cargo
	category : string

	categoryList : ModelMetadata.CategoryList
	--- Lifetime of cargo in seconds
	timeToDeliverInSeconds : integer

	loadSpeedFactor : number
end

--- An addon to the sides (or the center) of BaseEdge like noise barrier and alleys
global record EdgeDecoration
	new : function() : EdgeDecoration
	new : function(copy : EdgeDecoration) : EdgeDecoration

	--- Era information for user interface
	availability : ModelMetadata.Availability
	--- Localized strings and icons paths for user interface
	desc : ModelMetadata.Description
	--- Cost per unit of length
	cost : ModelMetadata.Cost
	--- Maintenance cost per unit of length
	maintenance : number
	--- Filtering tags for incompatibility between edge decorations and clima zone selection
	categoryList : ModelMetadata.CategoryList
	--- An edge decoration will only be able to be built if the union of the base edge tags and all edge decoration category list are
	--- containing all required tags. Base edges have special tags denoting whether they are "track" or "street" edges and if they are "bridge" and "tunnel edges"
	requiredTags : {string}
	--- An edge decoration will only be able to be built if the union of the base edge tags and all edge decoration category list are
	--- not containing any incompatible tags. Any edge with one or more decoration has the additional built-in tag "decorated"
	incompatibleTags : {string}
	--- Model name that will be repeated along the decoration
	repModel : string
	--- Length of the model
	length : number
	--- Do stretch the model to perfectly fill in thegaps
	stretch : boolean

	--- Align models vertically or based on the slope of the edge: 0 = keep models vertical, 1 = keep model vertical but apply vertical shear to fill the
	--- gaps and align with stree slop, 2 = rotate the model to be normal to the street
	verticalAlignment : integer
	--- Snapping mode for the decoration: 0 = at the centerline of the transport network, 1 = at the side of the transport network
	snapMode : integer
	--- Offset (orthogonal to the direction of the edge (in meters)) from the center line
	offset : number
	--- If a decoration is applied on the matching side of the same parallel strip, it will not be shown
	skipSameInParallelStrip : boolean
	--- Order for user interface menus
	order : integer
	--- Modifers that are applied to vehicles travelling onto edges with such edge decoration
	modifiers : Modifiers
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory
	-- Sound resource (.builder_audio) for construction action
	builderAudioRes : ResName
end

--- Specification for environment
global record Environment
	--- Specification for atmosphere parameters
	record AthmostphereParams
		new : function() : AthmostphereParams
		cloudCoverage : number
		cloudBase : number
		cloudTop : number
		cloudScattering : number
		dayOfYear : number
		sunRotation : number
	end

	new : function() : Environment

	atmosphere : AthmostphereParams
	name : string
	isToolEnvironment : boolean
end

--- Specification for ground textures
global record GroundTexture
	new : function() : GroundTexture
	new : function(copy : GroundTexture) : GroundTexture

	--- Mapping of material indices
	matIndexMap : table
	--- Texture indices
	indices : table
	--- Priority for texture selection
	priority : integer
	--- Size of the texture
	texSize : number

	--- Extra information for ground textures
	record Data
		--- Raw texture data
		data : table
		--- Size of the texture data
		size : integer
	end
end

--- Specification for the lanes of street
global record LaneConfig
	--- Speed limit for the lane
	speed : number
	--- Width of the lane
	width : number
	--- Height of the lane
	height : number
	--- Whether the lane is in forward direction
	forward : boolean
	--- Transport modes allowed on this lane
	transportModes : {TransportMode : boolean}
	--- Offset from center
	offset : number
end

--- Configure additiive modifiers for specific entities
global record Modifiers
	--- Create a new Modifiers object
	new : function() : Modifiers
	--- Create a copy of a Modifier object
	new : function(copy : Modifiers) : Modifiers
	--- Compare Modifier for equality
	equals : function(Modifiers, Modifiers) : boolean

	--- A value of X will mean that noise produced by the entity is equal to (baseValue * (1 + X))
	noiseModifier : number
	--- A value of X will mean that pollution produced by the entity is equal to (baseValue * (1 + X))
	pollutionModifier : number
	--- A value of X will mean that the top speed of the entity entity is equal to (baseValue * (1 + X))
	maxSpeedModifier : number
end

--- Specification for multiple units
global record MultipleUnit
	--- Create a new MultipleUnit object
	new : function() : MultipleUnit
	--- Create a copy of a MultiplUnit object 
	new : function(copy : MultipleUnit) : MultipleUnit

	--- List of models of which the multiple unit is compsed of
	vehicles : {MultipleUnit.Vehicle}
	--- Localized display name for the unit
	name : string
	--- Localized display description for the unit
	desc : string
	--- Vehicle filter tags
	filterTags : {string}
	--- Group string to combine availability notifications of related vehicles
	availabilityNotificationGroup : string
	--- sortkey for availability notification group
	availabilityNotificationSortKey : integer
	--- Used for variant goupings: multiple units belonging to the same group will be shown as variants of each other
	groupFileName : string

	--- Specification for multiple units individual vehicles
	record Vehicle 
		--- Vehicle resource name
		name : string
		--- Whether the vehicle faces forward
		forward : boolean
	end
end

--- Specification for railroad crossings
global record RailroadCrossingType
	--- Localized strings and icons paths for user interface
	description : ModelMetadata.Description
	--- Era information for user interface
	availability : ModelMetadata.Availability
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory
	--- Cost per unit length
	cost : number
	--- Top speed over the section type, limits top speed of road and tracks
	speedLimit : number
	--- Creates a new RailroadCrossingType object
	new : function() : RailroadCrossingType
	--- Sound effect to play when the crossing is closing
	soundFileName : string
	config : {RailroadCrossingType.ConfigEntry}
	trafficDelay : number
	crossingMaterial : string
	categoryList : ModelMetadata.CategoryList
	--- Allow to be used for auto railroad crossing selection while building roads and tracks, nil defaults to true
	isAutoSelectable : boolean

	--- Specification for railroad crossings models
	record ConfigEntry
		modelLeft : string
		modelRight : string
		streetWidth : number
	end
end

--- Specifies the look and feel of streets and tracks
global record StreetStyle
	categoryList : ModelMetadata.CategoryList
	--- Models used for stright sections of tracks
	trackStraightModel : {string, string, string, string}
end

--- Specification for street templates which define simulation relevant quantities like lanes, costs and transport modes
global record StreetTemplate
	--- Creates a new object of StreetTemplate type
	new : function(string) : StreetTemplate
	--- Localized display name
	roadType : RoadType
	--- Localized strings and icons paths for user interface
	description : ModelMetadata.Description
	--- Availability from/to year for UI and simulation
	availability : ModelMetadata.Availability
	--- if this template can be used by town developer / industry connections at all.
	simBuildable : boolean
	--- Initial value for the locking tool when built by the player
	initiallyLocked : boolean
	--- Whether to consider a country or town road, this affects simulation and UI behaviour in various ways
	country : boolean
	--- List of lanes with configuration, from left to right in the build direction
	laneConfigs : {LaneConfig}
	--- Transport network types applied to vehicle lanes
	transportModesStreet : {TransportMode}
	--- Modifiers applied to vehicles on the road
	modifiers : Modifiers
	--- Cost in unit-length
	cost : integer
	--- Maintenance cost in unit-length
	maintenanceCost : integer
	--- Ground texture applied to the interior of the road
	fillGroundTex : ResName
	--- Ground texture applied under sidewalks
	sidewalkFillGroundTex : ResName
	--- Ground texture applied at the edges of the road
	borderGroundTex : ResName
	--- Default street style deciding look and feel of the road/track
	streetStyle : ResName
	--- Default edge decorations when newly built
	defaultEdgeDecorations : {{ResName, boolean}}
	--- Whether to create crosswalks when the street is built
	defaultWithCrosswalk : boolean
	--- Terrain alignment embankment from below
	embankmentSlopeLow : number
	--- Terrain alignment embankment from above
	embankmentSlopeHigh : number
	--- Max slope of the road the user can select
	maxSlope : number
	--- Max slope for the resulting street
	maxSlopeShape : number
	--- Priority for applying the street style at crossings
	priority : integer
	--- Whether bus and tram lanes are by default on the rightmost lane
	busAndTramRight : boolean
	--- Pathfinding walk penalty when pedestran walk on sidewalk edges
	pedestrianWalkPenalty : number
	--- Max speed based on three different curvatures of the street
	speedCoeffs : {number}
	--- Minimal radius of the finial proposal
	minCurveRadius : number
	--- Minimal radius buildable by the player
	minCurveRadiusBuild : number
	--- Distance between track centers
	trackDistance : number
	--- Max slope when built by the player
	maxSlopeBuild : number
	--- How fine grained the selection of the slope will be
	slopeBuildSteps : number
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory

	record Emissions
		noise : number
		pollution : number
		radius : number
	end
	--- Static nosie and pollution emitter for each road segment
	emissions : Emissions
	--- The street template to use to replace this street template when adding catenary
	catenaryAdd : ResName
	--- The street template to use to replace this street template when removing catenary
	catenaryRemove : ResName
	-- Sound resource (.builder_audio) for construction action
	builderAudioRes : ResName
end

--- Specification for traffic lights
global record TrafficLightType
	--- Configures year availability of the traffic light (for AI and player building it)
	availability : ModelMetadata.Availability
	--- Localized strings and icons paths for user interface
	description : ModelMetadata.Description
	--- Cost per unit when built
	cost : number
	--- Tags for content selection and filtering
	categoryList : ModelMetadata.CategoryList
	--- Configure category, order and filter behaviour in the construction menu
	menuCategory : ModelMetadata.MenuCategory
	--- Whether to build North American style on the opposide side of the intersection if possible
	tryOpposite : boolean
	--- A script controlling the actual placement of models on the intersection
	modelScript : ScriptRef
	--- Deprecated
	relativePath : string
end

--- Specification for terrain material types
global record TerrainMaterialType
	new : function() : TerrainMaterialType
	new : function(copy : TerrainMaterialType) : TerrainMaterialType

	name : string
	desc : string
	icon : ResName
	previewIcon : ResName
	categories : {string}
	detailColorTexture : string
	detailMetalGlossAoHTexture : string
	detailNormalTexture : string
	overlayTexture : string
	detailSize : number
	overlaySize : number
	overlayStrength : number
	hScale : number
	order : integer
	menuCategory : ModelMetadata.MenuCategory
	priority : integer
	grass : ResName
	categoryList : ModelMetadata.CategoryList
end

global record PlacementParams
	requiredIndustryTags : {string}
	tags : {string}
	distanceWeights : {string : number }
	allowedOnLand : boolean
	allowedOnWater : boolean
	buildOrder : integer
	initWeight : integer
	tier : integer
	weights : {string : number }
end

global record PreviewColoring

end

-- Scripting Types

--- A structure that holds config for a chart
global record ChartConfig
	new : function() : ChartConfig
	--- The time in which the data gets collected.
	interval : integer
	--- The desired number of intervals.
	count : integer
	--- The minimum number of intervals to display.
	minCount : integer
	--- Modify y stepSize for fine-tuning.
	yStepScale : number
end

--- A structure that holds data for a chart
global record ChartResult
	equals : function(ChartResult, ChartResult) : boolean

	--- X-axis range
	xRange : {number}
	--- Y-axis range
	yRange : {number}
	--- Data series
	series : {{{number}}}
	--- X-axis markers
	xMarkers : {number}
	--- Y-axis markers
	yMarkers : {number}
	--- Number of potential groups
	numPotentialGroups : integer
end

-- Transport Types

--- Contains additional data about the transport network
global record TpNetData
	--- Data attached to a transport network node.
	record NodeData
		--- An individual port on a NodeData
		record Port
			--- The edge ID this port connects to
			edgeId : EdgeId
			--- The indices of the ports this port can transition to
			transitions : {integer}
		end

		--- The list of ports on this node
		ports : {Port}
	end

	--- Data attached to a transport network edge.
	record EdgeData
		--- The ports at both ends of the edge
		ports : {PortId, PortId}
		--- The equidistant parameter samples along the edge
		equidistParams : {number}
	end


	--- Get node data for a specific node
	getNodeData : function(TpNetData, NodeId) : NodeData
	--- Get edge data for a specific edge
	getEdgeData : function(TpNetData, EdgeId) : EdgeData
end


--- Engine Util Types

global record Failure
	record Reason
		Unkown : Reason
		NoPath : Reason
		NoElectric : Reason
		NoTram : Reason
		NoTramButTramTrack : Reason
		NoTramTrackButRail : Reason
		NoRail : Reason
		NoRoad : Reason
		NoSmallAircraft : Reason
		NoSmallShip : Reason
	end

	reason : Reason
	pos : Vec3f
end

global record FinanceData
	equals : function(FinanceData, FinanceData) : boolean

	transport : {JournalEntry.Carrier:{integer:{integer}}}
	investment : {integer:{integer}}
	other : {JournalEntry.Other, {integer}}
	loan : {integer}
	interest : {integer}
	loanBorrowing : {integer}
	loanRepayment : {integer}
	total : {integer}
	balance : {integer}
	header : {string}

	unfoldKey : function(FinanceData, integer) : {JournalEntry.Type, JournalEntry.Maintenance, JournalEntry.Construction}
	foreach_carrier : function(FinanceData, function(JournalEntry.Carrier, {integer:{integer}}))
	foreach_transport : function(FinanceData, function(integer, {integer}), JournalEntry.Carrier)
	foreach_investment : function(FinanceData, function(integer, {integer}))
	foreach_other : function(FinanceData, function(JournalEntry.Other, {integer}))
end

global record LineIssue
	record Type
		NowhereToLoad : Type
		NowhereToUnload : Type
		NoVehicleToLoadCargo : Type
		VehicleUseless : Type
		LineCargoConfig : Type
		None : Type
	end
	type : Type
	stopIndex : integer
	cargoType : CargoTypeId
end

-- Vehicle Types

--- Information about cargo of a single compartment of a transport vehicle
global record VehicleCargoInfo
	--- Capacity of this vehicle
	capacity : number
	--- Sum of the cargo capacities up to this vehicle
	offset : number
end

--- Information about all cargo of a transport vehicle
global record TransportVehicleInfo
	--- List of VehicleCargoInfo for vehicles, compartments and cargo types
	cargoInfos : {{{VehicleCargoInfo}}}
end

--- Information about carriages
global record CarriageInfo
	owningVehicle : Engine.Entity
	index : integer
	offset : number
	--- Whether the carriage is reversed
	reversed : boolean
	crew : Engine.Entity
	["end"] : number
end

--- Information about travel-direction extent of an entire vehicle (consist of carriages)
global record VehicleExtent
	--- negative distance in meters from back to vehicle pin position
	back : number

	--- positive distance in meters from vehicle pin position to front plus some random spacing ahead
	front : number
end

--- Information about an entire vehicle (consist of carriages)
global record VehicleData
	record CarriageData
		offset : number
		reversed : boolean
		--- Modified amount of emission for the carrriage
		emissions : ModelMetadata.Emissions
	end

	--- space in x-axis/driving direction, values for in front and behind of center
	bounds : VehicleExtent

	--- total length (without random spacing ahead)
	length : number

	--- minimum of all top speeds
	topSpeed : number

	--- Acceleration when breaking (in m / s^2)
	brakeDeceleration : number
	--- List of carriaces for the vehicle (applies to trams and trains)
	carriages : {CarriageData}
end

--- Details about a vehicle part
global record VehiclePartInfo
	--- A single seat in a vehicle
	record Seat 
		--- Entity occupying this seat
		occupied : Engine.Entity
		--- Animation playing for this seat
		animation : string

		crew : boolean
	end
	--- List of seats in this vehicle part
	seats : {Seat}
	--- Number of occupied seats on this vehicles
	count : number
end

-- Util Types

--- Collection of useful memory statistics
global record MemoryStatistics
	--- Video memory usage
	vidMemUsage : integer
	--- Tracked video memory usage
	trackedVidMemUsage : integer
	--- Maximum video memory
	vidMemMax : integer
	--- Peak video memory usage
	peakVidMem : integer
	--- RAM usage
	ramUsage : integer
	--- Tracked RAM usage
	trackedRamUsage : integer
	--- Maximum RAM
	ramMax : integer
	--- Peak RAM usage
	peakRam : integer
	--- Peak total memory usage
	peakTotalMem : integer
	--- Largest free memory block
	largestFreeBlock : integer
end

-- Paradox API Types

global record PdxErrorCodes
	AccountAlreadyExists : PdxErrorCodes 
	BadEmailAddressFormat : PdxErrorCodes
	BadPasswordLength : PdxErrorCodes
	BadDateFormat : PdxErrorCodes
	UnderAgeAccount : PdxErrorCodes
	MissingAccountInfo : PdxErrorCodes
	
	ProfileDoesNotExist : PdxErrorCodes

	ProfileAlreadyTaken : PdxErrorCodes
	ProfileAlreadyExists : PdxErrorCodes
	ProfileNameTooLong : PdxErrorCodes
	ProfileNameTooShort : PdxErrorCodes
	ProfileNameInvalid : PdxErrorCodes
end

global interface PdxResult
	success : boolean
	errorCode : PdxErrorCodes
end

global record PdxLoginResult is PdxResult

end

global record PdxAccountInfo is PdxResult
	email : string
end

global record PdxProfileResult is PdxResult
	id : string
	name : string
end

global record PdxLegalDocument is PdxResult
	title : string
	text : string
end

global record PdxCountry
	name : string
	code : integer
end

global record PdxThirdPartyLinkState
	NeitherAccountHasLink : PdxThirdPartyLinkState
	ParadoxAccountHasLink : PdxThirdPartyLinkState
	ThirdPartyAccountHasLink : PdxThirdPartyLinkState
	BothAccountsHaveLinks : PdxThirdPartyLinkState
	BothAccountsAreLinked : PdxThirdPartyLinkState
end

global record PdxThirdPartyAutoLoginPromptState
	NotShown : PdxThirdPartyAutoLoginPromptState
	Accepted : PdxThirdPartyAutoLoginPromptState
	Rejected : PdxThirdPartyAutoLoginPromptState
end

global record PdxFuture<T>
	-- return result if available (otherwise nil)
	getResult : function(PdxFuture<T>) : T
end


recordDef = false
