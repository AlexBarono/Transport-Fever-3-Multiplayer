recordDef = true

--- Repositories containing game resources (models, tracks, streets, ...)

global record GameScriptType
	getState : function(GameScriptType) : table
end

--- Generic interface for repositories
--- Resources are generally static (initialized when the game starts and don't change)
--- Make sure that resource exists before trying to access them
--- Resource ids are only valid within the same repository
global interface ResTypeRep<K, T>
	--- Gets the resource for a given id - (can be used to directly modify the resource,
	--- but this is discouraged, except for performance reasons. Use getAsTable and setAsTable instead.
	--- @param id a resource id
	--- @return the resource
	get : function(id : K) : T

	--- Gets the resource name for a given id
	--- @param id a resource id
	--- @return the resource name
	getName : function(id : K) : string

	--- Finds the id of the given resource name and returns its id
	--- @param resName a resource name
	--- @return the id of the resource, -1 if the resource doesn't exist
	find : function(resName : string) : K

	--- Finds the resource with the given name and returns it
	--- @param resName a resource name
	--- @return the resource, and an error if the resource is not found
	findAndGet : function(resName : string) : T

	--- Gets all resources
	--- @param includeInvisible if invisible resources should be included, false by default
	--- @return a dictionary containing all id and resource names
	getAll : function(includeInvisible? : boolean) : {K : string}

	--- Adds a new resource to the repository
	--- @param resName the resource name of the new resource
	--- @param resource the resource itself
	--- @param visible if the resource is visible
	--- @return the id of the newly added resource
	add : function(resName : ResName, resource : T, visible : boolean) : K

	--- Sets a resource visible
	--- @param id the id of the resource
	--- @param visible if the resource should be visible
	setVisible : function(id : K, visible : boolean)

	--- Checks if a resource is visible
	--- @param id the id of the resource
	--- @return if the resource is visible
	isVisible : function(id : K) : boolean

	--- Gets the resource for a given id as a pure lua table
	--- @param id a resource id
	--- @return the resource
	getAsTable : function(id : K) : T

	--- Updates the resource for a given id from a pure lua table (as if it was the resource file)
	--- @param id a resource id
	--- @param t the resource
	--- @return success
	setAsTable : function(id : K, t : T) : boolean

	--- Add a new resource from a pure lua table (as if it was the resource file)
	--- @param the name of the resource to add (should be unique)
	--- @param t the resource to add
	--- @return the newly added id
	addAsTable : function(resName : ResName, resource : T) : K
end

global record ModelRep is ResTypeRep<integer,Model>
	--- Iterates over all the models with a specific metadata
	--- @param metadata the name of the metadata
	--- @param callback a callback for every model that contains the specified metadata
	forEachModelWithMetadata : function(metadata : string, callback : function(name : string))
end

global record CargoTypeRep is ResTypeRep<CargoTypeId, CargoType>
	--- Iterates over all cargo types in a given cargo type set
	--- @param cargoTypeSet the cargo type set to iterate over
	--- @param callback a callback for each cargo type
	forEachCargoType : function(cargoTypeSet : CargoTypeSet, callback : function(cargoTypeId : CargoTypeId))

	--- Checks if a cargo type set contains a specific cargo type
	--- @param cargoTypeSet the cargo type set to check
	--- @param test the cargo type to test for
	--- @param inverse if true, the function returns true when any other cargo exists
	hasCargoType : function(cargoTypeSet : CargoTypeSet, test : CargoTypeId, inverse? : boolean) : boolean

	--- Returns the cargo type id for passenger
	getPassengerCargoTypeId : function() : CargoTypeId
end

global record CargoClassRep is ResTypeRep<integer,CargoClass>
	--- Gets the CargoClassId for a given CargoClass name
	--- @param cargoClass cargo class name
	--- @return cargo class id
	getCargoClassId : function(cargoClass : string) : CargoClassId
	--- Checks if the given cargo class is present, this can be used if some cargo classes exist but are invisible
	--- @param cargoClass cargo class name
	--- @return true if present
	hasCargoClass : function(scargoClass : string) : boolean
end

global record GenericRep is ResTypeRep<integer,GenericGameRes>
	--- Gets all Generic resource types of a given type name
	--- does not allow typeName in { "gui_res_overwrite", "gui_res" }, for those, use `api.gui.genericRep`
	--- @param typeName type name
	--- @param includeInvisible whether to include invisible
	--- @return resource ids
	getAllOfType : function(typeName : string, includeInvisible? : boolean) : {integer}
end

--- List of all repositories
--- @category main
global record Res
	--- A resource repository containing data for town buildings.
	buildingTypeRep : ResTypeRep<integer,BuildingType>
	--- A resource repository containing data from the bridge configuration files and from dynamically generated bridges.
	bridgeTypeRep : ResTypeRep<integer,BridgeType>
	--- A resource repository containing data from the ".con" files and from dynamically generated constructions.
	constructionRep : ResTypeRep<integer,ConstructionDesc>
	--- A resource repository containing data for all custom resources.
	metaConstructionRep : ResTypeRep<integer,MetaConstructionDesc>
	genericRep : GenericRep
	--- A resource repository containing data from the ".eco" economy resources.
	economyRep : ResTypeRep<integer,EconomyDesc>
	--- A resource repository containing data for the climates.
	climateRep : ResTypeRep<integer,ClimateDesc>
	--- A resource repository containing data for the environment.
	environmentRep : ResTypeRep<integer,Environment>
	--- A resource repository containing game scripts.
	gameScriptRep : ResTypeRep<integer,GameScriptType>
	--- A resource repository containing data with all the cargo classes.
	cargoClassRep : CargoClassRep
	--- A resource repository containing data with all the cargo types.
	cargoTypeRep : CargoTypeRep
	--- A resource repository containing all the game models and metadata.
	modelRep : ModelRep
	--- A resource repository containing data from the multiple unit files and from dynamically generated multiple units.
	multipleUnitRep : ResTypeRep<integer,MultipleUnit>
	--- A resource repository containing data from the street template files and from dynamically generated street templates.
	streetTemplateRep : ResTypeRep<integer,StreetTemplate>
	edgeDecorationRep : ResTypeRep<integer,EdgeDecoration>
	--- A resource repository containing materials.
	terrainMaterialTypeRep : ResTypeRep<integer,TerrainMaterialType>
	--- A resource repository containing data from the traffic lights.
	trafficLightTypeRep : ResTypeRep<integer, TrafficLightType>
	--- A resource repository containing data from the tunnel configuration files and from dynamically generated tunnels.
	tunnelTypeRep : ResTypeRep<integer,BridgeType>
	--- A resource repository containing data from the ".modules" files and from dynamically generated modules.
	moduleRep : ResTypeRep<integer,ModuleDesc>
	--- A resource repository containing data from the railroad crossing files and from dynamically generated railroad crossing types.
	railroadCrossingTypeRep : ResTypeRep<integer,RailroadCrossingType>
	--- A resource repository containing data from the street type files and from dynamically generated street types.
	streetStyleRep : ResTypeRep<integer,StreetStyle>
	--- A resource repository containing data for audio sets for building
	builderAudioSetRep : ResTypeRep<integer, BuilderAudioSet>
	--- A resource repository containing data for sound sets
	soundSetRep : ResTypeRep<integer, SoundSet>
	--- A resource repository containing data for ground textures.
	groundTextureRep : ResTypeRep<string, GroundTexture>
	--- A resource repository containing data for automatic ground texture definitions.
	autoGroundTexRep : ResTypeRep<string, AutoGroundTex>

	--- Gets the base config, it contains most of the data which was read from "base/base_config.lua".
	--- @return Table the configuration table. See https://wiki.transportfever3.com/doku.php?id=modding:baseconfig for a detailed explanation.
	getBaseConfig : function() : BaseConfig
end

recordDef = false
