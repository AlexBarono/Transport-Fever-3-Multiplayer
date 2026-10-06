recordDef = true

--- Contains all api definitions for the modhub interface.

--- Main Modhub interface
--- @category main
global record ModhubApi
	getBackendIDs : function() : {Modhub.BackendId}
	getBackendIdForSource : function(string) : Modhub.BackendId
	
	getUserInfo : function(Modhub.BackendId) : Modhub.UserInfo
	getDescription : function(Modhub.BackendId) : Modhub.Description
	getCapabilities : function(Modhub.BackendId) : Modhub.Capabilities
	getSortAndFilterOptions : function(Modhub.BackendId) : Modhub.SortAndFilterOptions

	requestEmailAuthCodeAsync : function (Modhub.BackendId, Modhub.EmailAuthCodeRequest, function(Modhub.AsyncResult<Modhub.EmailAuthCodeData>)) : Modhub.UniquePendingRequestId
	authenticateUserEmailAsync : function (Modhub.BackendId, Modhub.AuthenticateUserEmailRequest, function(Modhub.AsyncResult<Modhub.AuthenticateUserEmailData>)) : Modhub.UniquePendingRequestId
	getTermsOfUseAsync : function (Modhub.BackendId,  Modhub.TermsOfUseRequest, function(Modhub.AsyncResult<Modhub.TermsOfUseData>)) : Modhub.UniquePendingRequestId
	authenticateUserExternalAsync : function (Modhub.BackendId, Modhub.AuthenticateUserExternalRequest, function(Modhub.AsyncResult<Modhub.AuthenticateUserExternalData>)) : Modhub.UniquePendingRequestId
	logoutAsync : function (Modhub.BackendId, function(Modhub.AsyncResult<Modhub.LogoutData>)) : Modhub.UniquePendingRequestId	
	listModsAsync : function (Modhub.BackendId, Modhub.ListModsRequest, function(Modhub.AsyncResult<Modhub.ListModsData>)) : Modhub.UniquePendingRequestId
	getModDetailsAsync : function (Modhub.BackendId, Modhub.GetModDetailsRequest, function(Modhub.AsyncResult<Modhub.ModDetailsData>)) : Modhub.UniquePendingRequestId
	getModMediaAsync : function (Modhub.BackendId, Modhub.GetModMediaRequest, function(Modhub.AsyncResult<Modhub.ModMediaData>)) : Modhub.UniquePendingRequestId
	getModRatingAsync : function (Modhub.BackendId, Modhub.GetModRatingRequest, function(Modhub.AsyncResult<Modhub.ModRatingData>)) : Modhub.UniquePendingRequestId
	subscribeModAsync : function (Modhub.BackendId, Modhub.SubscribeModRequest, function(Modhub.AsyncResult<Modhub.SubscriptionData>)) : Modhub.UniquePendingRequestId
	unsubscribeModAsync : function (Modhub.BackendId, Modhub.UnsubscribeModRequest, function(Modhub.AsyncResult<Modhub.SubscriptionData>)) : Modhub.UniquePendingRequestId
	forceUninstallModAsync : function (Modhub.BackendId, Modhub.ForceUninstallModRequest, function(Modhub.AsyncResult<Modhub.ForceUninstallModData>)) : Modhub.UniquePendingRequestId
	refreshAsync : function (Modhub.BackendId, function(Modhub.AsyncResult<Modhub.RefreshData>)) : Modhub.UniquePendingRequestId
	specialRefreshModAsync : function (Modhub.BackendId, Modhub.SpecialRefreshModRequest, function(Modhub.AsyncResult<Modhub.SpecialRefreshModData>)) : Modhub.UniquePendingRequestId
	restartModBackendAsync : function (Modhub.BackendId, function(Modhub.AsyncResult<Modhub.RestartModBackendData>)) : Modhub.UniquePendingRequestId
	submitModRatingAsync : function (Modhub.BackendId, Modhub.SubmitModRatingRequest, function(Modhub.AsyncResult<Modhub.SubmitModRatingData>)) : Modhub.UniquePendingRequestId
	submitModReportAsync : function (Modhub.BackendId, Modhub.SubmitModReportRequest, function(Modhub.AsyncResult<Modhub.SubmitModReportData>)) : Modhub.UniquePendingRequestId

	setModManagementMode : function(Modhub.BackendId, Modhub.ModManagementMode)
	getModSubscriptionState : function(Modhub.BackendId, Modhub.ModId) : boolean
	getModInstallState : function(Modhub.BackendId, Modhub.ModId) : Modhub.InstallState
	getInstalledMods : function(Modhub.BackendId) : {Modhub.ModId}
	getModInstallInfo : function(Modhub.BackendId, Modhub.ModId) : Modhub.ModInstallInfo
	getModInfoForInstalledMod : function(Modhub.BackendId, Modhub.ModId) : Modhub.ModInfo
	getModInfoForSubscribedMod : function(Modhub.BackendId, Modhub.ModId) : Modhub.ModInfo
	getStorageInfo : function(Modhub.BackendId) : Modhub.StorageInfo
	getModManagementState : function(Modhub.BackendId) : Modhub.ModManagementState
	isInitialized : function(Modhub.BackendId) : boolean
	openExternalModPage : function(Modhub.BackendId, Modhub.ModId)

	shouldRetryInstall : function(Modhub.BackendId) : boolean

	getModHubModIdForModId : function(Mod.ModId) : Modhub.ModId

	getModhubModIdForSavegame : function(Modhub.BackendId, SaveGameId) : Modhub.ModId
	setModhubModIdForSavegame : function(Modhub.BackendId, SaveGameId, Modhub.ModId)

	--- @return the staged mod's local id, and any extra metadata computed while staging.
	stageSavegame : function(SaveGameId, boolean, Modhub.BackendId, Modhub.ModId) : {Modhub.ModId, {string:any}}

	openPath : function(path : string)
	exportValidatorResult : function(result : Modhub.ModValidatorResult) : string
end

recordDef = false
