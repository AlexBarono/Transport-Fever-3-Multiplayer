recordDef = true

--- Basic definitions for all APIs

--- Used instead of the regular lua `require` to include game related script
global ug_require : function(string) : any

--- Used to mark strings localized string (eg. `_("Some text to localize")`)
global _ : function(string) : string

--- Returns a localized string, with plural handling
--- @param singularId singular text (or id)
--- @param pluralId plural text (or id)
--- @param n number of object referred to in the plural text (for plural)
--- @return localized string
global nGetText : function(singularId : string, pluralId : string, n : integer) : string

--- Returns a localized string associated with a context
--- @param context localization context
--- @param id the string (or id) to localize
--- @return localized string
global pGetText : function(context : string, id : string) : string

--- Returns a localized string associated with a context, with plural handling
--- @param context localization context
--- @param singularId singular text (or id)
--- @param pluralId plural text (or id)
--- @param n number of object referred to in the plural text (for plural)
--- @return localized string
global npGetText : function(context : string, singularId : string, pluralId : string, n : integer) : string

--- Returns the appropriate string based on the current platform
--- @param playstation the string for playstation
--- @param xbox the string for xbox
--- @param desktop the string for desktop
global getStringForPlatform : function(playstation : string, xbox : string, desktop : string) : string

--- Returns the build version
global getBuildVersion : function() : string

--- Prints text to the console/log file
global debugPrint : function(... : any)

--- Resolves a file paths relative to the current file
--- @param relativePath a relative path 
--- @return the full filepath
global resolve : function(relativePath : string) : string

--- Returns the mod id of the current mod scope
--- This is the outermost mod in the require hierarchy (i.e. the current file might belong to a different mod)
--- @return modId string
global getCurrentModId : function() : string

--- Returns the mod id of the mod owning the current file
--- Note: This means you can not delegate calls to this function into helper files!
--- @return modId string
global getOwningModId : function() : string

global addModifier : function<T>(fileName : string, data : T) : T

global record game
	metamethod __index : function(game, string) : game

	record Res
		script : table
	end
	res : Res 
end

global _rootData : any

recordDef = false
