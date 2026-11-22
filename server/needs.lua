-- Needs state: one float per need and per loaded character, the decay loop and the starving loop.
-- The integer value players see is opx_core metadata; it is written only when it changes (each SetMetadata
-- sends the whole metadata table to the client).

Needs = {}

Needs.RESOURCE = GetCurrentResourceName()
Needs.KEYS = { 'hunger', 'thirst' } -- logical need names (Config.keys maps them to metadata keys)
Needs.players = {}                   -- [source] = { citizenId, isNew, hunger = float, thirst = float }

local CORE = 'opx_core'
local lastCall = {} -- [source] = GetGameTimer() of his last accepted request

-- Helpers ----------------------------------------------------------------------------------------

function Needs.Log(text) print(('[opx_needs] %s'):format(text)) end

-- A player id from anything (positive integer within uint32), or nil. Natives abort on anything else.
function Needs.toSource(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end

-- A finite number, or nil (refuses NaN and inf: json.encode of them aborts the server).
function Needs.finite(value)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

local MAX = math.max(1, math.tointeger(Needs.finite(Config.max) and math.floor(Config.max)) or 100)
Needs.MAX = MAX

-- A float clamped to 0..max.
function Needs.clamp(value)
	local n = Needs.finite(value) or 0
	return math.max(0, math.min(MAX, n))
end

-- The integer shown for a float: rounded up, so the gauge reads 0 only once the need is really empty.
function Needs.display(value)
	return math.tointeger(math.ceil(Needs.clamp(value))) or 0
end

-- A logical need name ('hunger' | 'thirst'), or nil.
function Needs.key(value)
	if value == 'hunger' or value == 'thirst' then return value end
	return nil
end

-- Calls an opx_core export: a, b | nil, 'core_unavailable'.
function Needs.core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil, 'core_unavailable' end
	return a, b
end

-- The resource filling an opx_core provider slot, or nil.
function Needs.provider(slot)
	local name = Needs.core('GetProvider', slot)
	return type(name) == 'string' and name or nil
end

-- Rate limit: false when the player asked again too soon.
function Needs.allow(source)
	local now = GetGameTimer()
	local last = lastCall[source]
	if last and now - last < (Config.rateLimitMs or 500) then return false end
	lastCall[source] = now
	return true
end

-- A locale key + params for the player's client, which translates it and shows it through opx_core Notify.
function Needs.notify(source, key, kind, params)
	pcall(TriggerClientEvent, 'opx_needs:notify', source, key, kind or 'info', params or {})
end

-- Down (medical provider) or dead. `medical` = the provider name read once by the caller (may be nil).
function Needs.isDown(source, medical)
	if Open77.players.isDead(source) == true then return true end
	if medical then
		local ok, down = pcall(Open77.exports.callSync, medical, 'IsDown', source)
		if ok and down == true then return true end
	end
	return false
end

-- State -------------------------------------------------------------------------------------------

-- Integer of a metadata value, clamped; missing -> max (a fresh character is full).
local function fromMetadata(value)
	if value == nil then return MAX end
	return Needs.display(value)
end

-- Starts tracking a loaded character from his PlayerData (opx:playerLoaded, adoption at start).
function Needs.load(source, data)
	if type(data) ~= 'table' or type(data.citizenId) ~= 'string' then return end
	local metadata = type(data.metadata) == 'table' and data.metadata or {}
	local st = { citizenId = data.citizenId, isNew = data.isNew == true }
	for _, key in ipairs(Needs.KEYS) do st[key] = fromMetadata(metadata[Config.keys[key]]) end
	Needs.players[source] = st
end

function Needs.forget(source)
	Needs.players[source] = nil
	lastCall[source] = nil
	Needs.cancelConsume(source)
end

-- The state of a loaded character, re-synced with opx_core's metadata (another resource or a staff tool may
-- have changed it). nil when no character is loaded (the entry is dropped) or opx_core does not answer.
function Needs.get(source)
	local st = Needs.players[source]
	local data, reason = Needs.core('GetPlayer', source)
	if reason == 'core_unavailable' then return nil end
	if type(data) ~= 'table' or type(data.citizenId) ~= 'string' then
		if st then Needs.forget(source) end
		return nil
	end
	if not st or st.citizenId ~= data.citizenId then
		Needs.load(source, data)
		return Needs.players[source]
	end
	st.isNew = data.isNew == true
	local metadata = type(data.metadata) == 'table' and data.metadata or {}
	for _, key in ipairs(Needs.KEYS) do
		local shown = fromMetadata(metadata[Config.keys[key]])
		if shown ~= Needs.display(st[key]) then st[key] = shown end
	end
	return st
end

-- Sets one need (float, clamped) and writes the metadata when the shown integer changed. Notifies the
-- thresholds crossed downward and raises opx:needs:starving when it reaches 0. Returns the shown integer.
function Needs.write(source, st, key, value)
	local before = Needs.display(st[key])
	st[key] = Needs.clamp(value)
	local after = Needs.display(st[key])
	if after == before then return after end

	local ok, why = Needs.core('SetMetadata', source, Config.keys[key], after)
	if ok ~= true then Needs.Log(('metadata %s of %d not written: %s'):format(key, source, tostring(why))) end

	if after < before then
		if after == 0 then
			Needs.notify(source, 'starving_' .. key, 'error')
			TriggerEvent('opx:needs:starving', source, key)
		else
			local crossed = nil
			for _, limit in ipairs(type(Config.warnAt) == 'table' and Config.warnAt or {}) do
				limit = Needs.finite(limit)
				if limit and after <= limit and before > limit and (not crossed or limit < crossed) then crossed = limit end
			end
			if crossed then Needs.notify(source, 'low_' .. key, 'warning', { value = after }) end
		end
	end
	return after
end

-- Loops ---------------------------------------------------------------------------------------------

local function positiveSeconds(value, default, min)
	local n = Needs.finite(value) or default
	return math.max(min, n)
end

-- Decay: every tickSeconds, each loaded character (not in the creator, not down when pauseWhenDown) loses
-- Config.decay points of each need.
CreateThread(function()
	while true do
		Wait(math.floor(positiveSeconds(Config.tickSeconds, 60, 5) * 1000))
		local medical = Config.pauseWhenDown ~= false and Needs.provider('medical') or nil
		local list = {}
		for source in pairs(Needs.players) do list[#list + 1] = source end
		for _, source in ipairs(list) do
			local st = Needs.get(source)
			if st and not st.isNew and not (Config.pauseWhenDown ~= false and Needs.isDown(source, medical)) then
				for _, key in ipairs(Needs.KEYS) do
					local loss = Needs.finite(type(Config.decay) == 'table' and Config.decay[key]) or 0
					if loss > 0 then Needs.write(source, st, key, st[key] - loss) end
				end
			end
		end
	end
end)

-- Starving: every starve.intervalSeconds, a character with a need at 0 takes damage (never while down).
CreateThread(function()
	local starve = type(Config.starve) == 'table' and Config.starve or {}
	local damage = Needs.finite(starve.damage) or 0
	local floor = math.max(0, Needs.finite(starve.minHealth) or 0)
	local warned = false
	while true do
		Wait(math.floor(positiveSeconds(starve.intervalSeconds, 30, 5) * 1000))
		if damage > 0 then
			local medical = Needs.provider('medical')
			local list = {}
			for source, st in pairs(Needs.players) do
				if not st.isNew and (Needs.display(st.hunger) == 0 or Needs.display(st.thirst) == 0) then
					list[#list + 1] = source
				end
			end
			for _, source in ipairs(list) do
				if Needs.players[source] and not Needs.isDown(source, medical) then
					local amount = damage
					if starve.lethal == false then
						local hp = Open77.stats.getHealth(source)
						local value = type(hp) == 'table' and Needs.finite(hp.value) or nil
						amount = value and math.min(damage, value - floor) or 0
					end
					if amount > 0 then
						local ok, why = Open77.players.damage(source, amount, { cause = 'environment' })
						if ok ~= true and not warned then
							warned = true
							Needs.Log(('starving damage refused: %s'):format(tostring(why)))
						end
					end
				end
			end
		end
	end
end)
