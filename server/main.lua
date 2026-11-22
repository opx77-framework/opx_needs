-- Entry: the client answer, exports for other resources, the staff command and the player lifecycle.

-- Client answer -----------------------------------------------------------------------------------

RegisterNetEvent('opx_needs:consumed', function(token, ok)
	local src = Needs.toSource(source)
	if not src or not Needs.allow(src) then return end
	Needs.consumed(src, token, ok)
end)

-- Exports -----------------------------------------------------------------------------------------

local api = {}

-- SYNC: { hunger, thirst } (integers 0..max) of a loaded character, or nil.
function api.GetNeeds(source)
	local src = Needs.toSource(source)
	local st = src and Needs.get(src)
	if not st then return nil end
	return { hunger = Needs.display(st.hunger), thirst = Needs.display(st.thirst) }
end

-- SYNC: sets one need (clamped to 0..max). true | false, reason.
function api.SetNeed(source, key, value)
	local src = Needs.toSource(source)
	if not src then return false, 'invalid_player' end
	key = Needs.key(key)
	if not key then return false, 'invalid_key' end
	value = Needs.finite(value)
	if not value then return false, 'invalid_value' end
	local st = Needs.get(src)
	if not st then return false, 'not_loaded' end
	Needs.write(src, st, key, value)
	return true
end

-- SYNC: adds delta (negative lowers) to one need, clamped. The new integer value | false, reason.
function api.AddNeed(source, key, delta)
	local src = Needs.toSource(source)
	if not src then return false, 'invalid_player' end
	key = Needs.key(key)
	if not key then return false, 'invalid_key' end
	delta = Needs.finite(delta)
	if not delta then return false, 'invalid_value' end
	local st = Needs.get(src)
	if not st then return false, 'not_loaded' end
	return Needs.write(src, st, key, st[key] + delta)
end

-- ASYNC (waits for the player's timed action): the usable-item handler registered on the inventory
-- provider. true = consume one item.
function api.UseConsumable(source, item, instanceId, meta)
	local ok, result = pcall(Needs.useConsumable, source, item)
	if not ok then
		Needs.Log(('UseConsumable raised: %s'):format(tostring(result)))
		return false
	end
	return result == true
end

for name, fn in pairs(api) do
	local ok, reason = exports(name, fn)
	if not ok then Needs.Log(('export %s not registered: %s'):format(name, tostring(reason))) end
end

-- Staff command -----------------------------------------------------------------------------------

-- English for the server console only; players read locales/<lang>.json.
local CONSOLE = {
	cmd_usage = 'Usage: {usage}',
	cmd_no_player = 'No loaded character for player {id}',
	cmd_done_hunger = 'Player {id}: hunger set to {value}',
	cmd_done_thirst = 'Player {id}: thirst set to {value}',
	cmd_failed = 'Failed: {error}',
}

local function reply(source, key, params, kind)
	if source == 0 then
		local text = (CONSOLE[key] or key):gsub('{([%w_]+)}', function(name)
			local value = params and params[name]
			return value ~= nil and tostring(value) or nil
		end)
		return print('[opx_needs] ' .. text)
	end
	Needs.notify(source, key, kind, params)
end

local function setNeedCommand(source, args, name)
	local usage = name .. ' <playerId|me> <hunger|thirst> <0-' .. Needs.MAX .. '>'
	if #args < 3 then return reply(source, 'cmd_usage', { usage = usage }, 'error') end
	local id = Needs.toSource(args[1])
	if not id and source ~= 0 and type(args[1]) == 'string' and args[1]:lower() == 'me' then id = source end
	if not id or not Needs.get(id) then return reply(source, 'cmd_no_player', { id = tostring(args[1]) }, 'error') end
	local key = Needs.key(type(args[2]) == 'string' and args[2]:lower() or nil)
	local value = Needs.finite(args[3])
	if not key or not value or value < 0 or value > Needs.MAX then
		return reply(source, 'cmd_usage', { usage = usage }, 'error')
	end
	local ok, why = api.SetNeed(id, key, value)
	if not ok then return reply(source, 'cmd_failed', { error = tostring(why) }, 'error') end
	reply(source, 'cmd_done_' .. key, { id = id, value = Needs.display(value) }, 'success')
end

local commandName = type(Config.commands) == 'table' and Config.commands.setneed
if type(commandName) == 'string' and commandName ~= '' then
	local ok, err = pcall(RegisterCommand, commandName, function(src, args)
		src = tonumber(src) or 0
		if src ~= 0 then
			src = Needs.toSource(src)
			if not src or not Needs.allow(src) then return end
		end
		local fine, failure = pcall(setNeedCommand, src, type(args) == 'table' and args or {}, commandName)
		if not fine then Needs.Log(('command %s raised: %s'):format(commandName, tostring(failure))) end
	end, true)
	if not ok then Needs.Log(('command %s not registered: %s'):format(commandName, tostring(err))) end
end

-- Command help shown in opx_chat when it runs (optional: nothing happens without it). Chat is not a
-- provider slot, so opx_chat is named here; its export only describes the command above.
local function publishCommandHelp()
	if type(commandName) ~= 'string' or commandName == '' or GetResourceState('opx_chat') ~= 'running' then return end
	pcall(Open77.exports.callSync, 'opx_chat', 'SetCommandHelp', commandName,
		{ en = 'Set the hunger or thirst of a player.', fr = "Régler la faim ou la soif d'un joueur." },
		{
			{ name = { en = 'playerId|me', fr = 'idJoueur|me' } },
			{ name = { en = 'hunger|thirst', fr = 'hunger|thirst' } },
			{ name = '0-' .. Needs.MAX },
		})
end

AddEventHandler('onResourceStart', function(name)
	if name == GetCurrentResourceName() or name == 'opx_chat' then publishCommandHelp() end
end)

-- Lifecycle ---------------------------------------------------------------------------------------

-- Characters already loaded when this resource (re)starts.
local function adoptLoaded()
	local list = Needs.core('GetPlayers')
	if type(list) ~= 'table' then return end
	for _, id in ipairs(list) do
		local src = Needs.toSource(id)
		if src and not Needs.players[src] then Needs.load(src, Needs.core('GetPlayer', src)) end
	end
end

AddEventHandler('opx:playerLoaded', function(playerId, data)
	local src = Needs.toSource(playerId)
	if src then
		Needs.cancelConsume(src)
		Needs.load(src, data)
	end
end)

AddEventHandler('opx:playerUnloaded', function(playerId)
	local src = Needs.toSource(playerId)
	if src then Needs.forget(src) end
end)

AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = Needs.toSource(playerId)
	if src then Needs.forget(src) end
end)

-- Back up after a revive or a hospital respawn (medical provider contract): both needs at least afterRevive.
AddEventHandler('opx:medical:up', function(playerId, reason)
	local src = Needs.toSource(playerId)
	if not src or reason == 'unloaded' then return end
	local floor = Needs.finite(Config.afterRevive) or 0
	if floor <= 0 then return end
	local st = Needs.get(src)
	if not st then return end
	for _, key in ipairs(Needs.KEYS) do
		if st[key] < floor then Needs.write(src, st, key, floor) end
	end
end)

-- Our own start (full start or hot reload): adopt the loaded characters, register the items and usables. The export
-- calls run from a thread (not at file scope); the wait lets the other resources' exports settle.
CreateThread(function()
	Wait(1000)
	adoptLoaded()
	Needs.registerItems()
end)

-- Items and usables again whenever the inventory provider (re)starts (its new VM needs our registrations
-- again); characters again when opx_core restarts.
AddEventHandler('onResourceStart', function(name)
	if name == Needs.RESOURCE then return end
	if name == Needs.provider('inventory') then
		CreateThread(function()
			Wait(1000)
			Needs.registerItems()
		end)
	elseif name == 'opx_core' then
		adoptLoaded()
	end
end)
