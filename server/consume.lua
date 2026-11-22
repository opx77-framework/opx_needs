-- Eating and drinking: the food and drink items of Config.consumables, owned by opx_needs and registered on the
-- inventory provider (RegisterItem + RegisterUsable).
-- The inventory calls the export UseConsumable asynchronously; it asks the player's client to run the timed
-- action (progress bar + animation), waits for the answer and accepts it only after the full duration.

local pending = {} -- [source] = { token, item, citizenId, startedAt, answer = nil|boolean, answeredAt }
local counter = 0

-- The definition of a consumable item, normalised, or nil.
local function definition(item)
	local def = type(item) == 'string' and type(Config.consumables) == 'table' and Config.consumables[item]
	if type(def) ~= 'table' then return nil end
	local hunger = Needs.finite(def.hunger) or 0
	local thirst = Needs.finite(def.thirst) or 0
	if hunger == 0 and thirst == 0 then return nil end
	return {
		hunger = hunger,
		thirst = thirst,
		seconds = math.max(1, math.min(60, Needs.finite(def.seconds) or 4)),
		animation = type(def.animation) == 'string' and def.animation ~= '' and def.animation or nil,
		still = def.still == true,
	}
end

-- A label / description as the inventory accepts it: a non-empty string or { en = ..., fr = ... } (strings only).
local function text(value)
	if type(value) == 'string' then return value ~= '' and value or nil end
	if type(value) ~= 'table' then return nil end
	local out, any = {}, false
	for lang, str in pairs(value) do
		if type(lang) == 'string' and type(str) == 'string' and str ~= '' then
			out[lang] = str
			any = true
		end
	end
	return any and out or nil
end

-- The RegisterItem definition of a consumable (only plain strings, integers and booleans), or nil, reason.
local function itemDefinition(item)
	local def = Config.consumables[item]
	local label = text(def.label)
	if not label then return nil, 'no label' end
	local weightG = math.tointeger(def.weightG)
	if not weightG or weightG < 0 then return nil, 'weightG is not an integer >= 0' end
	return { label = label, description = text(def.description), weightG = weightG, usable = true }
end

-- Registers every consumable on the inventory provider: the item itself (RegisterItem, opx_needs owns food and
-- drink) then its use (RegisterUsable). Both record the calling resource and VM generation, so a reload of
-- opx_needs registers the new VM; the inventory keeps the items in its catalogue while opx_needs is stopped.
function Needs.registerItems()
	local inventory = Needs.provider('inventory')
	if not inventory or type(Config.consumables) ~= 'table' then return end
	for item in pairs(Config.consumables) do
		local itemDef, invalid = nil, nil
		if type(item) ~= 'string' or not definition(item) then
			invalid = 'no hunger / thirst effect'
		else
			itemDef, invalid = itemDefinition(item)
		end
		if not itemDef then
			Needs.Log(('consumable %s ignored: %s'):format(tostring(item), tostring(invalid)))
		else
			local called, ok, why = pcall(Open77.exports.callSync, inventory, 'RegisterItem', item, itemDef)
			if not called then
				Needs.Log(('RegisterItem on %s failed: %s'):format(inventory, tostring(ok)))
				return
			end
			if ok ~= true then
				Needs.Log(('item %s not registered on %s: %s'):format(item, inventory, tostring(why)))
			else
				called, ok, why = pcall(Open77.exports.callSync, inventory, 'RegisterUsable', item, 'UseConsumable')
				if not called then
					Needs.Log(('RegisterUsable on %s failed: %s'):format(inventory, tostring(ok)))
					return
				end
				if ok ~= true then
					Needs.Log(('usable %s not registered on %s: %s'):format(item, inventory, tostring(why)))
				end
			end
		end
	end
end

-- Drops the pending action of a player (disconnect, unload); the waiting export then answers false.
function Needs.cancelConsume(source)
	pending[source] = nil
end

-- The client's answer: opx_needs:consumed (token, ok).
function Needs.consumed(source, token, ok)
	local entry = pending[source]
	if not entry or entry.answer ~= nil then return end
	if type(token) ~= 'number' or math.tointeger(token) ~= entry.token then return end
	entry.answer = ok == true
	entry.answeredAt = GetGameTimer()
end

-- Export body (may wait). true = the inventory removes one item; false = nothing consumed.
function Needs.useConsumable(source, item)
	source = Needs.toSource(source)
	if not source then return false end
	local def = definition(item)
	if not def then return false end
	local st = Needs.get(source)
	if not st or st.isNew then return false end
	if pending[source] then
		Needs.notify(source, 'busy', 'error')
		return false
	end
	if Open77.players.isDead(source) == true then return false end

	counter = counter + 1
	if counter > 2147483647 then counter = 1 end
	local entry = { token = counter, item = item, citizenId = st.citizenId, startedAt = GetGameTimer() }
	pending[source] = entry
	local sent = pcall(TriggerClientEvent, 'opx_needs:consume', source, entry.token, {
		item = item, seconds = def.seconds, animation = def.animation, still = def.still,
		kind = def.hunger > 0 and 'eat' or 'drink',
	})
	if not sent then
		pending[source] = nil
		return false
	end

	local deadline = entry.startedAt + (def.seconds + 5) * 1000
	while pending[source] == entry and entry.answer == nil and GetGameTimer() < deadline do Wait(100) end
	if pending[source] ~= entry then return false end -- disconnected, unloaded or replaced
	pending[source] = nil

	if entry.answer ~= true then return false end
	if entry.answeredAt - entry.startedAt < def.seconds * 1000 - 500 then return false end
	if Open77.players.isDead(source) == true then return false end
	st = Needs.get(source)
	if not st or st.citizenId ~= entry.citizenId then return false end

	if def.hunger ~= 0 then Needs.write(source, st, 'hunger', st.hunger + def.hunger) end
	if def.thirst ~= 0 then Needs.write(source, st, 'thirst', st.thirst + def.thirst) end
	return true
end
