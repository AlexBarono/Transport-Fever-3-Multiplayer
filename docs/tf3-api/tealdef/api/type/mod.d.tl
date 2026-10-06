recordDef = true

--- Contains all type definitions for the mods.

global type ModId = integer

--- Refer to https://wiki.transportfever3.com/doku.php?id=modding:moddefinition for more details about mod and mod interface in general
--- @category main
global record Mod
	--- Mod identifier
	record ModId
		new : function() : ModId
		equals : function(ModId, ModId) : boolean

		--- A string that identify the mod
		name : string
	end

	--- A reference to a mod
	record ModRef
		--- Mod id
		modId : ModId
		--- The minimum compatible revision
		revisionMin : integer
		--- The maximum compatible revision
		revisionMax : integer
	end

	--- User facing mod informations
	record ModRefInfo 
		--- Display name of the mod
		displayName : string
		--- URL to the mod page
		url : string
	end

	--- Describes a dependency to another mod
	record ModDependency
		--- Mod Ref of the depedency
		mod : ModRef
		--- If the depedency is optional
		optional : boolean
		--- If this depedency needs to be loaded before the dependant
		loadBefore : boolean
		--- Mod info for the depedency
		modInfo : ModRefInfo
	end

	--- Describes an incompatibility with another mod
	record ModIncompatibility
		mod : ModRef
	end

	--- Contains general information about the mod
	record GameModDesc
		--- Mod id
		modId : ModId
		--- The origin of the mod (eg. User Mod, Staging Area, DLC, mod.io, ...)
		modSource : string
		--- Mod id in the modhub backend
		modhubModId : string
		--- Display name of the mod (User facing)
		name : string
		--- If removing this mod could cause instability to a savegame.
		---	Any value above 0 will trigger a message when trying to remove the mod from a savegame
		---	0: None, 1: Warning, 2:Critical
		severityRemove : integer
	end

	record ModDesc
		--- If adding this mod could cause instability to a savegame.
		---	Any value above 0 will trigger a message when trying to add the mod to a savegame
		---	0: None, 1: Warning, 2:Critical
		severityAdd : integer
		--- If removing this mod could cause instability to a savegame.
		---	Any value above 0 will trigger a message when trying to remove the mod from a savegame
		---	0: None, 1: Warning, 2:Critical
		severityRemove : integer
		--- Script parameters to dynamically configure the mod
		params : {ScriptParam}
		--- If if the mod is visible, hidden mod cannot auto-activate
		visible : boolean
		--- If the mod is purely cosmetic, cosmetic mods still allow achievement from being earned while playing
		cosmetic : boolean
		--- If the mod is automatically activate by the game
		autoActivate : boolean
		--- URL to the mod page
		url : string

		--- Mods this mod depends on
		dependencies : {ModDependency}
		--- Mods this mod is incompatible with
		incompatibilities : {ModIncompatibility}
		--- version of the mod
		revision : integer
	end

	--- Information about the size of the mod
	record ModSize
		--- The number of models contained in the mod
		numModels : integer
		--- The number of texture contained in the mod
		numTextures : integer
		--- The number of meshes contained in the mod
		numMeshes : integer
		--- The approximate size of the mod
		totalEstimatedSizeMB : integer
	end

	-- global enum ModSource
	-- 	SteamWorkshop
	-- 	UserMods
	-- 	StagingArea
	-- 	BuiltInMods
	-- 	DLC
	-- end
end
