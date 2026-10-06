recordDef = true

--- Contains generic util functions that are not associated with a specific game instance.
--- All functions in this namespace can be called from anywhere.

--- main util interface
--- @category main
global record ApiUtil
	--- Obtains the total used memory by this lua state.
	--- @return int used memory in kb
	getLuaUsedMemory : function() : integer

	--- Formats a decimal value to percent.
	--- @param percentage the number to format
	--- @return string with formatted percentage
	toStringPercent : function(percentage : number) : string

	--- Formats a decimal value to percent.
	--- @param percentage the number to format
	--- @param decimals wished precision
	--- @return string with formatted percentage
	toStringPercentPrecision : function(percentage : number, decimals : integer) : string

	--- Formats a timestamp with appropriate localization.
	--- @param timestamp the timestamp to format
	--- @return string with formatted time
	formatTimestamp : function(timestamp : integer) : string

	--- Formats a timestamp with appropriate localization and according date format.
	--- @param timestamp long number The timestamp
	--- @param dateFormat DateFormat format The format to use for formatting
	--- @return string with formatted timestamp
	formatPosixTimestamp : function(timestamp : integer, dateFormat : DateFormat) : string

	--- Defaults to km/h unless the user selected another system of measurement.
	--- @param speed speed in meter per second
	--- @return string with formatted speed
	formatSpeed : function(speed : number) : string

	--- Formats an altitude with the correct locale and unit of measurement.
	--- Defaults to meters unless the user selected another system of measurement.
	--- @param meters length distance in meters
	--- @param decimals number of decimals (default: 1 decimal for numbers < 10, otherwise 0)
	--- @return string with formatted altitude
	formatAltitude : function(meters : number, decimals? : integer) : string

	--- Formats a distance with the correct locale and unit of measurement.
	--- Defaults to meters unless the user selected another system of measurement.
	--- @param meters length distance in meters
	--- @param decimals number of decimals (default: 1 decimal for numbers < 10, otherwise 0)
	--- @param forceSmallUnit : boolean If true, use m or ft even for big numbers (default: false)
	--- @return string with formatted distance
	formatLength : function(meters : number, decimals? : integer, forceSmallUnit? : boolean) : string

	--- Formats a money amount with the correct locale and currency.
	--- @param money amount of money or nil if money does not matter (aka is infinite)
	--- @return string with formatted amount of money
	formatMoney : function(money : integer) : string

	--- Formats a money amount with the opposite locale and currency (if current format is set to full it shows short and vice versa)
	--- @param money amount of money or nil if money does not matter (aka is infinite)
	--- @return string with formatted amount of money
	formatMoneyAlt : function(money : integer) : string

	--- Formats a money amount with the correct locale.
	--- @param money amount of money or nil if money does not matter (aka is infinite)
	--- @return string with formatted amount of money
	formatMoneyNumber : function(money : integer) : string

	--- Formats a number as weight with the correct locale.
	--- @param weight the number in metric tons
	--- @return string with formatted weight
	formatWeight : function(weight : number) : string

	--- Formats a number as power with the correct locale.
	--- @param power the number in kW
	--- @return string with formatted power
	formatPower : function(power : number) : string

	--- Converts Decibel To Power
	--- @param decibel the number to convert
	--- @return number with converted power
	decibelToPower : function(decibel : number) : number

	--- Converts Power To Decibel
	--- @param power the number to convert
	--- @return number with converted decibel
	powerToDecibel : function(power : number) : number

	--- Formats a number as force with the correct locale.
	--- @param force the number in kN
	--- @return string with formatted force
	formatForce : function(force : number) : string

	--- Formats a number as memory with the correct locale.
	--- @param memory the number in bytes
	--- @return string with formatted memory
	formatMemory : function(memory : integer) : string

	--- Obtains month duration in the game regarding the current game speed's millis per day.
	--- @param currentMillisPerDay number of milliseconds in a day
	--- @return integer with the current game ticks per month
	getMonthDuration : function(currentMillisPerDay : integer) : integer

	--- Obtains year duration in the game regarding the current game speed's millis per day.
	--- @param currentMillisPerDay number of milliseconds in a day
	--- @return integer with the current game ticks per year
	getYearDuration : function(currentMillisPerDay : integer) : integer

	--- Obtains the default day duration in the game.
	--- @return integer with the default game ticks per day
	getDefaultDayDuration : function() : integer

	--- Obtains the default month duration in the game.
	--- @return integer with the default game ticks per month
	getDefaultMonthDuration : function() : integer

	--- Obtains the default year duration in the game.
	--- @return integer with the default game ticks per year
	getDefaultYearDuration : function() : integer
	
	--- Formats number of seconds into string
	--- @param seconds the number of seconds to format
	--- @return string with formatted time
	formatSeconds : function(seconds : integer) : string

	--- Formats number of seconds into string
	--- @param seconds the number of seconds to format
	--- @param hideZeroSeconds omit the "0 s" suffix (optional, default: false)
	--- @return string with formatted time
	formatMinutesSeconds : function(seconds : integer, hideZeroSeconds? : boolean) : string

	--- Formats number of days into string
	--- @param days the number of days to format
	--- @return string with formatted time
	formatDays : function(days : integer) : string
	
	--- Formats given gameTime as real time string
	--- @param gameTime the gameTime to format
	--- @return string with formatted date
	formatGameTime : function(gameTime : integer) : string

	--- Formats given date with the correct locale.
	--- @param date the date to format
	--- @param dateFormat the format to use for formatting
	--- @return string with formatted date
	formatDate : function(date : Date, dateFormat : DateFormat) : string

	--- Get the local real time of the user machine
	--- @return the time
	getLocalTime : function() : integer

	--- Formats given time
	--- @param time the time to format
	--- @return string with formatted time
	formatTime : function(time : integer) : string

	--- Formats a number with K/M/B suffix.
	--- @param number the number to format
	--- @return string with formatted number
	formatKMB : function(number : number) : string

	--- Splits string into list of sentences
	--- @param sentences the string containing sentences
	--- @return list of sentences
	splitSentences : function(sentences : string) : {string}

	--- Generate n colors, equally distributed over the "rainbow"
	--- @param number number of wished colors
	--- @param alpha alpha, if not set, alpha is set to 1 (optional)
	--- @return vector or Vec4f colors
	getRainbowColors : function(number : integer, alpha? : number) : {Vec4f}

	--- Get seconds since application start. Only available in GUI thread.
	--- @return duration since application started
	getApplicationTime : function() : number -- 

	--- Returns the current input mode. Only available in GUI thread.
	--- @return the input mode
	getInputMode : function() : InputMode -- Get current input mode. Only available in GUI thread.

	--- Returns the current gamepad type.
	--- @return the gamepad type
	getGamepadType : function() : GamepadType -- Get current gamepad type.

	--- Returns if a controller is connected. Only available in GUI thread.
	--- @return if a controller is connected
	isControllerConnected : function() : boolean

	--- Returns if a keyboard is connected. Only available in GUI thread.
	--- @return if a keyboard is connected
	isKeyboardConnected : function() : boolean

	--- Returns if a mouse is connected. Only available in GUI thread.
	--- @return if a mouse is connected
	isMouseConnected : function() : boolean

	--- Returns the key sequence associated to the command (eg. `api.util.getKeyName("constructOptPrecise1")`)
	--- See the ''settings_keys_v3.lua'' file in the userdata local folder for a list of all available key commands.
	--- @param keyCommand the command to which the key sequence is associated.
	--- @return the key sequence associated with the given key command
	getKeyName : function(keyCommand : string) : string -- Get key combos for this input action. Only available in GUI thread.

	--- Returns the build version
	--- @return the build version
	getBuildVersion : function() : string

	--- Returns the build version string
	--- @return the build version
	getBuildVersionString : function() : string

	--- Returns whether build is development build
	--- @return true if build is development build
	isBuildTypeTesting : function() : boolean

	--- Returns whether build is release build
	--- @return true if build is release build
	isBuildTypeRelease : function() : boolean
	
	--- Returns whether the game is running on a console
	--- @return true if the game is running on a console
	isConsoleMode : function() : boolean

	getModMemoryLimitMB : function() : integer

	--- Returns whether build is of certain platform
	--- @param platform the platform to check
	--- @return true if build is of platform
	isPlatform : function(platform: Platform) : boolean

	--- Transforms string to platform
	--- @param platform the platform string
	--- @return the plafrom enum value
	string2Platform : function(platform : string) : Platform

	--- Returns whether build is of certain vendor
	--- @param vendor the vendor
	--- @return bool true if build is from the vendor
	isVendor : function(vendor : Vendor) : boolean

	--- Transforms string to vendor
	--- @param vendor the vendor string
	--- @return the value from the vendor enum
	string2Vendor : function(vendor : string) : Vendor

	--- Saves the game settings
	saveAppConfig : function()

	--- Returns the game settings
	--- @return the game settings
	getAppConfig : function() : AppConfig

	--- Returns the platform device specs
	--- @return platform device spec
	getPlaformDeviceSpec : function() : PlatformDeviceSpec

	--- Sets the game settings (does not save)
	--- @param appConfig game settings to set
	--- @param previewAudio if should play an audio preview for audio settings that changed
	setAppConfig : function(appConfig : AppConfig, previewAudio : boolean)

	--- Set the music volume for the game
	--- @param volume the music volume between 0 and 1
	setMusicVolume : function(volume : number)

	--- Returns the current language settings
	--- @return table language settings
	getLanguage : function() : table

	--- Returns some memory statistics.
	getMemoryStats : function() : table

	--- Sets whether the game can be shared or not
	setAllowSharing : function(allowSharing : boolean)
	
	record lang
		--- Tests if a string is equal to another
		--- @param a a string to test
		--- @param b another string to test
		--- @return -1 if the first string has a lower value, 0 if both strings are equal, 1 if the first string has a greater
		compareStrings : function(a : string, b : string) : integer

		--- Tests if a string contains another string
		--- @param text string to test against
		--- @param test string to test for
		--- @return true if the first string contains the second
		stringContains : function(text : string, test : string) : boolean

		--- Formats an integer with the correct locale.
		--- @param number number to format 
		--- @return string with formatted number
		formatInt : function(number : integer) : string

		--- Formats an integer with the correct locale.
		--- @param number number to format 
		--- @param integer width to format 
		--- @return string with formatted number
		formatIntWithWidth : function(number : integer, width : integer) : string

		--- Formats a decimal number with the correct locale and given number of digits.
		--- @param number number to format 
		--- @param decimals number of decimals to display
		--- @return string with formatted number
		formatNumber : function(number : number, decimals : integer) : string
	end

	record UtilDebug
		record Draw
			--- Clear all debug draw points of the given layer.
			--- @param layers the layer mask to clear
			clear : function(layers : integer)

			--- Draw a point at the given position with the given color in the given layer.
			--- @param pos the world position of the point
			--- @param color the color of the point
			--- @param layers the layer mask to draw on
			point : function(pos : Vec3f, color : Vec3f, layers : integer)
		end
		draw : Draw
	end
end

recordDef = false
