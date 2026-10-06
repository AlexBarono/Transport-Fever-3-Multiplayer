recordDef = true

require "api.util"
require "api.modhub"

global record api
	res : Res
	gui : Gui
	engine : Engine
	type : Type
	util : ApiUtil
	cmd : Cmd
	modhub : ModhubApi
end

global app : App = nil
global loaderHelper : LoaderHelper = nil

recordDef = false
