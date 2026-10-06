recordDef = true

--- Contains all type definitions for the modhub.

global type Mod

--- modhub types
--- @category main
global record Modhub
	--- Message from mod validator
	record ModValidatorMessage
		--- The context of the message, e.g. which check produced it
		context : string
		--- The file path where the issue was found
		file : string
		--- The severity level of the message
		level : LogLevel
		--- The validation message
		message : string
		--- Whether this issue only affects console platforms
		consoleOnly : boolean
	end

	--- Result from mod validation
	record ModValidatorResult
		--- List of validation messages
		messages : {ModValidatorMessage}
		--- Whether the validation found critical issues on PC
		criticalPc : boolean
		--- Whether the validation found critical issues on console
		criticalConsole : boolean
		--- Cooked PC Path
		cookedPcPath : string
		--- Cooked Console Path
		cookedConsolePath : string
		--- Minimum log level found on PC
		levelPc : LogLevel
		--- Minimum log level found on console
		levelConsole : LogLevel
	end

	record ModHubErrorCode
		--- Error Code Number
		code : integer
		--- Error Message (not localized, for debug purposes only)
		message : string
		--- Additional fields with more information about the error
		fields : {string : string}
	end

	record SortType
		Trending : SortType
		Rating : SortType
		SubscriberCount : SortType
		DateAdded : SortType
		DateUpdated : SortType

		Name : SortType
		Source : SortType
		Custom : SortType
	end

	record SortOrder
		sortType : SortType
		allowAscDesc : boolean
	end

	record TagGroup
		name : string
		values : {string}
		allowMultipleSelection : boolean
		noSortTag : boolean
		visible : boolean
	end

	record SortAndFilterOptions
		tagGroups : {TagGroup}
		sortOrders : {SortOrder}
		statusTagGroupIndex : integer
	end

	record UserInfo
		userName : string
		profileUrl : string
		displayName : string
	end
	
	record ModId
		new : function() : ModId
		clone : function(ModId) : ModId
		isValid : function(ModId) : boolean
		value : string
	end

	record UserId
		new : function(value? : integer) : UserId
		equals : function(UserId, UserId) : boolean
		isValid : function(UserId) : boolean

		value : integer
	end

	record ModManagementMode
		Disabled : ModManagementMode
		Restricted : ModManagementMode
		Full : ModManagementMode
	end

	record InstallState
		None : InstallState
		Downloading : InstallState
		UpdatePending : InstallState
		Installed : InstallState
		DownloadPending : InstallState
		InstallationPending : InstallState
		UninstallPending : InstallState
		Extracting : InstallState
		InsufficientSpace : InstallState
		MiscError : InstallState
	end
	
	record ModInstallInfo
		installPath : string
		runtimeRevision : integer
	end

	record ModReleaseInfo 
		version : string
		releaseNotes : string
		releaseUnixTimestamp : integer
	end

	record ModInfo
		clone : function(ModInfo) : ModInfo

		modId : ModId
		modSource : string
		visible : boolean
		numDownloads : integer
		numSubscribers : integer
		title : string
		url : string
		summary : string
		description : string
		descriptionHtml : string
		logoImage : string
		installSize : integer
		likes : integer
		dislikes : integer
		rating : number
		tags : { string }
		hasDependencies : boolean
		publishedUnixTimestamp : integer
		updatedUnixTimestamp : integer
		releaseInfo : ModReleaseInfo
	end

	record ModMediaType
		Logo : ModMediaType
		GalleryThumb180p : ModMediaType
		GalleryThumb720p : ModMediaType
		GalleryOriginal : ModMediaType
		AuthorAvatar : ModMediaType
	end

	record AuthenticationType
		Email : AuthenticationType
		Steam : AuthenticationType
		SteamOffline : AuthenticationType
		Gog : AuthenticationType
		Epic : AuthenticationType
		XboxLive : AuthenticationType
		PSN : AuthenticationType
		Paradox : AuthenticationType
	end
		
	record RatingType
		Neutral : RatingType
		Positive : RatingType
		Negative : RatingType
	end

	record ReportType
		Generic : ReportType
		DMCA : ReportType
		NotWorking : ReportType
		RudeContent : ReportType
		IllegalContent : ReportType
		StolenContent : ReportType
		FalseInformation : ReportType
		Other : ReportType
	end

	record StorageInfo
		usedSpace : integer
		totalSpace : integer
	end

	record ModManagementState
		uploading : boolean
		busy : boolean
		totalPending : integer
		pending : {ModId}
		finished : {ModId}
		progress : number
		currentModId : ModId
	end

	record Capabilities
		allowForceUninstall : boolean
		authenticationTypes : {AuthenticationType}
		manualRefresh : boolean
		specialModRefresh : boolean
		allowReport : boolean
		isInfoOnly : boolean
		allowUnsubscribeInstalledMods : boolean
		allowRestrictedMode : boolean
		allowModUpload : boolean
		visibleInModHub : boolean
	end

	record Description
		name : string
		nameLocalized : string
		url : string
		icon : string
	end

	record EmailAuthCodeRequest
		new : function(string) : EmailAuthCodeRequest

		email: string
	end
	record EmailAuthCodeData
		record Response
			ValidationError : Response
			NeedAuthCode : Response
			Authenticated : Response
		end
		response : Response
	end

	record AuthenticateUserEmailRequest
		new : function(string) : AuthenticateUserEmailRequest

		authCode: string
	end
	record AuthenticateUserEmailData
		record Response
			ValidationError : Response
			ExpiredAuthCode : Response
			Authenticated : Response
		end
		response : Response
	end

	record TermsOfUseRequest
		new : function(AuthenticationType) : TermsOfUseRequest

		type : AuthenticationType
	end
	record TermsOfUseData
		terms: string
		agreeLabel: string
		disagreeLabel: string
	end
			
	record AuthenticateUserExternalRequest
		new : function(AuthenticationType) : AuthenticateUserExternalRequest

		type : AuthenticationType
		email: string -- optional
	end
	record AuthenticateUserExternalData
		record Response
			UnkownError : Response
			PortalSignInError : Response
			ValidationError : Response
			Authenticated : Response
		end
		response : Response
	end

	record LogoutData
	end

	record ListModsRequest
		new : function() : ListModsRequest

		page : integer
		preferedPageSize : integer
		searchString : string
		sortType : SortType
		sortAscending : boolean
		tags : {integer}
		fetchLongDescription : boolean
	end
	record ListModsData
		modInfos : {ModInfo}
		modsPerPage : integer
		totalResultCount : integer
	end

	record GetModDetailsRequest
		new : function(ModId) : GetModDetailsRequest

		modId : ModId
	end

	record UserPortal
		XboxLive : UserPortal
		PlaystationNetwork : UserPortal
		Misc : UserPortal
	end

	record ModDetailsData
		new : function() : ModDetailsData

		modInfo : ModInfo
		author : string
		userId : UserId
		userPortal : UserPortal
		numGalleryImages : integer
		logoImage : string
		galleryImages : {string}
		dependencies : { {ModId, string} }
		found : boolean
	end

	record GetModMediaRequest
		new : function(ModId, ModMediaType, integer) : GetModMediaRequest
		modId : ModId
		type : ModMediaType
		galleryIndex : integer
	end
	record ModMediaData
		new : function() : ModMediaData
		width : integer
		height : integer
		channels : integer
		data : {integer}
		data_native : Vector<integer>
	end

	record GetModRatingRequest
		new : function(ModId) : GetModRatingRequest

		modId : ModId
	end
	record ModRatingData
		new : function() : ModRatingData
		rating : RatingType
	end

	record SubscribeModRequest
		new : function(ModId) : SubscribeModRequest

		modId : ModId
	end	
	record UnsubscribeModRequest
		new : function(ModId) : UnsubscribeModRequest

		modId : ModId
	end
	record SubscriptionData
	end

	record RefreshData
		numRefreshed : integer
	end

	record ForceUninstallModRequest
		new : function(ModId) : ForceUninstallModRequest

		modId : ModId
	end
	record ForceUninstallModData
	end

	record SpecialRefreshModRequest
		new : function(ModId, boolean) : SpecialRefreshModRequest

		modId : ModId
		unsubscribe : boolean
	end
	record SpecialRefreshModData
	end

	record RestartModBackendData
	end

	record SubmitModRatingRequest
		new : function(ModId, RatingType) : SubmitModRatingRequest

		modId : ModId
		rating : RatingType
	end
	record SubmitModRatingData
		rating : RatingType
	end

	record SubmitModReportRequest
		new : function(ModId, ReportType, string, ?string, ?string) : SubmitModReportRequest

		modId : ModId
		type : ReportType

		reportDescription : string
		reporterName : string
		reporterContact : string
	end
	record SubmitModReportData
		record Response 
			ValidationError : Response
			Submitted : Response
		end

		response : Response
	end

	record PartialUploadError
		step : string
		error : ModHubErrorCode
	end

	record UploadModData
		modId : ModId
		partialErrors : {PartialUploadError}
	end

	record UniquePendingRequestId
		abort : function(UniquePendingRequestId)
	end

	record AsyncResult<T>
		isSuccess : function(AsyncResult<T>) : boolean
		getData :function(AsyncResult<T>) : T
		getError : function(AsyncResult<T>) :  ModHubErrorCode
	end

	type BackendId = integer
	
	record ModBrowserDisplayData
		record Entry
			backendId : BackendId
			modInfo : ModInfo
			modId : Mod.ModId
		end

		entries : {Entry} -- nil: is currently loading, empty: no results
		error : Modhub.ModHubErrorCode -- nil: no error, otherwise error should be shown to user
		currentPage : integer
		numPages : integer
		displayPerPage : integer
		totalResults : integer
		appendResults : boolean
		searchString : string
		sortType : Modhub.SortType
		hasNoSortTag : boolean
		filterTags : { string }
		excludeTags : { string }
	end

	record ModBrowserDataProvider
		new : function(BackendId, integer) : ModBrowserDataProvider
		newForSelector : function(integer, function(mod1 : Mod.ModId, mod2 : Mod.ModId), gameModDescs : {Mod.GameModDesc}) : ModBrowserDataProvider

		suspend : function(ModBrowserDataProvider)
		resume : function(ModBrowserDataProvider)
		getDisplayData : function(ModBrowserDataProvider) : ModBrowserDisplayData
		setLoadPage : function(ModBrowserDataProvider, integer)
		setNextContinuousPage : function(ModBrowserDataProvider)
		setCurrentPage : function(ModBrowserDataProvider, integer)
		setSearchString : function(ModBrowserDataProvider, string)
		setSearchUserId : function(ModBrowserDataProvider, UserId)
		setNextPage : function(ModBrowserDataProvider)
		setPreviousPage : function(ModBrowserDataProvider)
		refreshCurrentPage : function(ModBrowserDataProvider, boolean)
		getSortType : function(ModBrowserDataProvider) : Modhub.SortType
		getTagToggled : function(ModBrowserDataProvider, string) : boolean
		setSortType : function(ModBrowserDataProvider, SortType)
		setNextSortType : function(ModBrowserDataProvider)
		toggleTag : function(ModBrowserDataProvider, string)
		resetFilters : function(ModBrowserDataProvider)

		getSortAndFilterOptions : function(ModBrowserDataProvider) : Modhub.SortAndFilterOptions
	end

	record StagingModData
		record State
			Sync : State
			Ready : State
			Publishing : State
			HasResult : State
		end
		
		equals : function(StagingModData, StagingModData) : boolean

		localModhubDetails : Modhub.ModDetailsData

		state : State
		modhubId : Modhub.ModId
		modhubDetails : Modhub.ModDetailsData

		publishResult : AsyncResult<UploadModData>
	end

	--- State of the validation of a single staging mod, see ModPublishHelper.validate
	record ValidationData
		equals : function(ValidationData, ValidationData) : boolean

		--- Whether a validation started with ModPublishHelper.validate is still running
		validating : boolean
		--- Progress of the running validation, in [0, 1]
		progress : number
		--- Name of the task the running validation is currently busy with
		task : string
		--- Result of the last completed validation, nil if the mod wasn't validated yet
		result : Modhub.ModValidatorResult
	end

	record PublishSettings
		new : function() : PublishSettings
		new : function(PublishSettings) : PublishSettings

		changeLog : string
		updateMetadata : boolean
		setPublic : boolean
		--- Shared savegames are uploaded as staged, they are not validated or cooked
		isSavegame : boolean
		
		--- The user confirmed the issues the last validation reported, so publishing only aborts if the
		--- validation it runs comes back worse than those
		issuesConfirmed : boolean

		--- Free-form extra metadata merged into the upload's metadata (eg. mapSize for savegames)
		additionalMetadata : {string:any}
	end

	record ModPublishHelper
		new : function(BackendId) : ModPublishHelper

		--- Checks if there are any mods in the staging area
		--- @param publishHelper the publish helper
		hasAnyStagingMods : function(publishHelper : ModPublishHelper) : boolean

		--- Checks if the publish helper can be refreshed
		--- @param publishHelper the publish helper
		canRefresh : function(publishHelper : ModPublishHelper) : boolean
		--- Refreshes the mod helper, this is an async operation
		--- @param publishHelper the publish helper
		--- @return the result of the async operation, including the number of mods that were refreshed
		refresh : function(publishHelper : ModPublishHelper) : AsyncResult<RefreshData>
		--- Polls the pending validations, has to be called regularly while a validation is running
		--- @param publishHelper the publish helper
		update : function(publishHelper : ModPublishHelper)

		--- Validates a staging mod, this is an async operation. Aborts a validation that is already
		--- running for that mod. The result ends up in ValidationData.result once
		--- ValidationData.validating turned false again. Does not cook, only publish does.
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		validate : function(publishHelper : ModPublishHelper, modId : Modhub.ModId)
		--- Aborts a running validation
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		abortValidation : function(publishHelper : ModPublishHelper, modId : Modhub.ModId)
		--- Returns the validation state of a staging mod
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		getValidationData : function(publishHelper : ModPublishHelper, modId : Modhub.ModId) : ValidationData
		
		--- Checks if a specific mod is in the staging area
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		hasStagingMod : function(publishHelper : ModPublishHelper, modId : Modhub.ModId) : boolean
		--- Returns the staging mod data for a specific mod
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		getStagingModData: function(publishHelper : ModPublishHelper, modId : Modhub.ModId) : StagingModData
		--- Sets the mod details data
		--- @param publishHelper the publish helper
		--- @param modId the local mod id of the mod to update
		--- @param modDetailsData the mod details data
		setModDetails : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, modDetailsData : Modhub.ModDetailsData)
		--- Update the local modId of a mod to the remote (eg. mod.io) mod.io of the mod when publishing
		--- @param publishHelper the publish helper
		--- @param localModId the local mod id of the mod to update
		--- @param remoteModId the remote mod id to set
		setRemoteModId : function(publishHelper : ModPublishHelper, localModId : Modhub.ModId, remoteModId : Modhub.ModId)
		--- Publishes a mod (eg. on mod.io), this is an async call.
		--- Validates and cooks the mod once more first and uploads the cooked folders, unless the settings
		--- mark it as a savegame; see PublishSettings.isSavegame and PublishSettings.issuesConfirmed
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param publishSettings the publish settings
		--- @return the result of the async call, also contains the remote mod id
		publish: function(publishHelper : ModPublishHelper, modId : Modhub.ModId, publishSettings : PublishSettings) : AsyncResult<UploadModData>
		--- Aborts the publication of a mod
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		abortPublish: function(publishHelper : ModPublishHelper, modId : Modhub.ModId) : UniquePendingRequestId

		--- Adds a list of image to the mod gallery
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param image image file to add to the gallery
		addLogoImage : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, image : string)
		--- Removes the logo image
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param index the index of the image in the gallery to remove
		removeLogoImage : function(publishHelper : ModPublishHelper, modId : Modhub.ModId)

		--- Adds a list of image to the mod gallery
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param images the list of image file to add to the gallery
		addGalleryImages : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, images : {string})
		--- Removes an image from the mod gallery
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param index the index of the image in the gallery to remove
		removeGalleryImage : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, index : integer)
		--- Moves an image position in the mod gallery
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param fromIndex the index in the mod gallery of the image to move
		--- @param toIndex the new position of the image in the mod gallery
		moveGalleryImage : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, fromIndex : integer, toIndex : integer)

		--- Set a function called after a mod has been successfuly published
		--- @param publishHelper the publish helper
		--- @param modId the mod id
		--- @param publishFn a function called after the mod has been published, the function gives the remote mod id as parameter
		setPostPublishFn : function(publishHelper : ModPublishHelper, modId : Modhub.ModId, publishFn : function(Modhub.ModId))

		--- Opens the mod folder
		--- @param publishHelper the publish helper
		--- @param modId the modId
		openFolder : function(publishHelper : ModPublishHelper, modId : Modhub.ModId)

		--- Gets the list of sorting and filtering options (eg. tags)
		--- @param publishHelper the publish helper
		--- @return an object containing the list of sort and filter options
		getSortAndFilterOptions : function(publishHelper : ModPublishHelper) : Modhub.SortAndFilterOptions
	end
end

recordDef = false
