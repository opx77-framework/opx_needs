-- opx_needs client: runs the eat / drink action the server asks for (progress provider: bar + animation)
-- and shows the server's notifications. It only answers; the server checks the timing and applies the effect.

local OPX = assert(require('@opx_core'))

local T = OPX.Locale()

local function text(key, params)
	return T(key, type(params) == 'table' and params or {})
end

-- A server answer: locale key + kind + params.
RegisterNetEvent('opx_needs:notify', function(key, kind, params)
	if type(key) ~= 'string' then return end
	OPX.Notify(text(key, params), type(kind) == 'string' and kind or 'info', nil, text('title'))
end)

-- Runs the timed action. true only when it ran to the end.
local function runAction(info)
	local duration = math.floor(info.seconds * 1000)
	local provider = OPX.GetProvider('progress')
	if provider then
		local pending = Open77.exports.call(provider, 'Start', {
			label = text(info.kind == 'eat' and 'eating' or 'drinking'),
			duration = duration,
			canCancel = true,
			disableMovement = info.still == true,
			disableCombat = true,
			animation = info.animation and { profile = info.animation } or nil,
		})
		if pending then
			local ok = pending:await()
			return ok == true
		end
	end
	-- No progress provider (or it refused the call): the action still takes its time.
	Wait(duration)
	return true
end

-- opx_needs:consume (token, { item, seconds, animation, still, kind }) -> opx_needs:consumed (token, ok).
RegisterNetEvent('opx_needs:consume', function(token, info)
	if type(token) ~= 'number' or type(info) ~= 'table' then return end
	local seconds = tonumber(info.seconds)
	if not seconds or seconds ~= seconds or seconds < 1 or seconds > 60 then return end
	info.seconds = seconds
	if type(info.animation) ~= 'string' then info.animation = nil end
	CreateThread(function()
		local ok, done = pcall(runAction, info)
		TriggerServerEvent('opx_needs:consumed', token, ok and done == true)
	end)
end)
